import Cocoa

// 在文件顶部添加私有 API 声明
private let AXValueType_CGPoint = 1
private let AXValueType_CGSize = 2
private let AXValueType_CGRect = 3
private let AXValueType_CFRange = 4

// 声明私有 API
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(
    _ axElement: AXUIElement, _ windowId: UnsafeMutablePointer<CGWindowID>
) -> AXError

class AccessibilityManager: ObservableObject {
    // 处理属性值的辅助函数
    private func processAttributeValue(
        _ attributeName: String, _ attributeValue: AnyObject?
    ) -> (String, Any)? {
        guard let attributeValue = attributeValue else { return nil }

        // 将属性名作为键
        let key = attributeName

        // 根据属性值的类型处理
        switch CFGetTypeID(attributeValue) {
        case CFStringGetTypeID():
            // 字符串类型
            return (key, attributeValue as! String)

        case CFBooleanGetTypeID():
            // 布尔类型
            return (key, (attributeValue as! CFBoolean) == kCFBooleanTrue)

        case CFNumberGetTypeID():
            // 数字类型
            let number = attributeValue as! CFNumber
            var value = 0
            CFNumberGetValue(number, CFNumberType.intType, &value)
            return (key, value)

        case AXUIElementGetTypeID():
            // 辅助功能元素类型 - 返回元素的角色
            let element = attributeValue as! AXUIElement
            var roleValue: CFTypeRef?
            let roleStatus = AXUIElementCopyAttributeValue(
                element, kAXRoleAttribute as CFString, &roleValue
            )
            if roleStatus == .success, let role = roleValue as? String {
                return (key, ["role": role])
            }
            return (key, ["role": "unknown"])

        case CFArrayGetTypeID():
            // 数组类型
            if let array = attributeValue as? [AnyObject], !array.isEmpty {
                // 检查是否为AXUIElement数组
                if let firstItem = array.first,
                   CFGetTypeID(firstItem) == AXUIElementGetTypeID()
                {
                    // 对于UI元素数组，只返回数量
                    return (key, ["count": array.count])
                } else {
                    // 其他数组尝试转换
                    var values: [Any] = []
                    for item in array {
                        if let stringItem = item as? String {
                            values.append(stringItem)
                        } else if let numberItem = item as? NSNumber {
                            values.append(numberItem)
                        } else {
                            values.append(String(describing: item))
                        }
                    }
                    return (key, values)
                }
            }
            return (key, [])

        case AXValueGetTypeID():
            // AXValue类型 (CGPoint, CGSize, CGRect等)
            let axValue = attributeValue as! AXValue
            let axValueType = AXValueGetType(axValue)

            switch Int(axValueType.rawValue) {
            case AXValueType_CGPoint:
                var point = CGPoint.zero
                AXValueGetValue(axValue, axValueType, &point)
                return (key, ["x": point.x, "y": point.y])

            case AXValueType_CGSize:
                var size = CGSize.zero
                AXValueGetValue(axValue, axValueType, &size)
                return (key, ["width": size.width, "height": size.height])

            case AXValueType_CGRect:
                var rect = CGRect.zero
                AXValueGetValue(axValue, axValueType, &rect)
                return (
                    key,
                    [
                        "x": rect.origin.x,
                        "y": rect.origin.y,
                        "width": rect.size.width,
                        "height": rect.size.height,
                    ]
                )

            default:
                return (key, String(describing: attributeValue))
            }

        default:
            // 其他类型
            return (key, String(describing: attributeValue))
        }
    }

    private func dfs(element: AXUIElement) -> [String: Any] {
        var result: [String: Any] = [:]

        // 获取元素支持的所有属性
        var attributeNamesRef: CFArray?
        let status = AXUIElementCopyAttributeNames(element, &attributeNamesRef)

        if status == .success,
           let attributeNames = attributeNamesRef as? [String]
        {
            for attributeName in attributeNames {
                var attributeValue: AnyObject?
                let valueStatus = AXUIElementCopyAttributeValue(
                    element,
                    attributeName as CFString,
                    &attributeValue
                )

                if valueStatus == .success {
                    if let (key, value) = processAttributeValue(
                        attributeName, attributeValue
                    ) {
                        result[key] = value
                    }
                }
            }
        }

        // 处理子元素
        var children: AnyObject?
        AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &children
        )
        if let childrenArray = children as? [AXUIElement],
           !childrenArray.isEmpty
        {
            var transformedArray: [[String: Any]] = []
            for childElement in childrenArray {
                transformedArray.append(dfs(element: childElement))
            }
            result["children"] = transformedArray
        }

