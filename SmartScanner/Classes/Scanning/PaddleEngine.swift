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
    private let maxExtractionCandidates = 12
    
    /// 统一号码提取器：从 OCR 文本中提取普通号/虚拟号/隐私号。
    private lazy var phoneExtractor: PhoneExtractor = {
        let filter = PrefixFilter(customPrefixes: [])
        return PhoneExtractor(
            prefixFilter: filter,
            enableLogging: DetectorConfig.shared.logEnabled,
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
        
        recognizePhones(in: sourceImage) { [weak self] result in
            guard let self else { return }
            self.append(extracted: result)
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
        
        recognizePhones(in: image) { result in
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
    
    func recognizePhones(in image: UIImage, completion: @escaping (ExtractionResult) -> Void) {
#if canImport(DHPaddleLiteSDK)
        let recognizer = DHPaddleLiteTextRecognition.sharedInstance()
        recognizer.recognizeImage(image, effectiveArea: .zero) { [weak self] results, error in
            guard let self else { return }
            guard error == nil, let results, !results.isEmpty else {
                completion(ExtractionResult())
                return
            }
            
            for item in results {
                debugPrint("*** OCR item index=\(item.index) confidence=\(item.confidence) text=\(item.text)")
            }
            
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
            completion(self.removeVirtualBaseNumbers(from: merged))
        }
#else
        completion(ExtractionResult())
#endif
    }

#if canImport(DHPaddleLiteSDK)
    /// 生成提取候选：单行 + 有条件合并的多行（2/3行）
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
        
        // 2) 有选择地合并 2/3 行，提升跨行号码命中率
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
            
            if i + 2 < lines.count {
                let triple = [lines[i], lines[i + 1], lines[i + 2]]
                if shouldMergePhoneLines(triple) {
                    appendIfNeeded(triple.joined())
                    if output.count >= maxExtractionCandidates {
                        return output
                    }
                }
            }
            
            // 3) 4 行定向合并：手机号分两行 + “转/专”单行 + 分机单行
            // 例如：
            // "备用号码：1301922" + "9964" + "转" + "8851"
            if i + 3 < lines.count {
                let quad = [lines[i], lines[i + 1], lines[i + 2], lines[i + 3]]
                if let normalized = normalizeFourLinePhonePattern(quad) {
                    appendIfNeeded(normalized)
                    if output.count >= maxExtractionCandidates {
                        return output
                    }
                } else if shouldMergePhoneLines(quad) {
                    appendIfNeeded(quad.joined())
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
    
    /// 针对 4 行拆分样式做归一化合并，命中后输出 "手机号转分机号"
    /// 输入示例：
    /// ["备用号码：1301922", "9964", "转", "8851"] -> "13019229964转8851"
    func normalizeFourLinePhonePattern(_ lines: [String]) -> String? {
        guard lines.count == 4 else { return nil }
        
        let l1 = lines[0]
        let l2 = lines[1]
        let l3 = lines[2]
        let l4 = lines[3]
        
        let digits1 = l1.filter(\.isNumber)
        let digits2 = l2.filter(\.isNumber)
        let digits4 = l4.filter(\.isNumber)
        
        let line3HasTransferToken = ["转", "专", "车转", "车专", "$", "#", "ext", "分机"]
            .contains { l3.lowercased().contains($0.lowercased()) }
        
        // 典型条件：
        // 1) 前两行拼起来正好 11 位手机号
        // 2) 第三行为“转/专”等分隔语义
        // 3) 第三、四行累计得到 3~4 位分机
        let extensionDigits = (l3 + l4).filter(\.isNumber)
        guard digits1.count + digits2.count == 11,
              line3HasTransferToken,
              (3...4).contains(extensionDigits.count) else {
            return nil
        }
        
        let phone = digits1 + digits2
        guard phone.count == 11,
              phone.hasPrefix("1"),
              let second = phone.dropFirst().first,
              ("3"..."9").contains(second) else {
            return nil
        }
        
        return "\(phone)转\(extensionDigits)"
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
