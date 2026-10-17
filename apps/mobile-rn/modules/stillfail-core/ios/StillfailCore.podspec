# The core for the React Native app on iOS: the Android app's engine (apps/android/core/src/main/cpp/engine.cpp,
# compiled into EngineApple.cpp) on React Native's Hermes and JSI, the Rust shell (client/shell) as a static library,
# and the core as Hermes bytecode. The last two are made by scripts/core-ios.sh into prebuilt/ (not committed): run it
# before `pod install`.
Pod::Spec.new do |s|
  s.name           = 'StillfailCore'
  s.version        = '0.1.0'
  s.summary        = "still.fail's core in its own Hermes engine"
  s.description    = "still.fail's core (client/core-ts) in a Hermes runtime of its own, its IO in the Rust shell"
  s.license        = 'MIT'
  s.author         = 'still.fail'
  s.homepage       = 'https://still.fail'
  s.platforms      = { :ios => '15.1' }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'
  s.dependency 'hermes-engine'
  s.dependency 'React-jsi'

  s.source_files = '*.{h,cpp,mm,swift}'
  # Swift sees the Objective-C class only; EngineApple.h is C++.
  s.public_header_files = 'CoreEngine.h'
  s.private_header_files = 'EngineApple.h'
  s.vendored_frameworks = 'prebuilt/StillfailShell.xcframework'
  s.resource_bundles = { 'StillfailCore' => ['prebuilt/core.hbc'] }
  # What the shell's Rust needs of the system (scripts/core-ios.sh prints rustc's native-static-libs).
  s.frameworks = 'Network', 'SystemConfiguration', 'Security', 'CoreFoundation', 'Foundation', 'LocalAuthentication'
  s.libraries = 'c++', 'iconv'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    # Hermes's headers declare more when its debugger is in (React Native's Debug build): the same here.
    'GCC_PREPROCESSOR_DEFINITIONS[config=*Debug*]' => '$(inherited) HERMES_ENABLE_DEBUGGER=1',
  }
end
