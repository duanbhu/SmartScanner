//
//  SwiftyCameraObjcCapturerBridge.swift
//  SwiftyCamera
//
//  Created by Codex on 2026/4/3.
//

import UIKit
import CoreMedia

@objc(SmartScannerObjcCapturerBridge)
@objcMembers
public final class SmartScannerObjcCapturerBridge: NSObject {
    private let cameraCapturer: CameraCapturer
    public let preview: UIView
    
    public init?(preview: UIView) {
        guard let cameraCapturer = CameraCapturer(preview: preview) else {
            return nil
        }
        self.preview = preview
        self.cameraCapturer = cameraCapturer
        super.init()
    }
    
    public func start() {
        cameraCapturer.start()
    }
    
    public func stop() {
        cameraCapturer.stop()
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
    
    @objc(setSampleBufferHandler:)
    public func setSampleBufferHandler(_ handler: ((CMSampleBuffer, CGRect) -> Void)?) {
        cameraCapturer.outputSampleBuffer(handler)
    }
    
    @objc(takePhotoWithSound:completion:)
    public func takePhoto(withSound isSound: Bool, completion: ((UIImage) -> Void)?) {
        cameraCapturer.takePhoto(isSound: isSound, completion: completion)
    }
}
