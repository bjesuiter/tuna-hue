import Darwin
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 4 else { exit(2) }
let staged = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
let dimensionsBySlug: [String: (Int, Int)] = [
  "bridge-connected": (744, 608),
  "check-connection": (1584, 1652),
  "choose-bridge": (1128, 968),
  "disconnect-bridge": (744, 692),
  "find-hue-command": (1584, 1652),
  "manage-bridges": (1008, 712),
  "manual-connection": (928, 1172),
  "press-link-button": (1128, 976),
  "turn-off": (1584, 1652),
  "turn-on": (960, 495),
]

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

let order = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
  .split(whereSeparator: \.isNewline).map(String.init)
guard order.count == dimensionsBySlug.count, Set(order) == Set(dimensionsBySlug.keys) else {
  fail("The screenshot order must list each known state exactly once.")
}

let appearances = ["light", "dark"]
let captures = order.enumerated().flatMap { index, slug in
  appearances.map { appearance in
    (name: String(format: "%02d", index + 1) + "-\(slug)-\(appearance).png", slug: slug)
  }
}
let expectedNames = Set(captures.map(\.name))
let legacyNames = Set(order.map { "\($0).png" })
let stagedNames = Set(try FileManager.default.contentsOfDirectory(atPath: staged))
let destinationNames = Set(try FileManager.default.contentsOfDirectory(atPath: destination))
guard stagedNames == expectedNames else {
  fail("Unexpected staged file set. Expected \(expectedNames.sorted().joined(separator: ", ")).")
}
guard destinationNames == expectedNames || destinationNames == legacyNames else {
  fail("Unexpected file set in \(destination).")
}

for (name, slug) in captures {
  let dimensions = dimensionsBySlug[slug]!
  let url = URL(fileURLWithPath: staged, isDirectory: true).appendingPathComponent(name)
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        CGImageSourceGetType(source) as String? == "public.png",
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("Cannot decode \(name) as PNG.")
  }
  if (image.width, image.height) == dimensions { continue }

  let framed: CGImage?
  if slug == "turn-on", image.width == 1584, [720, 1652].contains(image.height) {
    // Keep the launcher tiles at the same offset as the original close-up.
    framed = image.cropping(to: CGRect(x: 309, y: 108, width: 960, height: 495))
  } else if (image.width + 224, image.height + 224) == dimensions,
            let canvas = CGContext(
              data: nil, width: dimensions.0, height: dimensions.1,
              bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
    // Classic capture omits the desktop shadow around native alerts.
    canvas.draw(image, in: CGRect(x: 112, y: 148, width: image.width, height: image.height))
    framed = canvas.makeImage()
  } else {
    framed = nil
  }

  guard let framed, (framed.width, framed.height) == dimensions,
        let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fail("\(name) is \(image.width) × \(image.height); expected \(dimensions.0) × \(dimensions.1).")
  }
  CGImageDestinationAddImage(output, framed, nil)
  guard CGImageDestinationFinalize(output) else { fail("Cannot write \(name).") }
}

guard renamex_np(staged, destination, UInt32(RENAME_SWAP)) == 0 else {
  fail("Could not exchange the screenshot directories: \(String(cString: strerror(errno))).")
}
