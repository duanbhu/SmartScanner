# SmartScanner

[![CI Status](https://img.shields.io/travis/duanbhu/SmartScanner.svg?style=flat)](https://travis-ci.org/duanbhu/SmartScanner)
[![Version](https://img.shields.io/cocoapods/v/SmartScanner.svg?style=flat)](https://cocoapods.org/pods/SmartScanner)
[![License](https://img.shields.io/cocoapods/l/SmartScanner.svg?style=flat)](https://cocoapods.org/pods/SmartScanner)
[![Platform](https://img.shields.io/cocoapods/p/SmartScanner.svg?style=flat)](https://cocoapods.org/pods/SmartScanner)

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

## Installation

SmartScanner is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'SmartScanner'
```

`SmartScanner` 默认集成 `Core + Google`。

### Swift 按需集成

只使用相机采集、扫描框 UI、资源和桥接能力，不接入识别引擎：

```ruby
pod 'SmartScanner/Core'
```

使用苹果原生识别引擎：

```ruby
pod 'SmartScanner/Apple'
```

使用 Google ML Kit 识别引擎：

```ruby
pod 'SmartScanner/Google'
```

使用 Paddle 识别引擎（需同时声明 Paddle SDK 源）：

```ruby
pod 'DHPaddleLiteSDK', :git => 'https://github.com/duanbhu/DHPaddleLiteSDK.git', :branch => 'main'
pod 'SmartScanner/Paddle'
```

Objective-C projects can use the Objective-C friendly pod entrypoint:

```ruby
pod 'SmartScannerObjc'
```

`SmartScannerObjc` 默认集成 `Core + Google`。

### Objective-C 按需集成

只使用相机采集桥接能力，不接入识别引擎：

```ruby
pod 'SmartScannerObjc/Core'
```

使用苹果原生识别引擎：

```ruby
pod 'SmartScannerObjc/Apple'
```

使用 Google ML Kit 识别引擎：

```ruby
pod 'SmartScannerObjc/Google'
```

使用 Paddle 识别引擎（需同时声明 Paddle SDK 源）：

```ruby
pod 'DHPaddleLiteSDK', :git => 'https://github.com/duanbhu/DHPaddleLiteSDK.git', :branch => 'main'
pod 'SmartScannerObjc/Paddle'
```

### Subspec 说明

- `Core`：包含相机采集、扫描框 UI、资源文件、Objective-C 桥接类，不包含文本/码识别引擎。
- `Apple`：在 `Core` 基础上增加苹果原生识别引擎。
- `Google`：在 `Core` 基础上增加 Google ML Kit 识别引擎。
- `Paddle`：在 `Core` 基础上增加 Paddle 识别引擎（依赖 `DHPaddleLiteSDK`）。

如果你要直接使用 `ScanItViewController` 或 `SmartScannerObjcBridge` 的扫描识别能力，请选择 `Apple`、`Google` 或 `Paddle`，不要只集成 `Core`。

Example Objective-C import and usage:

```objc
#import <SmartScannerObjc/SmartScannerObjc.h>

[SmartScannerObjcBridge presentPhoneFrom:self
                           detectOptions:[SmartScannerObjcDetectOptions virtualPhone]
                           needAutoImage:NO
                              completion:^(SmartScannerDetectResult *result) {
  NSLog(@"phone: %@", [result phoneOrVirtual]);
}];
```

If you want an Objective-C equivalent of `CameraScannable`, use `SmartScannerObjcScanSession`:

```objc
#import <SmartScannerObjc/SmartScannerObjc.h>

@property (nonatomic, strong) SmartScannerObjcScanSession *scanSession;

self.scanSession =
    [[SmartScannerObjcScanSession alloc] initWithPreview:self.previewView
                                           detectOptions:[SmartScannerObjcDetectOptions virtualPhone]];
self.scanSession.needAutoPhoto = NO;
[self.scanSession setRegionRectInPreview:self.previewView.bounds];
[self.scanSession setResultHandler:^(SmartScannerDetectResult *result) {
  NSLog(@"phone: %@", [result phoneOrVirtual]);
}];
[self.scanSession start];
```

## Author

duanbhu, 310701836@qq.com

## License

SmartScanner is available under the MIT license. See the LICENSE file for more info.