        return result
    }

    // 修改用于导出 JSON 的辅助方法，返回 JSON 字符串
    private func exportAccessibilityTreeToJSON(element: AXUIElement) -> String {
        let tree = dfs(element: element)
        var jsonString = ""

        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: tree,
                options: [.prettyPrinted, .sortedKeys]
            )
            if let jsonStr = String(data: jsonData, encoding: .utf8) {
                jsonString = jsonStr
            }
        } catch {
            jsonString = "{\"error\": \"JSON 序列化失败\"}"
        }

        return jsonString
    }

    // 获取焦点窗口PID NAME windowID
    public func getFocusedWindowInfo() -> (pid: pid_t, name: String, windowID: UInt32) {
        var pid: pid_t = 0
        var windowID: UInt32 = 0
        var name = ""
        let systemWideElement = AXUIElementCreateSystemWide()

        // 获取聚焦元素
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement, kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        if result != .success {
            return (pid, name, windowID)
        }

        // 通过聚焦元素获取PID
        let pidResult = AXUIElementGetPid(
            focusedElement as! AXUIElement, &pid
        )
        if pidResult != .success {
            return (pid, name, windowID)
        }

        let appElement = AXUIElementCreateApplication(pid)

        // 获取应用名称
        var appName: AnyObject?
        let appNameResult = AXUIElementCopyAttributeValue(
            appElement, kAXTitleAttribute as CFString, &appName
        )
        if appNameResult == .success {
            name = appName as! String
        }

        //// 获取一个pid的多个窗口
        // var windowList: CFTypeRef?
        // let windowListResult = AXUIElementCopyAttributeValue(
        //    appElement, kAXWindowsAttribute as CFString, &windowList
        // )
        // if windowListResult == .success {}

        var window: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(
            focusedElement as! AXUIElement,
            kAXWindowAttribute as CFString, &window
        )
        if windowResult == .success {
            var windowRef: CGWindowID = 0
            let windowsNum = _AXUIElementGetWindow(
                window as! AXUIElement, &windowRef
            )
            if windowsNum == .success {
                windowID = windowRef
            }
        }

        return (pid, name, windowID)
    }

    // 根据聚焦窗口获取窗口结构
    public func getWindowStructure() -> String {
        let systemWideElement = AXUIElementCreateSystemWide()

        // 获取聚焦元素
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement, kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success, let focusedUIElement = focusedElement else {
            return "获取焦点窗口失败"
        }

        // 获取窗口
        var window: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(
            focusedUIElement as! AXUIElement, kAXWindowAttribute as CFString,
            &window
        )
        guard windowResult == .success, let windowUIElement = window else {
            return "获取窗口失败"
        }

        // 导出窗口的辅助功能树结构为JSON
        return exportAccessibilityTreeToJSON(
            element: windowUIElement as! AXUIElement)
    }

    // 根据PID获取窗口结构
    public func getWindowInfoByPID(_ pid: pid_t) -> String {
        let appElement = AXUIElementCreateApplication(pid)
        var windowList: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &windowList
        )

        if result == .success, let windows = windowList as? [AXUIElement] {
            for window in windows {
                let jsonString = exportAccessibilityTreeToJSON(element: window)
                return jsonString // 只处理第一个窗口
            }
        }
        return "获取窗口信息失败"
    }

    // 获取pid为1500以上的窗口信息列表
    public func getWindowsListInfo() -> String {
        var windowsArray: [[String: Any]] = []
        let options = CGWindowListOption(
            arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements
        )
        let windowList =
            CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as! [[String: Any]]

        for window in windowList {
            let windowOwnerPID = window[kCGWindowOwnerPID as String] as! Int
            if windowOwnerPID < 1500 {
                continue
            }
            windowsArray.append(window)
        }

        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: windowsArray,
                options: [.prettyPrinted, .sortedKeys]
            )
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            return "{\"error\": \"JSON 序列化失败\"}"
        }

        return "{\"error\": \"JSON 序列化失败\"}"
    }
}
