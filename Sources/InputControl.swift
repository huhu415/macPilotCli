import AppKit
import ApplicationServices
import Foundation

let eventFlagDictionary: [String: CGEventFlags] = [
    "alphaShift": .maskAlphaShift,
    "shift": .maskShift,
    "control": .maskControl,
    "option": .maskAlternate,
    "command": .maskCommand,
    "help": .maskHelp,
    "secondaryFn": .maskSecondaryFn,
    "numericPad": .maskNumericPad,
    "nonCoalesced": .maskNonCoalesced,
]

// https://gist.github.com/eegrok/949034
// Comprehensive mapping of virtual key codes for Mac QWERTY layout
enum VirtualKeyCode: CGKeyCode, CaseIterable {
    // Letters
    case a = 0x00
    case s = 0x01
    case d = 0x02
    case f = 0x03
    case h = 0x04
    case g = 0x05
    case z = 0x06
    case x = 0x07
    case c = 0x08
    case v = 0x09
    case sectionKey = 0x0A // Section (ISO layout)
    case b = 0x0B
    case q = 0x0C
    case w = 0x0D
    case e = 0x0E
    case r = 0x0F

    // More letters and numbers
    case y = 0x10
    case t = 0x11
    case one = 0x12
    case two = 0x13
    case three = 0x14
    case four = 0x15
    case six = 0x16
    case five = 0x17
    case equals = 0x18
    case nine = 0x19
    case seven = 0x1A
    case minus = 0x1B
    case eight = 0x1C
    case zero = 0x1D
    case rightBracket = 0x1E
    case o = 0x1F

    // More characters and symbols
    case u = 0x20
    case leftBracket = 0x21
    case i = 0x22
    case p = 0x23
    case returnKey = 0x24
    case l = 0x25
    case j = 0x26
    case quote = 0x27
    case k = 0x28
    case semicolon = 0x29
    case backslash = 0x2A
    case comma = 0x2B
    case forwardSlash = 0x2C
    case n = 0x2D
    case m = 0x2E
    case period = 0x2F

    // Special keys
    case tab = 0x30
    case space = 0x31
    case tilde = 0x32
    case delete = 0x33
    case powerBookEnter = 0x34
    case escape = 0x35
    case rightCommand = 0x36
    case command = 0x37
    case shift = 0x38
    case capsLock = 0x39
    case option = 0x3A
    case control = 0x3B
    case rightShift = 0x3C
    case rightOption = 0x3D
    case rightControl = 0x3E
    case function = 0x3F

    // Function and special keys
    case f17 = 0x40
    case keypadDecimal = 0x41
    case keypadMultiply = 0x43
    case keypadPlus = 0x45
    case numLock = 0x47
    case volumeUp = 0x48
    case volumeDown = 0x49
    case mute = 0x4A
    case keypadDivide = 0x4B
    case keypadEnter = 0x4C
    case keypadMinus = 0x4E
    case f18 = 0x4F

    // More function and keypad keys
    case f19 = 0x50
    case keypadEquals = 0x51
    case keypad0 = 0x52
    case keypad1 = 0x53
    case keypad2 = 0x54
    case keypad3 = 0x55
    case keypad4 = 0x56
    case keypad5 = 0x57
    case keypad6 = 0x58
    case keypad7 = 0x59
    case f20 = 0x5A
    case keypad8 = 0x5B
    case keypad9 = 0x5C
    case yen = 0x5D // JIS layout
    case underscore = 0x5E // JIS layout
    case keypadComma = 0x5F // JIS layout

    // Function keys
    case f5 = 0x60
    case f6 = 0x61
    case f7 = 0x62
    case f3 = 0x63
    case f8 = 0x64
    case f9 = 0x65
    case eisu = 0x66 // JIS layout
    case f11 = 0x67
    case kana = 0x68 // JIS layout
    case f13 = 0x69
    case f16 = 0x6A
    case f14 = 0x6B
    case f10 = 0x6D
    case menu = 0x6E
    case f12 = 0x6F

    // Navigation and additional function keys
    case f15 = 0x71
    case help = 0x72
    case home = 0x73
    case pageUp = 0x74
    case forwardDelete = 0x75
    case f4 = 0x76
    case end = 0x77
    case f2 = 0x78
    case pageDown = 0x79
    case f1 = 0x7A
    case leftArrow = 0x7B
    case rightArrow = 0x7C
    case downArrow = 0x7D
    case upArrow = 0x7E
    case power = 0x7F

    static func fromString(str: String) -> VirtualKeyCode? {
        // 直接通过枚举名称匹配
        return VirtualKeyCode.allCases.first {
            String(describing: $0) == str
        }
    }
}

class InputControl {
    // 获取当前鼠标位置, 原点在左上角, Quartz坐标系
    static func getCurrentMousePosition() -> CGPoint {
        let point = NSEvent.mouseLocation

        // 获取主屏幕的高度
        let screenHeight = NSScreen.main?.frame.size.height ?? 0

        // 转换坐标系：y坐标从底部向上变为从顶部向下
        let convertedPoint = NSPoint(x: point.x, y: screenHeight - point.y)

        return convertedPoint
    }

    // 移动鼠标到指定位置
    static func moveMouse(to point: CGPoint) {
        let moveEvent = CGEvent(
            mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left
        )
        moveEvent?.post(tap: .cghidEventTap)
    }

    // 模拟鼠标点击（新增 button 参数，默认左键）
    static func mouseClick(
        at point: CGPoint, button: CGMouseButton = .left, clickCount: Int = 1
    ) {
        // 根据按钮类型选择对应的事件类型
        let downEventType: CGEventType =
            (button == .left) ? .leftMouseDown : .rightMouseDown
        let upEventType: CGEventType =
            (button == .left) ? .leftMouseUp : .rightMouseUp

        // 循环执行点击次数
        for _ in 0 ..< clickCount {
            let clickDown = CGEvent(
                mouseEventSource: nil,
                mouseType: downEventType,
                mouseCursorPosition: point,
                mouseButton: button
            )
            let clickUp = CGEvent(
                mouseEventSource: nil,
                mouseType: upEventType,
                mouseCursorPosition: point,
                mouseButton: button
            )

            clickDown?.post(tap: .cghidEventTap)
            clickUp?.post(tap: .cghidEventTap)
        }
    }

    // 模拟鼠标滚动
    static func scrollMouse(deltaHorizontal: Int32, deltaVertical: Int32) {
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel, // 或使用 .line
            wheelCount: 2, // 使用两个维度
            wheel1: deltaVertical, // 垂直方向
            wheel2: deltaHorizontal, // 水平方向
            wheel3: 0 // 不旋转
        )

        scrollEvent?.post(tap: .cghidEventTap)
    }

    // 模拟键盘按键
    static func pressKey(keyCode: CGKeyCode) {
        let keyDown = CGEvent(
            keyboardEventSource: nil, virtualKey: keyCode, keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: nil, virtualKey: keyCode, keyDown: false
        )

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // 模拟组合按键（如 Command + C）
    static func pressKeys(modifiers: CGEventFlags, keyCodes: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)

        // 创建按键事件，并设置修饰键
        let keyDown = CGEvent(
            keyboardEventSource: source, virtualKey: keyCodes, keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: source, virtualKey: keyCodes, keyDown: false
        )

        // 设置修饰键标志
        keyDown?.flags = modifiers
        keyUp?.flags = modifiers

        // 发送事件
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
