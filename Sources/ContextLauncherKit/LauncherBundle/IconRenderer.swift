import AppKit
import Foundation

public enum IconRendererError: Error {
    case invalidCustomImage(String)
    case iconConversionFailed
}

public struct IconRenderer {
    public init() {}

    public func render(_ icon: ContextIcon, destination: URL) throws {
        let image: NSImage
        switch icon {
        case .symbol(let name):
            image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(systemSymbolName: "folder", accessibilityDescription: nil)!
        case .custom(let path):
            guard let loaded = NSImage(contentsOf: URL(fileURLWithPath: path)) else {
                throw IconRendererError.invalidCustomImage(path)
            }
            image = loaded
        }

        let fileManager = FileManager.default
        let iconset = destination.deletingLastPathComponent().appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
        try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: iconset) }

        for size in [16, 32, 128, 256, 512] {
            try write(image, pixels: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
            try write(image, pixels: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
        }

        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", "-o", destination.path, iconset.path]
        iconutil.standardError = Pipe()
        try iconutil.run()
        iconutil.waitUntilExit()
        if iconutil.terminationStatus != 0 {
            try writeICNSFallback(from: iconset.appendingPathComponent("icon_512x512@2x.png"), to: destination)
        }
    }

    private func write(_ image: NSImage, pixels: Int, to destination: URL) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw IconRendererError.iconConversionFailed }
        bitmap.size = NSSize(width: pixels, height: pixels)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: bitmap.size).fill()
        image.draw(in: NSRect(origin: .zero, size: bitmap.size), from: .zero, operation: .sourceOver, fraction: 1)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw IconRendererError.iconConversionFailed
        }
        try data.write(to: destination)
    }

    private func writeICNSFallback(from imageURL: URL, to destination: URL) throws {
        let image = try Data(contentsOf: imageURL)
        var data = Data("icns".utf8)
        data.append(length(image.count + 16))
        data.append(Data("ic10".utf8))
        data.append(length(image.count + 8))
        data.append(image)
        try data.write(to: destination)
    }

    private func length(_ value: Int) -> Data {
        var length = UInt32(value).bigEndian
        return Data(bytes: &length, count: MemoryLayout<UInt32>.size)
    }
}
