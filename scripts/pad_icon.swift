import Foundation
import AppKit
import CoreGraphics

// scripts/pad_icon.swift
// Usage: swift scripts/pad_icon.swift <input_png> <output_png> <content_size>

guard CommandLine.arguments.count == 4 else {
    print("Usage: swift pad_icon.swift <input.png> <output.png> <content_size>")
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let contentSize = CGFloat(Double(CommandLine.arguments[3]) ?? 824)
let targetSize: CGFloat = 1024

guard let inputImage = NSImage(contentsOfFile: inputPath) else {
    print("Error: Could not load input image at \(inputPath)")
    exit(1)
}

// Convert NSImage to CGImage
var imageRect = NSRect(x: 0, y: 0, width: inputImage.size.width, height: inputImage.size.height)
guard let cgImage = inputImage.cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else {
    print("Error: Could not create CGImage")
    exit(1)
}

// Create transparent context
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil,
                              width: Int(targetSize),
                              height: Int(targetSize),
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("Error: Could not create CGContext")
    exit(1)
}

// Draw centered
let padding = (targetSize - contentSize) / 2
let drawRect = CGRect(x: padding, y: padding, width: contentSize, height: contentSize)
context.draw(cgImage, in: drawRect)

guard let outputCGImage = context.makeImage() else {
    print("Error: Could not create output CGImage")
    exit(1)
}

let bitmapRep = NSBitmapImageRep(cgImage: outputCGImage)
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    print("Error: Could not create PNG data")
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Successfully created padded icon: \(outputPath) (Content size: \(contentSize))")
} catch {
    print("Error writing file: \(error)")
}
