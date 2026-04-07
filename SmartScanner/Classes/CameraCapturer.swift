// The Swift Programming Language
// https://docs.swift.org/swift-book

//
//  CameraCapturer.swift
//  Text Detection Starter Project
//
//  Created by Duanhu on 2023/11/1.
//  Copyright © 2023 AppCoda. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import AVFoundation

public extension CameraCapturer {
    enum CameraCapturerError: Error {
        /// The user didn't grant permission to use the camera.
        case authorizationDenied
        
        /// 权限受限
        case authorizationRestricted
    
        case unknownAuthorizationStatus
        
        /// An error occurred when setting up the user's device.
        case inputDevice
        /// An error occurred when trying to capture a picture.
        case capture
        /// Error when creating the CIImage.
        case ciImageCreation
    }
    
    enum RegionRectType {
        case normal //
        case appleNative // 苹果原生
    }
}

public enum SmartScannerLogType: Int {
    case capturer, photoOutput
}

public protocol SmartScannerLoggerProtocol: AnyObject {
    func logType(_ type: SmartScannerLogType, message: String)
}

@available(*, deprecated, renamed: "SmartScannerLogType")
public typealias SwiftyCameraLogType = SmartScannerLogType

@available(*, deprecated, renamed: "SmartScannerLoggerProtocol")
public typealias SwiftyCameraLoggerProtocol = SmartScannerLoggerProtocol

@objc(SmartScannerCameraCapturer)
public final class CameraCapturer: NSObject {
    
    public typealias OutputSampleBufferBlock = (CMSampleBuffer, CGRect) -> ()
    
    private lazy var sessionQueue = DispatchQueue(label: "com.sessionQueueLabel")
    
    private let captureSession = AVCaptureSession()
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    // 设置AVCapturePhotoOutput
    private lazy var photoOutput: AVCapturePhotoOutput = {
        let photoOutput = AVCapturePhotoOutput()
        photoOutput.isHighResolutionCaptureEnabled = true
        return photoOutput
    }()
                
    private var onSuccess: (() -> (Void))?

    private var onError: ((CameraCapturerError) -> (Void))?
    
    private let preview: UIView
    
    /// 采集视频流的回调
    private var videoDataOutputSampleBufferBlock: OutputSampleBufferBlock?
        
