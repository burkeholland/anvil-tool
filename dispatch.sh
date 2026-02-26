#!/bin/bash
# dispatch.sh — Parallel agent build loop for Anvil
#
# A single orchestration script that acts as PM + merge manager.
# It files GitHub issues describing work to do, assigns them to
# GitHub's cloud Copilot Coding Agent (@copilot), then pulls the
# resulting PRs, builds them locally, and merges.
#
# Usage:
#   ./dispatch.sh              # Run the full loop
#   ./dispatch.sh --dry-run    # Log actions without executing them
#
# Requirements: gh, copilot, jq, swift (for builds)

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

MAX_ACTIVE_AGENTS=5       # Max concurrent cloud agents (assigned issues w/ open PRs)
MAX_BACKLOG=5             # Stop filing issues when this many unassigned issues exist
LOOP_INTERVAL=300         # Seconds between cycles (5 min)
LABEL="anvil-auto"        # Label applied to all auto-created issues
REPO=""                   # Detected from gh repo view
ISSUE_AUTHOR=""             # Detected from gh auth status
SCREENSHOT_DIR="docs"     # Where to save screenshots
APP_BUNDLE=".build/Anvil.app"
DRY_RUN=false
DEBUG=false
DEBUG_PHASE=""            # Run only this phase in debug mode

# ─── Parse args ──────────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --debug) DEBUG=true ;;
    --debug-phase=*) DEBUG=true; DEBUG_PHASE="${arg#--debug-phase=}" ;;
    *) echo "Unknown argument: $arg"; echo "Usage: $0 [--dry-run] [--debug] [--debug-phase=merge|triage|plan|assign]"; exit 1 ;;
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
ISSUE_AUTHOR="$(gh api user -q .login 2>/dev/null)" || ISSUE_AUTHOR="burkeholland"

log "🏗️  dispatch.sh starting for $REPO"
log "   MAX_ACTIVE_AGENTS=$MAX_ACTIVE_AGENTS  MAX_BACKLOG=$MAX_BACKLOG"
log "   LOOP_INTERVAL=${LOOP_INTERVAL}s  DRY_RUN=$DRY_RUN  DEBUG=$DEBUG"

