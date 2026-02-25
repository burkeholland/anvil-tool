#!/bin/bash
# ralph-team.sh — Parallel agent build loop for Anvil
#
# A single orchestration script that acts as PM + merge manager.
# It files GitHub issues describing work to do, assigns them to
# GitHub's cloud Copilot Coding Agent (@copilot), then pulls the
# resulting PRs, builds them locally, and merges.
#
# Usage:
#   ./ralph-team.sh              # Run the full loop
#   ./ralph-team.sh --dry-run    # Log actions without executing them
#
# Requirements: gh, copilot, jq, swift (for builds)

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

MAX_ACTIVE_AGENTS=5       # Max concurrent cloud agents (assigned issues w/ open PRs)
MAX_BACKLOG=5             # Stop filing issues when this many unassigned issues exist
LOOP_INTERVAL=300         # Seconds between cycles (5 min)
LABEL="anvil-auto"        # Label applied to all auto-created issues
REPO=""                   # Detected from gh repo view
DRY_RUN=false

# ─── Parse args ──────────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ─── Setup ───────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log() { echo "$(date '+%H:%M:%S') $1"; }

# Verify required tools
for tool in gh jq copilot swift; do
  if ! command -v "$tool" &>/dev/null; then
    echo "❌ Required tool not found: $tool"
    exit 1
  fi
done

# Detect repo
REPO="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)" || {
  echo "❌ Could not detect GitHub repo. Run from a repo with a GitHub remote."
  exit 1
}
OWNER="$(echo "$REPO" | cut -d/ -f1)"
REPO_NAME="$(echo "$REPO" | cut -d/ -f2)"

log "🏗️  ralph-team.sh starting for $REPO"
log "   MAX_ACTIVE_AGENTS=$MAX_ACTIVE_AGENTS  MAX_BACKLOG=$MAX_BACKLOG"
log "   LOOP_INTERVAL=${LOOP_INTERVAL}s  DRY_RUN=$DRY_RUN"

# Ensure the label exists
if ! gh label list --repo "$REPO" --json name -q '.[].name' | grep -qx "$LABEL"; then
  if [ "$DRY_RUN" = true ]; then
    log "🏷️  [DRY RUN] Would create label: $LABEL"
  else
    gh label create "$LABEL" --repo "$REPO" --description "Auto-created by ralph-team.sh" --color "5319E7" 2>/dev/null || true
    log "🏷️  Created label: $LABEL"
  fi
fi

# ─── Project Context Prompt (reused from ralph.sh) ──────────────────────────

read -r -d '' PROJECT_CONTEXT << 'CONTEXT_EOF' || true
## What is Anvil?

Anvil is a native macOS desktop app that makes the GitHub Copilot CLI better by wrapping it in visual context.

Picture this: a developer opens Anvil. A terminal fills the center of the window — the Copilot CLI is already running in it. That terminal is the primary interface. But around it, the developer can see their file tree, preview files with syntax highlighting, view diffs of what the agent just changed, and inspect what the agent is doing in a structured activity feed. It feels like Xcode or VS Code, but the AI terminal is the centerpiece, not an afterthought in a sidebar.

The goal is not to replace the CLI. The goal is to give the developer eyes and context while the CLI does the work.

## Architecture

- **Swift 5.9+, SwiftUI, macOS 14+** — this is a native Mac app. No Electron. No web views. It should feel instant.
- **Swift Package Manager** for dependencies (Package.swift).
- **Reuse everything you can.** Before writing any component from scratch, search for an existing Swift package.
  - Terminal emulation: SwiftTerm
  - Syntax highlighting: Highlightr
  - File watching: FSEvents / DispatchSource (built into macOS)
- **AppKit bridging is fine** where SwiftUI falls short.

## The Copilot CLI

