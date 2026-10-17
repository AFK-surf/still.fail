# Views the app draws natively on iOS: Smooth, a box with still.fail's corners (Corners.swift, the curves of the
# Android app's ui/Corners.kt), clipping what it holds.
Pod::Spec.new do |s|
  s.name           = 'StillfailUi'
  s.version        = '0.1.0'
  s.summary        = "still.fail's corners as a view"
  s.description    = "still.fail's corners as a view"
  s.license        = 'MIT'
  s.author         = 'still.fail'
  s.homepage       = 'https://still.fail'
  s.platforms      = { :ios => '15.1' }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.source_files = '*.swift'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
