//
//  SmartScannerObjc.h
//  SmartScannerObjc
//
//  Created by Codex on 2026/4/7.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SmartScannerObjcScanType) {
    SmartScannerObjcScanTypeBarcode = 0,
    SmartScannerObjcScanTypeQrcode = 1,
    SmartScannerObjcScanTypeAllcode = 2,
    SmartScannerObjcScanTypePhone = 3,
};

@interface SmartScannerDetectResult : NSObject

@property (nullable, nonatomic, copy) NSString *barcode;
@property (nullable, nonatomic, copy) NSString *qrcode;
@property (nullable, nonatomic, copy) NSString *phone;
@property (nullable, nonatomic, copy) NSString *virtualNumber;
@property (nullable, nonatomic, copy) NSString *privacyNumber;
@property (nullable, nonatomic, strong) UIImage *picture;
@property (nullable, nonatomic, strong) UIImage *cropImage;

- (NSString *)phoneNo;
- (NSString *)phoneOrVirtual;

@end

@interface SmartScannerObjcDetectOptions : NSObject

+ (NSInteger)qrcode;
+ (NSInteger)barcode;
+ (NSInteger)phoneNumber;
+ (NSInteger)privacyNumber;
+ (NSInteger)virtualNumber;
+ (NSInteger)virtualPhone;
+ (NSInteger)secretSheet;
+ (NSInteger)allcode;

@end

@interface SmartScannerObjcBridge : NSObject

+ (void)presentFrom:(nullable UIViewController *)viewController
           scanType:(SmartScannerObjcScanType)scanType
      detectOptions:(NSInteger)detectOptions
      needAutoImage:(BOOL)needAutoImage
         completion:(void (^ _Nonnull)(SmartScannerDetectResult *result))completion;

+ (void)presentBarcodeFrom:(nullable UIViewController *)viewController
             needAutoImage:(BOOL)needAutoImage
                completion:(void (^ _Nonnull)(SmartScannerDetectResult *result))completion;

+ (void)presentQRCodeFrom:(nullable UIViewController *)viewController
            needAutoImage:(BOOL)needAutoImage
               completion:(void (^ _Nonnull)(SmartScannerDetectResult *result))completion;

+ (void)presentAllCodeFrom:(nullable UIViewController *)viewController
             needAutoImage:(BOOL)needAutoImage
                completion:(void (^ _Nonnull)(SmartScannerDetectResult *result))completion;

+ (void)presentPhoneFrom:(nullable UIViewController *)viewController
           detectOptions:(NSInteger)detectOptions
           needAutoImage:(BOOL)needAutoImage
              completion:(void (^ _Nonnull)(SmartScannerDetectResult *result))completion;

@end

@interface SmartScannerObjcCapturerBridge : NSObject

@property (nonatomic, strong, readonly) UIView *preview;

- (nullable instancetype)initWithPreview:(UIView *)preview NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)stop;
- (void)setTorchOpen:(BOOL)isOpen;
- (void)setRegionRectInPreview:(CGRect)regionRect;
- (void)setAppleRegionRectInPreview:(CGRect)regionRect;
- (void)setSampleBufferHandler:(void (^ _Nullable)(CMSampleBufferRef sampleBuffer, CGRect regionRect))handler;
- (void)takePhotoWithSound:(BOOL)isSound completion:(void (^ _Nullable)(UIImage *image))completion;

@end

@interface SmartScannerObjcScanSession : NSObject

@property (nonatomic, strong, readonly) UIView *preview;
@property (nonatomic, assign) BOOL needAutoPhoto;

- (nullable instancetype)initWithPreview:(UIView *)preview detectOptions:(NSInteger)detectOptions NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setResultHandler:(void (^ _Nullable)(SmartScannerDetectResult *result))handler;
- (void)setDetectOptionsRawValue:(NSInteger)detectOptionsRawValue;
- (void)start;
- (void)stop;
- (void)setTorchOpen:(BOOL)isOpen;
- (void)setRegionRectInPreview:(CGRect)regionRect;
- (void)setAppleRegionRectInPreview:(CGRect)regionRect;
- (void)takePhotoWithSound:(BOOL)isSound completion:(void (^ _Nullable)(UIImage *image))completion;

@end

NS_ASSUME_NONNULL_END
