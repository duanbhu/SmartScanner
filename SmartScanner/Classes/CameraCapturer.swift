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
    case capturer, photoOutput, captureOutput
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
        // stopRunning() 在拍照中途停止会话时不保证回调在途请求的 didFinishProcessingPhoto，
        // 且 CameraCapturer 可被反复 start/stop 复用，若不清理会残留 isPhotoCaptureInProgress=true，
        // 导致下次 start 后视频帧被永久暂停、takePhoto 被永久拒绝。
        failInFlightPhotoCaptures(reason: "会话停止")
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
    
    /// 进行中的拍照请求代理。AVCapturePhotoOutput 支持多张在途拍照并按 delegate 区分，
    /// 这里保存强引用直到照片派发完成；数组同时用于限制在途请求数量。
    private var inFlightPhotoCaptures: [PhotoCaptureDelegate] = []

    /// takePhoto 可能从主线程/识别线程调用，代理移除发生在 AVF 回调队列，需加锁
    private let inFlightPhotoCapturesLock = NSLock()

    /// 拍照回调完成前暂停视频帧采集，由 inFlightPhotoCapturesLock 保护
    private var isPhotoCaptureInProgress = false

    /// 业务不需要连拍，同一时间只允许一个拍照请求
    private static let maxInFlightPhotoCaptures = 1

    private func photoCaptureInProgress() -> Bool {
        inFlightPhotoCapturesLock.lock()
        defer { inFlightPhotoCapturesLock.unlock() }
        return isPhotoCaptureInProgress
    }

    /// 会话中断或运行错误时的兜底清理：让所有在途拍照请求立即失败并恢复视频帧采集。
    /// 若不清理，AVF 在会话异常后可能永远不回调 didFinishProcessingPhoto，
    /// isPhotoCaptureInProgress 将永久为 true —— 视频帧被无限期丢弃（扫描识别整体停摆），
    /// 且在途计数占满后所有后续 takePhoto 都会被拒绝。
    /// 即使 AVF 之后仍补发了回调，PhotoCaptureDelegate 内部保证业务回调不会二次触发。
    private func failInFlightPhotoCaptures(reason: String) {
        inFlightPhotoCapturesLock.lock()
        let pending = inFlightPhotoCaptures
        inFlightPhotoCaptures.removeAll()
        isPhotoCaptureInProgress = false
        inFlightPhotoCapturesLock.unlock()

        guard !pending.isEmpty else { return }
        logger?.logType(.photoOutput, message: "会话异常（\(reason)），取消 \(pending.count) 个在途拍照请求")
        // 在锁外派发失败回调，避免业务回调中再次调用 takePhoto 造成死锁
        pending.forEach { $0.cancel() }
    }

    /// 拍照
    /// - Parameters:
    ///   - isSound: 是否发出声音：咔嚓 默认是false
    ///   - maxPixelSize: 回调图片的最大边长（像素），默认 2048。
    ///     ⚠️ 自 1.2.1 起回调图片不再是拍摄原图：默认会缩放到最长边不超过该值，
    ///     以降低解码内存峰值并保证图片可直接渲染。需要更大尺寸（如保存原图）的
    ///     调用方请显式传入更大的值。
    ///   - completion: 图片回调（保证回调的图片已完成解码、可直接渲染）
    ///   - onFailure: 失败回调：采集失败、在途请求过多、照片数据无法解码或会话异常中断时触发
    ///
    /// 每次拍照使用独立的代理对象承接回调。历史实现共享一个回调槽位，
    /// 在“上一张照片已到达、回调尚未派发”的窗口内发起新的拍照会覆盖旧回调，
    /// 导致 A 请求拍到的图片被派发给 B 请求（业务表现：A 图配 B 单号水印），
    /// 而 B 的真实照片随后被业务层按单号去重丢弃。
    public func takePhoto(isSound: Bool = false,
                          maxPixelSize: CGFloat = 2048,
                          completion: ((UIImage) -> ())?,
                          onFailure: (() -> ())? = nil) {
        guard let connection = photoOutput.connection(with: .video), connection.isEnabled, connection.isActive else {
            logger?.logType(.photoOutput, message: "拍照采集失败")
            onFailure?()
            return
        }

        let delegate = PhotoCaptureDelegate(
            isSound: isSound,
            maxPixelSize: maxPixelSize,
            completion: completion,
            failure: onFailure,
            log: { [weak self] message in
                self?.logger?.logType(.photoOutput, message: message)
            },
            didFinish: { [weak self] finished in
                guard let self = self else { return }
                self.inFlightPhotoCapturesLock.lock()
                self.inFlightPhotoCaptures.removeAll { $0 === finished }
                self.isPhotoCaptureInProgress = !self.inFlightPhotoCaptures.isEmpty
                self.inFlightPhotoCapturesLock.unlock()
            }
        )

        inFlightPhotoCapturesLock.lock()
        guard inFlightPhotoCaptures.count < CameraCapturer.maxInFlightPhotoCaptures else {
            inFlightPhotoCapturesLock.unlock()
            logger?.logType(.photoOutput, message: "在途拍照请求过多，本次已丢弃")
            onFailure?()
            return
        }
        inFlightPhotoCaptures.append(delegate)
        isPhotoCaptureInProgress = true
        inFlightPhotoCapturesLock.unlock()

        // AVCapturePhotoSettings 不允许复用，必须每次新建
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = true
        photoSettings.isAutoStillImageStabilizationEnabled = true
        if #available(iOS 13.0, *) {
            photoSettings.photoQualityPrioritization = .speed
        } else {
            // Fallback on earlier versions
        }
        photoOutput.capturePhoto(with: photoSettings, delegate: delegate)
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
            self.failInFlightPhotoCaptures(reason: "会话中断")
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
            self.failInFlightPhotoCaptures(reason: "会话运行错误")
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
        let isPhotoCaptureInProgress = photoCaptureInProgress()
        guard isDetecting, isCollect, !isPhotoCaptureInProgress else {
            logger?.logType(.captureOutput, message: "不再采集-- isDetecting:\(isDetecting)&isCollect:\(isCollect)&isPhotoCaptureInProgress:\(isPhotoCaptureInProgress)")
            return
        }
        videoDataOutputSampleBufferBlock?(sampleBuffer, regionRectInImage)
    }
}

