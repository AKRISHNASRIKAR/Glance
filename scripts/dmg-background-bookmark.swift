// Finder's background bookmark must be produced by Foundation on modern macOS.
import Foundation
let image = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let bookmark = try image.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
var stale = false
let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
guard !stale, resolved.standardizedFileURL == image.standardizedFileURL else {
    fatalError("Installer background bookmark did not resolve to its image")
}
try bookmark.write(to: output)