    private var captureDevice: AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        for device in discoverySession.devices {
            if device.position == .back {
                return device
            }
        }
        return nil
    }
    
    /// 预制的分辨率  AVCaptureSession.Preset.hd1280x720
    private var sessionPresetSize = CGSize(width: 720, height: 1280)
    
    public var isDetecting = false {
        didSet {
            DetectorConfig.logPrint("是否允许识别：\(isDetecting)")
        }
    }
    
    /// 识别区域在获取图片上的位置,  默认为zero， 表示全屏
    private var regionRectInImage: CGRect = .zero
    
    private var isCollect = true
    
    private var timer: Timer?
    
    public weak var logger: SmartScannerLoggerProtocol?
    
    @objc static func capturer(preview: UIView) -> CameraCapturer? {
        return CameraCapturer(preview: preview)
    }
    
    public init?(
        preview: UIView,
        onError: ((CameraCapturerError) -> (Void))? = nil,
        videoDataOutputSampleBufferBlock: OutputSampleBufferBlock? = nil
    ) {
        self.preview = preview
        self.onError = onError
        self.videoDataOutputSampleBufferBlock = videoDataOutputSampleBufferBlock
        super.init()
                
        guard let device = AVCaptureDevice.default(for: AVMediaType.video) else {
            onError?(.inputDevice)
            return nil
        }
        
        captureSession.beginConfiguration()

        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true

        defer {
            device.unlockForConfiguration()
            captureSession.commitConfiguration()
        }
        
        guard let deviceInput = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(deviceInput),
              captureSession.canAddOutput(videoDataOutput) else {
            onError?(.inputDevice)
            return
        }
        
        captureSession.addInput(deviceInput)
        captureSession.addOutput(videoDataOutput)
        
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        
        do {
            try device.lockForConfiguration()
        } catch {
            onError?(.inputDevice)
            return
        }
        
        let photoPreset = AVCaptureSession.Preset.hd1280x720

        if captureSession.canSetSessionPreset(photoPreset) {
            captureSession.sessionPreset = photoPreset
        }
        
        // 设置竖屏
        let connection = videoDataOutput.connection(with: .video)
        connection?.videoOrientation = .portrait
        
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        for device in discoverySession.devices {
            configureDevice(captureDevice: device, mediaType: .video)
        }
        
        self.videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        guard let videoPreviewLayer = videoPreviewLayer else { return }
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewLayer.frame = preview.bounds
        preview.layer.insertSublayer(videoPreviewLayer, at: 0)
    }
    
    private func configureDevice(captureDevice: AVCaptureDevice, mediaType: AVMediaType) {
        
        if mediaType == AVMediaType.video {
            do {
                try captureDevice.lockForConfiguration()
                
                if captureDevice.isFocusModeSupported(.continuousAutoFocus) {
                    captureDevice.focusMode = .continuousAutoFocus
                    if captureDevice.isSmoothAutoFocusSupported {
                        // 启用平滑自动对焦
                        captureDevice.isSmoothAutoFocusEnabled = true
                    }
                }
                captureDevice.videoZoomFactor = 1.5
                if captureDevice.isExposureModeSupported(.continuousAutoExposure) {
                    captureDevice.exposureMode = .continuousAutoExposure
                }
                
                if captureDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    captureDevice.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                captureDevice.isSubjectAreaChangeMonitoringEnabled = true
                
                if captureDevice.isLowLightBoostSupported {
                    captureDevice.automaticallyEnablesLowLightBoostWhenAvailable = true
                }
                captureDevice.unlockForConfiguration()
            } catch {
                print("NextLevel, low light failed to lock device for configuration")
            }
        }
    }
    
    // MARK: Capture Session Life Cycle

    /// Starts the camera and detecting quadrilaterals.
    @objc public func start() {
        // 禁止长时间不操作，锁屏
        UIApplication.shared.isIdleTimerDisabled = true
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch authorizationStatus {
        case .authorized:
            startCaptureSession()
        case .notDetermined:
            requestCameraAuthorization()
        case .denied:
            onError?(.authorizationDenied)
        case .restricted:
            onError?(.authorizationRestricted)
        @unknown default:
            onError?(.unknownAuthorizationStatus)
        }
        logger?.logType(.capturer, message: "authorizationStatus: \(authorizationStatus)")
    }
    
    // MARK: - Private Methods
    private func startCaptureSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.setupCollectionTimer()
                self?.onSuccess?()
            }
        }
    }

    private func setupCollectionTimer() {
        // 确保在正确的线程上操作定时器
        DispatchQueue.main.async {
            self.stopCollectionTimer() // 先停止之前的定时器
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] timer in
                guard let self = self else {
                    // 清理定时器
                    timer.invalidate()
                    return
                }
                self.isCollect.toggle()
            }
            self.isDetecting = true
        }
    }

    /// 请求相机权限
    private func requestCameraAuthorization() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                granted ? self?.start() : self?.onError?(.authorizationDenied)
            }
        }
    }
    
    private func stopCollectionTimer() {
        timer?.invalidate()
        timer = nil
        isDetecting = false
    }

    @objc public func stop() {
        captureSession.stopRunning()
        UIApplication.shared.isIdleTimerDisabled = false
        stopCollectionTimer()
    }
    
    /// 打开、关闭手电筒
    public func setTorch(_ isOpen: Bool) {
        guard let captureDevice = captureDevice, captureDevice.hasTorch else {
            return
        }
        do {
            try captureDevice.lockForConfiguration()
            captureDevice.torchMode = isOpen ? .on : .off
            captureDevice.unlockForConfiguration()
        } catch {
            logger?.logType(.capturer, message: "打开、关闭手电筒失败")
        }
    }
    
    /// 视频流采集回调
    /// - Parameter callback: 回调
    public func outputSampleBuffer(_ callback: OutputSampleBufferBlock?) {
        self.videoDataOutputSampleBufferBlock = callback
    }
    
    public func onError(_ onError: ((CameraCapturerError) -> (Void))?) {
        self.onError = onError
    }
    
    public func onSuccess(_ onSuccess: (() -> (Void))?) {
        self.onSuccess = onSuccess
    }
    
    private var takePhotoCompletion: ((UIImage) -> ())?
    
    /// 标识是否正在拍照
    private var isTakingPhoto = false
    
    /// 拍照时，是否播放声音
    private var isSound = true
    
    /// 拍照
    /// - Parameters:
    ///   - isSound: 是否发出声音：咔嚓 默认是false
    ///   - completion: 图片回调
    public func takePhoto(isSound: Bool = false, completion: ((UIImage) -> ())?) {
        guard let connection = photoOutput.connection(with: .video), connection.isEnabled, connection.isActive else {
            logger?.logType(.photoOutput, message: "拍照采集失败")
            return
        }
        guard !isTakingPhoto else { return }
        isTakingPhoto = true
        self.isSound = isSound
        takePhotoCompletion = completion
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = true
        photoSettings.isAutoStillImageStabilizationEnabled = true
        if #available(iOS 13.0, *) {
            photoSettings.photoQualityPrioritization = .speed
        } else {
            // Fallback on earlier versions
        }
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
    // 在deinit中也确保停止定时器
    deinit {
        stopCollectionTimer()
    }
}

