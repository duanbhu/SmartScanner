//
//  String+Ext.swift
//  MobileExt
//
//  Created by Duanhu on 2024/3/22.
//

import Foundation

extension String {
    
    struct Regex {
        static let ignorePrefix = "(?<!YT|ZT|ST|JD|SF|TT|JT|\\d)"
        static let mobile = "1[3-9]\\d{9}"
    }
    
    func matches(of pattern: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count))
        var array: [String] = []
        for match in matches {
            if let range = Range(match.range, in: self) {
                array.append(String(self[range]))
            }
        }
        return array
    }
    
    func matcheResults(of pattern: String) -> [NSTextCheckingResult] {
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count))
        return matches
    }
    
    // 查询手机号
    @available(*, deprecated, message: "Use PhoneExtractor.extractNormalPhones instead")
    func matchePhoneNumbers() -> [String] {
        return matches(of: "\(Regex.ignorePrefix)\(Regex.mobile)")
    }
    
    /// 提取隐私号
    @available(*, deprecated, message: "Use PhoneExtractor.extractPrivacyPhones instead")
    func matchePrivacyPhones() -> [String] {
        let star = "[*^_^斗米关大美长女本水#+$okat4]"
        var pattern = "1[3-9]\\d\(star){3,7}\\d{4}"
        pattern += "|\(star){3,7}\\d{3,4}"
//        pattern += "|\(star){4,11}"
//        pattern += "|1\(star){4,10}"
        let list = matches(of: pattern)
//        debugPrint("提取隐私号\(list)--\(self)")
        return list.map { m in
            let mobile = m.pregReplace(pattern: "[^0-9]", with: "*")
            if mobile.hasPrefix("1") {
                return "\(mobile.prefix(3))****\(mobile.suffix(4))"
            } else if mobile.hasPrefix("*") {
                return "1******\(mobile.suffix(4))"
            }
            return mobile
        }
    }
    
    /// 提取虚拟号  @"1[3-9][\\d]{9}([\\s\\S]{0,3}\\d{3,4})";
    @available(*, deprecated, message: "Use PhoneExtractor.extractVirtualPhones instead")
    func matcheVirtualPhone() -> [String] {
        return matches(of: "\(Regex.ignorePrefix)\(Regex.mobile)[\\s\\S]{0,3}\\d{3,4}")
            .map { mobile in
                let pureNumbers = mobile.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if pureNumbers.count > 11 {
                    let len = pureNumbers.count > 15 ? 4 : (pureNumbers.count - 11)
                    return "\(pureNumbers.prefix(11))转\(pureNumbers.suffix(len))"
                }
                return mobile
            }
    }
    
    func containsDigit() -> Bool {
        let pattern = ".*[\\*\\d].*"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
    
    func isPhoneExt() -> Bool {
        var pattern = ""
        pattern += "1[3-9]\\d{9}([\\s\\S]{0,3}\\d{3,4})?" //虚拟号 普通手机号
        pattern += "|\\*{2,7}\\d{3,4}" // 隐私号
//        "^([^a-zA-Z]*[1\\*][3-9\\*][0-9\\*]{9}([\\s\\S]{0,5}\\d{3,4})?)(?:/[\\S]*)?$|\\*{4,7}\\d{3,4}"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
    
    // MARK: -
    func firstMatch(of pattern: String) -> String? {
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        
        guard let match = regex.firstMatch(in: self, range: NSRange(location: 0, length: self.utf16.count)) else {
            return nil
        }
        
        if let range = Range(match.range, in: self) {
            return String(self[range])
        }
        return nil
    }
    
    //使用正则表达式替换
    func pregReplace(pattern:  String , with string: String ,
                      options:  NSRegularExpression . Options  = []) ->  String  {
        let  regex = try! NSRegularExpression (pattern: pattern, options: options)
        return  regex.stringByReplacingMatches( in :  self , options: [],
                                                range:  NSMakeRange (0,  self.utf16.count),
                                                withTemplate: string)
    }
}

extension NSCountedSet {
    
    /// 出现次数大于max的值
    /// - Parameter max: 出现次数
    /// - Returns: 元素
    func elementExceed(_ max: Int, ignore: String? = nil, ignore2: String? = nil) -> Any? {
        for obj in self {
            if let obj = obj as? String {
                if let ignore = ignore,
                   ignore.contains(obj.prefix(3)), ignore.contains(obj.suffix(2)) {
                    break
                } else if let ignore = ignore2,
                          ignore.contains(obj.prefix(3)), ignore.contains(obj.suffix(2)) {
                    break
                }
            }
            if count(for: obj) > max {
                return obj
            }
        }
        return nil
    }
    
    func mostElement(max: Int) -> String? {
        for obj in self {
            if count(for: obj) > max {
                return obj as? String
            }
        }
        return nil
    }
}
