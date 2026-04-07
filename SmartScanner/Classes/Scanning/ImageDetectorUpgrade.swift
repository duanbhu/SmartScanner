//
//  ImageDetectorUpgrade.swift
//  SwiftyCamera
//
//  Created by Codex on 2026/3/28.
//

import UIKit
import CoreMedia

/// 试点版识别器：需要业务显式接入，不影响默认 ImageDetector 行为。
@objc(SmartScannerImageDetectorUpgrade)
public class ImageDetectorUpgrade: NSObject {
    
    public typealias CompletionHandler = (DetectResult) -> ()
    
    private let stateQueue = DispatchQueue(label: "com.swiftycamera.image-detector-upgrade")
    
    var detecteOptions: DetecteOptions
    
    let engines: [DetecteEngineProtocol]
    
    private var completion: CompletionHandler? = nil
    
    private var isCompleted = false
    
    private var response = RecognitionResponse()
    
    public init(options: DetecteOptions, engines: DetecteEngineProtocol...) {
        self.engines = engines
        self.detecteOptions = options
        
        for engine in engines {
            engine.response(&response)
        }
    }
    
    public func recognize(sampleBuffer: CMSampleBuffer, regionRect: CGRect) {
        guard canRecognize else { return }
        
        for engine in engines {
            guard canRecognize else { return }
            engine.recognize(sampleBuffer: sampleBuffer, regionRect: regionRect, handle: handle)
        }
    }
    
    public func recognize(image: UIImage, completion: @escaping (DetectResult) -> ()) {
        let engines = self.engines
        
        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()
            let callbackQueue = DispatchQueue(label: "com.swiftycamera.image-detector-upgrade.image-recognize")
            var didComplete = false
            
            for engine in engines {
                group.enter()
                engine.recognize(image: image) { ret in
                    let shouldComplete = callbackQueue.sync { () -> Bool in
                        guard !didComplete, ret.hasDetectedPayload else { return false }
                        didComplete = true
                        return true
                    }
                    
                    if shouldComplete {
                        DispatchQueue.main.async {
                            completion(ret)
                        }
                    }
                    
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                let shouldFallback = callbackQueue.sync { !didComplete }
                if shouldFallback {
                    completion(DetectResult())
                }
            }
        }
    }
    
    private func handle(_ image: UIImage?) {
        guard canRecognize else { return }
        handleOfSecretSheet(image)
        onlyBarcodeHandle()
        virtualPhoneHandle()
        onlyPhoneHandle()
        onlyQrcodeHandle()
        allCodeHandle()
    }
    
    private func stop(of result: DetectResult) {
        let completion = stateQueue.sync { () -> CompletionHandler? in
            guard !isCompleted, let completion = self.completion else { return nil }
            isCompleted = true
            return completion
        }
        
        guard let completion = completion else { return }
        
        response.cleanAll()
        DispatchQueue.main.async {
            completion(result)
        }
    }
    
    @discardableResult
    public func completion(_ completion: @escaping CompletionHandler) -> Self {
        stateQueue.sync {
            self.completion = completion
            self.isCompleted = false
        }
        return self
    }
    
    public func reset(detecteOptions: DetecteOptions) {
        stateQueue.sync {
            self.detecteOptions = detecteOptions
            self.isCompleted = false
        }
        response.cleanAll()
        engines.forEach {
            $0.reset(detecteOptions: detecteOptions)
        }
    }
    
    private var canRecognize: Bool {
        stateQueue.sync { !isCompleted }
    }
    
    private var currentDetecteOptions: DetecteOptions {
        stateQueue.sync { detecteOptions }
    }
}

extension ImageDetectorUpgrade {
    private func handleOfSecretSheet(_ image: UIImage?) {
        guard currentDetecteOptions == .secretSheet else { return }
        guard let barcode = response.barCountedSet.mostElement(max: 2) else { return }
        
        if let phone = response.phoneCountedSet.mostElement(max: 2) {
            stop(of: DetectResult(
                barcode: barcode,
                phone: phone,
                cropImage: image
            ))
        }
        
        if let privacy = response.privacyCountedSet.mostElement(max: 2) {
            stop(of: DetectResult(
                barcode: barcode,
                privacyNumber: privacy,
                cropImage: image
            ))
        }
    }
    
    private func onlyBarcodeHandle() {
        guard currentDetecteOptions == .barcode else { return }
        guard let barcode = response.barCountedSet.mostElement(max: 2) else { return }
        stop(of: DetectResult(barcode: barcode))
    }
    
    private func onlyPhoneHandle() {
        guard currentDetecteOptions == .phoneNumber else { return }
        guard let phone = response.phoneCountedSet.mostElement(max: 3) else { return }
        stop(of: DetectResult(phone: phone))
    }
    
    private func virtualPhoneHandle() {
        guard currentDetecteOptions == .virtualPhone else { return }
        if let virtual = response.virtualCountedSet.mostElement(max: DetectorConfig.shared.virtualNumberMinimum) {
            stop(of: DetectResult(virtualNumber: virtual))
        } else if let phone = response.phoneCountedSet.mostElement(max: 2) {
            stop(of: DetectResult(phone: phone))
        }
    }
    
    private func onlyQrcodeHandle() {
        guard currentDetecteOptions == .qrcode else { return }
        guard let qrcode = response.qrCountedSet.mostElement(max: 2) else { return }
        stop(of: DetectResult(qrcode: qrcode))
    }
    
    private func allCodeHandle() {
        guard currentDetecteOptions == .allcode else { return }
        
        if let barcode = response.barCountedSet.mostElement(max: 2) {
            stop(of: DetectResult(barcode: barcode))
        }
        
        if let qrcode = response.qrCountedSet.mostElement(max: 2) {
            stop(of: DetectResult(qrcode: qrcode))
        }
    }
}

private extension DetectResult {
    var hasDetectedPayload: Bool {
        barcode != nil ||
        qrcode != nil ||
        phone != nil ||
        virtualNumber != nil ||
        privacyNumber != nil
    }
}
