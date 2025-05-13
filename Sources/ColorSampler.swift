//
//  ColorSampler.swift
//  
//
//  Created by Daniel Capra on 29/10/2023.
//

import AppKit
import Combine
import Foundation
import ScreenCaptureKit
import struct SwiftUI.Binding
import Carbon.HIToolbox

internal class ColorSampler: NSObject {
    // Properties
    static let shared = ColorSampler()
    
    var colorSamplerWindow: ColorSamplerWindow?
    var configuration: SCColorSamplerConfiguration?
    
    var onMouseMovedHandlerBlock: ((NSColor) -> Void)?
    var selectionHandlerBlock: ((NSColor?) -> Void)?
    var monitors: [Any?] = []
    var isRunning: Bool = false;
    
    // Functions
    func sample(
        onMouseMoved: @escaping (NSColor) -> Void,
        selectionHandler: @escaping (NSColor?) -> Void,
        configuration: SCColorSamplerConfiguration
    ) {
        self.reset()
        self.onMouseMovedHandlerBlock = onMouseMoved
        self.selectionHandlerBlock = selectionHandler
        self.configuration = configuration
        self.show()
    }
    
    private func show() {
        // Should never happen
        guard let configuration = configuration else {
            return
        }
        
        // Make window a little bigger than use specified
        let loupeSize = configuration.loupeSize.getSize()
        let samplerWindowWidth = loupeSize.width + configuration.padding * 2
        let samplerWindowHeight = loupeSize.height + configuration.padding * 2
        
        var windowInit: (
            contentRect: NSRect,
            styleMask: NSWindow.StyleMask,
            backing: NSWindow.BackingStoreType,
            defer: Bool
        ) {
            return (
                NSRect.init(origin: .zero, size: CGSize(width: samplerWindowWidth, height: samplerWindowHeight)),
                NSWindow.StyleMask.borderless,
                NSWindow.BackingStoreType.buffered,
                true
            )
        }
        
        self.colorSamplerWindow = ColorSamplerWindow.init(
            contentRect: windowInit.contentRect,
            styleMask: windowInit.styleMask,
            backing: windowInit.backing,
            defer: windowInit.defer,
            delegate: self
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: self.colorSamplerWindow
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: self.colorSamplerWindow
        )
        addMouseMonitor()
        // 这里有问题，激活放大镜后，其它程序都变灰色了，取色就不对了（已修复）
        // NSApplication.shared.activate(ignoringOtherApps: false)
        self.colorSamplerWindow?.orderFront(self) // 不能变成 key
        self.colorSamplerWindow?.orderedIndex = 0
        // prepare image for window's contentView in advance
        self.colorSamplerWindow?.mouseMoved(with: NSEvent())
        
        self.isRunning = true
        if self.configuration?.loupeFollowMode == .center {
            NSCursor.hide()
        }
    }
    
    func reset() {
        NSCursor.unhide()
        NotificationCenter.default.removeObserver(self)
        if let window = self.colorSamplerWindow {
            window.stopStream()
            window.childWindows?.forEach({ $0.close() })
            window.close()
        }
        self.configuration = nil
        self.colorSamplerWindow = nil
        self.onMouseMovedHandlerBlock = nil
        self.selectionHandlerBlock = nil
    }
    
    func colorSelected() {
        self.isRunning = false
        self.colorSamplerWindow?.finalizeColor()
        self.removeMonitors()
        self.reset()
    }
    
    func cancel() {
        self.isRunning = false
        self.colorSamplerWindow?.cancel()
        self.removeMonitors()
        self.reset()
    }
    
    func addMouseMonitor() {
        
        // 假如鼠标移动过快导致窗口跟不上，需要此函数来找回监听。和键盘相关的全局事件需要辅助功能权限
        // 目前已经将隐形窗口放大（SCColorSamplerConfiguration.padding），这种情况应该很少出现了，如果出现，就需要这里发挥作用
        let global_mouseMoved = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { e in
            self.colorSamplerWindow?.mouseMoved(with: e)
        }
        monitors.append(global_mouseMoved)
        
        let local_mouseExited = NSEvent.addLocalMonitorForEvents(matching: .mouseExited) { e in
            self.colorSamplerWindow?.mouseMoved(with: e)
            return e
        }
        monitors.append(local_mouseExited)
        
        // 该事件只监听除了自身以外的程序，用于在鼠标按下捕获颜色，和键盘相关的全局事件需要辅助功能权限
        let global_mouse_down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { e in
            guard self.isRunning else {
                return
            }
            self.colorSelected()
        }
        monitors.append(global_mouse_down)
        
        // 用于在按下ESC关闭取色窗口，回车取色，和键盘相关的全局事件需要辅助功能权限
        let global_key = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in
            guard self.isRunning else {
                return
            }
            if e.keyCode == kVK_Escape {
                self.cancel()
            }
            if e.keyCode == kVK_Return {
                self.colorSelected()
            }
        }
        monitors.append(global_key)
         // 鼠标左键取色
        let local_mouse = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            guard self.isRunning else {
                return e
            }
            self.colorSelected()
            return e
        }
        monitors.append(local_mouse)
        
        // 用于在按下ESC关闭取色窗口，回车取色
        let local_key = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard self.isRunning else {
                return e
            }
            if e.keyCode == kVK_Escape {
                self.cancel()
            }
            if e.keyCode == kVK_Return {
                self.colorSelected()
            }
            return e
        }
        monitors.append(local_key)
    }
    
    func removeMonitors() {
        for i in 0 ..< self.monitors.count {
            if let m = self.monitors[i] {
                do {
                    NSEvent.removeMonitor(m)
                } catch {
                }
            }
        }
        // 防止出现 Thread 1: EXC_BAD_ACCESS (code=EXC_I386_GPFLT)
        self.monitors = []
    }
}
