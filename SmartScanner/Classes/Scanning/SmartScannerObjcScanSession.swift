//
//  SmartScannerObjcScanSession.swift
//  SmartScanner
//
//  Created by Codex on 2026/4/7.
//

import UIKit

@objc(SmartScannerObjcScanSession)
@objcMembers
public final class SmartScannerObjcScanSession: NSObject {
    private let cameraCapturer: CameraCapturer
    public let preview: UIView

    public var needAutoPhoto = false

    private var detector: ImageDetector
    private var resultHandler: ((DetectResult) -> Void)?

    public init?(preview: UIView, detectOptions: Int) {
        guard let cameraCapturer = CameraCapturer(preview: preview) else {
            return nil
        }

        self.preview = preview
        self.cameraCapturer = cameraCapturer
        self.detector = makeSmartScannerDefaultDetector(options: DetecteOptions(rawValue: detectOptions))
        super.init()
        bindRecognizer()
    }

    public func setResultHandler(_ handler: ((DetectResult) -> Void)?) {
        resultHandler = handler
    }

    public func setDetector(_ detector: ImageDetector) {
        self.detector = detector
        bindRecognizer()
    }

    @objc(setDetectOptionsRawValue:)
    public func setDetectOptions(_ detectOptionsRawValue: Int) {
        detector.reset(detecteOptions: DetecteOptions(rawValue: detectOptionsRawValue))
    }

    public func start() {
        cameraCapturer.start()
    }

    public func stop() {
        cameraCapturer.stop()
        detector.releaseResources()
    }

    @objc(setTorchOpen:)
    public func setTorchOpen(_ isOpen: Bool) {
        cameraCapturer.setTorch(isOpen)
    }

    @objc(setRegionRectInPreview:)
    public func setRegionRectInPreview(_ regionRect: CGRect) {
        cameraCapturer.setRegionRectInPreview(regionRect)
    }

    @objc(setAppleRegionRectInPreview:)
    public func setAppleRegionRectInPreview(_ regionRect: CGRect) {
        cameraCapturer.setRegionRectInPreview(regionRect, for: .appleNative)
    }

    @objc(takePhotoWithSound:completion:)
    public func takePhoto(withSound isSound: Bool, completion: ((UIImage) -> Void)?) {
        cameraCapturer.takePhoto(isSound: isSound, completion: completion)
    }

    /// 带失败回调的拍照：采集失败、在途请求过多、照片解码失败或会话异常时触发 failure。
    /// 旧的两参数版本在失败时 completion 静默不回调，建议新接入方使用本方法。
    @objc(takePhotoWithSound:completion:failure:)
    public func takePhoto(withSound isSound: Bool,
                          completion: ((UIImage) -> Void)?,
                          failure: (() -> Void)?) {
        cameraCapturer.takePhoto(isSound: isSound, completion: completion, onFailure: failure)
    }

    private func bindRecognizer() {
        cameraCapturer.outputSampleBuffer { [weak self] buffer, regionRect in
            guard let self = self else { return }
            self.detector.recognize(sampleBuffer: buffer, regionRect: regionRect)
        }

        detector.completion { [weak self] detectResult in
            self?.emit(detectResult)
        }
    }

    private func emit(_ detectResult: DetectResult) {
        guard needAutoPhoto else {
            notify(detectResult)
            return
        }

        cameraCapturer.takePhoto(completion: { [weak self] image in
            detectResult.picture = image
            self?.notify(detectResult)
        }, onFailure: { [weak self] in
            // 拍照失败时识别结果不能被吞掉：无图也要把结果给出去，由业务决定如何兜底
            self?.notify(detectResult)
        })
    }

    private func notify(_ detectResult: DetectResult) {
        DispatchQueue.main.async { [weak self] in
            self?.resultHandler?(detectResult)
        }
    }
}
