//
//  RegexPatterns.swift
//  SwiftyCamera
//
//  Created for phone number extraction optimization
//

import Foundation

/// 正则表达式模式管理器
/// 集中管理和预编译所有正则表达式，提供高性能的模式匹配
struct RegexPatterns {
    
    // MARK: - 基础模式
    
    /// 基础手机号模式: 1[3-9]\d{9}
    static let mobilePattern = "1[3-9]\\d{9}"
    
    /// 默认前缀过滤列表
    static let defaultIgnorePrefixes = ["YT", "ZT", "ST", "JD", "SF", "TT", "JT"]
    
    /// 星号字符集，用于隐私号识别
    /// 支持: *, ^, _, 斗, 米, 关, 大, 美, 长, 女, 本, 水,半, #, +, $, o, k, a, t, 4
    static let starCharacters = "[*^_斗米关大美长女本水半#+$okat4]"
    
    /// 分机号分隔符模式
    /// 支持:
    /// 1. 纯空白/短横线/下划线分隔
    /// 2. "转"、"专"、"车转"、"车专"、"$"、"#"、"*"、"ext"、"分机"、逗号/分号 前后带空格的分隔
    static let extensionSeparators = "(?:(?:\\s*(?:车转|车专|转|专|\\$|#|\\*|ext|分机|,|，|;|；|[-_])\\s*)|[\\s\\-_]{0,2})"
    
    // MARK: - 前缀过滤器
    
    /// 生成前缀过滤模式（负向后查找）
    /// - Parameter customPrefixes: 自定义前缀列表，将与默认前缀合并
    /// - Returns: 负向后查找正则表达式模式
    static func ignorePrefixPattern(customPrefixes: [String] = []) -> String {
        let allPrefixes = defaultIgnorePrefixes + customPrefixes
        let prefixPattern = allPrefixes.joined(separator: "|")
        return "(?<!\(prefixPattern)|\\d)"
    }
    
    // MARK: - 普通手机号模式
    
    /// 支持分隔符的手机号模式
    /// 格式: 1[3-9] 1位数字 [空格或短横线]? 4位数字 [空格或短横线]? 4位数字
    /// 分隔符位置：第 3 位和第 7 位之后
    static let mobileWithSeparators = "1[3-9]\\d[\\s\\-]?\\d{4}[\\s\\-]?\\d{4}"
    
    /// 普通手机号完整模式（包含前缀过滤）
    static let normalPhonePattern: String = {
        let prefix = ignorePrefixPattern()
        return "\(prefix)(?:\(mobilePattern)|\(mobileWithSeparators))"
    }()
    
    /// 预编译的普通手机号正则表达式
    static let normalPhoneRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: normalPhonePattern, options: [])
        } catch {
            assertionFailure("Failed to compile normal phone regex: \(error)")
            // 返回一个永远不匹配的正则表达式作为降级方案
            return try! NSRegularExpression(pattern: "(?!.*)", options: [])
        }
    }()
    
    // MARK: - 虚拟号模式
    
    /// 虚拟号完整模式（包含前缀过滤）
    /// 格式: 手机号（支持分隔符） + 分隔符 + 3-4位分机号
    static let virtualPhonePattern: String = {
        let prefix = ignorePrefixPattern()
        return "\(prefix)(?:\(mobilePattern)|\(mobileWithSeparators))\(extensionSeparators)\\d{3,4}"
    }()
    
    /// 预编译的虚拟号正则表达式
    static let virtualPhoneRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: virtualPhonePattern, options: [])
        } catch {
            assertionFailure("Failed to compile virtual phone regex: \(error)")
            return try! NSRegularExpression(pattern: "(?!.*)", options: [])
        }
    }()
    
    // MARK: - 隐私号模式
    
    /// 隐私号模式1: 以1开头的隐私号
    /// 格式: 1[3-9]\d{星号字符}{3,7}\d{4}
    private static let privacyPattern1 = "1[3-9]\\d\(starCharacters){3,7}\\d{4}"
    
    /// 隐私号模式2: 以星号开头的隐私号
    /// 格式: {星号字符}{3,7}\d{3,4}
    private static let privacyPattern2 = "\(starCharacters){3,7}\\d{3,4}"
    
    /// 隐私号完整模式（组合两种模式）
    static let privacyPhonePattern: String = {
        return "\(privacyPattern1)|\(privacyPattern2)"
    }()
    
    /// 预编译的隐私号正则表达式
    static let privacyPhoneRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: privacyPhonePattern, options: [])
        } catch {
            assertionFailure("Failed to compile privacy phone regex: \(error)")
            return try! NSRegularExpression(pattern: "(?!.*)", options: [])
        }
    }()
    
    // MARK: - 辅助方法
    
    /// 生成自定义前缀的普通手机号正则表达式
    /// - Parameter customPrefixes: 自定义前缀列表
    /// - Returns: 预编译的正则表达式，如果编译失败返回 nil
    static func normalPhoneRegex(withCustomPrefixes customPrefixes: [String]) -> NSRegularExpression? {
        let prefix = ignorePrefixPattern(customPrefixes: customPrefixes)
        let pattern = "\(prefix)(?:\(mobilePattern)|\(mobileWithSeparators))"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }
    
    /// 生成自定义前缀的虚拟号正则表达式
    /// - Parameter customPrefixes: 自定义前缀列表
    /// - Returns: 预编译的正则表达式，如果编译失败返回 nil
    static func virtualPhoneRegex(withCustomPrefixes customPrefixes: [String]) -> NSRegularExpression? {
        let prefix = ignorePrefixPattern(customPrefixes: customPrefixes)
        let pattern = "\(prefix)(?:\(mobilePattern)|\(mobileWithSeparators))\(extensionSeparators)\\d{3,4}"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }
}