extension CameraCapturer {
    /// 单次拍照请求的独立代理：持有本次请求的回调与配置，直到照片派发完成。
    /// 每个 capturePhoto 请求一个实例，从结构上杜绝共享回调槽位被后续请求覆盖、
    /// 图片与业务上下文（如运单号）错配的竞争问题。
    fileprivate final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        private let isSound: Bool
        private let maxPixelSize: CGFloat
        private let completion: ((UIImage) -> ())?
        private let failure: (() -> ())?
        private let log: (String) -> Void
        private let didFinish: (PhotoCaptureDelegate) -> Void

        /// 业务回调只允许派发一次：cancel（会话异常）与 AVF 正常回调可能都到达，需原子仲裁
        private let deliveryLock = NSLock()
        private var isDelivered = false

        init(isSound: Bool,
             maxPixelSize: CGFloat,
             completion: ((UIImage) -> ())?,
             failure: (() -> ())?,
             log: @escaping (String) -> Void,
             didFinish: @escaping (PhotoCaptureDelegate) -> Void) {
            self.isSound = isSound
            self.maxPixelSize = maxPixelSize
            self.completion = completion
            self.failure = failure
            self.log = log
            self.didFinish = didFinish
        }

        /// 原子获取派发权。返回 false 表示回调已被派发过（如已被 cancel），调用方不得再触发业务回调
        private func claimDelivery() -> Bool {
            deliveryLock.lock()
            defer { deliveryLock.unlock() }
            guard !isDelivered else { return false }
            isDelivered = true
            return true
        }

        /// 会话中断/运行错误时由 CameraCapturer 调用，使本次请求立即失败。
        /// 若 AVF 之后仍派发了 didFinishProcessingPhoto，claimDelivery 保证业务回调不会二次触发。
        func cancel() {
            guard claimDelivery() else { return }
            failure?()
        }

        func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
            guard !isSound else { return }
            AudioServicesDisposeSystemSoundID(1108)
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            defer { didFinish(self) }

            // 已被 cancel（会话异常兜底）时业务回调已派发，这里只做在途列表清理
            guard claimDelivery() else { return }

            guard error == nil else {
                log("\(error!)")
                failure?()
                return
            }

            // 历史问题：UIImage(data:) 产出的是懒解码图，高分辨率照片在内存紧张时
            // 首次渲染可能静默失败，业务侧表现为确认页空白、加水印后整图全黑。
            // 这里改为拍照后立即解码并限制最大边长，保证回调出去的图片一定可渲染；
            // 全部解码手段失败时走失败回调，而不是把坏图交给业务。
            if let imageData = photo.fileDataRepresentation(),
               let image = CameraCapturer.decodedImage(from: imageData, maxPixelSize: maxPixelSize) {
                completion?(image)
                return
            }

            // 兜底：直接取采集缓冲区的 CGImage（无需再走 JPEG 解码），按元数据还原方向。
            // 与主路径保持一致的最大边长限制，避免兜底时回调 12MP 大图导致两条路径行为不一致
            if let cgImage = photo.cgImageRepresentation() {
                log("照片数据解码失败，使用 cgImageRepresentation 兜底")
                let orientation = CameraCapturer.imageOrientation(fromPhotoMetadata: photo.metadata)
                let image = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
                completion?(CameraCapturer.downscaledImage(image, maxPixelSize: maxPixelSize))
                return
            }

            log("处理照片时出错：无法解码拍照数据")
            failure?()
        }
    }

    /// 立即解码照片数据并限制最大边长，返回已解码位图；失败返回 nil。
    /// - 下游展示与上传（压缩目标宽度约 1242px）都不需要原始 12MP 大图，
    ///   提前限制尺寸能显著降低解码内存峰值，也避免后续懒解码失败。
    /// - kCGImageSourceCreateThumbnailWithTransform 会同时应用 EXIF 方向，产出 .up 方向图片。
    private static func decodedImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
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

    /// 兜底路径的尺寸收敛：与主解码路径保持一致的最大边长限制。
    /// 重绘同时完成了立即解码与方向归一（产出 .up 方向位图），不超限时原样返回。
    private static func downscaledImage(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longSide = max(pixelWidth, pixelHeight)
        guard longSide > maxPixelSize, maxPixelSize > 0 else { return image }
        let ratio = maxPixelSize / longSide
        let targetSize = CGSize(width: (pixelWidth * ratio).rounded(.down),
                                height: (pixelHeight * ratio).rounded(.down))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
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
