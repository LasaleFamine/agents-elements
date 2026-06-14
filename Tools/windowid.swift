import CoreGraphics
import Foundation

// Prints the CGWindowID of the main AgentsElements window (height > 200 to skip the
// menu-bar popover). Used by shot.sh to screenshot just our window.
let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
for w in infos {
    guard let owner = w[kCGWindowOwnerName as String] as? String,
          owner.contains("Agents"),
          let num = w[kCGWindowNumber as String] as? Int,
          let bounds = w[kCGWindowBounds as String] as? [String: Any],
          let h = bounds["Height"] as? Double, h > 200 else { continue }
    print(num)
    exit(0)
}
exit(2)