extension CameraCapturer: AVCaptureVideoDataOutputSampleBufferDelegate {
    // 采集视频流
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isDetecting, isCollect else {
            logger?.logType(.capturer, message: "不再采集-- isDetecting:\(isDetecting)&isCollect:\(isCollect)")
            return
        }
        videoDataOutputSampleBufferBlock?(sampleBuffer, regionRectInImage)
    }
}

extension CameraCapturer: AVCapturePhotoCaptureDelegate {
    // 拍照
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        isTakingPhoto = false
        guard error == nil else {
            logger?.logType(.photoOutput, message: "\(error!)")
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) else {
            logger?.logType(.photoOutput, message: "处理照片时出错")
            return
        }
        takePhotoCompletion?(image)
    }
    
    public func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        guard !isSound else { return }
        AudioServicesDisposeSystemSoundID(1108)
    }
}

extension CameraCapturer {
    /// 识别区域
    /// - Parameters:
    ///   - regionRectInPreview: 识别区域的布局坐标- 相对preview
    ///   - type: 类型
    public func setRegionRectInPreview(_ regionRectInPreview: CGRect, for type: RegionRectType = .normal) {
        guard regionRectInPreview != .zero else {
            regionRectInImage = .zero
            return
        }
        let videoLayerSize = preview.frame.size
        let videoSize = sessionPresetSize
        let cropRect = regionRectInPreview
        
        let scaleX = videoSize.width / videoLayerSize.width
        let scaleY = videoSize.height / videoLayerSize.height
        switch type {
        case .normal:
            regionRectInImage = CGRect(
                x: cropRect.origin.x * scaleX,
                y: cropRect.origin.y * scaleY,
                width: cropRect.size.width * scaleX,
                height: cropRect.size.height * scaleY
            )
        case .appleNative:
            let scaledCropRect = CGRect(
                x: cropRect.origin.x * scaleX,
                y: cropRect.origin.y * scaleY,
                width: cropRect.size.width * scaleX,
                height: cropRect.size.height * scaleY
            )
            regionRectInImage = CGRect(
                x: 1 - ((scaledCropRect.origin.y + scaledCropRect.size.height) / videoSize.height),
                y: scaledCropRect.origin.x / videoSize.width,
                width: scaledCropRect.size.height / videoSize.height,
                height: scaledCropRect.size.width / videoSize.width
            )
        }
    }
}
#endif
