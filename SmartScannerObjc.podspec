Pod::Spec.new do |s|
  s.name             = 'SmartScannerObjc'
  s.module_name      = 'SmartScannerObjc'
  s.version          = '1.0.0'
  s.summary          = 'Objective-C friendly wrapper for SmartScanner camera and scanning APIs'

  s.description      = <<-DESC
Objective-C friendly CocoaPods entrypoint for SmartScanner. It ships the same
camera scanning implementation as SmartScanner while exposing Objective-C
compatible bridge APIs.
                       DESC

  s.homepage         = 'https://github.com/duanbhu/SmartScanner'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'duanbhu' => '310701836@qq.com' }
  s.source           = { :git => 'https://github.com/duanbhu/SmartScanner.git', :tag => s.version.to_s }

  s.ios.deployment_target = '12.0'
  s.swift_version = '5.0'
  s.static_framework = true
  s.default_subspecs = 'Core', 'Google'

  s.subspec 'Core' do |core|
    core.source_files = 'SmartScanner/Classes/**/*'
    core.resource_bundles = {
      'SmartScanner' => [
        'SmartScanner/Assets/Images.xcassets',
        'SmartScanner/Assets/voice_scan.caf'
      ]
    }
    core.exclude_files = [
      'SmartScanner/Classes/Scanning/AppleEngine.swift',
      'SmartScanner/Classes/Scanning/GoogleEngine.swift',
      'SmartScanner/Classes/Scanning/GoogleEngineUpgrade.swift'
    ]
    core.public_header_files = 'SmartScanner/Classes/*.h'
  end

  s.subspec 'Apple' do |apple|
    apple.dependency 'SmartScannerObjc/Core'
    apple.source_files = 'SmartScanner/Classes/Scanning/AppleEngine.swift'
    apple.pod_target_xcconfig = {
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) SMARTSCANNER_APPLE_ENGINE SWIFTYCAMERA_APPLE_ENGINE'
    }
  end

  s.subspec 'Google' do |google|
    google.dependency 'SmartScannerObjc/Core'
    google.source_files = [
      'SmartScanner/Classes/Scanning/GoogleEngine.swift',
      'SmartScanner/Classes/Scanning/GoogleEngineUpgrade.swift'
    ]
    google.dependency 'GoogleMLKit/BarcodeScanning'
    google.dependency 'GoogleMLKit/TextRecognition'
    google.dependency 'GoogleMLKit/TextRecognitionChinese'
    google.pod_target_xcconfig = {
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) SMARTSCANNER_GOOGLE_ENGINE SWIFTYCAMERA_GOOGLE_ENGINE'
    }
  end
end
