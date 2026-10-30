#!/usr/bin/ruby
# Usage: ruby generate.rb /absolute/path/to/compiled.app [generated-directory] [iphoneos|iphonesimulator]
# Generates only an Xcode packaging bridge: it never compiles or signs code.
require 'fileutils'
require 'digest'
require 'json'
require 'open3'

abort "Usage: #{$PROGRAM_NAME} COMPILED.app [GENERATED_DIRECTORY] [iphoneos|iphonesimulator]" unless (1..3).cover?(ARGV.length)
input = File.realpath(ARGV[0])
out = File.expand_path(ARGV[1] || File.join(Dir.pwd, '.airbuild/packaging/generated'))
abort 'Input must be an .app directory' unless File.directory?(input) && input.end_with?('.app')
abort 'Input and generated directory must not overlap' if input == out || input.start_with?(out + '/') || out.start_with?(input + '/')
%w[Info.plist mbui PlugIns/Share.appex/Info.plist PlugIns/Share.appex/Share Frameworks/hermes.framework/Info.plist Frameworks/hermes.framework/hermes core.hbc].each do |relative|
  abort "Missing compiled input: #{relative}" unless File.file?(File.join(input, relative))
end
def read_plist(path)
  json, status = Open3.capture2('/usr/bin/plutil', '-convert', 'json', '-o', '-', path)
  abort "Cannot read plist: #{path}" unless status.success?
  JSON.parse(json)
end
metadata = read_plist(File.join(input, 'Info.plist'))
platform_sdks = { 'iPhoneOS' => 'iphoneos', 'iPhoneSimulator' => 'iphonesimulator' }
sdk = ARGV[2] || platform_sdks[Array(metadata['CFBundleSupportedPlatforms']).first] || metadata['DTPlatformName']
abort 'Cannot determine input platform; specify iphoneos or iphonesimulator as third argument' unless platform_sdks.value?(sdk)
platform = platform_sdks.key(sdk)

FileUtils.mkdir_p(out)
staged = File.join(out, 'staged')
FileUtils.rm_rf(staged)
FileUtils.mkdir_p(staged)

def run!(*args)
  abort "Failed: #{args.first}" unless system(*args)
end

def stage_payload(source, destination)
  FileUtils.mkdir_p(destination)
  run!('/usr/bin/rsync', '-a', '--exclude=/Info.plist', '--exclude=/Frameworks', '--exclude=/PlugIns', '--exclude=_CodeSignature', '--exclude=*.mobileprovision', '--exclude=*.provisionprofile', source + '/', destination + '/')
end
stage_payload(input, File.join(staged, 'App'))
stage_payload(File.join(input, 'PlugIns/Share.appex'), File.join(staged, 'Share'))
FileUtils.mkdir_p(File.join(staged, 'Frameworks'))
run!('/usr/bin/rsync', '-a', '--exclude=_CodeSignature', '--exclude=*.mobileprovision', '--exclude=*.provisionprofile', File.join(input, 'Frameworks/hermes.framework'), File.join(staged, 'Frameworks') + '/')

# Retain all app-specific metadata (scenes, privacy strings, extension activation
# rules, versions, localizations, etc.). Only packaging identity/platform changes.
[['App', input], ['Share', File.join(input, 'PlugIns/Share.appex')]].each do |name, source|
  plist = File.join(staged, "#{name}-Info.plist")
  FileUtils.cp(File.join(source, 'Info.plist'), plist)
  run!('/usr/bin/plutil', '-convert', 'xml1', plist)
  # Xcode's ProcessInfoPlistFile supplies current SDK/toolchain metadata.
  # Do not let copied compiler provenance pin a different SDK or platform.
  read_plist(plist).keys.grep(/\ADT/).each do |key|
    run!('/usr/bin/plutil', '-remove', key, plist)
  end
  {
    'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)',
    'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
    'CFBundleSupportedPlatforms' => [platform],
    'MinimumOSVersion' => '17.0',
    'MBUIAppGroup' => 'group.fail.still.mbui'
  }.each do |key, value|
    # plutil -replace supports inserting absent keys on macOS.
    if value.is_a?(Array)
      run!('/usr/bin/plutil', '-replace', key, '-json', JSON.generate(value), plist)
    else
      run!('/usr/bin/plutil', '-replace', key, '-string', value, plist)
    end
  end
end
FileUtils.cp(File.join(__dir__, 'install-prebuilt.sh'), File.join(out, 'install-prebuilt.sh'))
entitlements = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
    <key>com.apple.security.application-groups</key>
    <array><string>group.fail.still.mbui</string></array>
  </dict></plist>
