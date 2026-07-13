//
//  GoogleEngine.swift
//  MobileExt
//
//  Created by Duanhu on 2024/3/22.
//

import UIKit
import CoreMedia
#if targetEnvironment(simulator)
@objc(SmartScannerGoogleEngine)
public class GoogleEngine: NSObject, DetecteEngineProtocol {
    
    var options: DetecteOptions
    
    private var response: RecognitionResponse? = nil
    
    public init(options: DetecteOptions) {
        self.options = options
    }
    
    public func response(_ response: inout RecognitionResponse) {
        self.response = response
    }
    
    public func recognize(sampleBuffer: CMSampleBuffer, regionRect: CGRect, handle: @escaping (UIImage?) -> ()) {
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

/// 默认 Google 引擎：保持旧版实现，避免影响存量扫描业务。
@objc(SmartScannerGoogleEngine)
public class GoogleEngine: NSObject, DetecteEngineProtocol {

    /// MLKit 的 TextRecognizer/BarcodeScanner 工厂方法返回的是按 options 缓存的共享实例，
    /// 底层 visionkit::Pipeline 要求串行、按帧序处理；多个扫描场景（如页面切换时新旧会话的
    /// 采集队列短暂并存、悬浮窗与扫描页同时运行）从各自的 sessionQueue 并发调用 results(in:)
    /// 会命中其内部 CHECK 断言直接 abort（线上崩溃点：visionkit::Pipeline::Process →
    /// LogMessageFatal → abort，覆盖 1.2.4~1.3.0、iOS 16~26 全部版本）。
    /// 因此所有引擎实例的 MLKit 同步识别调用统一收口到这条全局串行队列。
    static let mlkitRecognitionQueue = DispatchQueue(label: "com.smartscanner.mlkit.recognition")

    var options: DetecteOptions

    private var response: RecognitionResponse? = nil

    public init(options: DetecteOptions) {
        self.options = options
    }
    
    public func response(_ response: inout RecognitionResponse) {
        self.response = response
    }
    
    public func recognize(sampleBuffer: CMSampleBuffer, regionRect: CGRect, handle: @escaping (UIImage?) -> ()) {
        var visionImage = VisionImage(buffer: sampleBuffer)
        recognizeBarcode(in: visionImage)
        var cropImage: UIImage? = nil
        if regionRect != .zero, let image = ImageUtilities.cropImageFromSampleBuffer(sampleBuffer: sampleBuffer, cropRect: regionRect) {
            cropImage = image
            visionImage = VisionImage(image: image)
        }
        recognizeText(in: visionImage)
        
        handle(cropImage)
    }
    
    public func reset(detecteOptions: DetecteOptions) {
        self.options = detecteOptions
    }
    
    /// 识别图片， 目前仅处理条码、二维码识别
    public func recognize(image: UIImage, completion: (DetectResult) -> ()) {
        let visionImage = VisionImage(image: image)
        recognizeBarcode(in: visionImage, completion: completion)
    }
}

extension GoogleEngine {
    
    /// 扫描条形码和二维码
    /// - Parameter visionImage: 图片
    /// - Returns: 扫描结果数组
    private func scanBarcodes(in visionImage: VisionImage) -> [Barcode] {
        var barcodes: [Barcode] = []
        do {
            // This method must be called on a background thread.
            // 串行收口，防止多采集队列并发触发 MLKit 内部断言崩溃，见 mlkitRecognitionQueue 注释
            barcodes = try GoogleEngine.mlkitRecognitionQueue.sync {
                try BarcodeScanner.barcodeScanner(options: BarcodeScannerOptions(formats: .all))
                    .results(in: visionImage)
            }
        } catch let error {
            DetectorConfig.logPrint("Failed to scan barcodes with error: \(error.localizedDescription).")
        }
        return barcodes
    }
    
    /// 识别条形码并添加到响应
    /// - Parameter visionImage: 图片
    private func recognizeBarcode(in visionImage: VisionImage) {
        guard options.contains(.barcode) || options.contains(.qrcode)  else {  return  }
        
        let barcodes = scanBarcodes(in: visionImage)
        let qrFormats: [BarcodeFormat] = [.dataMatrix, .qrCode, .PDF417, .aztec]
        for barcode in barcodes {
            guard let code = barcode.displayValue else { continue }
            if qrFormats.contains(where: {$0 == barcode.format}) {
                response?.addQrcode(code)
            } else {
                response?.addBarcode(code)
            }
            DetectorConfig.logPrint("扫描：\(barcode.format), \(code)")
        }
    }
    
    /// 识别条形码并返回结果
    /// - Parameters:
    ///   - visionImage: 图片
    ///   - completion: 完成回调
    private func recognizeBarcode(in visionImage: VisionImage, completion: (DetectResult) -> ()) {
        guard options.contains(.barcode) || options.contains(.qrcode)  else {  return  }
        
        let barcodes = scanBarcodes(in: visionImage)
        let result = DetectResult()
        let qrFormats: [BarcodeFormat] = [.dataMatrix, .qrCode, .PDF417, .aztec]
        for barcode in barcodes {
            guard let code = barcode.displayValue else { continue }
            if qrFormats.contains(where: {$0 == barcode.format}) {
                result.qrcode = code
            } else {
                result.barcode = code
            }
            DetectorConfig.logPrint("扫描：\(code)")
        }
        completion(result)
    }
    
    /// 识别文本
    private func recognizeText(sampleBuffer: CMSampleBuffer, regionRect: CGRect) {
        guard options.containsText else {
            return
        }
    
        if regionRect != .zero, let image = ImageUtilities.cropImageFromSampleBuffer(sampleBuffer: sampleBuffer, cropRect: regionRect) {
            let visionImage = VisionImage(image: image)
            recognizeText(in: visionImage)
        }
    }
    
    /// 识别文本
    private func recognizeText(in image: VisionImage) {
        guard options.containsText else {
            return
        }
        
        var recognizedText: Text?
        let textRecognizer = TextRecognizer.textRecognizer(options: ChineseTextRecognizerOptions())
        do {
            // 串行收口，防止多采集队列并发触发 MLKit 内部断言崩溃，见 mlkitRecognitionQueue 注释
            recognizedText = try GoogleEngine.mlkitRecognitionQueue.sync {
                try textRecognizer.results(in: image)
            }
        } catch let error {
            DetectorConfig.logPrint("Failed to recognize text with error: \(error.localizedDescription).")
        }
        guard let recognizedText = recognizedText else { return }
        
        if options.contains(.barcode) {
            response?.checkClean()
        }
        for block in recognizedText.blocks {
            for line in block.lines {
                let text = line.elements.map { $0.text }.joined()
                DetectorConfig.logPrint("扫描：\(text)")
                let virtuals = text.matcheVirtualPhone()
                if virtuals.count > 0 {
                    response?.virtualCountedSet.addObjects(from: virtuals)
                } else {
                    let mobiles = text.matchePhoneNumbers()
                    if mobiles.count > 0 {
                        response?.phoneCountedSet.addObjects(from: mobiles)
                    }
                }
                let privacys = text.matchePrivacyPhones()
                if privacys.count > 0 {
                    response?.privacyCountedSet.addObjects(from: privacys)
                }
            }
        }
    }
}
#endif
