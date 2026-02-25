
import Foundation

let parent = URL(fileURLWithPath: "/Users/me/project")
let child = URL(fileURLWithPath: "/Users/me/project/src")
let sibling = URL(fileURLWithPath: "/Users/me/project_backup")

let parentPath = parent.path
let childPath = child.path
let siblingPath = sibling.path

print("Parent: \(parentPath)")
print("Child: \(childPath)")
print("Sibling: \(siblingPath)")

func shouldRemove(_ url: URL, under parent: URL) -> Bool {
    return url.path.hasPrefix(parent.path + "/")
}

print("Remove child? \(shouldRemove(child, under: parent))")
print("Remove sibling? \(shouldRemove(sibling, under: parent))")
