//
//  PaddleEngine.swift
//  SmartScanner
//
//  Created by Codex on 2026/4/17.
//

import UIKit
import CoreMedia

#if targetEnvironment(simulator)
@objc(SmartScannerPaddleEngine)
public final class PaddleEngine: NSObject, DetecteEngineProtocol {
    
    var options: DetecteOptions
    
    private var response: RecognitionResponse?
    
    public init(options: DetecteOptions) {
        self.options = options
    }
    
    public func response(_ response: inout RecognitionResponse) {
        self.response = response
    }
    
    public func reset(detecteOptions: DetecteOptions) {
        self.options = detecteOptions
    }
    
    public func recognize(sampleBuffer: CMSampleBuffer, regionRect: CGRect, handle: @escaping Handler) {
        handle(nil)
    }
    
    public func recognize(image: UIImage, completion: (DetectResult) -> ()) {
        completion(DetectResult())
    }
}

#else
#if canImport(DHPaddleLiteSDK)
import DHPaddleLiteSDK
#endif

/// Paddle 引擎：仅处理手机号相关识别（普通号/虚拟号/隐私号）。
@objc(SmartScannerPaddleEngine)
public final class PaddleEngine: NSObject, DetecteEngineProtocol {
    
    var options: DetecteOptions
    
    private var response: RecognitionResponse?
    
    /// 实时流识别状态，控制 OCR 触发频率，避免每帧都跑模型。
    private let stateQueue = DispatchQueue(label: "com.swiftycamera.paddle-engine.state")
    private var lastRealtimeRecognitionTime: CFAbsoluteTime = 0
    private let minimumRealtimeRecognitionInterval: CFTimeInterval = 0.14
    
    /// 候选文本上限，避免多行组合过多导致后处理耗时上升。
    private let maxExtractionCandidates = 4
    /// 高置信度直接命中阈值：满足时走 direct-hit，不依赖计数阈值。
    private let directHitConfidenceThreshold: CGFloat = 0.95
    
    
    /// 统一号码提取器：从 OCR 文本中提取普通号/虚拟号/隐私号。
    private lazy var phoneExtractor: PhoneExtractor = {
        let filter = PrefixFilter(customPrefixes: [])
        return PhoneExtractor(
            prefixFilter: filter,
            enableLogging: DetectorConfig.shared.logEnabled,
            enableNewlineHandling: true
        )
    }()
    
    /// 用于证据校验，避免重复打印提取日志。
    private lazy var silentPhoneExtractor: PhoneExtractor = {
        let filter = PrefixFilter(customPrefixes: [])
        return PhoneExtractor(
            prefixFilter: filter,
            enableLogging: false,
            enableNewlineHandling: true
        )
    }()
    
    public init(options: DetecteOptions) {
        self.options = options
    }
    
    public func response(_ response: inout RecognitionResponse) {
        self.response = response
    }
    
    public func reset(detecteOptions: DetecteOptions) {
        self.options = detecteOptions
    }
    
    public func recognize(sampleBuffer: CMSampleBuffer, regionRect: CGRect, handle: @escaping Handler) {
        // Paddle 引擎仅负责文本号码识别，不处理条码/二维码。
        guard options.containsText else {
            handle(nil)
            return
        }
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer),
              shouldRunRealtimeTextRecognition() else {
            handle(nil)
            return
        }
        
        let cropImage: UIImage?
        let sourceImage: UIImage?
        
        if regionRect != .zero,
           let regionImage = ImageUtilities.cropImageFromSampleBuffer(sampleBuffer: sampleBuffer, cropRect: regionRect) {
            cropImage = regionImage
            sourceImage = regionImage
        } else {
            cropImage = nil
            sourceImage = fullImage(from: sampleBuffer)
        }
        
        guard let sourceImage else {
            handle(nil)
            return
        }
        