# Ensure the label exists
if ! gh label list --repo "$REPO" --json name -q '.[].name' | grep -qx "$LABEL"; then
  if [ "$DRY_RUN" = true ]; then
    log "🏷️  [DRY RUN] Would create label: $LABEL"
  else
    gh label create "$LABEL" --repo "$REPO" --description "Auto-created by dispatch.sh" --color "5319E7" 2>/dev/null || true
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

  # Get Copilot PRs that are ready (not WIP), oldest first
  local pr_numbers
  pr_numbers="$(gh pr list --repo "$REPO" --state open \
    --json number,author,title,createdAt \
    --jq '[.[] | select(.author.login == "app/copilot-swe-agent") | select(.title | startswith("[WIP]") | not)] | sort_by(.createdAt) | .[].number')" || return 0

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

    # Only action PRs linked to issues with our label (ignore community PRs)
    # Note: closingIssuesReferences doesn't include labels, so fetch the linked issue separately
    local linked_issue_num
    linked_issue_num="$(gh pr view "$pr_num" --repo "$REPO" --json closingIssuesReferences \
      --jq '(.closingIssuesReferences // [])[0].number // empty')" || linked_issue_num=""
    if [ -z "$linked_issue_num" ]; then
      log "   ⏭️  PR #$pr_num has no linked issue. Skipping."
      continue
    fi
    local linked_labels
    linked_labels="$(gh issue view "$linked_issue_num" --repo "$REPO" --json labels \
      --jq '[.labels[].name] | join(",")')" || linked_labels=""
    if ! echo "$linked_labels" | grep -q "$LABEL"; then
      log "   ⏭️  PR #$pr_num linked issue #$linked_issue_num missing $LABEL label. Skipping."
      continue
    fi

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
      # Smart conflict resolution: ask @copilot to rebase, track progress
      local our_rebase_comment
      our_rebase_comment="$(gh pr view "$pr_num" --repo "$REPO" --json comments \
        --jq '[.comments[] | select(.author.login != "app/copilot-swe-agent" and .author.login != "copilot-swe-agent") | select(.body | contains("dispatch:") and contains("@copilot") and contains("rebase"))] | last')" || our_rebase_comment=""

      if [ "$our_rebase_comment" = "null" ] || [ -z "$our_rebase_comment" ]; then
        log "   ⚠️  PR #$pr_num has merge conflicts. Asking @copilot to rebase."
        gh pr comment "$pr_num" --repo "$REPO" \
          --body "⚠️ dispatch: This PR has merge conflicts with main. @copilot please rebase this branch onto main and resolve any conflicts, keeping the intent of your changes intact." \
          2>/dev/null || true
      else
        local our_comment_date
        our_comment_date="$(echo "$our_rebase_comment" | jq -r '.createdAt')" || our_comment_date=""
        local latest_commit_date
        latest_commit_date="$(gh pr view "$pr_num" --repo "$REPO" --json commits \
          --jq '[.commits[].committedDate] | sort | last')" || latest_commit_date=""

        if [ -n "$latest_commit_date" ] && [ -n "$our_comment_date" ] && [[ "$latest_commit_date" > "$our_comment_date" ]]; then
          log "   🗑️  PR #$pr_num: agent pushed after rebase request but still conflicting. Closing."
          local linked_issue
          linked_issue="$(gh pr view "$pr_num" --repo "$REPO" --json closingIssuesReferences \
            --jq '(.closingIssuesReferences // [])[0].number // empty')" || linked_issue=""
          gh pr close "$pr_num" --repo "$REPO" \
            --comment "Closed by dispatch: agent attempted rebase but merge conflicts persist. Will reopen the linked issue for a fresh attempt." \
            2>/dev/null || true
          if [ -n "$linked_issue" ] && [ "$linked_issue" != "null" ]; then
            gh issue reopen "$linked_issue" --repo "$REPO" 2>/dev/null || true
            gh issue edit "$linked_issue" --repo "$REPO" --remove-assignee "copilot-swe-agent" 2>/dev/null || true
            log "   ♻️  Reopened issue #$linked_issue for fresh attempt."
          fi
        else
          log "   ⏳ PR #$pr_num: waiting for @copilot to rebase (no new commits yet)."
        fi
      fi
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

    git checkout -B "dispatch/test-merge" main --quiet 2>/dev/null || {
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
    local build_output
    build_output="$(swift build 2>&1)"
    local build_exit=$?
    echo "$build_output" | tail -3

    if [ "$build_exit" -eq 0 ]; then
      log "   ✅ Build passed for PR #$pr_num. Marking ready and merging..."
      git checkout main --force --quiet 2>/dev/null || true
      # Mark as ready (PRs from Copilot arrive as drafts)
      gh pr ready "$pr_num" --repo "$REPO" 2>/dev/null || true
      gh pr merge "$pr_num" --repo "$REPO" --squash --delete-branch \
        --body "Merged by dispatch.sh after local build verification." || {
        log "   ❌ Merge failed for PR #$pr_num."
        continue
      }
      git pull --quiet origin main 2>/dev/null || true
      merged_count=$((merged_count + 1))
      # Break after merge — next cycle will re-evaluate remaining PRs against updated main
      break
    else
      log "   ❌ Build failed for PR #$pr_num."
      git checkout main --force --quiet 2>/dev/null || true

      # Smart build-failure handling: check if we already asked @copilot to fix
      local our_build_comment
      our_build_comment="$(gh pr view "$pr_num" --repo "$REPO" --json comments \
        --jq '[.comments[] | select(.author.login != "app/copilot-swe-agent" and .author.login != "copilot-swe-agent") | select(.body | contains("dispatch:") and contains("@copilot") and contains("Build failed"))] | last')" || our_build_comment=""

      if [ "$our_build_comment" = "null" ] || [ -z "$our_build_comment" ]; then
        # First time — include compilation errors and mention @copilot
        local error_lines
        error_lines="$(echo "$build_output" | grep -E '(error:|fatal error:)' | head -20)"
        gh pr comment "$pr_num" --repo "$REPO" \
          --body "$(printf '❌ dispatch: Build failed locally (\`swift build\`). @copilot please fix these compilation errors:\n\n```\n%s\n```' "$error_lines")" \
          2>/dev/null || true
      else
        # Already asked — check if agent pushed new commits since our comment
        local our_comment_date
        our_comment_date="$(echo "$our_build_comment" | jq -r '.createdAt')" || our_comment_date=""
        local latest_commit_date
        latest_commit_date="$(gh pr view "$pr_num" --repo "$REPO" --json commits \
          --jq '[.commits[].committedDate] | sort | last')" || latest_commit_date=""

        if [ -n "$latest_commit_date" ] && [ -n "$our_comment_date" ] && [[ "$latest_commit_date" > "$our_comment_date" ]]; then
          # Agent pushed but build still fails — update with new errors
          local error_lines
          error_lines="$(echo "$build_output" | grep -E '(error:|fatal error:)' | head -20)"
          gh pr comment "$pr_num" --repo "$REPO" \
            --body "$(printf '❌ dispatch: Build still failing after your latest push. @copilot please fix these remaining errors:\n\n```\n%s\n```' "$error_lines")" \
            2>/dev/null || true
        else
          log "   ⏳ PR #$pr_num: waiting for @copilot to fix build (no new commits yet)."
        fi
      fi
    fi
  done <<< "$pr_numbers"

  # Clean up test branch
  git checkout main --force --quiet 2>/dev/null || true
  git branch -D "dispatch/test-merge" 2>/dev/null || true

  log "   Merged $merged_count PR(s) this cycle."
}

