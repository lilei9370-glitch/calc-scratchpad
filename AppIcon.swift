import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func icon(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    let base = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 184, cornerHeight: 184, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x152954, alpha: 0.24))
    context.addPath(base)
    context.setFillColor(color(0x244CA4))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(base)
    context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [color(0x527FDE), color(0x244CA4)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 245, y: 924),
                               end: CGPoint(x: 795, y: 100),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    let sheet = CGPath(roundedRect: CGRect(x: 313, y: 274, width: 398, height: 476),
                       cornerWidth: 72, cornerHeight: 72, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -13), blur: 24, color: color(0x102E71, alpha: 0.33))
    context.addPath(sheet)
    context.setFillColor(color(0xF6F9FF))
    context.fillPath()
    context.restoreGState()

    for (rect, fill) in [
        (CGRect(x: 393, y: 632, width: 132, height: 26), color(0xA4B9E9)),
        (CGRect(x: 393, y: 570, width: 238, height: 22), color(0xCCD9F3)),
        (CGRect(x: 423, y: 451, width: 178, height: 42), color(0x335FC3)),
        (CGRect(x: 423, y: 375, width: 178, height: 42), color(0x335FC3)),
    ] {
        let radius = rect.height / 2
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(fill)
        context.fillPath()
    }
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try icon(size: size).write(to: output.appending(path: "icon_\(size)x\(size).png"))
    try icon(size: size * 2).write(to: output.appending(path: "icon_\(size)x\(size)@2x.png"))
}