        recognizePhones(in: sourceImage) { [weak self] result, maxConfidence, hasDirectLineEvidence in
            guard let self else { return }
            self.append(extracted: result)
            self.setHighConfidenceDirectResultIfNeeded(extracted: result,
                                                       maxConfidence: maxConfidence,
                                                       hasDirectLineEvidence: hasDirectLineEvidence,
                                                       cropImage: cropImage)
            handle(cropImage)
        }
    }
    
    /// 识别图片（相册场景）：协议是同步 completion，这里短暂等待 OCR 回调再返回。
    public func recognize(image: UIImage, completion: (DetectResult) -> ()) {
        guard options.containsText else {
            completion(DetectResult())
            return
        }
        
        // 图片识别接口同样是同步 completion，保持与其它引擎行为一致。
        let semaphore = DispatchSemaphore(value: 0)
        let lock = DispatchQueue(label: "com.swiftycamera.paddle-engine.image-result")
        var extracted = ExtractionResult()
        
        recognizePhones(in: image) { result, _, _ in
            lock.sync {
                extracted = result
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + .seconds(2))
        
        let final = lock.sync { extracted }
        let detectResult = DetectResult()
        
        if options.contains(.virtualNumber), let virtual = final.virtualPhones.first {
            detectResult.virtualNumber = virtual
        }
        if options.contains(.phoneNumber), let phone = final.normalPhones.first {
            detectResult.phone = phone
        }
        if options.contains(.privacyNumber), let privacy = final.privacyPhones.first {
            detectResult.privacyNumber = privacy
        }
        
        completion(detectResult)
    }
}

private extension PaddleEngine {
    func shouldRunRealtimeTextRecognition() -> Bool {
        stateQueue.sync {
            let now = CFAbsoluteTimeGetCurrent()
            // 节流：限制实时 OCR 最小间隔，降低 CPU 与功耗开销。
            guard now - lastRealtimeRecognitionTime >= minimumRealtimeRecognitionInterval else {
                return false
            }
            lastRealtimeRecognitionTime = now
            return true
        }
    }
    
    func fullImage(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        return ImageUtilities.cropImageFromSampleBuffer(sampleBuffer: sampleBuffer, cropRect: rect)
    }
    
    func recognizePhones(in image: UIImage, completion: @escaping (ExtractionResult, CGFloat, Bool) -> Void) {
#if canImport(DHPaddleLiteSDK)
        let recognizer = DHPaddleLiteTextRecognition.sharedInstance()
        recognizer.recognizeImage(image, effectiveArea: .zero) { [weak self] results, error in
            guard let self else { return }
            guard error == nil, let results, !results.isEmpty else {
                completion(ExtractionResult(), 0, false)
                return
            }
            
            for item in results {
                debugPrint("*** OCR item index=\(item.index) confidence=\(item.confidence) text=\(item.text)")
            }
            let maxConfidence = results.map(\.confidence).max() ?? 0
            let lines = results
                .sorted { $0.index < $1.index }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var merged = ExtractionResult()
            let candidates = self.extractionCandidates(from: results)
            let hasVirtualHints = candidates.contains { self.containsVirtualHint($0) }
            for text in candidates {
                let extracted = self.phoneExtractor.extractPhones(from: text)
                extracted.normalPhones.forEach { merged.addNormal($0) }
                extracted.virtualPhones.forEach { merged.addVirtual($0) }
                extracted.privacyPhones.forEach { merged.addPrivacy($0) }
                
                // 命中当前目标后提前结束本轮，降低单帧处理时间。
                if self.shouldStopEarly(with: merged, hasVirtualHints: hasVirtualHints) {
                    break
                }
            }
            let final = self.removeVirtualBaseNumbers(from: merged)
            let hasDirectLineEvidence = self.hasSingleLineDirectEvidence(lines: lines, extracted: final)
            completion(final, maxConfidence, hasDirectLineEvidence)
        }
#else
        completion(ExtractionResult(), 0, false)
#endif
    }

#if canImport(DHPaddleLiteSDK)
    /// 生成提取候选：单行 + 有条件合并的两行
    /// 例如：
    /// "手机：" + "191-2384-7" + "967" => "手机：191-2384-7967"
    func extractionCandidates(from results: [DLTextRecognitionResult]) -> [String] {
        let lines = results
            .sorted { $0.index < $1.index }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !lines.isEmpty else { return [] }
        
        var output: [String] = []
        var seen = Set<String>()
        
        @inline(__always)
        func appendIfNeeded(_ value: String) {
            guard !value.isEmpty, !seen.contains(value) else { return }
            seen.insert(value)
            output.append(value)
        }
        
        // 1) 先加入原始单行
        for line in lines {
            appendIfNeeded(line)
            if output.count >= maxExtractionCandidates {
                return output
            }
        }
        
        // 2) 有选择地合并 2 行，提升跨行号码命中率
        for i in 0..<lines.count {
            if i + 1 < lines.count {
                let pair = [lines[i], lines[i + 1]]
                if shouldMergePhoneLines(pair) {
                    appendIfNeeded(pair.joined())
                    if output.count >= maxExtractionCandidates {
                        return output
                    }
                }
            }
        }
        
        return output
    }
    
