//
//  SmartScannerObjcTypes.swift
//  SmartScanner
//
//  Created by Codex on 2026/4/7.
//

import Foundation

@objc(SmartScannerObjcScanType)
public enum SmartScannerObjcScanType: Int {
    case barcode = 0
    case qrcode = 1
    case allcode = 2
    case phone = 3
}

@objc(SmartScannerObjcDetectOptions)
@objcMembers
public final class SmartScannerObjcDetectOptions: NSObject {
    public static func qrcode() -> Int { DetecteOptions.qrcode.rawValue }
    public static func barcode() -> Int { DetecteOptions.barcode.rawValue }
    public static func phoneNumber() -> Int { DetecteOptions.phoneNumber.rawValue }
    public static func privacyNumber() -> Int { DetecteOptions.privacyNumber.rawValue }
    public static func virtualNumber() -> Int { DetecteOptions.virtualNumber.rawValue }
    public static func virtualPhone() -> Int { DetecteOptions.virtualPhone.rawValue }
    public static func secretSheet() -> Int { DetecteOptions.secretSheet.rawValue }
    public static func allcode() -> Int { DetecteOptions.allcode.rawValue }
}
