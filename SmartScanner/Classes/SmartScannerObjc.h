//
//  SmartScannerObjc.h
//  SmartScannerObjc
//
//  Created by Codex on 2026/4/7.
//

#ifndef SMARTSCANNER_OBJC_H
#define SMARTSCANNER_OBJC_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>

// Swift @objc public APIs are exposed via the generated -Swift.h header.
#if __has_include(<SmartScanner/SmartScanner-Swift.h>)
#import <SmartScanner/SmartScanner-Swift.h>
#elif __has_include(<SmartScannerObjc/SmartScannerObjc-Swift.h>)
#import <SmartScannerObjc/SmartScannerObjc-Swift.h>
#elif __has_include("SmartScanner-Swift.h")
#import "SmartScanner-Swift.h"
#elif __has_include("SmartScannerObjc-Swift.h")
#import "SmartScannerObjc-Swift.h"
#endif

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SmartScannerObjcScanType) {
    SmartScannerObjcScanTypeBarcode = 0,
    SmartScannerObjcScanTypeQrcode = 1,
    SmartScannerObjcScanTypeAllcode = 2,
    SmartScannerObjcScanTypePhone = 3,
};

NS_ASSUME_NONNULL_END

#endif /* SMARTSCANNER_OBJC_H */
