//
//  AppleEngine.swift
//  SwiftyCamera
//
//  Created by Codex on 2026/3/27.
//

import UIKit
import CoreMedia
import Vision
import ImageIO

@objc(SmartScannerAppleEngine)
public class AppleEngine: NSObject, DetecteEngineProtocol {
    
    var options: DetecteOptions
    
    private var response: RecognitionResponse? = nil
    
    /// 是否启用换行处理模式
    private var enableNewlineHandling: Bool = true
    
    /// 是否启用图片预处理
    private var enableImagePreprocessing: Bool = true
    
    /// 图片预处理选项
    private var preprocessOptions: ImagePreprocessor.PreprocessOptions = .recommended
    
    /// 实时 OCR 最小间隔，避免占用过高
    private let minimumRealtimeRecognitionInterval: CFTimeInterval = 0.2
    
    /// 上次实时 OCR 时间
    private var lastRealtimeRecognitionTime: CFAbsoluteTime = 0
    
    /// 防止同一时间重复执行实时 OCR
    private var isRealtimeTextRecognitionInFlight = false
    
    /// 文本识别语言
    private let recognitionLanguages = ["zh-Hans", "en-US"]
    
    /// CIContext 仅用于 CIImage 转 CGImage
    private lazy var ciContext = CIContext(options: nil)
    
    /// 手机号提取器
    private lazy var phoneExtractor: PhoneExtractor = {
        let filter = PrefixFilter(customPrefixes: [])
        return PhoneExtractor(
            prefixFilter: filter,
            enableLogging: DetectorConfig.shared.logEnabled,
            enableNewlineHandling: self.enableNewlineHandling
        )
    }()
    
    public init(options: DetecteOptions) {
        self.options = options
    }
    
    public func response(_ response: inout RecognitionResponse) {
        self.response = response
    }
    
    public func setNewlineHandling(enabled: Bool) {
        self.enableNewlineHandling = enabled
        self.phoneExtractor = PhoneExtractor(
            prefixFilter: PrefixFilter(customPrefixes: []),
            enableLogging: DetectorConfig.shared.logEnabled,
            enableNewlineHandling: enabled
        )
    }
    
    internal func setImagePreprocessing(enabled: Bool,
                                        options: ImagePreprocessor.PreprocessOptions = .recommended) {
        self.enableImagePreprocessing = enabled
        self.preprocessOptions = options
    }
    
    public func recognize(sampleBuffer: CMSampleBuffer, regionRect: CGRect, handle: Handler) {
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer) else {
            DetectorConfig.logPrint("AppleEngine: invalid or not ready sample buffer")
            handle(nil)
            return
        }
        
        recognizeBarcode(in: sampleBuffer)
        
        var cropImage: UIImage? = nil
        if regionRect != .zero,
           let image = ImageUtilities.cropImageFromSampleBuffer(sampleBuffer: sampleBuffer, cropRect: regionRect) {
            cropImage = image
            recognizeRealtimeText(from: image)
        } else {
            recognizeText(in: sampleBuffer)
        }
        
        handle(cropImage)
    }
    
    public func reset(detecteOptions: DetecteOptions) {
        self.options = detecteOptions
    }
    
    public func recognize(image: UIImage, completion: (DetectResult) -> ()) {
        let result = DetectResult()
        let observations = detectBarcodes(in: image)
        
        for observation in observations {
            guard let code = observation.payloadStringValue else { continue }
            if observation.symbology.isQRCodeFamily {
                result.qrcode = code
            } else {
                result.barcode = code
            }
        }
        
        completion(result)
    }
}

extension AppleEngine {
    
    private func recognizeBarcode(in sampleBuffer: CMSampleBuffer) {
        guard options.contains(.barcode) || options.contains(.qrcode) else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectBarcodesRequest()
        
        do {
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .right,
                options: [:]
            )
            try handler.perform([request])
        } catch {
            DetectorConfig.logPrint("AppleEngine barcode recognize failed: \(error.localizedDescription)")
            return
        }
        
