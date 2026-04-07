//
//  PhoneExtractor.swift
//  SwiftyCamera
//
//  Created for phone number extraction optimization
//

import Foundation

/// 手机号提取器
/// 封装所有号码提取逻辑，提供统一的提取接口
class PhoneExtractor {
    
    // MARK: - Properties
    
    /// 前缀过滤器，用于排除误识别的号码
    private let prefixFilter: PrefixFilter
    
    /// 是否启用日志记录
    private let enableLogging: Bool
    
    /// 是否启用换行处理模式
    /// 当启用时，系统会移除换行符以识别跨行的手机号
    private let enableNewlineHandling: Bool
    
    // MARK: - Initialization
    
    /// 初始化手机号提取器
    /// - Parameters:
    ///   - prefixFilter: 前缀过滤器实例
    ///   - enableLogging: 是否启用日志记录，默认为 true
    ///   - enableNewlineHandling: 是否启用换行处理模式，默认为 false
    init(prefixFilter: PrefixFilter, enableLogging: Bool = true, enableNewlineHandling: Bool = false) {
        self.prefixFilter = prefixFilter
        self.enableLogging = enableLogging
        self.enableNewlineHandling = enableNewlineHandling
    }
    
    // MARK: - Private Helper Methods
    
    /// 预处理文本,处理换行符
    /// - Parameter text: 原始文本
    /// - Returns: 处理后的文本
    private func preprocessText(_ text: String) -> String {
        guard enableNewlineHandling else {
            return text
        }
        
        // 移除所有换行符（\r\n, \n, \r）
        var processed = text.replacingOccurrences(of: "\r\n", with: "")
        processed = processed.replacingOccurrences(of: "\n", with: "")
        processed = processed.replacingOccurrences(of: "\r", with: "")
        
        return processed
    }
    
    /// OCR 错误纠正
    /// - Parameter text: 原始文本
    /// - Returns: 纠正后的文本
    private func correctOCRErrors(_ text: String) -> String {
        var corrected = text
        
        // O -> 0
        corrected = corrected.replacingOccurrences(of: "O", with: "0")
        corrected = corrected.replacingOccurrences(of: "o", with: "0")
        
        // l -> 1 (仅在数字上下文中)
        corrected = corrected.replacingOccurrences(of: "l", with: "1")
        corrected = corrected.replacingOccurrences(of: "I", with: "1")
        
        // S -> 5 (仅在数字上下文中)
        if corrected.contains(where: { $0.isNumber }) {
            corrected = corrected.replacingOccurrences(of: "S", with: "5")
        }
        
        return corrected
    }
    
    /// 脱敏处理：将手机号替换为 "1XX****XXXX"
    /// - Parameter message: 原始日志消息
    /// - Returns: 脱敏后的消息
    private func sanitizeMessage(_ message: String) -> String {
        // 将完整手机号（1[3-9]\d{9}）替换为 "1XX****XXXX"
        let sanitized = message.replacingOccurrences(
            of: "1[3-9]\\d{9}",
            with: "1XX****XXXX",
            options: .regularExpression
        )
        return sanitized
    }
    
    /// 记录调试日志
    /// - Parameter message: 日志消息
    private func logDebug(_ message: String) {
        guard enableLogging else { return }
        
        // 脱敏处理：将手机号替换为 "1XX****XXXX"
        let sanitized = sanitizeMessage(message)
        
        print("🔍 [DEBUG] PhoneExtractor: \(sanitized)")
    }
    
    /// 记录信息日志
    /// - Parameter message: 日志消息
    private func logInfo(_ message: String) {
        guard enableLogging else { return }
        
        // 脱敏处理：将手机号替换为 "1XX****XXXX"
        let sanitized = sanitizeMessage(message)
        
        print("ℹ️ [INFO] PhoneExtractor: \(sanitized)")
    }
    
