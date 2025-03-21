import AppKit
import ApplicationServices
import Foundation

enum KeyCode: CGKeyCode {
    case space = 49
    case returnKey = 36
    case delete = 51
    case escape = 53
    case leftArrow = 123
    case rightArrow = 124
    case upArrow = 126
    case downArrow = 125
    case c = 8
    case v = 9
}

class InputControl {
    // 获取当前鼠标位置
    static func getCurrentMousePosition() -> CGPoint {
        return NSEvent.mouseLocation
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
