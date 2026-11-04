// Renders the 1024x1024 app icon. Usage: swift scripts/make_icon.swift out.png
import AppKit
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let colors = [NSColor(red: 0.16, green: 0.47, blue: 0.98, alpha: 1).cgColor,
              NSColor(red: 0.36, green: 0.22, blue: 0.86, alpha: 1).cgColor] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
// NAS box
NSColor.white.withAlphaComponent(0.95).setFill()
let box = NSBezierPath(roundedRect: NSRect(x: 232, y: 170, width: 560, height: 250), xRadius: 56, yRadius: 56)
box.fill()
NSColor(red: 0.26, green: 0.35, blue: 0.92, alpha: 1).setFill()
for i in 0..<3 { NSBezierPath(ovalIn: NSRect(x: 300 + Double(i) * 70, y: 270, width: 46, height: 46)).fill() }
NSBezierPath(roundedRect: NSRect(x: 560, y: 278, width: 170, height: 30), xRadius: 15, yRadius: 15).fill()
// Arrow
NSColor.white.setFill()
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 512, y: 880))
arrow.line(to: NSPoint(x: 720, y: 660))
arrow.line(to: NSPoint(x: 590, y: 660))
arrow.line(to: NSPoint(x: 590, y: 480))
arrow.line(to: NSPoint(x: 434, y: 480))
arrow.line(to: NSPoint(x: 434, y: 660))
arrow.line(to: NSPoint(x: 304, y: 660))
arrow.close()
arrow.fill()
img.unlockFocus()
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
