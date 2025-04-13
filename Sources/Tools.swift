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
    let x: String?
    let y: String?
    let click: Bool?
    let rightClick: Bool?
}

@Schemable
struct PasteInput {
    let text: String
}

@Schemable
struct ExecuteCommandInput {
    let command: String
    let args: [String]?
}

@Schemable
struct LaunchAppInput {
    let bundleId: String?
    let appName: String?
}

@Schemable
struct WindowsInfoInput {
    let focusedOnly: Bool?
}

@Schemable
struct WindowInfoInput {
    let pid: Int?
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
        description: "Move the mouse to the specified position and optionally click. If no coordinates are provided, click at the current position. Use rightClick=true for right-click"
    ) { (input: MouseControlInput) in
        // 确定使用哪个鼠标按钮
        let mouseButton: CGMouseButton = input.rightClick == true ? .right : .left
        
        // 如果提供了坐标，移动鼠标到指定位置
        if let xStr = input.x, let yStr = input.y,
           let x = Double(xStr), let y = Double(yStr)
        {
            InputControl.moveMouse(to: CGPoint(x: x, y: y))

            // 如果需要点击，在新位置点击
            if input.click == true {
                InputControl.mouseClick(at: CGPoint(x: x, y: y), button: mouseButton)
                let buttonType = input.rightClick == true ? "right-clicked" : "clicked"
                return [.text(.init(text: "Mouse moved to \(x), \(y) and \(buttonType)"))]
            }
            return [.text(.init(text: "Mouse moved to \(x), \(y)"))]
        }

        // 如果没有提供坐标但需要点击，在当前位置点击
        if input.click == true {
            InputControl.mouseClick(at: InputControl.getCurrentMousePosition(), button: mouseButton)
            let buttonType = input.rightClick == true ? "right-clicked" : "clicked"
            return [.text(.init(text: "Mouse \(buttonType) at current position"))]
        }

        return [.text(.init(text: "Invalid parameters, please provide coordinates or set click to true"))]
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
        let args = input.args ?? []
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [input.command] + args
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
        description: "Get all windows information. If focusedOnly is true, returns only the focused window, otherwise returns all windows list"
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
        description: "Get the window accessibility information. If pid and windowNumber are provided, get the window information by PID and windowNumber, otherwise get the focused window information"
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
