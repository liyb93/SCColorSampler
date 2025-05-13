//
//  ColorSamplerWindow.swift
//  
//
//  Created by Daniel Capra on 29/10/2023.
//

import AppKit
import Foundation
import struct SwiftUI.Binding
import Carbon.HIToolbox
import ScreenCaptureKit

internal class ColorSamplerWindow: NSWindow {
    // Override NSWindow properties
    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    // Stored properties
    private var image: CGImage?
    private var croppedImageBinding: Binding<CGImage?>!
    
    private var zoom: SCColorSamplerConfiguration.ZoomValue?
    private var zoomBinding: Binding<SCColorSamplerConfiguration.ZoomValue?>!
    
    private var loupeColor: NSColor = .white
    private var loupeColorBinding: Binding<NSColor>!
    
    private var currentlySampledColor: NSColor?
    private var currentlySampledColorBinding: Binding<NSColor?>!
    
    private var colorDescriptionBinding: Binding<String?>!
    
    private var childWindow: NSWindow?
        
    let captureEngine = CaptureEngine()
    
    private var activeDisplay: NSScreen? {
        didSet {
            updateStreamConfiguration()
        }
    }
    
    // Computed properties
    private var unwrappedDelegate: ColorSamplerDelegate {
        // Force unwrapped because it is a requirement in the init so it's impossible for it to not be there
        self.delegate! as! ColorSamplerDelegate
    }
        
    // Init
    init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool,
        delegate: ColorSamplerDelegate
    ) {
        super.init(contentRect: contentRect,
                   styleMask: style,
                   backing: backingStoreType,
                   defer: flag
        )
        // NSWindow properties
        self.delegate = delegate
        self.isOpaque = false
        self.backgroundColor = .init(red: 1, green: 1, blue: 1, alpha: 0.001) // 让隐形窗口不可见，但是不能透传点击事件到底部
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        // Start stream
        Task {
            await startStream()
        }
        // Define bindings
        self.croppedImageBinding = Binding<CGImage?>(get: {
            guard let image = self.image else { return nil }
            return self.cutImageAroundPosition(NSEvent.mouseLocation, image: image)
        }, set: { _ in })
        
        self.zoomBinding = Binding<SCColorSamplerConfiguration.ZoomValue?>(get: {
            guard let delegate = self.delegate as? ColorSamplerDelegate else {
                return nil
            }
            
            if self.zoom == nil {
                self.zoom = delegate.config.defaultZoomValue
            }
            
            return self.zoom
        }, set: { _ in })
        
        self.loupeColorBinding = Binding<NSColor>(get: {
            self.loupeColor
        }, set: { _ in })
        
        self.currentlySampledColorBinding = Binding<NSColor?>(get: {
            guard self.croppedImageBinding.wrappedValue != nil else {
                return nil
            }
            return self.currentlySampledColor
        }, set: { _ in })
        
        self.colorDescriptionBinding = Binding<String?>(get: {
            guard self.croppedImageBinding.wrappedValue != nil else {
                return nil
            }
            guard let color = self.currentlySampledColor else {
                return nil
            }
            
            let description = self.unwrappedDelegate.config.colorDescriptionMethod(color)
            return description
        }, set: { _ in })
        
        // Check config
        if unwrappedDelegate.config.showColorDescription {
            // Define child window (color string description)
            self.childWindow = ColorDescriptionWindow(
                contentRect: .init(
                    origin: .init(
                        x: self.frame.midX - 50,
                        y: self.frame.minY - 35 + delegate.config.padding // 实时颜色的位置根据用户可见区域计算
                    ),
                    size: .init(
                        width: 100,
                        height: 25)
                ),
                styleMask: .borderless,
                backing: .buffered,
                defer: true
            )
            
            self.addChildWindow(self.childWindow!, ordered: .below)
        }
    }
    
    /// This function get user view frame from calculated window frame.
    ///
    /// Be cautious this function should only be used after window frame is set by `getWindowOriginPoint`
    private func getUserViewSize() -> CGSize {
        return unwrappedDelegate.config.loupeSize.getSize()
    }
    
    // Get origin point(zero point) of the rectangle area(loupe)
    private func getWindowOriginPoint(_ position: NSPoint, _ display: NSScreen) -> NSPoint {
        let displayOrigin = display.frame.origin
        // should minus display origin point for multiple displays
        let position = NSPoint(x: position.x - displayOrigin.x, y: position.y - displayOrigin.y)
        let config = unwrappedDelegate.config
        let safeAreaDistance: CGFloat = 10
        
        var origin: NSPoint = .zero
        // 在隐形窗口之内的用户可见区域
        let size: CGSize = getUserViewSize()
        // Need dodge when mouse reach edge of screen, especially bottom and right edge
        switch config.loupeFollowMode {
        case .center:
            origin = .init(x: position.x - self.frame.size.width / 2, y: position.y - (self.frame.size.height / 2))
        case .noBlock:
            if position.x + size.width >= display.frame.width - safeAreaDistance && position.y - size.height <= safeAreaDistance {
                // right and bottom
                origin = .init(
                    x: position.x - self.frame.size.width + config.padding,
                    y: position.y - config.padding
                )
            } else if position.x + size.width >= display.frame.width - safeAreaDistance { // 使用用户可见区域判断
                // right
                origin = .init(
                    x: position.x - self.frame.size.width + config.padding,
                    y: position.y - self.frame.size.height + config.padding - config.loupeFollowDistance // 但是使用窗口大小计算，因为计算的不是可见区域的原点，而是外部窗口的原点
                )
            } else if position.y - size.height <= safeAreaDistance {
                // bottom
                origin = .init(
                    x: position.x - config.padding,
                    y: position.y - config.padding
                )
            } else {
                // top and left
                origin = .init(
                    x: position.x - config.padding + config.loupeFollowDistance,
                    y: position.y - self.frame.size.height + config.padding - config.loupeFollowDistance
                )
            }
        }
        
        // should add origin back cause we want an absolute value caculated base on (0,0)
        return .init(
            x: origin.x + displayOrigin.x,
            y: origin.y + displayOrigin.y
        )
    }
    // Override NSWindow methods
    // 这个方法需要采样窗口一直是key，但是这样其它窗口就会失去焦点，颜色会变，因此不能再用了
    override open func mouseMoved(with event: NSEvent) {
        let position = NSEvent.mouseLocation
        guard let screenWithMouse = NSScreen.screens.first(
            where: { NSMouseInRect(position, $0.frame, false) }
        )
        else {
            // Odd? Mouse not on any screen?
            return
        }
        if self.activeDisplay != screenWithMouse {
            self.activeDisplay = screenWithMouse
        }
        
        let origin: NSPoint = getWindowOriginPoint(position, screenWithMouse)
        self.setFrameOrigin(origin)
        
        if let image = croppedImageBinding.wrappedValue,
           let color = image.colorAtCenter(),
           let delegate = self.delegate as? ColorSamplerDelegate {
            // Change loupe color
            self.loupeColor = color.brightnessComponent > 0.8 ? .black : .white
            if unwrappedDelegate.config.showColorDescription {
                // Change text description background color
                self.currentlySampledColor = color
                self.childWindow?.contentView?.needsDisplay = true
            }
            // Call Handler
            delegate.callMouseMovedHandler(color: color)
        }
        
        let contentView = self.contentView
        contentView?.needsDisplay = true
        
        super.mouseMoved(with: event)
    }
    
