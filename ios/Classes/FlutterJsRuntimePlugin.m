#import "FlutterJsRuntimePlugin.h"
#if __has_include(<flutter_js_runtime/flutter_js_runtime-Swift.h>)
#import <flutter_js_runtime/flutter_js_runtime-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "flutter_js_runtime-Swift.h"
#endif

@implementation FlutterJsRuntimePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFlutterJsRuntimePlugin registerWithRegistrar:registrar];
}
@end
