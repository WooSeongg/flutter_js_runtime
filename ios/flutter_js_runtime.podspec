#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_js_runtime.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_js_runtime'
  s.version          = '0.9.1'
  s.summary          = 'Run JavaScript in Flutter apps.'
  s.description      = <<-DESC
Run JavaScript in Flutter apps. Uses QuickJS on Android, Windows and Linux, and JavaScriptCore on iOS and macOS.
                       DESC
  s.homepage         = 'https://github.com/WooSeongg/flutter_js_runtime'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'WS' => 'blb138@naver.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_js_runtime/Sources/flutter_js_runtime/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'JavaScriptCore'
  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
