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
    @objc(presentFrom:scanType:detectOptions:needAutoImage:completion:)
    public static func present(from viewController: UIViewController?,
                               scanType: SmartScannerObjcScanType,
                               detectOptions: Int,
                               needAutoImage: Bool,
                               completion: @escaping (DetectResult) -> Void) {
        present(from: viewController,
                scanTypeRawValue: scanType.rawValue,
                detectOptionsRawValue: detectOptions,
                needAutoImage: needAutoImage,
                completion: completion)
    }

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

    @objc(presentBarcodeFrom:needAutoImage:completion:)
    public static func presentBarcode(from viewController: UIViewController?,
                                      needAutoImage: Bool,
                                      completion: @escaping (DetectResult) -> Void) {
        present(from: viewController,
                scanType: .barcode,
                detectOptions: SmartScannerObjcDetectOptions.barcode(),
                needAutoImage: needAutoImage,
                completion: completion)
    }

    @objc(presentQRCodeFrom:needAutoImage:completion:)
    public static func presentQRCode(from viewController: UIViewController?,
                                     needAutoImage: Bool,
                                     completion: @escaping (DetectResult) -> Void) {
        present(from: viewController,
                scanType: .qrcode,
                detectOptions: SmartScannerObjcDetectOptions.qrcode(),
                needAutoImage: needAutoImage,
                completion: completion)
    }

    @objc(presentAllCodeFrom:needAutoImage:completion:)
    public static func presentAllCode(from viewController: UIViewController?,
                                      needAutoImage: Bool,
                                      completion: @escaping (DetectResult) -> Void) {
        present(from: viewController,
                scanType: .allcode,
                detectOptions: SmartScannerObjcDetectOptions.allcode(),
                needAutoImage: needAutoImage,
                completion: completion)
    }

    @objc(presentPhoneFrom:detectOptions:needAutoImage:completion:)
    public static func presentPhone(from viewController: UIViewController?,
                                    detectOptions: Int,
                                    needAutoImage: Bool,
                                    completion: @escaping (DetectResult) -> Void) {
        present(from: viewController,
                scanType: .phone,
                detectOptions: detectOptions,
                needAutoImage: needAutoImage,
                completion: completion)
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