        let observations = request.results ?? []
        appendBarcodes(from: observations)
    }
    
    private func detectBarcodes(in image: UIImage) -> [VNBarcodeObservation] {
        guard let cgImage = image.normalizedCGImage(using: ciContext) else { return [] }
        
        let request = VNDetectBarcodesRequest()
        do {
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: image.cgImagePropertyOrientation,
                options: [:]
            )
            try handler.perform([request])
        } catch {
            DetectorConfig.logPrint("AppleEngine image barcode recognize failed: \(error.localizedDescription)")
            return []
        }
        
        return request.results ?? []
    }
    
    private func appendBarcodes(from observations: [VNBarcodeObservation]) {
        for observation in observations {
            guard let code = observation.payloadStringValue else { continue }
            if observation.symbology.isQRCodeFamily {
                response?.addQrcode(code)
            } else {
                response?.addBarcode(code)
            }
            DetectorConfig.logPrint("AppleEngine 扫描：\(observation.symbology.rawValue), \(code)")
        }
    }
    
    private func recognizeRealtimeText(from image: UIImage) {
        guard options.containsText else { return }
        guard shouldRunRealtimeTextRecognition() else { return }
        guard #available(iOS 13.0, *) else { return }
        
        isRealtimeTextRecognitionInFlight = true
        defer { isRealtimeTextRecognitionInFlight = false }
        
        let sourceImage: UIImage
        if enableImagePreprocessing {
            sourceImage = ImagePreprocessor.preprocess(image, options: preprocessOptions)
        } else {
            sourceImage = image
        }
        
        recognizeText(in: sourceImage)
        lastRealtimeRecognitionTime = CFAbsoluteTimeGetCurrent()
    }
    
    private func recognizeText(in sampleBuffer: CMSampleBuffer) {
        guard options.containsText else { return }
        guard #available(iOS 13.0, *) else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = makeTextRequest()
        do {
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .right,
                options: [:]
            )
            try handler.perform([request])
        } catch {
            DetectorConfig.logPrint("AppleEngine text recognize failed: \(error.localizedDescription)")
            return
        }
        
        handleRecognizedText(request.results)
    }
    
    private func recognizeText(in image: UIImage) {
        guard options.containsText else { return }
        guard #available(iOS 13.0, *) else { return }
        guard let cgImage = image.normalizedCGImage(using: ciContext) else { return }
        
        let request = makeTextRequest()
        do {
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: image.cgImagePropertyOrientation,
                options: [:]
            )
            try handler.perform([request])
        } catch {
            DetectorConfig.logPrint("AppleEngine image text recognize failed: \(error.localizedDescription)")
            return
        }
        
        handleRecognizedText(request.results)
    }
    
    @available(iOS 13.0, *)
    private func makeTextRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = recognitionLanguages
        return request
    }
    
    @available(iOS 13.0, *)
    private func handleRecognizedText(_ observations: [VNRecognizedTextObservation]?) {
        let text = observations?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
        
        guard !text.isEmpty else { return }
        
        if options.contains(.barcode) {
            response?.checkClean()
        }
        
        DetectorConfig.logPrint("AppleEngine 识别结果：\(text)")
        extractPhones(from: text)
    }
    
    private func shouldRunRealtimeTextRecognition() -> Bool {
        guard !isRealtimeTextRecognitionInFlight else { return false }
        let now = CFAbsoluteTimeGetCurrent()
        return now - lastRealtimeRecognitionTime >= minimumRealtimeRecognitionInterval
    }
    
    private func extractPhones(from text: String) {
        let result = phoneExtractor.extractPhones(from: text)
        
        if !result.virtualPhones.isEmpty {
            response?.virtualCountedSet.addObjects(from: Array(result.virtualPhones))
        } else if !result.normalPhones.isEmpty {
            response?.phoneCountedSet.addObjects(from: Array(result.normalPhones))
        }
        
        if !result.privacyPhones.isEmpty {
            response?.privacyCountedSet.addObjects(from: Array(result.privacyPhones))
        }
    }
}

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:
            return .up
        case .down:
            return .down
        case .left:
            return .left
        case .right:
            return .right
        case .upMirrored:
            return .upMirrored
        case .downMirrored:
            return .downMirrored
        case .leftMirrored:
            return .leftMirrored
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
    
    func normalizedCGImage(using context: CIContext) -> CGImage? {
        if let cgImage = cgImage {
            return cgImage
        }
        
        guard let ciImage = ciImage else { return nil }
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}

private extension VNBarcodeSymbology {
    var isQRCodeFamily: Bool {
        switch self {
        case .aztec, .dataMatrix, .qr, .pdf417:
            return true
        default:
            return false
        }
    }
}