XML
%w[App Share].each { |name| File.write(File.join(out, "#{name}.entitlements"), entitlements) }

# Write an OpenStep project without requiring xcodeproj or other downloaded gems.
objects = {}
id = ->(name) { Digest::SHA256.hexdigest(name)[0, 24].upcase }
add = lambda do |name, isa, values|
  objects[id.call(name)] = { 'isa' => isa }.merge(values)
  id.call(name)
end
app_product = add.call('app-product', 'PBXFileReference', 'explicitFileType' => 'wrapper.application', 'includeInIndex' => 0, 'path' => 'mbui.app', 'sourceTree' => 'BUILT_PRODUCTS_DIR')
share_product = add.call('share-product', 'PBXFileReference', 'explicitFileType' => 'wrapper.app-extension', 'includeInIndex' => 0, 'path' => 'Share.appex', 'sourceTree' => 'BUILT_PRODUCTS_DIR')
framework = add.call('hermes', 'PBXFileReference', 'lastKnownFileType' => 'wrapper.framework', 'path' => 'staged/Frameworks/hermes.framework', 'sourceTree' => '<group>')
products = add.call('products', 'PBXGroup', 'children' => [app_product, share_product], 'name' => 'Products', 'sourceTree' => '<group>')
main = add.call('main', 'PBXGroup', 'children' => [framework, products], 'sourceTree' => '<group>')
framework_build = add.call('embed-hermes', 'PBXBuildFile', 'fileRef' => framework, 'settings' => { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] })
share_build = add.call('embed-share', 'PBXBuildFile', 'fileRef' => share_product, 'settings' => { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] })
embed_framework = add.call('framework-phase', 'PBXCopyFilesBuildPhase', 'buildActionMask' => 2147483647, 'dstPath' => '', 'dstSubfolderSpec' => 10, 'files' => [framework_build], 'name' => 'Embed Frameworks', 'runOnlyForDeploymentPostprocessing' => 0)
embed_share = add.call('share-phase', 'PBXCopyFilesBuildPhase', 'buildActionMask' => 2147483647, 'dstPath' => '', 'dstSubfolderSpec' => 13, 'files' => [share_build], 'name' => 'Embed App Extensions', 'runOnlyForDeploymentPostprocessing' => 0)
proxy = add.call('share-proxy', 'PBXContainerItemProxy', 'containerPortal' => id.call('project'), 'proxyType' => 1, 'remoteGlobalIDString' => id.call('share-target'), 'remoteInfo' => 'Share')
dependency = add.call('share-dependency', 'PBXTargetDependency', 'target' => id.call('share-target'), 'targetProxy' => proxy)
common = {
  'SDKROOT' => sdk, 'SUPPORTED_PLATFORMS' => sdk,
  'IPHONEOS_DEPLOYMENT_TARGET' => '17.0', 'TARGETED_DEVICE_FAMILY' => '1',
  'ARCHS' => 'arm64', 'ONLY_ACTIVE_ARCH' => 'NO',
  'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
  'COPY_PHASE_STRIP' => 'NO', 'STRIP_INSTALLED_PRODUCT' => 'NO'
}
config_list = lambda do |name, settings|
  configs = %w[Debug Release].map do |configuration|
    add.call("#{name}-#{configuration}", 'XCBuildConfiguration', 'buildSettings' => settings, 'name' => configuration)
  end
  add.call("#{name}-configs", 'XCConfigurationList', 'buildConfigurations' => configs, 'defaultConfigurationIsVisible' => 0, 'defaultConfigurationName' => 'Release')