//    override open func mouseDown(with event: NSEvent) {
//        if let color = self.croppedImageBinding.wrappedValue?.colorAtCenter(),
//           let delegate = self.delegate as? ColorSamplerDelegate {
//            delegate.callSelectionHandler(color: color)
//        }
//        self.orderOut(self)
//    }
//    
    func finalizeColor() {
//        print("finalize color down")
        if let color = self.croppedImageBinding.wrappedValue?.colorAtCenter(),
           let delegate = self.delegate as? ColorSamplerDelegate {
            delegate.callSelectionHandler(color: color)
        }
        self.orderOut(self)
    }
    
    override open func magnify(with event: NSEvent) {
        guard let delegate = self.delegate as? ColorSamplerDelegate else {
            self.mouseMoved(with: event)
            super.magnify(with: event)
            return
        }
        
        if event.magnification > 0.01 {
            guard let nextZoom = zoom?.getNextZoom(available: delegate.config.zoomValues) else {
                return
            }
            zoom = nextZoom
        } else if event.magnification < -0.01 {
            guard let previousZoom = zoom?.getPreviousZoom(available: delegate.config.zoomValues) else {
                return
            }
            zoom = previousZoom
        }
        
        self.mouseMoved(with: event)
        super.magnify(with: event)
    }
    
    override func scrollWheel(with event: NSEvent) {
        guard let delegate = self.delegate as? ColorSamplerDelegate else {
            self.mouseMoved(with: event)
            super.magnify(with: event)
            return
        }
        
        let deltaY = delegate.config.zoomWheelInverse ? -event.scrollingDeltaY : event.scrollingDeltaY
        
        if deltaY < -1 {
            guard let nextZoom = zoom?.getNextZoom(available: delegate.config.zoomValues) else {
                return
            }
            zoom = nextZoom
        } else if deltaY > 1 {
            guard let previousZoom = zoom?.getPreviousZoom(available: delegate.config.zoomValues) else {
                return
            }
            zoom = previousZoom
        }
        
        self.mouseMoved(with: event)
        super.scrollWheel(with: event)
    }
    
    func cancel() {
        if let delegate = self.delegate as? ColorSamplerDelegate {
            delegate.callSelectionHandler(color: nil)
        }
        self.orderOut(self)
    }
    
    // 取消置顶后，这里的keydonw就不能用了
//    override func keyDown(with event: NSEvent) {
//        if event.keyCode == kVK_Escape {
//            if let delegate = self.delegate as? ColorSamplerDelegate {
//                delegate.callSelectionHandler(color: nil)
//            }
//            self.orderOut(self)
//        }
//    }
}

