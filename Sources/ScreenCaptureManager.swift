import ScreenCaptureKit
import SwiftUI

// 添加 ScreenCaptureManager 类
class ScreenCaptureManager: NSObject, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream? // 这是一个可选类型的属性
    private var hasProcessedFrame = false // 添加标志位来追踪是否已处理过帧
    private var completionHandler: ((NSImage?) -> Void)?

    // 捕获全屏截图
    func captureFullScreen(completion: @escaping (NSImage?) -> Void) {
        completionHandler = completion

        SCShareableContent.getWithCompletionHandler {
            [weak self] content, error in
            guard let self else { return }

            if let error {
                print("获取共享内容失败: \(error.localizedDescription)")
                completionHandler?(nil)
                return
            }

            guard let content, !content.displays.isEmpty else {
                print("未找到可用的显示器")
                completionHandler?(nil)
                return
            }

            let primaryDisplay = content.displays[0]
            let filter = SCContentFilter(
                display: primaryDisplay, excludingWindows: []
            )

            // 获取主屏幕缩放因子
            let scaleFactor = NSScreen.main?.backingScaleFactor ?? 1.0

            // 计算实际像素尺寸
            let pixelWidth = Int(CGFloat(primaryDisplay.width) * scaleFactor)
            let pixelHeight = Int(CGFloat(primaryDisplay.height) * scaleFactor)

            let config = SCStreamConfiguration()
            config.capturesAudio = false
            config.width = pixelWidth // 设置物理像素宽度
            config.height = pixelHeight // 设置物理像素高度

            do {
                stream = SCStream(
                    filter: filter, configuration: config, delegate: self
                )
                try stream?.addStreamOutput(
                    self, type: .screen,
                    sampleHandlerQueue: .global(qos: .userInteractive)
                )
                stream?.startCapture()
            } catch {
                print("创建流失败: \(error.localizedDescription)")
                stream = nil
                completionHandler?(nil)
            }
        }
    }

    // 处理捕获到的帧, 这是回调
    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, !hasProcessedFrame else { return }

        if let image = NSImage(from: sampleBuffer) {
            hasProcessedFrame = true
            completionHandler?(image)
            stream.stopCapture { [weak self] error in
                if let error {
                    print("停止捕获失败: \(error)")
                }
                self?.stream = nil
                self?.hasProcessedFrame = false
                self?.completionHandler = nil
            }
        }
    }
}

// 处理CMSampleBuffer
extension NSImage {
    convenience init?(from sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return nil }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)

        // 使用高质量渲染选项
        let context = CIContext(options: [
            .highQualityDownsample: true,
            .useSoftwareRenderer: false,
        ])

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        else { return nil }
        self.init(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
