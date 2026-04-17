//
//  ImageDetector.swift
//  MobileExt
//
//  Created by Duanhu on 2024/3/22.
//

import UIKit
import CoreMedia

public protocol DetecteEngineProtocol {
    
    typealias Handler = (UIImage?) -> ()
    
    /// 图像识别
    /// - Parameters:
    ///   - sampleBuffer: 图像
    ///   - regionRect: 识别区域-- 仅针对文本， 条码、二维码为全屏扫
    ///   - response: 识别结果
    ///   - handle: 识别后处理回调
    func recognize(sampleBuffer: CMSampleBuffer, regionRect: CGRect, handle: @escaping Handler)
    
    func response(_ response: inout RecognitionResponse)
    
    func reset(detecteOptions: DetecteOptions)
    
    /// 识别图片， 目前仅处理条码、二维码识别
    func recognize(image: UIImage, completion: (DetectResult) -> ())
}

public struct DetecteOptions: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let qrcode        = DetecteOptions(rawValue : 1 << 0) // 二维码  不支持和文本同时识别
    public static let barcode       = DetecteOptions(rawValue : 1 << 1) // 条形码
    public static let phoneNumber   = DetecteOptions(rawValue : 1 << 2) // 手机号
    public static let privacyNumber = DetecteOptions(rawValue : 1 << 3) // 隐私号，带星号
    public static let virtualNumber = DetecteOptions(rawValue : 1 << 4) // 虚拟号-分机号
    
    /// 虚拟号+手机号
    public static let virtualPhone: DetecteOptions = [.virtualNumber, .phoneNumber]
    
    /// 隐私面单
    public static let secretSheet: DetecteOptions = [.barcode, .privacyNumber, .phoneNumber]
    
    /// 识别条码与二维码
    public static let allcode: DetecteOptions = [.qrcode, .barcode]

    /// 是否需要识别文本
    public var containsText: Bool {
        return contains(.phoneNumber) || contains(.privacyNumber) || contains(.virtualNumber)
    }
}

@objc(SmartScannerDetectorConfig)
public class DetectorConfig: NSObject {
    
    public static let shared: DetectorConfig = .init()
    
    /// 是否支持换行，仅对识别手机号、虚拟号，在识别区域小时可设置true  (TODO)
    public var isSupportLineBreaks = false
    
    /// 虚拟号， 一个识别周期内，重复出现次数达到minimum，则认为识别成功
    public var virtualNumberMinimum = 2
    
    /// 是否开启打印日志， 默认为false
    public var logEnabled = false
    
    static func logPrint(_ text: String) {
        guard shared.logEnabled else { return }
        debugPrint(text)
    }
}

@objc(SmartScannerImageDetector)
public class ImageDetector: NSObject {
    
    public typealias CompletionHandler = (DetectResult) -> ()
    
    /// 检测目标的选项， 如条形码、手机号、隐私号...
    var detecteOptions: DetecteOptions
    
    /// 识别引擎：谷歌MLKit、苹果原生
    let engines: [DetecteEngineProtocol]
    
    /// 识别结果
    private var completion: CompletionHandler? = nil
    
    /// 识别返回的元素集合
    private var response = RecognitionResponse()
    
    // MARK: - init
    public init(options: DetecteOptions, engines: DetecteEngineProtocol...) {
        self.engines = engines
        self.detecteOptions = options
        
        for engine in engines {
            engine.response(&response)
        }
    }
    
    public func recognize(sampleBuffer: CMSampleBuffer, regionRect: CGRect) {
        for engine in engines {
            engine.recognize(sampleBuffer: sampleBuffer, regionRect: regionRect, handle: handle)
        }
    }
    
    /// 识别图片， 目前仅处理条码、二维码识别
    public func recognize(image: UIImage, completion: @escaping (DetectResult) -> ()) {
        DispatchQueue.global(qos: .userInitiated).async {
            for engine in self.engines {
                engine.recognize(image: image) { ret in
                    DispatchQueue.main.async {
                        completion(ret)
                    }
                }
            }
        }
    }
    
    private func handle(_ image: UIImage?) {
        handleOfSecretSheet(image)
        onlyBarcodeHandle()
        virtualPhoneHandle()
        onlyPhoneHandle()
        onlyQrcodeHandle()
        allCodeHandle()
    }
    
    private func stop(of result: DetectResult) {
        response.cleanAll()
        DispatchQueue.main.async { [self] in
            completion?(result)
        }
    }
    
    @discardableResult
    public func completion(_ completion: @escaping CompletionHandler) -> Self {
        self.completion = completion
        return self
    }
    
    /// 重置识别目标类型
    /// - Parameter detecteOptions: 识别类型
    public func reset(detecteOptions: DetecteOptions) {
        self.detecteOptions = detecteOptions
        response.cleanAll()
        engines.forEach {
            $0.reset(detecteOptions: detecteOptions)
        }
    }
}

extension ImageDetector {
    /// 隐私面单  - 识别单号+手机号/隐私号
    private func handleOfSecretSheet(_ image: UIImage?) {
        guard detecteOptions == .secretSheet else { return }
        // 先获取单号
        guard let barcode = response.barCountedSet.mostElement(max: 2) else { return }

        if let phone = response.phoneCountedSet.mostElement(max: 2) {
            let ret = DetectResult(
                barcode: barcode,
                phone: phone,
                cropImage: image
            )
            stop(of: ret)
        }
        
        // 隐私号
        if let privacy = response.privacyCountedSet.mostElement(max: 2) {
            stop(of: .init(
                barcode: barcode,
                privacyNumber: privacy,
                cropImage: image
            ))
        }
    }
    
    /// 仅需要单号
    private func onlyBarcodeHandle() {
        guard detecteOptions == .barcode else { return }
        guard let barcode = response.barCountedSet.mostElement(max: 2) else { return }
        stop(of: .init(
            barcode: barcode
        ))
    }
    
    /// 仅需要手机号
    private func onlyPhoneHandle() {
        guard detecteOptions == .phoneNumber else { return }
        guard let phone = response.phoneCountedSet.mostElement(max: 3) else { return }
        stop(of: .init(
            phone: phone
        ))
    }
    
    /// 虚拟号+手机号
    private func virtualPhoneHandle() {
        guard detecteOptions == .virtualPhone else { return }
        if let virtual = response.virtualCountedSet.mostElement(max: DetectorConfig.shared.virtualNumberMinimum) {
            // 仅识别出虚拟号
            let ret = DetectResult(
                virtualNumber: virtual
            )
            stop(of: ret)
        } else if let phone = response.phoneCountedSet.mostElement(max: 2) {
            let ret = DetectResult(
                phone: phone
            )
            stop(of: ret)
        }
    }
    
    /// 仅需要二维码
    private func onlyQrcodeHandle() {
        guard detecteOptions == .qrcode else { return }
        guard let qrcode = response.qrCountedSet.mostElement(max: 2) else { return }
        stop(of: .init(
            qrcode: qrcode
        ))
    }
    
    /// 条形码与二维码
    private func allCodeHandle() {
        guard detecteOptions == .allcode else { return }
        
        if let qrcode = response.barCountedSet.mostElement(max: 2) {
            stop(of: .init(
                barcode: qrcode
            ))
        }
        
        if let qrcode = response.qrCountedSet.mostElement(max: 2) {
            stop(of: .init(
                qrcode: qrcode
            ))
        }
    }
}