- Invocation: `copilot` launches an interactive TUI session with ANSI escape sequences.
- Working directory matters: the CLI operates on cwd.
- Session-based with conversation history, file context, and tool calls.
- Slash commands: /help, /diff, /model, /compact, /session, /agent, /mcp, /ide, /review, /tasks, /context, /instructions, etc.
- Modes: Interactive (default), Plan (Shift+Tab). Experimental: Autopilot.
- Capabilities: reads/writes files, runs bash, searches code, manages git, calls GitHub APIs via MCP.
CONTEXT_EOF

# ─── Phase 1: MERGE ─────────────────────────────────────────────────────────

phase_merge() {
  log "📦 Phase 1: MERGE — checking for mergeable PRs..."

  # Get Copilot PRs that are ready (not WIP, no build-failed label), oldest first
  local pr_numbers
  pr_numbers="$(gh pr list --repo "$REPO" --state open \
    --json number,author,title,createdAt,labels \
    --jq '[.[] | select(.author.login == "app/copilot-swe-agent") | select(.title | startswith("[WIP]") | not) | select(([.labels[]?.name] | index("build-failed")) | not)] | sort_by(.createdAt) | .[].number')" || return 0

  if [ -z "$pr_numbers" ]; then
    log "   No ready Copilot PRs found (WIP PRs are skipped)."
    return 0
  fi

  # Make sure we're on main with latest
  git checkout main --force --quiet 2>/dev/null || true
  git pull --quiet origin main 2>/dev/null || true

  local merged_count=0
  local pr_num
  while IFS= read -r pr_num; do
    [ -z "$pr_num" ] && continue
    log "   Checking PR #$pr_num..."

    if [ "$DRY_RUN" = true ]; then
      log "   [DRY RUN] Would attempt to merge PR #$pr_num"
      continue
    fi

    # Check if PR is mergeable (no conflicts)
    local mergeable
    mergeable="$(gh pr view "$pr_num" --repo "$REPO" --json mergeable -q '.mergeable')" || {
      log "   ⚠️  Could not check mergeability for PR #$pr_num. Skipping."
      continue
    }
    if [ "$mergeable" = "CONFLICTING" ]; then
      log "   ⚠️  PR #$pr_num has merge conflicts. Commenting and skipping."
      gh pr comment "$pr_num" --repo "$REPO" \
        --body "⚠️ ralph-team: This PR has merge conflicts with main. Please rebase or I'll close it on the next triage pass." \
        2>/dev/null || true
      continue
    fi

    # Fetch PR head and test-merge into a temp branch (keeps main clean)
    local pr_head
    pr_head="$(gh pr view "$pr_num" --repo "$REPO" --json headRefOid -q '.headRefOid')" || {
      log "   ⚠️  Could not get head SHA for PR #$pr_num. Skipping."
      continue
    }
    git fetch --quiet origin "$pr_head" 2>/dev/null || {
      log "   ❌ Could not fetch PR #$pr_num head. Skipping."
      continue
    }

    git checkout -B "ralph-team/test-merge" main --quiet 2>/dev/null || {
      log "   ❌ Could not create test branch for PR #$pr_num. Skipping."
      git checkout main --force --quiet 2>/dev/null || true
      continue
    }

    if ! git merge --no-edit --quiet "$pr_head" 2>/dev/null; then
      log "   ⚠️  PR #$pr_num merge conflicts locally. Skipping."
      git merge --abort 2>/dev/null || true
      git checkout main --force --quiet 2>/dev/null || true
      continue
    fi

    log "   🔨 Building PR #$pr_num..."
    if swift build 2>&1 | tail -3; then
      log "   ✅ Build passed for PR #$pr_num. Marking ready and merging..."
      git checkout main --force --quiet 2>/dev/null || true
      # Mark as ready (PRs from Copilot arrive as drafts)
      gh pr ready "$pr_num" --repo "$REPO" 2>/dev/null || true
      gh pr merge "$pr_num" --repo "$REPO" --squash --delete-branch \
        --body "Merged by ralph-team.sh after local build verification." || {
        log "   ❌ Merge failed for PR #$pr_num."
        continue
      }
      git pull --quiet origin main 2>/dev/null || true
      merged_count=$((merged_count + 1))
      # Break after merge — next cycle will re-evaluate remaining PRs against updated main
      break
    else
      log "   ❌ Build failed for PR #$pr_num. Commenting and labeling."
      git checkout main --force --quiet 2>/dev/null || true
      gh pr comment "$pr_num" --repo "$REPO" \
        --body "❌ ralph-team: Build failed locally (\`swift build\`). Please fix compilation errors." \
        2>/dev/null || true
      # Add build-failed label so we skip it next cycle
      gh pr edit "$pr_num" --repo "$REPO" --add-label "build-failed" 2>/dev/null || true
    fi
  done <<< "$pr_numbers"

  # Clean up test branch
  git checkout main --force --quiet 2>/dev/null || true
  git branch -D "ralph-team/test-merge" 2>/dev/null || true

  log "   Merged $merged_count PR(s) this cycle."
}

