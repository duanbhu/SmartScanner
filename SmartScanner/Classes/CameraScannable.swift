//
//  File.swift
//
//
//  Created by Duanhu on 2024/3/21.
//

#if canImport(UIKit)
import UIKit
fileprivate var CameraCapturerContext: UInt8 = 0

func makeSmartScannerDefaultDetector(options: DetecteOptions) -> ImageDetector {
#if SMARTSCANNER_GOOGLE_ENGINE || SWIFTYCAMERA_GOOGLE_ENGINE
    return ImageDetector(options: options, engines: GoogleEngine(options: options))
#elseif SMARTSCANNER_APPLE_ENGINE || SWIFTYCAMERA_APPLE_ENGINE
    return ImageDetector(options: options, engines: AppleEngine(options: options))
#else
    fatalError("SmartScanner requires an engine subspec. Add `SmartScanner/Google` or `SmartScanner/Apple`.")
#endif
}

public protocol CameraScannable {
    /// 预览  AVCaptureVideoPreviewLayer
    var preview: UIView { get }
    
    var cameraCapturer: CameraCapturer? { get }
}

extension CameraScannable {
    
    public var cameraCapturer: CameraCapturer? {
        if let cameraCapturer = objc_getAssociatedObject(self, &CameraCapturerContext) {
            return cameraCapturer as? CameraCapturer
        } else {
            let cameraCapturer: CameraCapturer? = CameraCapturer(preview: preview)
            objc_setAssociatedObject(self, &CameraCapturerContext, cameraCapturer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return cameraCapturer
        }
    }
}

fileprivate var CameraScanViewContext: UInt8 = 0
fileprivate var CameraDetectorContext: UInt8 = 0

public protocol CameraScanViewable: UIViewController, CameraScannable {
    var cameraCapturer: CameraCapturer? { get }
    
    var detector: ImageDetector { get }
    
    /// 工厂方法：创建默认识别器
    func makeDetector() -> ImageDetector
    
    /// 返回扫描结果时，是否需要拍照
    /// - Returns: 是否需要自动拍照
    func isNeedAutoTakePhoto() -> Bool
}

extension CameraScanViewable {
    public var scanView: CameraScanView {
        if let view = objc_getAssociatedObject(self, &CameraScanViewContext) as? CameraScanView {
            return view
        } else {
            let scanView = CameraScanView(frame: view.bounds)
            objc_setAssociatedObject(self, &CameraScanViewContext, scanView, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            self.view = scanView
            return scanView
        }
    }
    
    public var detector: ImageDetector {
        if let view = objc_getAssociatedObject(self, &CameraDetectorContext) as? ImageDetector {
            return view
        } else {
            let detector = makeDetector()
            objc_setAssociatedObject(self, &CameraDetectorContext, detector, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return detector
        }
    }
    
    /// 默认工厂方法：优先保持 Google 引擎兼容，未集成时自动回落到 Apple 引擎
    public func makeDetector() -> ImageDetector {
        let options: DetecteOptions = []
        return makeSmartScannerDefaultDetector(options: options)
    }
    
    /// 注入自定义识别器，未注入时保持默认引擎不变
    public func setDetector(_ detector: ImageDetector) {
        objc_setAssociatedObject(self, &CameraDetectorContext, detector, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    public var preview: UIView { return scanView }
    
    /// 配置获取识别结果
    /// - Parameter completion: 识别回调
    public func configRecognize(completion: @escaping ImageDetector.CompletionHandler) {
        cameraCapturer?.outputSampleBuffer({ [weak self] buffer, regionRect in
            self?.detector.recognize(sampleBuffer: buffer, regionRect: regionRect)
        })
        detector.completion { [weak self] detectResult in
            if true == self?.isNeedAutoTakePhoto() {
                self?.cameraCapturer?.takePhoto(completion: { image in
                    detectResult.picture = image
                    completion(detectResult)
                })
            } else {
                completion(detectResult)
            }
        }
    }
    
    /// 试点版识别配置：仅在显式传入 ImageDetectorUpgrade 时生效，不影响默认识别器。
    public func configRecognize(detector: ImageDetectorUpgrade,
                                completion: @escaping ImageDetectorUpgrade.CompletionHandler) {
        cameraCapturer?.outputSampleBuffer({ [weak self] buffer, regionRect in
            guard self != nil else { return }
            detector.recognize(sampleBuffer: buffer, regionRect: regionRect)
        })
        detector.completion { [weak self] detectResult in
            if true == self?.isNeedAutoTakePhoto() {
                self?.cameraCapturer?.takePhoto(completion: { image in
                    detectResult.picture = image
                    completion(detectResult)
                })
            } else {
                completion(detectResult)
            }
        }
    }
    
    public func configRecognize(detector: ImageDetector,
                                completion: @escaping ImageDetectorUpgrade.CompletionHandler) {
        cameraCapturer?.outputSampleBuffer({ [weak self] buffer, regionRect in
            guard self != nil else { return }
            detector.recognize(sampleBuffer: buffer, regionRect: regionRect)
        })
        detector.completion { [weak self] detectResult in
            if true == self?.isNeedAutoTakePhoto() {
                self?.cameraCapturer?.takePhoto(completion: { image in
                    detectResult.picture = image
                    completion(detectResult)
                })
            } else {
                completion(detectResult)
            }
        }
    }
    
    /// 开始扫描
    public func startScanning() {
        cameraCapturer?.start()
        scanView.startFlashing()
    }
    
    /// 结束扫描
    public func stopScan() {
        cameraCapturer?.stop()
    }
}

#endif
