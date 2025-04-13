import AppKit
import Foundation
import JSONSchemaBuilder
import MCPServer
import os

let mcpLogger = Logger(subsystem: "com.macpilot.mcp", category: "mcp")

@Schemable
struct EmptyInput {}

@Schemable
struct MouseControlInput {
    @SchemaOptions(description: "X coordinate for mouse position, omit to use current position")
    let x: String?
    @SchemaOptions(description: "Y coordinate for mouse position, omit to use current position")
    let y: String?
    @SchemaOptions(description: "Click the mouse: left, right, null")
    let clickType: String
}

@Schemable
struct ScrollMouseInput {
    @SchemaOptions(description: "negative for left, positive for right, 0 for no horizontal scroll")
    let horizontal: Int
    @SchemaOptions(description: "negative for down, positive for up, 0 for no vertical scroll")
    let vertical: Int
}

@Schemable
struct PasteInput {
    @SchemaOptions(description: "Text to paste")
    let text: String
}

@Schemable
struct ExecuteCommandInput {
    @SchemaOptions(description: "Command to execute")
    let command: String
}

@Schemable
struct LaunchAppInput {
    @SchemaOptions(description: "Bundle identifier of the application. (choose either this or appName)")
    let bundleId: String?
    @SchemaOptions(description: "Name of the application. (choose either this or bundleId)")
    let appName: String?
}

@Schemable
struct WindowsInfoInput {
    @SchemaOptions(description: "true: only focused window, false: all windows")
    let focusedOnly: Bool
}

@Schemable
struct WindowInfoInput {
    @SchemaOptions(description: "Process ID of the window (recommended to provide both pid and windowNumber, or neither for focused window)")
    let pid: Int?
    @SchemaOptions(description: "Window identifier number (recommended to provide both pid and windowNumber, or neither for focused window)")
    let windowNumber: Int?
}

