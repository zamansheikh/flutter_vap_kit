Pod::Spec.new do |s|
  s.name             = 'flutter_vap_kit'
  s.version          = '0.1.2'
  s.summary          = 'Play Tencent VAP transparent-video animations in Flutter.'
  s.description      = <<-DESC
A Flutter plugin that plays Tencent VAP (alpha-channel MP4) animations with a
single widget: seamless looping, first-frame poster, asset caching.
                       DESC
  s.homepage         = 'https://github.com/zamansheikh/flutter_vap_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Zaman Sheikh' => 'zaman6545@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_vap_kit/Sources/**/*.{swift,h,m}'
  s.frameworks       = 'Metal', 'MetalKit', 'VideoToolbox', 'AVFoundation', 'CoreMedia', 'CoreVideo', 'QuartzCore'
  s.resource_bundles = { 'flutter_vap_kit_privacy' => ['flutter_vap_kit/Sources/flutter_vap_kit/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
