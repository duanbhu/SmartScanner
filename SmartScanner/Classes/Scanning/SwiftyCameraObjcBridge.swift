//
//  SwiftyCameraObjcBridge.swift
//  SwiftyCamera
//
//  Created by Codex on 2026/4/3.
//

import UIKit

@objc(SmartScannerObjcBridge)
@objcMembers
public final class SmartScannerObjcBridge: NSObject {
    @objc(presentFrom:scanTypeRawValue:detectOptionsRawValue:needAutoImage:completion:)
    public static func present(from viewController: UIViewController?,
                               scanTypeRawValue: Int,
                               detectOptionsRawValue: Int,
                               needAutoImage: Bool,
                               completion: @escaping (DetectResult) -> Void) {
        guard let viewController = viewController else { return }
        
        let itType = makeItType(scanTypeRawValue: scanTypeRawValue,
                                detectOptionsRawValue: detectOptionsRawValue)
        let scanner = ScanItViewController(itType: itType, isNeedAutoImage: needAutoImage)
        scanner.detectResultCallback = completion
        scanner.show(at: viewController)
    }
    
    private static func makeItType(scanTypeRawValue: Int,
                                   detectOptionsRawValue: Int) -> ScanItViewController.ItType {
        switch scanTypeRawValue {
        case 0:
            return .barcode
        case 1:
            return .qrcode
        case 2:
            return .allcode
        case 3:
            let options = DetecteOptions(rawValue: detectOptionsRawValue)
            return .phone(options: options)
        default:
            return .barcode
        }
    }
}