@MainActor
let tools: [any CallableTool] = [
    Tool(
        name: "getCursorPosition",
        description: "Get the current mouse position in the system, including x, y, screen width, height, and scale"
    ) { (_: EmptyInput) in
        let position = InputControl.getCurrentMousePosition()
        let mainScreen = NSScreen.main
        let response: [String: Any] = [
            "x": position.x,
            "y": position.y,
            "screen": [
                "width": mainScreen?.frame.width as Any,
                "height": mainScreen?.frame.height as Any,
                "scale": mainScreen?.backingScaleFactor as Any,
            ],
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: response, options: .sortedKeys),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            return [.text(.init(text: jsonString))]
        }
        return [.text(.init(text: "获取鼠标位置失败"))]
    },

    Tool(
        name: "controlMouse",
        description: "Move the mouse to the specified absolute position (not relative movement) and optionally click."
    ) { (input: MouseControlInput) in
        // 确定目标位置
        var targetPosition: CGPoint

        // 如果提供了坐标，移动鼠标到指定位置
        if let xStr = input.x, let yStr = input.y,
           let x = Double(xStr), let y = Double(yStr)
        {
            targetPosition = CGPoint(x: x, y: y)
            InputControl.moveMouse(to: targetPosition)
        } else {
            // 否则使用当前位置
            targetPosition = InputControl.getCurrentMousePosition()
        }

        // 处理点击
        var mouseButton: CGMouseButton
        var buttonTypeString: String

        switch input.clickType.lowercased() {
        case "right":
            mouseButton = .right
            buttonTypeString = "right-clicked"
        case "left":
            mouseButton = .left
            buttonTypeString = "left-clicked"
        case "null":
            return [.text(.init(text: "Mouse moved to \(targetPosition.x), \(targetPosition.y)"))]
        default:
            return [.text(.init(text: "Invalid click type, please use 'left' or 'right'"))]
        }

        InputControl.mouseClick(at: targetPosition, button: mouseButton)

        if let x = input.x, let y = input.y {
            return [.text(.init(text: "Mouse moved to \(x), \(y) and \(buttonTypeString)"))]
        } else {
            return [.text(.init(text: "Mouse \(buttonTypeString) at current position"))]
        }
    },

    // 增加滚动工具
    Tool(
        name: "scrollMouse",
        description: "Scroll the mouse wheel in the specified direction (relative movement)"
    ) { (input: ScrollMouseInput) in
        InputControl.scrollMouse(deltaHorizontal: Int32(input.horizontal), deltaVertical: Int32(input.vertical))
        return [.text(.init(text: "Mouse scrolled \(input.horizontal), \(input.vertical)"))]
    },

    // 本质是把文本放在剪贴板, 然后按下command+v
    Tool(
        name: "pasteText",
        description: "Paste text by copying it to clipboard and simulating Command+V keystroke"
    ) { (input: PasteInput) in
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(input.text, forType: .string)

        InputControl.pressKeys(modifiers: .maskCommand, keyCodes: KeyCode.v.rawValue)
        return [.text(.init(text: "已粘贴文本"))]
    },

    Tool(
        name: "captureScreen",
        description: "Capture the full screen and return the image data(base64 encoded)"
    ) { (_: EmptyInput) async throws in
        let screenCaptureManager = ScreenCaptureManager()

        let image: Data? = await withCheckedContinuation {
            (continuation: CheckedContinuation<Data?, Never>) in
            mcpLogger.info("Capturing screen...")
            screenCaptureManager.captureFullScreen { capturedImage in
                if let unwrappedImage = capturedImage,
                   let tiffData = unwrappedImage.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmapImage.representation(
                       using: .jpeg, properties: [.compressionFactor: 0.75]
                   )
                {
                    mcpLogger.info("Capturing screen successful")
                    continuation.resume(returning: jpegData)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }

        if image == nil {
            return [.text(.init(text: "Screenshot failed"))]
        }

        return [.image(.init(data: image!.base64EncodedString(), mimeType: "image/jpeg"))]
    },

    Tool(
        name: "shell",
        description: "Executes a shell command in the terminal and returns the command output, exit status, and any error messages"
    ) { (input: ExecuteCommandInput) in
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = input.command.components(separatedBy: .whitespaces)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var response: [String: Any] = [:]

        do {
            try process.run()
            process.waitUntilExit()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            response["exitStatus"] = process.terminationStatus
            response["output"] = String(data: outputData, encoding: .utf8)
            response["error"] = String(data: errorData, encoding: .utf8)
        } catch {
            response["error"] = error.localizedDescription
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: response, options: .sortedKeys),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            return [.text(.init(text: jsonString))]
        }
        return [.text(.init(text: "命令执行失败"))]
    },

    Tool(
        name: "openApp",
        description: "Open an application using either appName or bundleId"
    ) { (input: LaunchAppInput) in
        guard input.bundleId != nil || input.appName != nil else {
            return [.text(.init(text: "错误：必须提供bundleId或appName"))]
        }

        let finalBundleId: String?

        if let bundleId = input.bundleId {
            finalBundleId = bundleId
        } else if let appName = input.appName {
            let apps = getInstalledApplications()
            finalBundleId = apps.first { $0.name.lowercased() == appName.lowercased() }?.bundleId

            guard finalBundleId != nil else {
                return [.text(.init(text: "找不到应用：\(appName)"))]
            }
        } else {
            return [.text(.init(text: "参数无效"))]
        }

        guard
            let appUrl = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: finalBundleId!)
        else {
            return [.text(.init(text: "找不到应用"))]
        }

        NSWorkspace.shared.openApplication(
            at: appUrl,
            configuration: NSWorkspace.OpenConfiguration()
        )

        return [.text(.init(text: "已启动应用"))]
    },

    Tool(
        name: "listApps",
        description: "List all installed applications with their appName and bundleId"
    ) { (_: EmptyInput) in
        let apps = getInstalledApplications()
        let appList = apps.map { ["appName": $0.name, "bundleId": $0.bundleId] }

        if let jsonData = try? JSONSerialization.data(withJSONObject: appList, options: .sortedKeys),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            return [.text(.init(text: jsonString))]
        }
        return [.text(.init(text: "获取应用列表失败"))]
    },

    Tool(
        name: "getWindowsInfo",
        description: "Get all windows information. include pid, name, windowID, etc."
    ) { (input: WindowsInfoInput) in
        let accessibilityManager = AccessibilityManager()

        // 如果focusedOnly为true，则获取当前焦点窗口信息
        if input.focusedOnly == true {
            let focusedWindow: (pid: pid_t, name: String, windowID: UInt32) = accessibilityManager.getFocusedWindowInfo()

            let resultString = """
            {
              "pid": \(focusedWindow.pid),
              "name": "\(focusedWindow.name)",
              "windowID": \(focusedWindow.windowID)
            }
            """

            return [.text(.init(text: resultString))]
        }

        // 否则获取所有窗口列表
        let jsonString = accessibilityManager.getWindowsListInfo()
        return [.text(.init(text: jsonString))]
    },

    Tool(
        name: "getWindowA11yInfo",
        description: "Get the window accessibility information. The focused window may not work reliably. If it doesn't work, use getWindowsInfo to get the pid and windowNumber, then use getWindowA11yInfo"
    ) { (input: WindowInfoInput) in
        let accessibilityManager = AccessibilityManager()

        if let pid = input.pid, let windowNumber = input.windowNumber, pid > 0, windowNumber > 0 {
            let jsonString = accessibilityManager.getWindowsStructureByPID(
                pid_t(pid), UInt32(windowNumber)
            )
            return [.text(.init(text: jsonString))]
        }

        // 获取当前焦点窗口信息
        let jsonString = accessibilityManager.getFocusedWindowStructure()
        return [.text(.init(text: jsonString))]
    },
]

private func getInstalledApplications() -> [AppInfo] {
    var apps = [AppInfo]()

    // 搜索系统应用目录和用户应用目录
    let searchPaths = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    for path in searchPaths {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                atPath: path)
        else { continue }

        for item in contents where item.hasSuffix(".app") {
            let appPath = URL(fileURLWithPath: path).appendingPathComponent(
                item)
            let plistPath = appPath.appendingPathComponent(
                "Contents/Info.plist")

            guard let plistData = try? Data(contentsOf: plistPath),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: plistData, options: [], format: nil
                  )
                  as? [String: Any],
                  let bundleId = plist["CFBundleIdentifier"] as? String,
                  let name = plist["CFBundleName"] as? String ?? plist[
                      "CFBundleExecutable"] as? String
            else { continue }

            apps.append(AppInfo(name: name, bundleId: bundleId))
        }
    }

    return apps.sorted { $0.name < $1.name }
}

private struct AppInfo {
    let name: String
    let bundleId: String
}
