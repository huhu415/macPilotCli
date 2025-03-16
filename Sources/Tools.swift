import AppKit
import Foundation
import JSONSchemaBuilder
import MCPServer
import os

let mcpLogger = Logger(subsystem: "com.macpilot.mcp", category: "mcp")

@Schemable
struct EmptyInput {}

@Schemable
struct CursorMoveInput {
    let x: String
    let y: String
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
struct WindowInfoInput {
    let pid: String?
}

@Schemable
struct RepeatToolInput {
    let text: String
}

@MainActor
let tools: [any CallableTool] = [
    Tool(name: "repeat") { (input: RepeatToolInput) in
        [.text(.init(text: input.text))]
    },

    Tool(name: "getCursorPosition") { (_: EmptyInput) in
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

        if let jsonData = try? JSONSerialization.data(withJSONObject: response),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            return [.text(.init(text: jsonString))]
        }
        return [.text(.init(text: "获取鼠标位置失败"))]
    },

    Tool(name: "moveCursor") { (input: CursorMoveInput) in
        guard let x = Double(input.x), let y = Double(input.y) else {
            return [.text(.init(text: "参数无效"))]
        }
        InputControl.moveMouse(to: CGPoint(x: x, y: y))
        return [.text(.init(text: "鼠标已移动到 \(input.x), \(input.y)"))]
    },

    Tool(name: "clickMouse") { (_: EmptyInput) in
        InputControl.mouseClick(at: InputControl.getCurrentMousePosition())
        return [.text(.init(text: "已点击鼠标"))]
    },

    Tool(name: "pasteText") { (input: PasteInput) in
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(input.text, forType: .string)

        InputControl.pressKeys(modifiers: .maskCommand, keyCodes: KeyCode.v.rawValue)
        return [.text(.init(text: "已粘贴文本"))]
    },

    Tool(name: "captureScreen") { (_: EmptyInput) async throws in
        let screenCaptureManager = ScreenCaptureManager()

        let image: Data? = await withCheckedContinuation {
            (continuation: CheckedContinuation<Data?, Never>) in
            screenCaptureManager.captureFullScreen { capturedImage in
                if let unwrappedImage = capturedImage,
                   let tiffData = unwrappedImage.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmapImage.representation(
                       using: .jpeg, properties: [.compressionFactor: 0.75]
                   )
                {
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

    Tool(name: "executeCommand") { (input: ExecuteCommandInput) in
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

        if let jsonData = try? JSONSerialization.data(withJSONObject: response),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            return [.text(.init(text: jsonString))]
        }
        return [.text(.init(text: "命令执行失败"))]
    },

    Tool(name: "launchApp") { (input: LaunchAppInput) in
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

    Tool(name: "getAppsList") { (_: EmptyInput) in
        let apps = getInstalledApplications()
        let appList = apps.map { ["appName": $0.name, "bundleId": $0.bundleId] }

        if let jsonData = try? JSONSerialization.data(withJSONObject: appList),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            return [.text(.init(text: jsonString))]
        }
        return [.text(.init(text: "获取应用列表失败"))]
    },

    Tool(name: "getWindowsList") { (_: EmptyInput) in
        let accessibilityManager = AccessibilityManager()
        let jsonString = accessibilityManager.getWindowsListInfo()
        return [.text(.init(text: jsonString))]
    },

    Tool(name: "getWindowInfo") { (input: WindowInfoInput) async throws in
        let accessibilityManager = AccessibilityManager()

        if let pid = input.pid {
            guard let pidInt = Int(pid) else {
                return [.text(.init(text: "参数无效"))]
            }
            let jsonString = accessibilityManager.getWindowInfoByPID(pid_t(pidInt))
            return [.text(.init(text: jsonString))]
        }

        // 获取当前焦点窗口信息
        let jsonString = accessibilityManager.getWindowStructure()
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
