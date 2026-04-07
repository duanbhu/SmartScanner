//
//  DetectReslt.swift
//  MobileExt
//
//  Created by Duanhu on 2024/3/22.
//

import UIKit

@objc(SmartScannerDetectResult)
@objcMembers
public class DetectResult: NSObject {
    /// 单号
    public var barcode: String?
    
    /// 二维码
    public var qrcode: String?
    
    /// 手机号
    public var phone: String?
    
    /// 虚拟号
    public var virtualNumber: String?
    
    /// 隐私号
    public var privacyNumber: String?
    
    public var picture: UIImage?
    
    public var cropImage: UIImage?
    
    public init(
        barcode: String? = nil,
        qrcode: String? = nil,
        phone: String? = nil,
        virtualNumber: String? = nil,
        privacyNumber: String? = nil,
        picture: UIImage? = nil,
        cropImage: UIImage? = nil
    ) {
        self.barcode = barcode
        self.qrcode = qrcode
        self.phone = phone
        self.virtualNumber = virtualNumber
        self.privacyNumber = privacyNumber
        self.picture = picture
        self.cropImage = cropImage
    }

    /// 手机号或者隐私号
    public func phoneNo() -> String {
        if let phone = phone {
            return phone
        } else if let phone = privacyNumber {
            return phone
        }
        return ""
    }
    
    /// 手机号或者虚拟号
    public func phoneOrVirtual() -> String {
        if let phone = phone {
            return phone
        } else if let phone = virtualNumber {
            return phone
        }
        return ""
    }
}
