// Renders an SVG onto a transparent square canvas.
// usage: swift rasterize.swift <in.svg> <out.png> <canvasPx>
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let canvas = Int(args[3]),
      let image = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: rasterize.swift in.svg out.png canvasPx\n".utf8))
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(canvas), height: CGFloat(canvas)))
NSGraphicsContext.current = nil

try rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: args[2]))
