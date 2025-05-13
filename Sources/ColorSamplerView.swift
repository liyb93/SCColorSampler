//
//  ColorSamplerView.swift
//
//
//  Created by Daniel Capra on 29/10/2023.
//

import AppKit
import Foundation
import struct SwiftUI.Binding

internal class ColorSamplerView: NSView {
    var zoom: Binding<SCColorSamplerConfiguration.ZoomValue?>!
    var image: Binding<CGImage?>!
    var loupeColor: Binding<NSColor>!
    
    var config: SCColorSamplerConfiguration!
    var frameRect: NSRect!
    
    init(
        frame frameRect: NSRect,
        zoom: Binding<SCColorSamplerConfiguration.ZoomValue?>,
        image: Binding<CGImage?>,
        loupeColor: Binding<NSColor>,
        config: SCColorSamplerConfiguration
    ) {
        self.zoom = zoom
        self.image = image
        self.loupeColor = loupeColor
        self.config = config
        self.frameRect = frameRect
        super.init(
            frame: frameRect
        )
    }
    
    private func getUserViewFrame() -> NSRect {
        let windowFrame = self.window!.frame
        var size: CGSize = config.loupeSize.getSize()
        let originOffset = config.loupeFollowMode == .noBlock ? config.padding : 0
        var origin: CGPoint = .init(x: self.frameRect.origin.x + config.padding, y: self.frameRect.origin.y + originOffset)
        return .init(origin: origin, size: size)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    private var currentContext: CGContext? {
        NSGraphicsContext.current?.cgContext
    }
    
    override func draw(_: NSRect) {
        guard let context = currentContext else {
            // Weird ??
            fatalError()
        }
        let quality = config.quality
        let shape = config.loupeShape
        let windowRect: NSRect = window!.frame
        
        // User specified region
        // 这个 rect 是放大镜的绘画区域，它的坐标系是相对于这个view本身，因此它的原点不是零点，而是（P, P）, P=config.padding
        let rect: NSRect = .init(origin: .init(x: config.padding, y: config.padding), size: config.loupeSize.getSize())
        
        // 以下debug信息非常重要，保留
//        print("window frame \(self.window!.frame.debugDescription)")
//        print("view frame \(self.frame.debugDescription)")
//        print("draw zone: \(rect.debugDescription)")
//        
//        // Invisible window for debug
//        context.setLineWidth(4.0)
//        context.setStrokeColor(CGColor(red: 255, green: 0, blue: 0, alpha: 1))
//        var shape1: SCColorSamplerConfiguration.LoupeShape = .rect
//        context.addPath(shape1.path(in: rect))
//        context.strokePath()
//        
//        // Inviisible bounds window for debug
//        context.setLineWidth(4.0)
//        context.setStrokeColor(CGColor(red: 0, green: 255, blue: 0, alpha: 1))
//        var shape2: SCColorSamplerConfiguration.LoupeShape = .rect
//        context.addPath(shape2.path(in: self.bounds))
//        context.strokePath()
//        
//        // Inviisible Out window for debug
//        context.setLineWidth(4.0)
//        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 255, alpha: 1))
//        var shape3: SCColorSamplerConfiguration.LoupeShape = .rect
//        context.addPath(shape3.path(in: windowRect))
//        context.strokePath()
        // 以上debug信息非常重要，保留
        
        // mask
        let path = shape.path(in: rect)
        context.addPath(path)
        context.clip()
        
        guard let image = self.image.wrappedValue,
              let zoom = self.zoom.wrappedValue else {
            return
        }
        
        // draw image
        let width: CGFloat = rect.width
        let height: CGFloat = rect.height
        
        context.setRenderingIntent(.relativeColorimetric)
        context.interpolationQuality = .none
        context.draw(image, in: rect)
        
        // Get dimensions
        let apertureSize: CGFloat = zoom.getApertureSize()
        
        // 孔径位置
        let x: CGFloat = (self.frameRect.width / 2.0) - (apertureSize / 2.0)
        let y: CGFloat = (self.frameRect.height / 2.0) - (apertureSize / 2.0)
        
        // Square pattern
        let replicatorLayer = CAReplicatorLayer()
        
        let square = CALayer()
        let squareSize = zoom.getSquarePatternSize()
        let squareDisplacement = zoom.getSquarePatternDisplacement()
        square.borderWidth = 0.5
        square.borderColor = .black.copy(alpha: 0.05)
        square.frame = CGRect(x: x - (squareSize * 25),
                              y: y - (squareSize * 25),
                              width: squareSize,
                              height: squareSize)
        
        let instanceCount: Double = 50

        replicatorLayer.instanceCount = Int(instanceCount)
        replicatorLayer.instanceTransform = CATransform3DMakeTranslation(squareSize, squareDisplacement, 0)
        
        replicatorLayer.addSublayer(square)
        
        let outerReplicatorLayer = CAReplicatorLayer()
        
        outerReplicatorLayer.addSublayer(replicatorLayer)
        
        outerReplicatorLayer.instanceCount = Int(instanceCount)
        outerReplicatorLayer.instanceTransform = CATransform3DMakeTranslation(squareDisplacement, squareSize, 0)
        
        outerReplicatorLayer.render(in: context)
        
        // Draw inner rectangle
        let apertureRect = CGRect(x: x, y: y, width: apertureSize, height: apertureSize)
        context.setLineWidth(zoom.getApertureLineWidth())
        context.setStrokeColor(loupeColor.wrappedValue.cgColor)
//        context.setStrokeColor(CGColor(red: 255, green: 0, blue: 0, alpha: 1))
        context.setShouldAntialias(false)
        context.stroke(apertureRect.insetBy(dx: zoom.getInsetAmount(), dy: zoom.getInsetAmount()))
        
        // Stroke outer rectangle
        context.setShouldAntialias(true)
        context.setLineWidth(4.0)
        context.setStrokeColor(loupeColor.wrappedValue.cgColor)
        //context.setStrokeColor(CGColor(red: 0, green: 255, blue: 0, alpha: 1))
        context.addPath(path)
        context.strokePath()
    }
}
