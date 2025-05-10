import ScreenCaptureKit
import SwiftUI

// 添加 ScreenCaptureManager 类
class ScreenCaptureManager: NSObject, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream?
    private var frameProcessor: ((NSImage) -> Void)?

    // 捕获全屏截图
    func captureFullScreen(processor: @escaping (NSImage) -> Void) {
        frameProcessor = processor

        SCShareableContent.getWithCompletionHandler { [weak self] content, error in
            guard let self else { return }

            if let error {
                mcpLogger.error("获取共享内容失败: \(error.localizedDescription)")
                return
            }

            guard let content, !content.displays.isEmpty else {
                mcpLogger.error("未找到可用的显示器")
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
                mcpLogger.error("创建流失败: \(error.localizedDescription)")
                stream = nil
            }
        }
    }

    // 处理捕获到的帧
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        mcpLogger.info("process stream output")
        guard type == .screen else { return }

        // Convert CMSampleBuffer to NSImage
        guard let image = NSImage(from: sampleBuffer) else {
            mcpLogger.error("Failed to convert CMSampleBuffer to NSImage")
            // Optionally, handle the error, e.g., stop the stream or call frameProcessor with an error indicator
            stream.stopCapture { [weak self] error in
                if let error {
                    mcpLogger.error("停止捕获失败: \(error)")
                }
                self?.stream = nil
                self?.frameProcessor = nil
            }
            return
        }

        // 调用处理器
        frameProcessor?(image)

        // 停止捕获
        stream.stopCapture { [weak self] error in
            if let error {
                mcpLogger.error("停止捕获失败: \(error)")
            }
            self?.stream = nil
            self?.frameProcessor = nil
        }
    }

    // 处理流错误
    func stream(
        _: SCStream,
        didStopWithError error: Error
    ) {
        mcpLogger.error("屏幕捕获流错误: \(error.localizedDescription)")
        stream = nil
        frameProcessor = nil
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
