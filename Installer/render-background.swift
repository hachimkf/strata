import AppKit
// Installer background: Strata's red-orange folder, peeking from the bottom-left corner behind the step list.
// Usage: swift render-background.swift <icon-source.png> <out.png> <dark: 0|1>
let args = CommandLine.arguments
let art = NSImage(contentsOfFile: args[1])!
let dark = args[3] == "1"
let W = 1240, H = 836   // @2x of the 620 × 418 Installer pane
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: 620, height: 418)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
let orange = NSColor(srgbRed: 0.98, green: 0.27, blue: 0.16, alpha: 1)
let pink = NSColor(srgbRed: 0.99, green: 0.79, blue: 0.86, alpha: 1)
// Big tilted folder in the corner.
let ctx = NSGraphicsContext.current!.cgContext
ctx.saveGState()
ctx.translateBy(x: -26, y: -36)
ctx.scaleBy(x: 0.52, y: 0.52)
ctx.rotate(by: 0.12)
let body = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 300, height: 210), xRadius: 34, yRadius: 34)
let tab = NSBezierPath(roundedRect: NSRect(x: 0, y: 160, width: 130, height: 80), xRadius: 28, yRadius: 28)
orange.withAlphaComponent(dark ? 0.95 : 1).setFill()
tab.fill(); body.fill()
// A pink sheet sliding out of it.
ctx.saveGState()
ctx.rotate(by: -0.2)
pink.setFill()
NSBezierPath(roundedRect: NSRect(x: 120, y: 190, width: 130, height: 150), xRadius: 18, yRadius: 18).fill()
ctx.restoreGState()
orange.setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 300, height: 190), xRadius: 34, yRadius: 34).fill()
ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
