#!/usr/bin/env swift
// gen_icon.swift — generates AppIcon.icns for ClipHistory
import AppKit

guard CommandLine.arguments.count > 1 else { exit(1) }
let outPath = CommandLine.arguments[1]

let size: CGFloat = 512
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// Blue rounded-rect background
let rect = NSRect(x: 14, y: 14, width: 484, height: 484)
let path = NSBezierPath(roundedRect: rect, xRadius: 88, yRadius: 88)
NSColor(red: 0.18, green: 0.48, blue: 0.96, alpha: 1.0).setFill()
path.fill()

// Subtle inner shadow / highlight
let inner = NSBezierPath(roundedRect: NSRect(x: 18, y: 18, width: 476, height: 476), xRadius: 82, yRadius: 82)
NSColor(white: 1.0, alpha: 0.08).setFill()
inner.fill()

// Clipboard emoji centered
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 310)
]
let s = NSAttributedString(string: "📋", attributes: attrs)
let sz = s.size()
s.draw(at: NSPoint(x: (size - sz.width) / 2, y: (size - sz.height) / 2 + 14))

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep  = NSBitmapImageRep(data: tiff),
      let png  = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
