#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'open3'
# Run even after partial prepare failure. All paths are confined to the hosted runner.
abort 'Cleanup is GitHub Actions only' unless ENV['GITHUB_ACTIONS'] == 'true'
dir = ENV.fetch('MBUI_RELEASE_PRIVATE')
abort 'Unexpected cleanup directory' unless dir == File.join(ENV.fetch('RUNNER_TEMP'), 'mbui-testflight-private')
failed = false
begin
  original = File.join(dir, 'original-keychains.json')
  if File.file?(original)
    _, status = Open3.capture2e('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *JSON.parse(File.read(original)))
    failed ||= !status.success?
  end
  keychain = File.join(dir, 'release.keychain-db')
  if File.exist?(keychain)
    _, status = Open3.capture2e('/usr/bin/security', 'delete-keychain', keychain)
    failed ||= !status.success?
  end
  installed = File.join(dir, 'installed-profiles')
  if File.file?(installed)
    File.readlines(installed, chomp: true).each do |path|
      root = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')
      abort 'Unexpected profile cleanup path' unless File.dirname(path) == root && File.basename(path).match?(/\A[0-9a-fA-F-]{36}\.mobileprovision\z/)
      FileUtils.rm_f(path)
    end
  end
ensure
  FileUtils.rm_rf(dir)
end
abort 'Private signing cleanup failed (details withheld)' if failed