    func shouldMergePhoneLines(_ lines: [String]) -> Bool {
        guard !lines.isEmpty else { return false }
        
        let joined = lines.joined()
        let digitCount = joined.filter(\.isNumber).count
        
        // 号码合并最基本范围：至少要接近手机号长度，最多覆盖“手机号+分机号”
        guard digitCount >= 7, digitCount <= 16 else { return false }
        
        // 地址行不参与合并，除非明确含有手机号语义词
        if lines.contains(where: { isLikelyAddressLine($0) }),
           !lines.contains(where: { isLikelyPhoneContextLine($0) }) {
            return false
        }
        
        // 至少大部分行应当是手机号相关片段
        let phoneLikeCount = lines.filter { isLikelyPhoneFragment($0) || isLikelyPhoneContextLine($0) }.count
        return phoneLikeCount >= max(1, lines.count - 1)
    }
    
    func isLikelyPhoneContextLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = ["手机", "号码", "电话", "联系", "联系方式", "联系电话", "tel", "phone"]
        return keywords.contains { lower.contains($0) }
    }
    
    func isLikelyAddressLine(_ text: String) -> Bool {
        let tokens = ["省", "市", "区", "县", "镇", "乡", "路", "街", "大道", "巷", "栋", "单元", "室", "楼", "园", "号"]
        return tokens.contains { text.contains($0) }
    }
    
    func isLikelyPhoneFragment(_ text: String) -> Bool {
        let separators = ["-", "转", "专", "车转", "车专", "#", "*", "$", "ext", "分机", ":"]
        if text.contains(where: \.isNumber) { return true }
        return separators.contains { text.lowercased().contains($0.lowercased()) }
    }
    
    func shouldStopEarly(with result: ExtractionResult, hasVirtualHints: Bool) -> Bool {
        // 仅虚拟号：必须命中虚拟号才提前结束。
        if options == .virtualNumber {
            return !result.virtualPhones.isEmpty
        }
        
        // 虚拟号 + 普通号：有虚拟号线索时优先等虚拟号；
        // 无线索时允许普通号提前返回，避免普通手机号迟迟不吐数据。
        if options == .virtualPhone {
            if !result.virtualPhones.isEmpty { return true }
            if !hasVirtualHints && !result.normalPhones.isEmpty { return true }
            return false
        }
        
        // 仅手机号
        if options == .phoneNumber {
            return !result.normalPhones.isEmpty
        }
        // 仅隐私号
        if options == .privacyNumber {
            return !result.privacyPhones.isEmpty
        }
        // 其它不含虚拟号的组合：命中任一文本号码即可结束当前帧处理
        return !result.virtualPhones.isEmpty ||
               !result.normalPhones.isEmpty ||
               !result.privacyPhones.isEmpty
    }
    
    func containsVirtualHint(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hints = ["转", "专", "车转", "车专", "#", "*", "$", "_", "ext", "分机", ",", "，", ";", "；"]
        return hints.contains { lower.contains($0) }
    }
    
    /// 不将虚拟号主号重复计入普通手机号。
    /// 例如：存在 "18430789198转9804" 时，普通号中的 "18430789198" 会被移除。
    func removeVirtualBaseNumbers(from source: ExtractionResult) -> ExtractionResult {
        var result = source
        guard !result.virtualPhones.isEmpty, !result.normalPhones.isEmpty else { return result }
        
        let virtualBases: Set<String> = Set(
            result.virtualPhones.map { value in
                value.components(separatedBy: "转").first ?? value
            }
        )
        
        result.normalPhones = result.normalPhones.filter { !virtualBases.contains($0) }
        return result
    }