# ─── Phase 2: TRIAGE ────────────────────────────────────────────────────────

phase_triage() {
  log "🧹 Phase 2: TRIAGE — checking for stale issues and PRs..."

  # Close PRs that have been conflicting for more than 1 cycle (have our conflict comment)
  local conflicting_prs
  conflicting_prs="$(gh pr list --repo "$REPO" --state open \
    --json number,author,comments \
    --jq '[.[] | select(.author.login == "app/copilot-swe-agent") | select(.comments | length > 0)] | .[].number')" || true

  local pr_num
  while IFS= read -r pr_num; do
    [ -z "$pr_num" ] && continue

    # Check if we already commented about conflicts
    local has_conflict_comment
    has_conflict_comment="$(gh pr view "$pr_num" --repo "$REPO" --json comments \
      --jq '[.comments[] | select(.body | contains("merge conflicts"))] | length')" || continue

    if [ "$has_conflict_comment" -gt 0 ]; then
      # Check if still conflicting
      local mergeable
      mergeable="$(gh pr view "$pr_num" --repo "$REPO" --json mergeable -q '.mergeable')" || continue
      if [ "$mergeable" = "CONFLICTING" ]; then
        if [ "$DRY_RUN" = true ]; then
          log "   [DRY RUN] Would close stale conflicting PR #$pr_num"
        else
          log "   🗑️  Closing stale conflicting PR #$pr_num"
          gh pr close "$pr_num" --repo "$REPO" \
            --comment "Closed by ralph-team: merge conflicts were not resolved." \
            2>/dev/null || true
        fi
      fi
    fi
  done <<< "$conflicting_prs"

  # Check open issues — use copilot to evaluate staleness
  local open_issues
  open_issues="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
    --json number,title,body \
    --jq 'length')" || true

  if [ "${open_issues:-0}" -gt "$MAX_BACKLOG" ]; then
    log "   $open_issues open issues — checking for stale ones..."

    local issue_list
    issue_list="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
      --json number,title --jq '.[] | "\(.number)\t\(.title)"')"

    # Check which issues were closed by merged Copilot PRs (using GitHub's linked references)
    local closed_by_prs
    closed_by_prs="$(gh pr list --repo "$REPO" --state merged \
      --limit 20 --json author,closingIssuesReferences \
      --jq '[.[] | select(.author.login == "app/copilot-swe-agent") | .closingIssuesReferences[].number] | unique | .[]' 2>/dev/null)" || closed_by_prs=""

    local issue_num issue_title
    while IFS=$'\t' read -r issue_num issue_title; do
      [ -z "$issue_num" ] && continue

      # Only close if a merged PR explicitly linked/closed this issue number
      local is_resolved=false
      while IFS= read -r closed_num; do
        [ -z "$closed_num" ] && continue
        if [ "$issue_num" = "$closed_num" ]; then
          is_resolved=true
          break
        fi
      done <<< "$closed_by_prs"

      if [ "$is_resolved" = true ]; then
        if [ "$DRY_RUN" = true ]; then
          log "   [DRY RUN] Would close resolved issue #$issue_num: $issue_title"
        else
          log "   🗑️  Closing resolved issue #$issue_num: $issue_title"
          gh issue close "$issue_num" --repo "$REPO" \
            --comment "Closed by ralph-team: a merged PR resolved this issue." \
            2>/dev/null || true
        fi
      fi
    done <<< "$issue_list"
  else
    log "   $open_issues open issue(s) — within backlog limit."
  fi
}