    /// 记录警告日志
    /// - Parameter message: 日志消息
    private func logWarning(_ message: String) {
        guard enableLogging else { return }
        
        // 脱敏处理：将手机号替换为 "1XX****XXXX"
        let sanitized = sanitizeMessage(message)
        
        print("⚠️ [WARNING] PhoneExtractor: \(sanitized)")
    }
    
    /// 记录错误日志
    /// - Parameter message: 日志消息
    private func logError(_ message: String) {
        guard enableLogging else { return }
        
        // 脱敏处理：将手机号替换为 "1XX****XXXX"
        let sanitized = sanitizeMessage(message)
        
        print("❌ [ERROR] PhoneExtractor: \(sanitized)")
    }
    
    // MARK: - Public Extraction Methods
    
    /// 提取普通手机号
    /// - Parameter text: 待提取的文本
    /// - Returns: 提取到的手机号数组（已去重）
    func extractNormalPhones(from text: String) -> [String] {
        // 1. 输入验证：空文本检查
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logDebug("Empty text provided, returning empty result")
            return []
        }
        
        // 2. 输入验证：必须包含数字
        guard text.containsDigit() else {
            logDebug("Text contains no digits, returning empty result")
            return []
        }
        
        // 3. 文本长度限制
        let maxTextLength = 500
        let processText: String
        
        if text.count > maxTextLength {
            logWarning("Text length (\(text.count)) exceeds maximum (\(maxTextLength)), truncating")
            processText = String(text.prefix(maxTextLength))
        } else {
            processText = text
        }
        
        // 4. 预处理文本（处理换行符和 OCR 错误）
        let processedText = correctOCRErrors(preprocessText(processText))
        
        // 4. 使用 RegexPatterns.normalPhoneRegex 进行匹配
        let matches = RegexPatterns.normalPhoneRegex.matches(
            in: processedText,
            options: [],
            range: NSRange(location: 0, length: processedText.utf16.count)
        )
        
        // 5. 使用 Set 进行去重
        var uniquePhones = Set<String>()
        
        for match in matches {
            // 转换 NSRange 到 Swift Range（错误处理）
            guard let range = Range(match.range, in: processedText) else {
                logWarning("Failed to convert NSRange to Range for match at location \(match.range.location)")
                continue
            }
            
            let matchedText = String(processedText[range])
            
            // 6. 使用 PrefixFilter 进行前缀过滤
            if prefixFilter.shouldFilter(text: processedText, at: match.range) {
                logDebug("Filtered phone with prefix: \(matchedText)")
                continue
            }
            
            // 7. 移除分隔符（空格、短横线）
            let normalized = matchedText.replacingOccurrences(of: " ", with: "")
                                       .replacingOccurrences(of: "-", with: "")
            
            // 8. 验证提取的号码
            // - 必须是 11 位数字
            // - 必须以 1 开头
            // - 第二位必须是 3-9
            guard normalized.count == 11,
                  normalized.allSatisfy({ $0.isNumber }),
                  normalized.hasPrefix("1"),
                  let secondDigit = normalized.dropFirst().first,
                  ("3"..."9").contains(secondDigit) else {
                logDebug("Invalid phone number after normalization: \(normalized)")
                continue
            }
            
            // 9. 添加到去重集合
            uniquePhones.insert(normalized)
        }
        
        let result = Array(uniquePhones)
        logInfo("Extracted \(result.count) normal phone(s)")
        
