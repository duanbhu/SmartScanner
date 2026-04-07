//
//  GoogleEngineUpgrade.swift
//  SwiftyCamera
//
//  Created by Codex on 2026/3/28.
//

import UIKit
import CoreMedia
#if targetEnvironment(simulator)
@objc(SmartScannerGoogleEngineUpgrade)
public class GoogleEngineUpgrade: NSObject, DetecteEngineProtocol {
    
    var options: DetecteOptions
    
    private var response: RecognitionResponse? = nil
    
    public init(options: DetecteOptions) {
        self.options = options
    }
    
    public func response(_ response: inout RecognitionResponse) {
        self.response = response
    }
    
    public func recognize(sampleBuffer: CMSampleBuffer, regionRect: CGRect, handle: (UIImage?) -> ()) {
    }
    
    public func reset(detecteOptions: DetecteOptions) {
        self.options = detecteOptions
    }
    
    public func recognize(image: UIImage, completion: (DetectResult) -> ()) {
        
    }
}

#else
import MLKitCommon
import MLKitVision
import MLImage
import MLKitBarcodeScanning
import MLKitTextRecognition
import MLKitTextRecognitionChinese

/// Google 升级版引擎：用于单点试点，不影响默认 GoogleEngine。
@objc(SmartScannerGoogleEngineUpgrade)
public class GoogleEngineUpgrade: NSObject, DetecteEngineProtocol {
    
    var options: DetecteOptions
    
    private var response: RecognitionResponse? = nil
    
    /// 是否启用换行处理模式
    private var enableNewlineHandling: Bool = true
    
    /// 是否启用图片预处理以提高 OCR 准确度
    private var enableImagePreprocessing: Bool = true
    
    /// 图片预处理选项
    private var preprocessOptions: ImagePreprocessor.PreprocessOptions = .recommended
    
    /// 最多尝试的 OCR 候选图数量
    private let maxOCRCandidates = 3
    
    /// 实时流最多尝试的 OCR 候选图数量
    private let maxRealtimeOCRCandidates = 2
    
    /// 实时 OCR 最小间隔，避免高频重复识别打满 CPU
    private let minimumRealtimeRecognitionInterval: CFTimeInterval = 0.22
    
    /// 文本识别器复用，避免每次重复创建重对象
    private lazy var textRecognizer = TextRecognizer.textRecognizer(options: ChineseTextRecognizerOptions())
    
    /// 实时 OCR 是否正在执行
    private var isRealtimeTextRecognitionInFlight = false
    
    /// 上次实时 OCR 时间
    private var lastRealtimeRecognitionTime: CFAbsoluteTime = 0
    
    /// 手机号提取器（懒加载）
    private lazy var phoneExtractor: PhoneExtractor = {
        let filter = PrefixFilter(customPrefixes: [])
        return PhoneExtractor(prefixFilter: filter,
                            enableLogging: DetectorConfig.shared.logEnabled,
                            enableNewlineHandling: self.enableNewlineHandling)
    }()
    
    public init(options: DetecteOptions) {
        self.options = options
    }
    
    public func response(_ response: inout RecognitionResponse) {
        self.response = response
    }
    
    /// 配置换行处理模式
    /// - Parameter enabled: 是否启用换行处理
    public func setNewlineHandling(enabled: Bool) {
        self.enableNewlineHandling = enabled
        self.phoneExtractor = PhoneExtractor(
            prefixFilter: PrefixFilter(customPrefixes: []),
            enableLogging: DetectorConfig.shared.logEnabled,
            enableNewlineHandling: enabled
        )
    }
    
    /// 配置图片预处理
    /// - Parameters:
    ///   - enabled: 是否启用图片预处理
    ///   - options: 预处理选项，默认使用推荐配置
    internal func setImagePreprocessing(enabled: Bool, options: ImagePreprocessor.PreprocessOptions = .recommended) {
        self.enableImagePreprocessing = enabled
        self.preprocessOptions = options
    }
    
    public func recognize(sampleBuffer: CMSampleBuffer, regionRect: CGRect, handle: (UIImage?) -> ()) {
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer) else {
            DetectorConfig.logPrint("Invalid or not ready sample buffer")
            handle(nil)
            return
        }
        
        let visionImage = VisionImage(buffer: sampleBuffer)
        recognizeBarcode(in: visionImage)
        var cropImage: UIImage? = nil
        if regionRect != .zero, let image = ImageUtilities.cropImageFromSampleBuffer(sampleBuffer: sampleBuffer, cropRect: regionRect) {
            cropImage = image
            recognizeRealtimeTextCandidates(from: image)
        } else {
            recognizeText(in: visionImage)
        }
        
        handle(cropImage)
    }
    
    public func reset(detecteOptions: DetecteOptions) {
        self.options = detecteOptions
    }
    
    public func recognize(image: UIImage, completion: (DetectResult) -> ()) {
        guard image.cgImage != nil || image.ciImage != nil else {
            DetectorConfig.logPrint("Invalid UIImage: no CGImage or CIImage available")
            completion(DetectResult())
            return
        }
        
        let visionImage = VisionImage(image: image)
        recognizeBarcode(in: visionImage, completion: completion)
    }
}

extension GoogleEngineUpgrade {
    