extension ColorSamplerWindow {
    // ScreenCaptureKit methods
    func startStream() async {
        do {
            guard let config = await streamConfiguration() else {
                return
            }
            guard let filter = await contentFilter() else {
                return
            }
            // Start the stream and await new video frames.
            for try await frame in captureEngine.startCapture(configuration: config, filter: filter) {
                if image == nil {
                    // Initialize contentView on the receival of the first frame
                    // Afterwards it will only be updated on mouse movements
                    image = frame
                    guard let delegate = self.delegate as? ColorSamplerDelegate else {
                        return
                    }
                    if let image = croppedImageBinding.wrappedValue,
                       let color = image.colorAtCenter() {
                        // Change loupe color
                        self.loupeColor = color.brightnessComponent > 0.8 ? .black : .white
                        // Change text description background color
                        self.currentlySampledColor = color
                    }
                    let contentView = ColorSamplerView(
                        frame: self.frame,
                        zoom: zoomBinding,
                        image: croppedImageBinding,
                        loupeColor: loupeColorBinding,
                        config: delegate.config
                    )
                    self.contentView = contentView
                    if unwrappedDelegate.config.showColorDescription {
                        let windowFrameWidthBinding = Binding<CGFloat?>(get: {
                            self.childWindow?.frame.width
                        }, set: {
                            let newWidth = $0 ?? 100
                            self.childWindow?.setFrame(
                            NSRect.init(
                                origin: .init(
                                    x: self.frame.midX - newWidth / 2,
                                    y: self.frame.minY - 35 + delegate.config.padding
                                ),
                                size: .init(
                                    width: newWidth,
                                    height: 25)
                            ),
                            display: true
                        )})
                        self.childWindow?.contentView = ColorDescriptionView(
                            frame: self.frame,
                            textColor: loupeColorBinding,
                            currentlySampledColor: currentlySampledColorBinding,
                            colorDescription: colorDescriptionBinding,
                            windowFrameWidthBinding: windowFrameWidthBinding
                        )
                    }
                } else {
                    image = frame
                }
            }
        } catch {
            self.unwrappedDelegate.callSelectionHandler(color: nil)
        }
    }
    
    private func streamConfiguration() async -> SCStreamConfiguration? {
        let config = SCStreamConfiguration()
        
        guard let content = try? await SCShareableContent.current else {
            return nil
        }
        
        guard let display = content.displays.first(where:{
            $0.displayID == activeDisplay?.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
        }) else { return nil }
        
        let delegate = unwrappedDelegate
        
        config.width = Int(CGFloat(display.width) * delegate.config.quality.getMultiplier())
        config.height = Int(CGFloat(display.height) * delegate.config.quality.getMultiplier())
        
        config.showsCursor = false

        return config
    }
    
    private func contentFilter() async -> SCContentFilter? {
        guard let content = try? await SCShareableContent.current else {
            return nil
        }
        
        guard let display = content.displays.first(where:{
            $0.displayID == activeDisplay?.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
        }) else { return nil }
        
        let excludedWindows = content.windows.filter {
            if unwrappedDelegate.config.showColorDescription,
                let childWindow = self.childWindow {
                $0.windowID == CGWindowID(self.windowNumber) ||
                $0.windowID == CGWindowID(childWindow.windowNumber)
            } else {
                $0.windowID == CGWindowID(self.windowNumber)
            }
        }
        
        let filter = SCContentFilter(display: display,
                                     excludingWindows: excludedWindows)
        
        return filter
    }
}

internal extension ColorSamplerWindow {
    // Helper Functions
    func stopStream() {
        Task {
            await captureEngine.stopCapture()
        }
    }
    
    func updateStreamConfiguration() {
        Task {
            guard let newConfig = await streamConfiguration(),
            let newFilter = await contentFilter() else {
                return
            }
            await captureEngine.updateConfiguration(
                newConfig: newConfig,
                newFilter: newFilter
            )
        }
    }
    
    func cutImageAroundPosition(_ position: NSPoint, image: CGImage) -> CGImage? {
        let delegate = self.unwrappedDelegate
        
        guard let display = self.activeDisplay else { return nil }
                                
        if self.zoom == nil {
            self.zoom = delegate.config.defaultZoomValue
        }
                    
        var captureSize: CGFloat = round(
            round(
                delegate.config.loupeSize.getSize().width / self.zoom!.getPixelZoom(quality: delegate.config.quality)
            ) * delegate.config.quality.getMultiplier()
        )
        
        if captureSize.truncatingRemainder(dividingBy: 2) != 0 { captureSize += 1 }
        
        let loupeSize = delegate.config.loupeSize.getSize()
        let captureSizeY = captureSize * loupeSize.height / loupeSize.width
        
        let x = (position.x - display.frame.origin.x) * delegate.config.quality.getMultiplier()
        let y = (display.frame.height - (position.y - display.frame.origin.y)) * delegate.config.quality.getMultiplier()
        
        let captureRect = NSRect(
            x: x - (captureSize / 2),
            y: y - (captureSizeY / 2),
            width: captureSize,
            height: captureSizeY
        )
                        
        guard let croppedImage = image.cropping(to: captureRect) else {
            return nil
        }
        
        return croppedImage
    }
}