        return result
    }
    
    /// 提取虚拟号（手机号 + 分机号）
    /// - Parameter text: 待提取的文本
    /// - Returns: 提取到的虚拟号数组（已去重），格式为"手机号转分机号"
    func extractVirtualPhones(from text: String) -> [String] {
        // 1. 输入验证：空文本检查
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logDebug("Empty text provided, returning empty result")
            return []
        }
        
        // 2. 输入验证：必须包含数字
        guard text.containsDigit() else {
            logDebug("Text contains no digits, returning empty result")
            return []
        }
        
        // 3. 文本长度限制
        let maxTextLength = 500
        let processText: String
        
        if text.count > maxTextLength {
            logWarning("Text length (\(text.count)) exceeds maximum (\(maxTextLength)), truncating")
            processText = String(text.prefix(maxTextLength))
        } else {
            processText = text
        }
        
        // 4. 预处理文本（处理换行符和 OCR 错误）
        let processedText = correctOCRErrors(preprocessText(processText))
        
        // 5. 使用 RegexPatterns.virtualPhoneRegex 进行匹配
        let matches = RegexPatterns.virtualPhoneRegex.matches(
            in: processedText,
            options: [],
            range: NSRange(location: 0, length: processedText.utf16.count)
        )
        
        // 6. 使用 Set 进行去重
        var uniqueVirtualPhones = Set<String>()
        
        for match in matches {
            // 转换 NSRange 到 Swift Range（错误处理）
            guard let range = Range(match.range, in: processedText) else {
                logWarning("Failed to convert NSRange to Range for match at location \(match.range.location)")
                continue
            }
            
            let matchedText = String(processedText[range])
            
            // 7. 使用 PrefixFilter 进行前缀过滤
            if prefixFilter.shouldFilter(text: processedText, at: match.range) {
                logDebug("Filtered virtual phone with prefix: \(matchedText)")
                continue
            }
            
            // 8. 规范化虚拟号格式
            if let normalized = normalizeVirtualPhone(matchedText) {
                uniqueVirtualPhones.insert(normalized)
            } else {
                logDebug("Failed to normalize virtual phone: \(matchedText)")
            }
        }
        
        let result = Array(uniqueVirtualPhones)
        logInfo("Extracted \(result.count) virtual phone(s)")
        
        return result
    }
    
    /// 提取隐私号
    /// - Parameter text: 待提取的文本
    /// - Returns: 提取到的隐私号数组（已去重）
    func extractPrivacyPhones(from text: String) -> [String] {
        // 1. 输入验证：空文本检查
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logDebug("Empty text provided, returning empty result")
            return []
        }
        
        // 2. 输入验证：必须包含数字或星号字符
        guard text.containsDigit() else {
            logDebug("Text contains no digits, returning empty result")
            return []
        }
        
        // 3. 文本长度限制
        let maxTextLength = 500
        let processText: String
        
        if text.count > maxTextLength {
            logWarning("Text length (\(text.count)) exceeds maximum (\(maxTextLength)), truncating")
            processText = String(text.prefix(maxTextLength))
        } else {
            processText = text
        }
        
        // 4. 预处理文本（处理换行符和 OCR 错误）
        let processedText = correctOCRErrors(preprocessText(processText))
        
        // 5. 使用 RegexPatterns.privacyPhoneRegex 进行匹配
        let matches = RegexPatterns.privacyPhoneRegex.matches(
            in: processedText,
            options: [],
            range: NSRange(location: 0, length: processedText.utf16.count)
        )
        
        // 6. 使用 Set 进行去重
        var uniquePrivacyPhones = Set<String>()
        
        for match in matches {
            // 转换 NSRange 到 Swift Range（错误处理）
            guard let range = Range(match.range, in: processedText) else {
                logWarning("Failed to convert NSRange to Range for match at location \(match.range.location)")
                continue
            }
            
            let matchedText = String(processedText[range])
            
            // 7. 规范化隐私号格式
            if let normalized = normalizePrivacyPhone(matchedText) {
                uniquePrivacyPhones.insert(normalized)
            } else {
                logDebug("Failed to normalize privacy phone: \(matchedText)")
            }
        }
        
        let result = Array(uniquePrivacyPhones)
        logInfo("Extracted \(result.count) privacy phone(s)")
        
        return result
    }
    
    /// 规范化虚拟号格式
    /// - Parameter text: 原始虚拟号文本
    /// - Returns: 规范化后的虚拟号，格式为"手机号转分机号"，如果无法规范化则返回 nil
    private func normalizeVirtualPhone(_ text: String) -> String? {
        // 1. 提取所有数字
        let digits = text.filter { $0.isNumber }
        
        // 2. 验证数字长度
        guard digits.count >= 14 else {
            logDebug("Virtual phone has too few digits: \(digits.count)")
            return nil
        }
        
        var phoneNumber: String
        var extensionNumber: String
        
        // 3. 根据总长度处理
        if digits.count > 15 {
            // 超过 15 位：取前 11 位作为手机号，后 4 位作为分机号
            phoneNumber = String(digits.prefix(11))
            extensionNumber = String(digits.suffix(4))
            logDebug("Long digit string (\(digits.count) digits), taking first 11 as phone, last 4 as extension")
        } else if digits.count >= 14 && digits.count <= 15 {
            // 14-15 位：前 11 位为手机号，剩余为分机号
            phoneNumber = String(digits.prefix(11))
            extensionNumber = String(digits.suffix(digits.count - 11))
        } else {
            // 不应该到达这里，因为正则表达式已经限制了长度
            logWarning("Unexpected digit count: \(digits.count)")
            return nil
        }
        
        // 4. 验证手机号格式
        guard phoneNumber.count == 11,
              phoneNumber.hasPrefix("1"),
              let secondDigit = phoneNumber.dropFirst().first,
              ("3"..."9").contains(secondDigit) else {
            logDebug("Invalid phone number format: \(phoneNumber)")
            return nil
        }
        
        // 5. 验证分机号长度
        if extensionNumber.count < 3 {
            // 分机号少于 3 位，降级为普通手机号（返回 nil 表示不作为虚拟号处理）
            logDebug("Extension too short (\(extensionNumber.count) digits), downgrading to normal phone")
            return nil
        } else if extensionNumber.count > 4 {
            // 分机号超过 4 位，只取前 4 位
            extensionNumber = String(extensionNumber.prefix(4))
            logDebug("Extension too long, truncated to 4 digits: \(extensionNumber)")
        }
        
        // 6. 格式化为统一格式："手机号转分机号"
        let normalized = "\(phoneNumber)转\(extensionNumber)"
        
        return normalized
    }
    
    /// 规范化隐私号格式
    /// - Parameter text: 原始隐私号文本
    /// - Returns: 规范化后的隐私号，如果无法规范化则返回 nil
    private func normalizePrivacyPhone(_ text: String) -> String? {
        // 1. 将所有非数字字符替换为 "*"
        var normalized = ""
        for char in text {
            if char.isNumber {
                normalized.append(char)
            } else {
                normalized.append("*")
            }
        }
        
        // 2. 判断格式类型并进行格式化
        var result: String
        
        if normalized.hasPrefix("1"), normalized.count >= 2 {
            // 检查第二位是否为 3-9
            let secondChar = normalized[normalized.index(normalized.startIndex, offsetBy: 1)]
            if ("3"..."9").contains(secondChar) {
                // 格式 1: 以 1 开头且第二位是 3-9
                // 格式化为 "前3位****后4位"
                
                // 提取前 3 位数字
                var prefix = ""
                var digitCount = 0
                for char in normalized {
                    if char.isNumber {
                        prefix.append(char)
                        digitCount += 1
                        if digitCount == 3 {
                            break
                        }
                    }
                }
                
                // 提取后 4 位数字
                var suffix = ""
                var digits: [Character] = []
                for char in normalized {
                    if char.isNumber {
                        digits.append(char)
                    }
                }
                if digits.count >= 4 {
                    suffix = String(digits.suffix(4))
                }
                
                // 验证是否有足够的数字
                guard prefix.count == 3, suffix.count == 4 else {
                    logDebug("Invalid privacy phone format (type 1): not enough digits")
                    return nil
                }
                
                // 格式化为 "前3位****后4位"
                result = "\(prefix)****\(suffix)"
            } else {
                // 第二位不是 3-9，按格式 2 处理
                result = formatAsPattern2(normalized)
            }
        } else if normalized.hasPrefix("*") {
            // 格式 2: 以星号开头
            // 格式化为 "1******后4位"
            result = formatAsPattern2(normalized)
        } else {
            logDebug("Invalid privacy phone format: doesn't match any pattern")
            return nil
        }
        
        // 3. 验证最终格式
        // 必须包含至少 4 个 "*" 和 4 个数字
        let starCount = result.filter { $0 == "*" }.count
        let digitCount = result.filter { $0.isNumber }.count
        
        guard starCount >= 4, digitCount >= 4 else {
            logDebug("Invalid privacy phone format: insufficient stars (\(starCount)) or digits (\(digitCount))")
            return nil
        }
        
        return result
    }
    
    /// 格式化为模式 2: "1******后4位"
    /// - Parameter text: 已将非数字字符替换为 "*" 的文本
    /// - Returns: 格式化后的隐私号
    private func formatAsPattern2(_ text: String) -> String {
        // 提取所有数字
        let digits = text.filter { $0.isNumber }
        
        // 需要至少 4 位数字作为后缀
        guard digits.count >= 4 else {
            return text // 返回原文本，让验证步骤处理
        }
        
        // 取后 4 位数字
        let suffix = String(digits.suffix(4))
        
        // 格式化为 "1******后4位"
        return "1******\(suffix)"
    }
    
    /// 从超长数字串中提取有效手机号
    /// 使用滑动窗口查找所有可能的 11 位手机号
    /// - Parameter digits: 纯数字字符串（超过 15 位）
    /// - Returns: 提取到的有效手机号数组
    private func extractFromLongDigitString(_ digits: String) -> [String] {
        var results: [String] = []
        
        // 验证输入是否为纯数字
        guard digits.allSatisfy({ $0.isNumber }) else {
            logDebug("Input contains non-digit characters")
            return []
        }
        
        // 验证长度是否足够
        guard digits.count >= 11 else {
            logDebug("Digit string too short: \(digits.count)")
            return []
        }
        
        // 滑动窗口查找 11 位手机号
        for i in 0...(digits.count - 11) {
            let start = digits.index(digits.startIndex, offsetBy: i)
            let end = digits.index(start, offsetBy: 11)
            let candidate = String(digits[start..<end])
            
            // 验证是否为有效手机号
            // 1. 必须以 1 开头
            // 2. 第二位必须是 3-9
            if candidate.hasPrefix("1"),
               let secondDigit = candidate.dropFirst().first,
               ("3"..."9").contains(secondDigit) {
                results.append(candidate)
            }
        }
        
        logDebug("Extracted \(results.count) phone(s) from long digit string (length: \(digits.count))")
        
        return results
    }
    
    // MARK: - Unified Extraction Method
    
    /// 统一提取方法：从文本中提取所有类型的手机号
    /// - Parameter text: 待提取的文本
    /// - Returns: ExtractionResult 结构体，包含分类后的所有号码
    func extractPhones(from text: String) -> ExtractionResult {
        var result = ExtractionResult()
        
        // 1. 先提取虚拟号（优先级最高）
        let virtuals = extractVirtualPhones(from: text)
        virtuals.forEach { result.addVirtual($0) }
        
        // 2. 提取普通手机号
        // 注意：当前实现中，extractNormalPhones 不支持排除区域
        // 依赖 ExtractionResult 中的 Set 去重来避免重复
        let normals = extractNormalPhones(from: text)
        normals.forEach { result.addNormal($0) }
        
        // 3. 提取隐私号（独立处理）
        let privacies = extractPrivacyPhones(from: text)
        privacies.forEach { result.addPrivacy($0) }
        
        logInfo("Extraction complete: \(result.normalPhones.count) normal, \(result.virtualPhones.count) virtual, \(result.privacyPhones.count) privacy")
        
        return result
    }
}
