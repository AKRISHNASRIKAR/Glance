import AppKit
let root=CommandLine.arguments[1]
for size in [16,32,48,128] {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    let scale=CGFloat(size)/128
    let transform=NSAffineTransform();transform.scale(by:scale);transform.concat()
    NSColor(srgbRed:228/255,green:236/255,blue:227/255,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:4,y:4,width:120,height:120),xRadius:30,yRadius:30).fill()
    let forest=NSColor(srgbRed:39/255,green:72/255,blue:53/255,alpha:1)
    forest.setStroke()
    let frame=NSBezierPath(roundedRect:NSRect(x:27,y:27,width:74,height:74),xRadius:16,yRadius:16)
    frame.lineWidth=8;frame.stroke()
    forest.setFill()
    NSBezierPath(roundedRect:NSRect(x:49,y:83,width:30,height:20),xRadius:6,yRadius:6).fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"\(root)/outline-\(size).png"))
}