# ─── Phase 3: PLAN ──────────────────────────────────────────────────────────

phase_plan() {
  log "📝 Phase 3: PLAN — deciding what to build next..."

  # Count open unassigned issues
  local unassigned_count
  unassigned_count="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
    --json number,assignees \
    --jq '[.[] | select(.assignees | length == 0)] | length')" || unassigned_count=0

  if [ "$unassigned_count" -ge "$MAX_BACKLOG" ]; then
    log "   Backlog full ($unassigned_count unassigned issues). Skipping planning."
    return 0
  fi

  local issues_to_create=$((MAX_BACKLOG - unassigned_count))
  if [ "$issues_to_create" -gt 3 ]; then
    issues_to_create=3
  fi

  log "   Need $issues_to_create new issue(s). Asking Copilot for ideas..."

  # Pull latest and gather context
  git checkout main --quiet 2>/dev/null || true
  git pull --quiet origin main 2>/dev/null || true

  local git_log file_list open_issue_titles
  git_log="$(git log --oneline -30)"
  file_list="$(find . -type f -not -path './.git/*' -not -path './.build/*' | head -80)"
  open_issue_titles="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
    --json title -q '.[].title' 2>/dev/null)" || open_issue_titles=""

  local plan_prompt
  plan_prompt="You are a PM for the Anvil project. Your job is to decide what to build next.

$PROJECT_CONTEXT

## Current State

