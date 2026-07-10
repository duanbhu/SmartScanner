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
import ImageIO

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
    
    /// 会话通知观察者，deinit 时统一释放
    private var notificationObservers: [NSObjectProtocol] = []
    
    /// 记录当前页面是否期望会话处于运行状态（用于中断恢复）
    private var shouldKeepSessionRunning = false
    
    /// 防止多处并发触发 startRunning 导致状态竞争。
    private var isStartingSession = false
    
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
        var didLockDevice = false
        
        captureSession.beginConfiguration()

        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true

        defer {
            if didLockDevice {
                device.unlockForConfiguration()
            }
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
            didLockDevice = true
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
        
        setupSessionObservers()
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
        shouldKeepSessionRunning = true
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
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isStartingSession else { return }
            guard !self.captureSession.isRunning else {
                DispatchQueue.main.async {
                    self.setupCollectionTimer()
                    self.onSuccess?()
                }
                return
            }
            self.isStartingSession = true
            self.captureSession.startRunning()
            self.isStartingSession = false
            DispatchQueue.main.async {
                self.setupCollectionTimer()
                self.onSuccess?()
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
        shouldKeepSessionRunning = false
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
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

    /// 拍照失败回调（无法产出可渲染图片时触发），避免业务侧静默卡死
    private var takePhotoFailure: (() -> ())?

    /// 标识是否正在拍照
    private var isTakingPhoto = false

    /// 拍照时，是否播放声音
    private var isSound = true

    /// 拍照
    /// - Parameters:
    ///   - isSound: 是否发出声音：咔嚓 默认是false
    ///   - completion: 图片回调（保证回调的图片已完成解码、可直接渲染）
    ///   - onFailure: 失败回调：采集失败或照片数据无法解码时触发（正在拍照被忽略时不触发）
    public func takePhoto(isSound: Bool = false, completion: ((UIImage) -> ())?, onFailure: (() -> ())? = nil) {
        guard let connection = photoOutput.connection(with: .video), connection.isEnabled, connection.isActive else {
            logger?.logType(.photoOutput, message: "拍照采集失败")
            onFailure?()
            return
        }
        guard !isTakingPhoto else { return }
        isTakingPhoto = true
        self.isSound = isSound
        takePhotoCompletion = completion
        takePhotoFailure = onFailure
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
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
        stopCollectionTimer()
    }
}

private extension CameraCapturer {
    func setupSessionObservers() {
        let center = NotificationCenter.default
        
        let interrupted = center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.logger?.logType(.capturer, message: "会话中断，暂停采集")
            self.stopCollectionTimer()
        }
        
        let interruptionEnded = center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.logger?.logType(.capturer, message: "会话中断结束，尝试恢复")
            guard self.shouldKeepSessionRunning else { return }
            self.startCaptureSession()
        }
        
        let runtimeError = center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let nsError = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self.logger?.logType(.capturer, message: "会话运行错误: \(nsError?.localizedDescription ?? "unknown")")
            guard self.shouldKeepSessionRunning else { return }
            self.startCaptureSession()
        }
        
        let becameActive = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            guard self.shouldKeepSessionRunning else { return }
            self.startCaptureSession()
        }
        
        notificationObservers.append(contentsOf: [interrupted, interruptionEnded, runtimeError, becameActive])
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
            finishTakePhoto(with: nil)
            return
        }

        // 历史问题：UIImage(data:) 产出的是懒解码图，高分辨率照片在内存紧张时
        // 首次渲染可能静默失败，业务侧表现为确认页空白、加水印后整图全黑。
        // 这里改为拍照后立即解码并限制最大边长，保证回调出去的图片一定可渲染；
        // 全部解码手段失败时走失败回调，而不是把坏图交给业务。
        if let imageData = photo.fileDataRepresentation(),
           let image = CameraCapturer.decodedImage(from: imageData) {
            finishTakePhoto(with: image)
            return
        }

        // 兜底：直接取采集缓冲区的 CGImage（无需再走 JPEG 解码），按元数据还原方向
        if let cgImage = photo.cgImageRepresentation() {
            logger?.logType(.photoOutput, message: "照片数据解码失败，使用 cgImageRepresentation 兜底")
            let orientation = CameraCapturer.imageOrientation(fromPhotoMetadata: photo.metadata)
            finishTakePhoto(with: UIImage(cgImage: cgImage, scale: 1, orientation: orientation))
            return
        }

        logger?.logType(.photoOutput, message: "处理照片时出错：无法解码拍照数据")
        finishTakePhoto(with: nil)
    }

    /// 统一收口拍照结果：成功回调图片，失败回调 onFailure，并清理一次性回调
    private func finishTakePhoto(with image: UIImage?) {
        let completion = takePhotoCompletion
        let failure = takePhotoFailure
        takePhotoCompletion = nil
        takePhotoFailure = nil
        if let image = image {
            completion?(image)
        } else {
            failure?()
        }
    }

    /// 立即解码照片数据并限制最大边长，返回已解码位图；失败返回 nil。
    /// - 下游展示与上传（压缩目标宽度约 1242px）都不需要原始 12MP 大图，
    ///   提前限制尺寸能显著降低解码内存峰值，也避免后续懒解码失败。
    /// - kCGImageSourceCreateThumbnailWithTransform 会同时应用 EXIF 方向，产出 .up 方向图片。
    private static func decodedImage(from data: Data, maxPixelSize: CGFloat = 2048) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// 从拍照元数据中读取 EXIF 方向并转换为 UIImage.Orientation
    private static func imageOrientation(fromPhotoMetadata metadata: [String: Any]) -> UIImage.Orientation {
        guard let raw = (metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.uint32Value,
              let cgOrientation = CGImagePropertyOrientation(rawValue: raw) else {
            return .up
        }
        switch cgOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
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
