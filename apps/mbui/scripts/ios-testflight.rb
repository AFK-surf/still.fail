#!/usr/bin/env ruby
# Standalone GitHub release only. Never uses AirBuild/runtime authentication.
require 'base64'
require 'json'
require 'openssl'
require 'net/http'
require 'uri'
require 'open3'
require 'fileutils'
require 'digest'
require 'time'
require 'rexml/document'

module TestFlight
  APP = '6826455869'
  TEAM = 'D9AAN3VJK8'
  BUNDLES = %w[fail.still.mbui fail.still.mbui.share].freeze
  GROUP = 'group.fail.still.mbui'
  SECRETS = %w[MBUI_IOS_CERTIFICATE_P12_BASE64 MBUI_IOS_CERTIFICATE_PASSWORD MBUI_IOS_APP_PROFILE_BASE64 MBUI_IOS_SHARE_PROFILE_BASE64 MBUI_ASC_KEY_ID MBUI_ASC_ISSUER_ID MBUI_ASC_PRIVATE_KEY_BASE64].freeze
  # Each stage's secrets (upload never touches the signing identity).
  STAGE_SECRETS = {'prepare' => SECRETS, 'package' => [], 'upload' => %w[MBUI_ASC_KEY_ID MBUI_ASC_ISSUER_ID MBUI_ASC_PRIVATE_KEY_BASE64]}.freeze
  class Failure < StandardError; end
  def self.check(value, message)
    raise Failure, message unless value
  end
  def self.command(*args)
    output, status = Open3.capture2e(*args)
    check(status.success?, "Command failed: #{File.basename(args.first)} (output withheld)")
    output
  end
  # plutil JSON cannot represent provisioning-profile DATE/DATA values.
  # Keep these as ISO date/base64 strings, exactly as the policy validator expects.
  def self.parse_plist(xml)
    document = REXML::Document.new(xml)
    decode = lambda do |node|
      case node.name
      when 'dict'
        children = node.elements.to_a
        check(children.length.even?, 'Malformed plist dictionary')
        children.each_slice(2).to_h do |k, v|
          check(k.name == 'key', 'Malformed plist key')
          [k.text.to_s, decode.call(v)]
        end
      when 'array' then node.elements.map { |e| decode.call(e) }
      when 'true' then true
      when 'false' then false
      when 'integer' then Integer(node.text)
      when 'real' then Float(node.text)
      when 'string', 'key', 'date' then node.text.to_s
      when 'data' then node.text.to_s.gsub(/\s+/, '')
      else raise Failure, 'Unsupported plist value'
      end
    end
    check(document.root&.name == 'plist', 'Invalid plist root')
    decode.call(document.root.elements[1])
  end
  def self.plist(path)
    parse_plist(command('/usr/bin/plutil', '-convert', 'xml1', '-o', '-', path))
  end
  def self.validate_key!(key)
    check(key.is_a?(OpenSSL::PKey::EC) && key.private? && key.group.curve_name == 'prime256v1', 'ASC key must be a private P-256 key')
  end
  def self.validate_p12!(p12, now = Time.now)
    cert = p12.certificate
    check(p12.key && cert && cert.not_after > now + 3600 && cert.not_before < now && cert.check_private_key(p12.key), 'Invalid/expired signing certificate')
    check(cert.subject.to_a.any? { |k, v, _| k == 'OU' && v == TEAM } && cert.subject.to_a.any? { |k, v, _| k == 'CN' && v.start_with?('Apple Distribution:') }, 'Wrong signing certificate identity')
    cert
  end
  def self.profile_valid!(p, bundle, now = Time.now)
    e = p.fetch('Entitlements')
    check(p['TeamIdentifier'] == [TEAM] && e['com.apple.developer.team-identifier'] == TEAM, 'Profile team mismatch')
    check(e['application-identifier'] == "#{TEAM}.#{bundle}", 'Profile bundle mismatch')
    check(e['com.apple.security.application-groups'] == [GROUP], 'Profile App Groups mismatch')
    check(e['get-task-allow'] == false && e['beta-reports-active'] == true, 'Not an App Store distribution profile')
    check(!p.key?('ProvisionedDevices') && !p.key?('ProvisionsAllDevices'), 'Device/ad hoc/enterprise profile rejected')
    check(Time.parse(p.fetch('ExpirationDate')) > now + 3600, 'Profile expires too soon')
    check(p.fetch('UUID').match?(/\A[0-9a-fA-F-]{36}\z/), 'Invalid profile UUID')
  end
  # The group gets every processed build by itself (Apple's automatic distribution): no job waits for Apple's
  # processing, which takes longer than a CI job may (10 minutes).
  def self.group_valid!(g)
    a = g.fetch('attributes')
    check(a['isInternalGroup'] == true && a['publicLinkEnabled'] != true, 'Group must be internal, without a public link')
    check(a['hasAccessToAllBuilds'] == true, 'Turn on automatic distribution for the group in App Store Connect')
  end
  # The build is main's commit count, as every still.fail app's (version 0.1.<it>).
  def self.build_number(count)
    check(count.is_a?(Integer) && count.between?(1, 9999), 'Marketing version component exhausted; owner version migration required')
    count
  end
  class API
    def initialize(key, key_id, issuer)
      @key, @key_id, @issuer = key, key_id, issuer
    end
    def token(now = Time.now.to_i)
      enc = ->(s) { Base64.urlsafe_encode64(s, padding: false) }
      head = enc.call(JSON.generate(alg: 'ES256', kid: @key_id, typ: 'JWT'))
      body = enc.call(JSON.generate(iss: @issuer, iat: now - 5, exp: now + 300, aud: 'appstoreconnect-v1'))
      input = "#{head}.#{body}"
      der = @key.sign(OpenSSL::Digest::SHA256.new, input)
      pair = OpenSSL::ASN1.decode(der).value.map { |i| i.value.to_i.to_s(16).rjust(64, '0') }
      TestFlight.check(pair.all? { |i| i.size == 64 }, 'Invalid ES256 signature')
      "#{input}.#{enc.call([pair.join].pack('H*'))}"
    end
    def send_request(http, req)
      http.request(req)
    end
    def retry_delay(attempt)
      sleep [2**attempt, 8].min
    end
    def request(method, path, body = nil)
      uri = URI.join('https://api.appstoreconnect.apple.com', path)
      TestFlight.check(uri.scheme == 'https' && uri.host == 'api.appstoreconnect.apple.com', 'Unexpected API pagination host')
      5.times do |attempt|
        req = Net::HTTP.const_get(method.capitalize).new(uri)
        req['Authorization'] = "Bearer #{token}"
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate(body) if body
        http = Net::HTTP.new(uri.host, 443)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = 60
        begin
          response = send_request(http, req)
        rescue IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
          if method == 'get' && attempt < 4
            retry_delay(attempt)
            next
          end
          raise Failure, 'Apple API transport failed; mutations are never blindly replayed'
        end
        if method == 'get' && response.code.to_i.between?(500, 599) && attempt < 4
          retry_delay(attempt)
          next
        end
        if method == 'get' && response.code == '429' && attempt < 4
          delay = response['Retry-After'].to_s
          TestFlight.check(delay.match?(/\A\d+\z/) && delay.to_i <= 120, 'Unbounded Apple rate limit; resume later')
          sleep delay.to_i # bounded external API rate-limit event, not app settling
          next
        end
        TestFlight.check(response.code.to_i.between?(200, 299), "Apple API HTTP #{response.code} (response withheld)")
        return response.body.to_s.empty? ? {} : JSON.parse(response.body)
      end
    end
    def all(path)
      rows = []
      100.times do
        result = request('get', path)
        rows.concat(result.fetch('data'))
        path = result.fetch('links', {})['next']
        return rows unless path
      end
      raise Failure, 'API pagination limit exceeded'
    end
    def query(path, params)
      path + '?' + URI.encode_www_form(params)
    end
    def preflight(group)
      app = request('get', "/v1/apps/#{APP}").fetch('data')
      TestFlight.check(app.dig('attributes', 'bundleId') == BUNDLES.first, 'ASC app identity mismatch')
      groups = all("/v1/apps/#{APP}/betaGroups?limit=200")
      selected = groups.find { |g| g['id'] == group }
      TestFlight.check(selected, 'Authorized group does not belong to release app')
      TestFlight.group_valid!(selected)
      owner = request('get', "/v1/betaGroups/#{group}/app").dig('data', 'id')
      TestFlight.check(owner == APP, 'Beta group app relationship mismatch')
      TestFlight.check(groups.all? { |g| g.dig('attributes', 'publicLinkEnabled') != true }, 'App has a public beta link; owner must disable it')
    end
    def builds(number = nil)
      params = { 'filter[app]' => APP, 'limit' => '200' }
      params['filter[version]'] = number.to_s if number
      all(query('/v1/builds', params))
    end
  end

  def self.main
    check(ENV['GITHUB_ACTIONS'] == 'true' && ENV['GITHUB_REF'] == 'refs/heads/main' && ENV['GITHUB_REPOSITORY'] == 'AFK-surf/still.fail', 'Release is restricted to upstream main on GitHub Actions')
    check(%w[push workflow_dispatch].include?(ENV['GITHUB_EVENT_NAME']), 'Unsupported release event')
    stage = ARGV.fetch(0, '')
    check(STAGE_SECRETS.key?(stage), 'Expected prepare, package or upload')
    STAGE_SECRETS.fetch(stage).each { |name| check(!ENV[name].to_s.empty?, "Missing dedicated secret: #{name}") }
    private_dir = ENV.fetch('MBUI_RELEASE_PRIVATE')
    safe_dir = ENV.fetch('MBUI_RELEASE_SAFE')
    check(private_dir == File.join(ENV.fetch('RUNNER_TEMP'), 'mbui-testflight-private') && safe_dir == File.join(ENV.fetch('RUNNER_TEMP'), 'mbui-testflight-artifacts'), 'Release paths must stay in the ephemeral runner directory')
    FileUtils.mkdir_p([private_dir, safe_dir], mode: 0700)
    return package(private_dir, safe_dir) if stage == 'package'
    group = ENV.fetch('MBUI_TESTFLIGHT_GROUP_ID', '')
    check(group.match?(/\A[0-9a-fA-F-]{36}\z/), 'Set MBUI_TESTFLIGHT_GROUP_ID to the internal group')
    key = OpenSSL::PKey.read(Base64.strict_decode64(ENV.fetch('MBUI_ASC_PRIVATE_KEY_BASE64')))
    validate_key!(key)
    check(ENV.fetch('MBUI_ASC_KEY_ID').match?(/\A[A-Z0-9]{10}\z/) && ENV.fetch('MBUI_ASC_ISSUER_ID').match?(/\A[0-9a-fA-F-]{36}\z/), 'Invalid ASC key/issuer ID')
    api = API.new(key, ENV.fetch('MBUI_ASC_KEY_ID'), ENV.fetch('MBUI_ASC_ISSUER_ID'))
    api.preflight(group)
    stage == 'prepare' ? prepare(api, private_dir, safe_dir) : upload(api, private_dir, safe_dir, key)
  end

  # A build number Apple already has is this commit's, uploaded by an earlier run: nothing to do (skip=true), so a
  # rerun or a second dispatch never uploads twice.
  def self.prepare(api, private_dir, safe_dir)
    n = build_number(command('git', 'rev-list', '--count', 'HEAD').strip.to_i)
    stamp = { 'sha' => ENV.fetch('GITHUB_SHA'), 'run' => ENV.fetch('GITHUB_RUN_ID'), 'build' => n, 'version' => "0.1.#{n}" }
    File.write(File.join(safe_dir, 'stamp.json'), JSON.pretty_generate(stamp))
    uploaded = api.builds(n).any?
    File.open(ENV.fetch('GITHUB_OUTPUT'), 'a') { |f| f.puts "skip=#{uploaded}"; f.puts "build=#{n}" }
    return puts("Build #{n} is already in App Store Connect; nothing to upload") if uploaded
    File.open(ENV.fetch('GITHUB_ENV'), 'a') { |f| f.puts "MBUI_IOS_BUILD=#{stamp.fetch('build')}" }
    # No credentials persist in source, Actions cache, or retained artifacts.
    File.write(File.join(private_dir, 'certificate.p12'), Base64.strict_decode64(ENV.fetch('MBUI_IOS_CERTIFICATE_P12_BASE64')), mode: 'wb', perm: 0600)
    p12 = OpenSSL::PKCS12.new(File.binread(File.join(private_dir, 'certificate.p12')), ENV.fetch('MBUI_IOS_CERTIFICATE_PASSWORD'))
    cert = validate_p12!(p12)
    profiles = {}
    %w[APP SHARE].zip(BUNDLES).each do |kind, bundle|
      path = File.join(private_dir, "#{kind}.mobileprovision")
      File.binwrite(path, Base64.strict_decode64(ENV.fetch("MBUI_IOS_#{kind}_PROFILE_BASE64")))
      xml = command('/usr/bin/security', 'cms', '-D', '-i', path)
      decoded = File.join(private_dir, "#{kind}.plist")
      File.write(decoded, xml)
      p = plist(decoded)
      profile_valid!(p, bundle)
      check(Array(p['DeveloperCertificates']).any? { |c| Base64.decode64(c) == cert.to_der }, 'Certificate not included in profile')
      profiles[bundle] = p.fetch('UUID')
      destination = File.expand_path("~/Library/MobileDevice/Provisioning Profiles/#{p.fetch('UUID')}.mobileprovision")
      check(!File.exist?(destination), 'Refusing to replace an existing profile')
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(path, destination)
      File.open(File.join(private_dir, 'installed-profiles'), 'a') { |f| f.puts destination }
    end
    File.write(File.join(private_dir, 'profiles.json'), JSON.generate(profiles))
    password = OpenSSL::Random.random_bytes(32).unpack1('H*')
    keychain = File.join(private_dir, 'release.keychain-db')
    command('/usr/bin/security', 'create-keychain', '-p', password, keychain)
    command('/usr/bin/security', 'set-keychain-settings', '-lut', '21600', keychain)
    command('/usr/bin/security', 'unlock-keychain', '-p', password, keychain)
    command('/usr/bin/security', 'import', File.join(private_dir, 'certificate.p12'), '-P', ENV.fetch('MBUI_IOS_CERTIFICATE_PASSWORD'), '-A', '-t', 'cert', '-f', 'pkcs12', '-k', keychain)
    command('/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain)
    original = command('/usr/bin/security', 'list-keychains', '-d', 'user').scan(/"([^"]+)"/).flatten
    File.write(File.join(private_dir, 'original-keychains.json'), JSON.generate(original))
    command('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', keychain, *original)
    identities = command('/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning', keychain)
    check(identities.include?(cert.serial.to_s) || identities.include?(OpenSSL::Digest::SHA1.hexdigest(cert.to_der).upcase), 'Imported distribution identity unavailable')
  end

  def self.verify_app(app, stamp)
    expected = {app => BUNDLES[0], File.join(app, 'PlugIns/Share.appex') => BUNDLES[1]}
    expected.each do |path, bundle|
      p = plist(File.join(path, 'Info.plist'))
      check(p['CFBundleIdentifier'] == bundle && p['CFBundleVersion'].to_s == stamp.fetch('build').to_s && p['CFBundleShortVersionString'] == stamp.fetch('version') && p['MinimumOSVersion'] == '17.0' && p['MBUIAppGroup'] == GROUP, 'Packaged app identity/version/minimum OS mismatch')
      xml = command('/usr/bin/codesign', '-d', '--entitlements', ':-', path)
      # codesign diagnostics share stderr: extract only the XML document.
      start = xml.index('<?xml')
      check(start, 'Signed entitlements missing')
      file = File.join(ENV.fetch('MBUI_RELEASE_PRIVATE'), 'entitlements.plist')
      File.write(file, xml[start..])
      e = plist(file)
      check(e['application-identifier'] == "#{TEAM}.#{bundle}" && e['com.apple.developer.team-identifier'] == TEAM && e['com.apple.security.application-groups'] == [GROUP] && e['get-task-allow'] != true, 'Signed entitlements mismatch')
      command('/usr/bin/codesign', '--verify', '--strict', path)
    end
    hermes = File.join(app, 'Frameworks/hermes.framework')
    command('/usr/bin/codesign', '--verify', '--strict', hermes)
    details = command('/usr/bin/codesign', '-dv', hermes)
    check(details.include?("TeamIdentifier=#{TEAM}"), 'Hermes signing team mismatch')
    check(File.size?(File.join(app, 'core.hbc')), 'Missing core bytecode')
    command('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
  end

  def self.package(private_dir, safe_dir)
    stamp = JSON.parse(File.read(File.join(safe_dir, 'stamp.json')))
    check(stamp.values_at('sha', 'run') == ENV.values_at('GITHUB_SHA', 'GITHUB_RUN_ID'), 'Package receipt identity mismatch')
    root = ENV.fetch('GITHUB_WORKSPACE')
    ENV['MBUI_IOS_CI_PROFILES'] = File.read(File.join(private_dir, 'profiles.json'))
    generator = File.join(root, 'apps/mbui/scripts/ios-package/generate.rb')
    generated = File.join(private_dir, 'packaging')
    command('/usr/bin/ruby', generator, File.join(root, 'apps/mbui/out/ios-device/MBUI.app'), generated, 'iphoneos')
    archive = File.join(private_dir, 'mbui.xcarchive')
    command('xcodebuild', 'archive', '-project', File.join(generated, 'MBUIPackaging.xcodeproj'), '-scheme', 'MBUI', '-configuration', 'Release', '-destination', 'generic/platform=iOS', '-archivePath', archive, "OTHER_CODE_SIGN_FLAGS=--keychain #{File.join(private_dir, 'release.keychain-db')}")
    verify_app(File.join(archive, 'Products/Applications/mbui.app'), stamp)
    export = { 'method' => 'app-store-connect', 'destination' => 'export', 'signingStyle' => 'manual', 'teamID' => TEAM, 'signingCertificate' => 'Apple Distribution', 'provisioningProfiles' => JSON.parse(ENV.fetch('MBUI_IOS_CI_PROFILES')), 'manageAppVersionAndBuildNumber' => false, 'uploadSymbols' => false }
    json = File.join(private_dir, 'ExportOptions.plist')
    File.write(json, JSON.generate(export))
    command('/usr/bin/plutil', '-convert', 'xml1', json)
    export_dir = File.join(private_dir, 'export')
    command('xcodebuild', '-exportArchive', '-archivePath', archive, '-exportPath', export_dir, '-exportOptionsPlist', json)
    ipas = Dir.glob(File.join(export_dir, '*.ipa'))
    check(ipas.size == 1, 'Expected exactly one exported IPA')
    unpacked = File.join(private_dir, 'export-check')
    command('/usr/bin/ditto', '-x', '-k', ipas.first, unpacked)
    apps = Dir.glob(File.join(unpacked, 'Payload/*.app'))
    check(apps.size == 1, 'Unexpected exported app payload')
    verify_app(apps.first, stamp)
    stamp['ipa_sha256'] = Digest::SHA256.file(ipas.first).hexdigest
    FileUtils.mv(ipas.first, File.join(safe_dir, 'mbui-testflight.ipa'))
    File.write(File.join(safe_dir, 'build-identity.json'), JSON.pretty_generate(stamp))
  end

  # Its own job: the IPA and its identity come from the build job's artifact; the group takes the build once Apple
  # has processed it (group_valid!).
  def self.upload(api, private_dir, safe_dir, key)
    identity = JSON.parse(File.read(File.join(safe_dir, 'build-identity.json')))
    check(identity.values_at('sha', 'run') == ENV.values_at('GITHUB_SHA', 'GITHUB_RUN_ID') && identity['ipa_sha256'].to_s.match?(/\A[0-9a-f]{64}\z/), 'IPA identity receipt mismatch')
    return puts("Build #{identity.fetch('build')} is already in App Store Connect") if api.builds(identity.fetch('build')).any?
    ipa = File.join(safe_dir, 'mbui-testflight.ipa')
    check(Digest::SHA256.file(ipa).hexdigest == identity.fetch('ipa_sha256'), 'Approved IPA hash mismatch')
    keys = File.join(private_dir, 'private_keys')
    FileUtils.mkdir_p(keys, mode: 0700)
    File.write(File.join(keys, "AuthKey_#{ENV.fetch('MBUI_ASC_KEY_ID')}.p8"), key.private_to_pem, mode: 'w', perm: 0600)
    ENV['API_PRIVATE_KEYS_DIR'] = keys
    command('xcrun', 'altool', '--upload-package', ipa, '--api-key', ENV.fetch('MBUI_ASC_KEY_ID'), '--api-issuer', ENV.fetch('MBUI_ASC_ISSUER_ID'))
    puts "Uploaded #{identity.fetch('version')} (#{identity.fetch('build')}); TestFlight's group gets it once Apple has processed it"
  end
end
if $PROGRAM_NAME == __FILE__
  begin
    TestFlight.main
  rescue StandardError => e
    warn "::error::#{e.is_a?(TestFlight::Failure) ? e.message : 'Release failed (diagnostics withheld to protect credentials)'}"
    exit 1
  end
end