    private func scanBarcodes(in visionImage: VisionImage) -> [Barcode] {
        var barcodes: [Barcode] = []
        do {
            barcodes = try BarcodeScanner.barcodeScanner(options: BarcodeScannerOptions(formats: .all))
                .results(in: visionImage)
        } catch let error {
            DetectorConfig.logPrint("Failed to scan barcodes with error: \(error.localizedDescription).")
        }
        return barcodes
    }
    
    private func recognizeBarcode(in visionImage: VisionImage) {
        guard options.contains(.barcode) || options.contains(.qrcode)  else { return }
        
        let barcodes = scanBarcodes(in: visionImage)
        let qrFormats: [BarcodeFormat] = [.dataMatrix, .qrCode, .PDF417, .aztec]
        for barcode in barcodes {
            guard let code = barcode.displayValue else { continue }
            if qrFormats.contains(where: { $0 == barcode.format }) {
                response?.addQrcode(code)
            } else {
                response?.addBarcode(code)
            }
            DetectorConfig.logPrint("扫描：\(barcode.format), \(code)")
        }
    }
    
    private func recognizeBarcode(in visionImage: VisionImage, completion: (DetectResult) -> ()) {
        guard options.contains(.barcode) || options.contains(.qrcode)  else { return }
        
        let barcodes = scanBarcodes(in: visionImage)
        let result = DetectResult()
        let qrFormats: [BarcodeFormat] = [.dataMatrix, .qrCode, .PDF417, .aztec]
        for barcode in barcodes {
            guard let code = barcode.displayValue else { continue }
            if qrFormats.contains(where: { $0 == barcode.format }) {
                result.qrcode = code
            } else {
                result.barcode = code
            }
            DetectorConfig.logPrint("扫描：\(code)")
        }
        completion(result)
    }
    
    private func recognizeText(in image: VisionImage) {
        guard options.containsText else {
            return
        }
        
        var recognizedText: Text?
        do {
            image.orientation = .up
            recognizedText = try textRecognizer.results(in: image)
        } catch let error {
            DetectorConfig.logPrint("Failed to recognize text with error: \(error.localizedDescription).")
            if let nsError = error as NSError? {
                DetectorConfig.logPrint("Error domain: \(nsError.domain), code: \(nsError.code)")
                DetectorConfig.logPrint("Error userInfo: \(nsError.userInfo)")
            }
            return
        }
        guard let recognizedText = recognizedText else {
            DetectorConfig.logPrint("Text recognition returned nil result")
            return
        }
        
        if options.contains(.barcode) {
            response?.checkClean()
        }
        debugPrint("识别结果：\(recognizedText.text)")
        extractPhones(from: recognizedText.text)
    }
    
    private func recognizeTextCandidates(from image: UIImage) {
        guard options.containsText else { return }
        
        let candidates: [ImagePreprocessor.Candidate]
        let start = CFAbsoluteTimeGetCurrent()
        
        if enableImagePreprocessing {
            candidates = Array(
                ImagePreprocessor.preprocessCandidates(image, baseOptions: preprocessOptions)
                    .prefix(maxOCRCandidates)
            )
        } else {
            candidates = [.init(name: "original", image: image)]
        }
        
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        DetectorConfig.logPrint("🧠 预处理候选数: \(candidates.count), 耗时: \(String(format: "%.2f", duration)) ms")
        
        for candidate in candidates {
            DetectorConfig.logPrint("🧠 OCR候选图: \(candidate.name)")
            let visionImage = VisionImage(image: candidate.image)
            recognizeText(in: visionImage)
        }
    }
    
    private func recognizeRealtimeTextCandidates(from image: UIImage) {
        guard options.containsText else { return }
        guard shouldRunRealtimeTextRecognition() else { return }
        
        isRealtimeTextRecognitionInFlight = true
        defer { isRealtimeTextRecognitionInFlight = false }
        
        let candidates: [ImagePreprocessor.Candidate]
        let start = CFAbsoluteTimeGetCurrent()
        
        if enableImagePreprocessing {
            candidates = Array(
                ImagePreprocessor.preprocessCandidates(image, baseOptions: preprocessOptions)
                    .prefix(maxRealtimeOCRCandidates)
            )
        } else {
            candidates = [.init(name: "original", image: image)]
        }
        
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        DetectorConfig.logPrint("🧠 实时预处理候选数: \(candidates.count), 耗时: \(String(format: "%.2f", duration)) ms")
        
        for candidate in candidates {
            let visionImage = VisionImage(image: candidate.image)
            recognizeText(in: visionImage)
        }
        
        lastRealtimeRecognitionTime = CFAbsoluteTimeGetCurrent()
    }
    
    private func shouldRunRealtimeTextRecognition() -> Bool {
        guard !isRealtimeTextRecognitionInFlight else { return false }
        let now = CFAbsoluteTimeGetCurrent()
        return now - lastRealtimeRecognitionTime >= minimumRealtimeRecognitionInterval
    }
    
    private func extractPhones(from text: String) {
        let result = phoneExtractor.extractPhones(from: text)
        
        if result.virtualPhones.count > 0 {
            DetectorConfig.logPrint("扫描结果：\(result.virtualPhones)")
            response?.virtualCountedSet.addObjects(from: Array(result.virtualPhones))
        } else if result.normalPhones.count > 0 {
            DetectorConfig.logPrint("扫描结果：\(result.normalPhones)")
            response?.phoneCountedSet.addObjects(from: Array(result.normalPhones))
        }
        
        if result.privacyPhones.count > 0 {
            response?.privacyCountedSet.addObjects(from: Array(result.privacyPhones))
        }
    }
}

#endif