Recent git log:
\`\`\`
$git_log
\`\`\`

File listing:
\`\`\`
$file_list
\`\`\`

Open issues already filed (DO NOT duplicate these):
\`\`\`
$open_issue_titles
\`\`\`

## Your Task

Identify exactly $issues_to_create improvements or features to build next. Each should be:
1. A single focused unit of work (completable in one session)
2. Scoped to a specific area of the app (to minimize merge conflicts with parallel work)
3. Not duplicating any open issue listed above
4. Impactful — ask yourself what matters most to a developer using this app right now

Do NOT specify which files to modify — the implementing agent will figure that out.

Output ONLY a JSON array. No markdown, no explanation, no code fences. Just the raw JSON array:
[
  {
    \"title\": \"Short descriptive title\",
    \"problem\": \"What is the current problem or gap (1-2 sentences)\",
    \"solution\": \"What to build and how it should work (2-4 sentences)\"
  }
]"

  local copilot_output
  if [ "$DRY_RUN" = true ]; then
    log "   [DRY RUN] Would ask Copilot to generate $issues_to_create issues"
    return 0
  fi

  copilot_output="$(copilot -p "$plan_prompt" --model claude-opus-4.6 --silent 2>/dev/null)" || {
    log "   ⚠️  Copilot planning failed. Skipping issue creation."
    return 0
  }

  # Extract JSON array — handle cases where copilot wraps in markdown
  local json_output
  json_output="$(echo "$copilot_output" | sed -n '/^\[/,/^\]/p')"
  if [ -z "$json_output" ]; then
    # Try extracting from code fences
    json_output="$(echo "$copilot_output" | sed -n '/```json/,/```/p' | sed '1d;$d')"
  fi
  if [ -z "$json_output" ]; then
    json_output="$(echo "$copilot_output" | sed -n '/```/,/```/p' | sed '1d;$d')"
  fi

  if ! echo "$json_output" | jq empty 2>/dev/null; then
    log "   ⚠️  Copilot output was not valid JSON. Skipping."
    log "   Raw output: $(echo "$copilot_output" | head -5)"
    return 0
  fi

  local count
  count="$(echo "$json_output" | jq 'length')"
  # Cap to requested amount regardless of model output
  if [ "$count" -gt "$issues_to_create" ]; then
    count="$issues_to_create"
  fi
  log "   Creating $count issue(s)..."

  local i=0
  while [ "$i" -lt "$count" ]; do
    local title problem solution
    title="$(echo "$json_output" | jq -r ".[$i].title")"
    problem="$(echo "$json_output" | jq -r ".[$i].problem // .[$i].description // empty")"
    solution="$(echo "$json_output" | jq -r ".[$i].solution // empty")"

    # Compose structured issue body
    local full_body="## Problem

$problem"

    if [ -n "$solution" ]; then
      full_body="$full_body

## Solution

$solution"
    fi

    full_body="$full_body

---
🤖 *Filed by ralph-team.sh*"

    log "   📋 Creating issue: $title"
    gh issue create --repo "$REPO" \
      --title "$title" \
      --body "$full_body" \
      --label "$LABEL" 2>/dev/null || {
      log "   ⚠️  Failed to create issue: $title"
    }

    i=$((i + 1))
  done
}

# ─── Phase 4: ASSIGN ────────────────────────────────────────────────────────

phase_assign() {
  log "🤖 Phase 4: ASSIGN — dispatching work to cloud agents..."

  # Count currently active agents (issues assigned to Copilot)
  local active_count
  active_count="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
    --json number,assignees \
    --jq '[.[] | select(.assignees | map(.login) | index("Copilot"))] | length' 2>/dev/null)" || active_count=0

  # Also count open Copilot PRs as active work
  local open_pr_count
  open_pr_count="$(gh pr list --repo "$REPO" --state open \
    --json number,author \
    --jq '[.[] | select(.author.login == "app/copilot-swe-agent")] | length' 2>/dev/null)" || open_pr_count=0

  # Use the higher of the two as "active"
  local effective_active=$active_count
  if [ "$open_pr_count" -gt "$effective_active" ]; then
    effective_active=$open_pr_count
  fi

  local slots_available=$((MAX_ACTIVE_AGENTS - effective_active))
  if [ "$slots_available" -le 0 ]; then
    log "   All $MAX_ACTIVE_AGENTS agent slots occupied. Waiting for PRs."
    return 0
  fi

  log "   $effective_active active agent(s), $slots_available slot(s) available."

  # Get unassigned issues
  local unassigned
  unassigned="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
    --json number,title,assignees \
    --jq '[.[] | select(.assignees | length == 0)] | sort_by(.number) | .[].number')" || return 0

  if [ -z "$unassigned" ]; then
    log "   No unassigned issues to dispatch."
    return 0
  fi

  local assigned_count=0
  local issue_num
  while IFS= read -r issue_num; do
    [ -z "$issue_num" ] && continue
    if [ "$assigned_count" -ge "$slots_available" ]; then
      break
    fi

    if [ "$DRY_RUN" = true ]; then
      log "   [DRY RUN] Would assign issue #$issue_num to @copilot"
    else
      log "   🚀 Assigning issue #$issue_num to @copilot"
      # Assigning to "copilot-swe-agent" triggers the Copilot Coding Agent
      gh issue edit "$issue_num" --repo "$REPO" --add-assignee "copilot-swe-agent" 2>/dev/null || {
        log "   ⚠️  Failed to assign issue #$issue_num"
        continue
      }
    fi

    assigned_count=$((assigned_count + 1))
  done <<< "$unassigned"

  log "   Assigned $assigned_count issue(s) this cycle."
}

# ─── Main Loop ───────────────────────────────────────────────────────────────

ITERATION=0

while true; do
  ITERATION=$((ITERATION + 1))
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🏗️  ralph-team.sh — Cycle $ITERATION"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  phase_merge || log "⚠️  phase_merge failed, continuing..."
  echo ""

  phase_triage || log "⚠️  phase_triage failed, continuing..."
  echo ""

  phase_plan || log "⚠️  phase_plan failed, continuing..."
  echo ""

  phase_assign || log "⚠️  phase_assign failed, continuing..."
  echo ""

  log "💤 Cycle $ITERATION complete. Sleeping ${LOOP_INTERVAL}s..."
  sleep "$LOOP_INTERVAL"
done