#endif
    
    func setHighConfidenceDirectResultIfNeeded(extracted: ExtractionResult,
                                               maxConfidence: CGFloat,
                                               hasDirectLineEvidence: Bool,
                                               cropImage: UIImage?) {
        guard maxConfidence >= directHitConfidenceThreshold else { return }
        // 仅允许“单行直接可提取”的结果走直出，避免多行短片段拼接误判。
        guard hasDirectLineEvidence else { return }
        
        let direct = DetectResult()
        direct.cropImage = cropImage
        
        if options == .phoneNumber, let phone = extracted.normalPhones.first {
            direct.phone = phone
        } else if options == .privacyNumber, let privacy = extracted.privacyPhones.first {
            direct.privacyNumber = privacy
        } else if options == .virtualNumber, let virtual = extracted.virtualPhones.first {
            direct.virtualNumber = virtual
        } else if options == .virtualPhone {
            // 避免虚拟号场景再次误退化到普通号，direct-hit 仅接受虚拟号。
            if let virtual = extracted.virtualPhones.first {
                direct.virtualNumber = virtual
            } else {
                return
            }
        } else if options.contains(.virtualNumber), let virtual = extracted.virtualPhones.first {
            direct.virtualNumber = virtual
        } else if options.contains(.phoneNumber), let phone = extracted.normalPhones.first {
            direct.phone = phone
        } else if options.contains(.privacyNumber), let privacy = extracted.privacyPhones.first {
            direct.privacyNumber = privacy
        } else {
            return
        }
        
        response?.highConfidenceDirectResult = direct
    }
    
    func hasSingleLineDirectEvidence(lines: [String], extracted: ExtractionResult) -> Bool {
        guard !lines.isEmpty else { return false }
        guard !extracted.normalPhones.isEmpty || !extracted.virtualPhones.isEmpty || !extracted.privacyPhones.isEmpty else {
            return false
        }
        
        for line in lines {
            let lineResult = silentPhoneExtractor.extractPhones(from: line)
            let hasVirtual = !lineResult.virtualPhones.isDisjoint(with: extracted.virtualPhones)
            let hasNormal = !lineResult.normalPhones.isDisjoint(with: extracted.normalPhones)
            let hasPrivacy = !lineResult.privacyPhones.isDisjoint(with: extracted.privacyPhones)
            if hasVirtual || hasNormal || hasPrivacy {
                return true
            }
        }
        return false
    }
    
    func append(extracted: ExtractionResult) {
        if options.contains(.virtualNumber) {
            response?.virtualCountedSet.addObjects(from: Array(extracted.virtualPhones))
        }
        if options.contains(.phoneNumber) {
            response?.phoneCountedSet.addObjects(from: Array(extracted.normalPhones))
        }
        if options.contains(.privacyNumber) {
            response?.privacyCountedSet.addObjects(from: Array(extracted.privacyPhones))
        }
    }
}
#endif
