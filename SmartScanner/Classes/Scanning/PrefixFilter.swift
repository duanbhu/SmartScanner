//
//  PrefixFilter.swift
//  SwiftyCamera
//
//  Created for phone number extraction optimization
//

import Foundation

/// 前缀过滤器
/// 用于排除误识别的号码，支持自定义前缀和正则表达式前缀
class PrefixFilter {
    
    // MARK: - Properties
    
    /// 默认前缀列表
    private let defaultPrefixes = ["YT", "ZT", "ST", "JD", "SF", "TT", "JT", "DPK"]
    
    /// 自定义前缀列表
    private var customPrefixes: [String]
    
    /// 正则表达式前缀列表
    private var regexPrefixes: [NSRegularExpression]
    
    // MARK: - Initialization
    
    /// 初始化前缀过滤器
    /// - Parameters:
    ///   - customPrefixes: 自定义前缀列表，将与默认前缀合并
    ///   - regexPatterns: 正则表达式格式的前缀过滤规则
    init(customPrefixes: [String] = [], regexPatterns: [String] = []) {
        self.customPrefixes = customPrefixes
        
        // 编译正则表达式，忽略无效的
        self.regexPrefixes = regexPatterns.compactMap { pattern in
            do {
                return try NSRegularExpression(pattern: pattern, options: [])
            } catch {
                if DetectorConfig.shared.logEnabled {
                    print("⚠️ [WARNING] PrefixFilter: Invalid regex pattern '\(pattern)', error: \(error.localizedDescription)")
                }
                return nil
            }
        }
        
        if DetectorConfig.shared.logEnabled && regexPatterns.count != self.regexPrefixes.count {
            print("⚠️ [WARNING] PrefixFilter: Some regex patterns were invalid and ignored")
        }
    }
    
    // MARK: - Public Methods
    
    /// 检查是否应该过滤指定位置的文本
    /// - Parameters:
    ///   - text: 完整文本
    ///   - range: 匹配到的手机号在文本中的范围
    /// - Returns: 如果应该过滤返回 true，否则返回 false
    func shouldFilter(text: String, at range: NSRange) -> Bool {
        // 检查前面是否有数字
        if range.location > 0 {
            let prevIndex = text.index(text.startIndex, offsetBy: range.location - 1)
            if text[prevIndex].isNumber {
                return true
            }
        }
        
        // 检查默认前缀和自定义前缀
        let allPrefixes = mergedPrefixes()
        for prefix in allPrefixes {
            if range.location >= prefix.count {
                let start = text.index(text.startIndex, offsetBy: range.location - prefix.count)
                let end = text.index(text.startIndex, offsetBy: range.location)
                if text[start..<end].uppercased() == prefix.uppercased() {
                    return true
                }
            }
        }
        
        // 检查正则表达式前缀
        for regex in regexPrefixes {
            // 检查前面最多 10 个字符
            let checkStart = max(0, range.location - 10)
            let checkLength = range.location - checkStart
            let checkRange = NSRange(location: checkStart, length: checkLength)
            
            if regex.firstMatch(in: text, options: [], range: checkRange) != nil {
                return true
            }
        }
        
        return false
    }
    
    /// 合并默认前缀和自定义前缀
    /// - Returns: 合并后的前缀列表
    func mergedPrefixes() -> [String] {
        return defaultPrefixes + customPrefixes
    }
}
