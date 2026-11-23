import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
  as? [[String: Any]] ?? []
let tunaWindows = windows.filter { $0[kCGWindowOwnerName as String] as? String == "Tuna" }
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: tunaWindows))