end
project_configs = config_list.call('project', common)
[['app', 'App', 'mbui', 'fail.still.mbui', 'com.apple.product-type.application'],
 ['share', 'Share', 'Share', 'fail.still.mbui.share', 'com.apple.product-type.app-extension']].each do |kind, payload, executable, bundle_id, type|
  outputs = ['$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)']
  outputs << '$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/core.hbc' if kind == 'app'
  phase = add.call("#{kind}-install", 'PBXShellScriptBuildPhase',
    'buildActionMask' => 2147483647, 'files' => [], 'alwaysOutOfDate' => 1,
    'inputPaths' => ["$(SRCROOT)/staged/#{payload}", '$(SRCROOT)/install-prebuilt.sh'],
    'outputPaths' => outputs, 'name' => 'Install Prebuilt Payload',
    'runOnlyForDeploymentPostprocessing' => 0, 'shellPath' => '/bin/bash',
    'shellScript' => "/bin/bash \"$SRCROOT/install-prebuilt.sh\" #{kind}\n")
  settings = {
    'PRODUCT_NAME' => executable, 'EXECUTABLE_NAME' => executable,
    'PRODUCT_BUNDLE_IDENTIFIER' => bundle_id,
    'INFOPLIST_FILE' => "staged/#{payload}-Info.plist",
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'CODE_SIGN_ENTITLEMENTS' => "#{payload}.entitlements",
    'SKIP_INSTALL' => kind == 'app' ? 'NO' : 'YES',
    'INSTALL_PATH' => kind == 'app' ? '$(LOCAL_APPS_DIR)' : '$(LOCAL_LIBRARY_DIR)/PlugIns'
  }
  # Explicit cloud-only mapping; managed/local signing remains entirely untouched.
  if ENV['MBUI_IOS_CI_PROFILES']
    abort 'Cloud profiles cannot override managed signing' if ENV['AIRBUILD_SIGN'] == '1' || ENV['XCODE_XCCONFIG_FILE']
    profiles = JSON.parse(ENV.fetch('MBUI_IOS_CI_PROFILES'))
    abort 'Cloud profile mapping must cover exactly app and Share' unless profiles.keys.sort == %w[fail.still.mbui fail.still.mbui.share]
    profile = profiles.fetch(bundle_id)
    abort 'Invalid cloud profile UUID' unless profile.match?(/\A[0-9A-Fa-f-]{36}\z/)
    settings.merge!('CODE_SIGN_STYLE' => 'Manual', 'DEVELOPMENT_TEAM' => 'D9AAN3VJK8',
      'CODE_SIGN_IDENTITY' => 'Apple Distribution', 'PROVISIONING_PROFILE_SPECIFIER' => profile)
  end
  settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES' if kind == 'share'
  configs = config_list.call(kind, settings)
  add.call("#{kind}-target", 'PBXNativeTarget',
    'buildConfigurationList' => configs,
    'buildPhases' => kind == 'app' ? [phase, embed_framework, embed_share] : [phase],
    'buildRules' => [], 'dependencies' => kind == 'app' ? [dependency] : [],
    'name' => executable, 'productName' => executable,
    'productReference' => kind == 'app' ? app_product : share_product, 'productType' => type)
end
project = add.call('project', 'PBXProject', 'attributes' => { 'BuildIndependentTargetsInParallel' => 'YES' },
  'buildConfigurationList' => project_configs, 'compatibilityVersion' => 'Xcode 14.0',
  'developmentRegion' => 'zh-Hans', 'hasScannedForEncodings' => 0,
  'knownRegions' => ['zh-Hans', 'en', 'Base'], 'mainGroup' => main,
  'productRefGroup' => products, 'projectDirPath' => '', 'projectRoot' => '',
  'targets' => [id.call('app-target'), id.call('share-target')])
def openstep(value, indent = 0)
  case value
  when Hash
    "{\n" + value.map { |k, v| "#{'  ' * (indent + 1)}#{openstep(k)} = #{openstep(v, indent + 1)};\n" }.join + "#{'  ' * indent}}"
  when Array
    '(' + value.map { |v| openstep(v, indent + 1) }.join(', ') + ')'
  when Integer then value.to_s
  else '"' + value.to_s.gsub('\\', '\\\\').gsub('"', '\\"').gsub("\n", '\\n') + '"'
  end
end
project_dir = File.join(out, 'MBUIPackaging.xcodeproj')
FileUtils.mkdir_p(project_dir)
File.write(File.join(project_dir, 'project.pbxproj'), "// !$*UTF8*$!\n" + openstep({ 'archiveVersion' => 1, 'classes' => {}, 'objectVersion' => 56, 'objects' => objects, 'rootObject' => project }) + "\n")
scheme_dir = File.join(project_dir, 'xcshareddata/xcschemes')
FileUtils.mkdir_p(scheme_dir)
File.write(File.join(scheme_dir, 'MBUI.xcscheme'), <<~XML)
  <?xml version="1.0" encoding="UTF-8"?>
  <Scheme LastUpgradeVersion="1600" version="1.3">
    <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries><BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{id.call('app-target')}" BuildableName="mbui.app" BlueprintName="mbui" ReferencedContainer="container:MBUIPackaging.xcodeproj"/>
      </BuildActionEntry></BuildActionEntries>
    </BuildAction>
    <TestAction buildConfiguration="Debug"/>
    <LaunchAction buildConfiguration="Debug" useCustomWorkingDirectory="NO"/>
    <ProfileAction buildConfiguration="Release" useCustomWorkingDirectory="NO"/>
    <AnalyzeAction buildConfiguration="Debug"/>
    <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
  </Scheme>
XML
puts project_dir
