#
# Be sure to run `pod lib lint SmartScanner.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SmartScanner'
  s.module_name      = 'SmartScanner'
  s.version          = '1.0.0'
  s.summary          = '相机采集视频流、谷歌MLKit识别手机号、条形码'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
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
      'SmartScanner/Classes/Scanning/GoogleEngineUpgrade.swift',
      'SmartScanner/Classes/Scanning/PaddleEngine.swift'
    ]
    core.public_header_files = 'SmartScanner/Classes/*.h'
  end

  s.subspec 'Apple' do |apple|
    apple.dependency 'SmartScanner/Core'
    apple.source_files = 'SmartScanner/Classes/Scanning/AppleEngine.swift'
    apple.pod_target_xcconfig = {
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) SMARTSCANNER_APPLE_ENGINE SWIFTYCAMERA_APPLE_ENGINE'
    }
  end

  s.subspec 'Google' do |google|
    google.dependency 'SmartScanner/Core'
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

  s.subspec 'Paddle' do |paddle|
    paddle.dependency 'SmartScanner/Core'
    paddle.dependency 'DHPaddleLiteSDK'
    paddle.source_files = 'SmartScanner/Classes/Scanning/PaddleEngine.swift'
    paddle.pod_target_xcconfig = {
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) SMARTSCANNER_PADDLE_ENGINE SWIFTYCAMERA_PADDLE_ENGINE'
    }
  end
  
end
