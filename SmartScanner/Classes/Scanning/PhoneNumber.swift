//
//  PhoneNumber.swift
//  SwiftyCamera
//
//  Created by Kiro
//

import Foundation

/// 手机号类型枚举，支持三种号码类型
enum PhoneNumber: Equatable, Hashable {
    /// 普通手机号：11位数字
    case normal(String)
    
    /// 虚拟号：手机号 + 分机号
    case virtual(String, String)
    
    /// 隐私号：部分数字被遮蔽
    case privacy(String)
    
    /// 显示值，用于展示给用户
    var displayValue: String {
        switch self {
        case .normal(let number):
            return number
        case .virtual(let number, let ext):
            return "\(number)转\(ext)"
        case .privacy(let number):
            return number
        }
    }
    
    /// 原始号码，移除遮蔽字符
    var rawNumber: String {
        switch self {
        case .normal(let number):
            return number
        case .virtual(let number, _):
            return number
        case .privacy(let number):
            return number.replacingOccurrences(of: "*", with: "")
        }
    }
}

/// 提取结果结构体，封装提取结果并提供去重和分类功能
struct ExtractionResult {
    var normalPhones: Set<String> = []
    var virtualPhones: Set<String> = []
    var privacyPhones: Set<String> = []
    
    /// 添加普通手机号
    mutating func addNormal(_ phone: String) {
        normalPhones.insert(phone)
    }
    
    /// 添加虚拟号
    mutating func addVirtual(_ phone: String) {
        virtualPhones.insert(phone)
    }
    
    /// 添加隐私号
    mutating func addPrivacy(_ phone: String) {
        privacyPhones.insert(phone)
    }
    
    /// 返回所有号码的数组
    func allPhones() -> [PhoneNumber] {
        var result: [PhoneNumber] = []
        
        // 添加普通手机号
        result += normalPhones.map { PhoneNumber.normal($0) }
        
        // 添加虚拟号（解析格式 "手机号转分机号"）
        for virtual in virtualPhones {
            let components = virtual.components(separatedBy: "转")
            if components.count == 2 {
                result.append(PhoneNumber.virtual(components[0], components[1]))
            } else {
                // 如果格式不正确，作为普通手机号处理
                result.append(PhoneNumber.normal(virtual))
            }
        }
        
        // 添加隐私号
        result += privacyPhones.map { PhoneNumber.privacy($0) }
        
        return result
    }
}