# ─── Phase 1b: SCREENSHOT ───────────────────────────────────────────────────

# Launches Anvil with a given sidebar tab, captures the content window, kills app.
# Usage: capture_app_screenshot <sidebar_tab> <output_file>
#   sidebar_tab: files, changes, activity, search, history
capture_app_screenshot() {
  local tab="$1"
  local output="$2"

  # Map tab name to ⌘ shortcut number
  local shortcut
  case "$tab" in
    files)   shortcut="1" ;;
    changes) shortcut="2" ;;
    activity) shortcut="3" ;;
    search)  shortcut="4" ;;
    history) shortcut="5" ;;
    *)       shortcut="1" ;;
  esac

  # Set project directory via UserDefaults before launch
  defaults write dev.burkeholland.anvil "dev.anvil.lastOpenedDirectory" "$SCRIPT_DIR"

  # Kill any existing Anvil instance
  local existing_pid
  existing_pid="$(pgrep -x Anvil)" && kill "$existing_pid" 2>/dev/null && sleep 1

  # Launch in background (no focus steal)
  open -g "$APP_BUNDLE"
  sleep 6

  # Activate, resize, and use ⌘N keystroke to switch tab (forces sidebar open)
  osascript -e "
    tell application \"Anvil\" to activate
    delay 2
    tell application \"System Events\"
      tell process \"Anvil\"
        try
          set frontmost to true
          -- Resize window to a good screenshot size
          tell window 1
            set position to {100, 100}
            set size to {1400, 900}
          end tell
          -- Send ⌘${shortcut} to switch sidebar tab (also forces sidebar visible)
          keystroke \"${shortcut}\" using command down
        end try
      end tell
    end tell
    -- Give file tree time to enumerate and render
    delay 5
  " 2>/dev/null || true

  # Find the content window (largest by area, skip menu bar items)
  local window_id
  window_id="$(swift -e '
import CoreGraphics
var bestId = 0
var bestArea = 0
if let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
    for w in windows {
        let name = w[kCGWindowOwnerName as String] as? String ?? ""
        if name.contains("Anvil") {
            let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let h = bounds["Height"] as? Int ?? 0
            let w2 = bounds["Width"] as? Int ?? 0
            let area = h * w2
            if h > 100 && area > bestArea {
                bestArea = area
                bestId = w[kCGWindowNumber as String] as? Int ?? 0
            }
        }
    }
}
print(bestId)
' 2>/dev/null)" || window_id=""

  if [ -z "$window_id" ] || [ "$window_id" = "0" ]; then
    log "   ⚠️  Could not find Anvil window for tab '$tab'."
    local cleanup_pid
    cleanup_pid="$(pgrep -x Anvil)" && kill "$cleanup_pid" 2>/dev/null
    return 1
  fi

  # Capture the window
  if screencapture -l "$window_id" "$output" 2>/dev/null && [ -f "$output" ]; then
    local fsize
    fsize="$(stat -f%z "$output" 2>/dev/null || echo 0)"
    if [ "$fsize" -lt 50000 ]; then
      log "   ⚠️  Screenshot for '$tab' looks blank ($fsize bytes). Skipping."
      rm -f "$output"
      local cleanup_pid
      cleanup_pid="$(pgrep -x Anvil)" && kill "$cleanup_pid" 2>/dev/null
      return 1
    fi
    log "   ✅ Captured $tab → $output"
  else
    log "   ⚠️  screencapture failed for tab '$tab'."
    local cleanup_pid
    cleanup_pid="$(pgrep -x Anvil)" && kill "$cleanup_pid" 2>/dev/null
    return 1
  fi

  # Kill the app so next launch picks up new UserDefaults
  local cleanup_pid
  cleanup_pid="$(pgrep -x Anvil)" && kill "$cleanup_pid" 2>/dev/null
  sleep 1
  return 0
}

