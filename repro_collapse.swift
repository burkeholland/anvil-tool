
import Foundation

struct MockEntry {
    let name: String
    let depth: Int
}

var entries: [MockEntry] = [
    MockEntry(name: "Dir A", depth: 0),     // index 0
    MockEntry(name: "Dir B", depth: 1),     // index 1
    MockEntry(name: "File C", depth: 2),    // index 2
    MockEntry(name: "Dir D", depth: 0)      // index 3
]

let index = 0 // Dir A
let entryDepth = 0

var removeCount = 0
for i in (index + 1)..<entries.count {
    if entries[i].depth > entryDepth {
        removeCount += 1
    } else {
        break
    }
}

print("Remove count: \(removeCount)") 
// Expected: 2 (Dir B, File C)
// If logic is correct, it stops at Dir D (depth 0 is not > 0)