phase_screenshot() {
  log "📸 Phase 1b: SCREENSHOT — capturing app state..."

  if [ "$DRY_RUN" = true ]; then
    log "   [DRY RUN] Would build, screenshot, update README, and file visual review."
    return 0
  fi

  # Build the app
  log "   Building app for screenshot..."
  if ! swift build 2>/dev/null; then
    log "   ⚠️  Build failed — skipping screenshot."
    return 0
  fi

  # Prepare .app bundle
  local bundle_macos="$APP_BUNDLE/Contents/MacOS"
  mkdir -p "$bundle_macos"
  cp .build/debug/Anvil "$bundle_macos/Anvil"

  if [ ! -f "$APP_BUNDLE/Contents/Info.plist" ]; then
    cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Anvil</string>
    <key>CFBundleIdentifier</key>
    <string>dev.burkeholland.anvil</string>
    <key>CFBundleName</key>
    <string>Anvil</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST
  fi

  # Capture multiple views
  mkdir -p "$SCREENSHOT_DIR"
  local captured=0

  # Main view — Files sidebar (the hero screenshot)
  if capture_app_screenshot "files" "$SCREENSHOT_DIR/screenshot.png"; then
    captured=$((captured + 1))
  fi

  # Changes view
  if capture_app_screenshot "changes" "$SCREENSHOT_DIR/screenshot-changes.png"; then
    captured=$((captured + 1))
  fi

  # Commit History view
  if capture_app_screenshot "history" "$SCREENSHOT_DIR/screenshot-history.png"; then
    captured=$((captured + 1))
  fi

  if [ "$captured" -eq 0 ]; then
    log "   ⚠️  No screenshots captured. Skipping."
    return 0
  fi

  log "   📷 Captured $captured screenshot(s)."

  # ── Update README.md ──────────────────────────────────────────────────────
  local timestamp
  timestamp="$(date -u '+%Y-%m-%d %H:%M UTC')"

  cat > README.md << READMEEOF
# Anvil

A native macOS app that wraps the GitHub Copilot CLI in a beautiful, full-featured IDE experience.

> **Last updated**: $timestamp

## Screenshots

### File Explorer
![File Explorer](docs/screenshot.png)

### Changes View
![Changes](docs/screenshot-changes.png)

### Commit History
![Commit History](docs/screenshot-history.png)

## Features

- 🗂️ File explorer with git status indicators
- ✏️ Syntax-highlighted file preview
- 🔀 Inline diff viewer for changes
- 🖥️ Integrated terminal with Copilot CLI
- 📋 Git commit history browser
- 🔍 Project-wide search
- 🤖 Agent activity feed

## Build

\`\`\`bash
swift build
\`\`\`

## Design

Built with SwiftUI. Target aesthetic: clean, minimal, polished native macOS feel.
Design reference: [postrboard.com](https://postrboard.com)
READMEEOF

  log "   📝 README.md updated with screenshots and timestamp."

  # ── Commit everything ────────────────────────────────────────────────────
  git add "$SCREENSHOT_DIR"/*.png README.md
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "docs: update app screenshots and README ($timestamp)

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" --quiet
    git push --quiet origin main 2>/dev/null || true
    log "   📤 Screenshots + README committed and pushed."
  else
    log "   No changes to commit."
  fi

  # ── File / update visual review issue ──────────────────────────────────
  local base_url="https://raw.githubusercontent.com/$REPO/main/$SCREENSHOT_DIR"
  local issue_title="Visual review: app screenshots ($timestamp)"

  local issue_body
  read -r -d '' issue_body << ISSUEEOF || true
📸 **Automated visual review** — $timestamp

Review these screenshots of the Anvil app for any visual issues.

### File Explorer
![File Explorer](${base_url}/screenshot.png)

### Changes View
![Changes](${base_url}/screenshot-changes.png)

### Commit History
![Commit History](${base_url}/screenshot-history.png)

---

**What to look for:**
- Broken or misaligned layouts
- Overlapping or truncated text
- Empty areas that should have content
- UI elements that look wrong or out of place
- Inconsistent spacing, colors, or typography
- Anything that doesn't match a clean, minimal, polished macOS aesthetic

**Design reference**: The target look and feel is clean and minimal — dark theme with clear hierarchy, no clutter, generous spacing. Reference: https://postrboard.com

If you find visual issues, describe them specifically and open a new issue for each fix. If everything looks good, close this issue.
ISSUEEOF

  # Always create a new visual review issue (one per cycle)
  gh issue create --repo "$REPO" \
    --title "$issue_title" \
    --label "$LABEL" \
    --body "$issue_body" \
    2>/dev/null || true
  log "   📝 Filed visual review issue."
}

# ─── Phase 2: TRIAGE ────────────────────────────────────────────────────────

phase_triage() {
  log "🧹 Phase 2: TRIAGE — checking for stale issues and PRs..."

  # Note: merge conflict and build failure resolution is handled in phase_merge
  # via @copilot rebase/fix requests with smart dedup.

  # Check open issues — use copilot to evaluate staleness
  local open_issues
  open_issues="$(gh issue list --repo "$REPO" --label "$LABEL" --author "$ISSUE_AUTHOR" --state open \
    --json number,title,body \
    --jq 'length')" || true

  if [ "${open_issues:-0}" -gt "$MAX_BACKLOG" ]; then
    log "   $open_issues open issues — checking for stale ones..."

    local issue_list
    issue_list="$(gh issue list --repo "$REPO" --label "$LABEL" --author "$ISSUE_AUTHOR" --state open \
      --json number,title --jq '.[] | "\(.number)\t\(.title)"')"

    # Check which issues were closed by merged Copilot PRs (using GitHub's linked references)
    local closed_by_prs
    closed_by_prs="$(gh pr list --repo "$REPO" --state merged \
      --limit 20 --json author,closingIssuesReferences \
      --jq '[.[] | select(.author.login == "app/copilot-swe-agent") | (.closingIssuesReferences // [])[].number] | unique | .[]' 2>/dev/null)" || closed_by_prs=""

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
            --comment "Closed by dispatch: a merged PR resolved this issue." \
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
  unassigned_count="$(gh issue list --repo "$REPO" --label "$LABEL" --author "$ISSUE_AUTHOR" --state open \
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
  open_issue_titles="$(gh issue list --repo "$REPO" --label "$LABEL" --author "$ISSUE_AUTHOR" --state open \
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
🤖 *Filed by dispatch.sh*"

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

  # Count active agents by open PRs (ground truth for "agent is working")
  local open_pr_count
  open_pr_count="$(gh pr list --repo "$REPO" --state open \
    --json number,author \
    --jq '[.[] | select(.author.login == "app/copilot-swe-agent")] | length' 2>/dev/null)" || open_pr_count=0

  local slots_available=$((MAX_ACTIVE_AGENTS - open_pr_count))
  if [ "$slots_available" -le 0 ]; then
    log "   All $MAX_ACTIVE_AGENTS agent slots occupied. Waiting for PRs."
    return 0
  fi

  log "   $open_pr_count active PR(s), $slots_available slot(s) available."

  # Get unassigned issues
  local unassigned
  unassigned="$(gh issue list --repo "$REPO" --label "$LABEL" --author "$ISSUE_AUTHOR" --state open \
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

# ─── Run Cycle ────────────────────────────────────────────────────────────────

run_cycle() {
  local iteration="$1"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🏗️  dispatch.sh — Cycle $iteration"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [ -z "$DEBUG_PHASE" ] || [ "$DEBUG_PHASE" = "merge" ]; then
    phase_merge || log "⚠️  phase_merge failed, continuing..."
    echo ""
  fi

  if [ -z "$DEBUG_PHASE" ] || [ "$DEBUG_PHASE" = "screenshot" ]; then
    phase_screenshot || log "⚠️  phase_screenshot failed, continuing..."
    echo ""
  fi

  if [ -z "$DEBUG_PHASE" ] || [ "$DEBUG_PHASE" = "triage" ]; then
    phase_triage || log "⚠️  phase_triage failed, continuing..."
    echo ""
  fi

  if [ -z "$DEBUG_PHASE" ] || [ "$DEBUG_PHASE" = "plan" ]; then
    phase_plan || log "⚠️  phase_plan failed, continuing..."
    echo ""
  fi

  if [ -z "$DEBUG_PHASE" ] || [ "$DEBUG_PHASE" = "assign" ]; then
    phase_assign || log "⚠️  phase_assign failed, continuing..."
    echo ""
  fi
}

# ─── Main Loop ───────────────────────────────────────────────────────────────

ITERATION=0

if [ "$DEBUG" = true ]; then
  ITERATION=1
  log "🐛 DEBUG MODE — running 1 cycle${DEBUG_PHASE:+ (phase: $DEBUG_PHASE)} then exiting"
  run_cycle "$ITERATION"
  log "🐛 DEBUG complete."
  exit 0
fi

while true; do
  ITERATION=$((ITERATION + 1))
  run_cycle "$ITERATION"
  log "💤 Cycle $ITERATION complete. Sleeping ${LOOP_INTERVAL}s..."
  sleep "$LOOP_INTERVAL"
done
