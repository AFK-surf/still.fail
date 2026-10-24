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
  IDENTITY_STEP = 'Retain immutable IPA identity for safe upload/group resume'
  UPLOAD_STEP = 'Upload once, verify Apple processing and explicit group assignment'
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
  def self.group_valid!(g)
    a = g.fetch('attributes')
    check(a['isInternalGroup'] == true && a['publicLinkEnabled'] != true && a['hasAccessToAllBuilds'] == false, 'Group must be internal, private, and explicitly assigned only')
  end
  def self.next_number(builds, count, run_number = 1)
    numbers = builds.map do |b|
      v = b.fetch('attributes').fetch('version')
      check(v.match?(/\A[1-9][0-9]*\z/), 'Non-integer existing build number; owner reconciliation required')
      v.to_i
    end
    check(run_number.is_a?(Integer) && run_number.positive?, 'Invalid workflow run number')
    n = ([count] + numbers).max + run_number
    check(n <= 9999, 'Marketing version component exhausted; owner version migration required')
    n
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
      # Refuse pre-existing broad automatic distribution, rather than silently notifying it.
      TestFlight.check(groups.all? { |g| g.dig('attributes', 'hasAccessToAllBuilds') == false && g.dig('attributes', 'publicLinkEnabled') != true }, 'App has broad/automatic beta distribution; owner must disable it')
    end
    def builds(number = nil)
      params = { 'filter[app]' => APP, 'limit' => '200' }
      params['filter[version]'] = number.to_s if number
      all(query('/v1/builds', params))
    end
    def distribute(stamp, group)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1800
      loop do
        matches = builds(stamp.fetch('build'))
        TestFlight.check(matches.size <= 1, 'Ambiguous Apple build lookup')
        if (build = matches.first)
          version = request('get', "/v1/builds/#{build.fetch('id')}/preReleaseVersion").dig('data', 'attributes', 'version')
          TestFlight.check(version == stamp.fetch('version'), 'Apple marketing version mismatch')
          state = build.dig('attributes', 'processingState')
          TestFlight.check(%w[PROCESSING VALID].include?(state), 'Apple build processing failed or unknown state')
          if state == 'VALID'
            preflight(group)
            id = build.fetch('id')
            existing = all("/v1/builds/#{id}/betaGroups?limit=200")
            TestFlight.check(existing.all? { |g| g['id'] == group }, 'Build already assigned to unauthorized groups')
            request('post', "/v1/builds/#{id}/relationships/betaGroups", data: [{type: 'betaGroups', id: group}]) unless existing.any?
            assigned = all("/v1/builds/#{id}/betaGroups?limit=200")
            TestFlight.check(assigned.map { |g| g['id'] } == [group], 'Group assignment verification failed')
            return id
          end
        end
        TestFlight.check(Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline, 'Apple processing deadline exceeded; rerun this run to resume')
        sleep 20 # wait for the external Apple build-processing state; bounded above
      end
    end
  end

  def self.main
    check(ENV['GITHUB_ACTIONS'] == 'true' && ENV['GITHUB_REF'] == 'refs/heads/main' && ENV['GITHUB_REPOSITORY'] == 'AFK-surf/still.fail', 'Release is restricted to upstream main on GitHub Actions')
    check(%w[push workflow_dispatch].include?(ENV['GITHUB_EVENT_NAME']), 'Unsupported release event')
    SECRETS.each { |name| check(!ENV[name].to_s.empty?, "Missing dedicated secret: #{name}") }
    group = ENV.fetch('MBUI_TESTFLIGHT_GROUP_ID', '')
    check(group.match?(/\A[0-9a-fA-F-]{36}\z/), 'Set an explicit owner-authorized non-France internal group ID')
    private_dir = ENV.fetch('MBUI_RELEASE_PRIVATE')
    safe_dir = ENV.fetch('MBUI_RELEASE_SAFE')
    check(private_dir == File.join(ENV.fetch('RUNNER_TEMP'), 'mbui-testflight-private') && safe_dir == File.join(ENV.fetch('RUNNER_TEMP'), 'mbui-testflight-artifacts'), 'Release paths must stay in the ephemeral runner directory')
    FileUtils.mkdir_p([private_dir, safe_dir], mode: 0700)
    key = OpenSSL::PKey.read(Base64.strict_decode64(ENV.fetch('MBUI_ASC_PRIVATE_KEY_BASE64')))
    validate_key!(key)
    check(ENV.fetch('MBUI_ASC_KEY_ID').match?(/\A[A-Z0-9]{10}\z/) && ENV.fetch('MBUI_ASC_ISSUER_ID').match?(/\A[0-9a-fA-F-]{36}\z/), 'Invalid ASC key/issuer ID')
    api = API.new(key, ENV.fetch('MBUI_ASC_KEY_ID'), ENV.fetch('MBUI_ASC_ISSUER_ID'))
    api.preflight(group)
    case ARGV.fetch(0)
    when 'prepare'
      prepare(api, private_dir, safe_dir)
    when 'package'
      package(private_dir, safe_dir)
    when 'release'
      release(api, private_dir, safe_dir, group)
    else
      raise Failure, 'Expected prepare or release'
    end
  end

  def self.history_complete?(runs, earlier)
    runs.length < 100 || earlier.any? { |r| r['status'] == 'completed' && r['conclusion'] == 'success' }
  end
  def self.jobs_prove_preupload?(payload)
    jobs = payload['jobs']
    total = payload['total_count']
    return false unless jobs.is_a?(Array) && total.is_a?(Integer) && total == jobs.length && jobs.length <= 100
    # GitHub concurrency can cancel a queued run before any job executes.
    # A complete all-attempt zero-job response positively proves no execution.
    return true if jobs.empty?
    jobs.all? do |job|
      steps = Array(job['steps'])
      boundary = steps.select { |s| [IDENTITY_STEP, UPLOAD_STEP].include?(s['name']) }
      boundary.map { |s| s['name'] }.sort == [IDENTITY_STEP, UPLOAD_STEP].sort &&
        boundary.all? { |s| s['status'] == 'completed' && s['conclusion'] == 'skipped' }
    end
  end
  def self.prior_safe_to_supersede?(prior, artifacts)
    return true if prior.nil? || (prior['status'] == 'completed' && prior['conclusion'] == 'success')
    prior['status'] == 'completed' && artifacts.none? { |a| a['name'] == "mbui-testflight-identity-#{prior.fetch('id')}" }
  end

  def self.prepare(api, private_dir, safe_dir)
    stamp_path = File.join(safe_dir, 'stamp.json')
    if ENV.fetch('GITHUB_RUN_ATTEMPT') != '1'
      check(File.file?(stamp_path), 'Rerun receipt missing: fail closed; never allocate another build on rerun')
      stamp = JSON.parse(File.read(stamp_path))
      check(stamp.values_at('sha', 'run') == ENV.values_at('GITHUB_SHA', 'GITHUB_RUN_ID'), 'Rerun receipt identity mismatch')
      check(stamp['build'].is_a?(Integer) && stamp['build'].between?(1, 9999) && stamp['version'] == "0.1.#{stamp['build']}", 'Invalid rerun receipt')
    else
      check(!File.exist?(stamp_path), 'Unexpected preexisting release receipt')
      # A failed earlier reservation must be reconciled in that run, not silently
      # replaced by a new run/number. Serialization alone cannot enforce this.
      uri = URI('https://api.github.com/repos/AFK-surf/still.fail/actions/workflows/mbui-testflight.yml/runs?branch=main&per_page=100')
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{ENV.fetch('GH_RELEASE_TOKEN')}"
      req['Accept'] = 'application/vnd.github+json'
      req['X-GitHub-Api-Version'] = '2022-11-28'
      http = Net::HTTP.new(uri.host, 443)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 30
      response = http.request(req)
      check(response.code == '200', 'Cannot verify prior release reservation history')
      history = JSON.parse(response.body)
      runs = history.fetch('workflow_runs')
      earlier = runs.select { |r| r.fetch('id').to_i < ENV.fetch('GITHUB_RUN_ID').to_i }.sort_by { |r| -r.fetch('id').to_i }
      pending = earlier.take_while { |r| !(r['status'] == 'completed' && r['conclusion'] == 'success') }
      check(history_complete?(runs, earlier), 'Release history exceeds bounded reconciliation window')
      pending.each do |prior|
        artifacts_uri = URI("https://api.github.com/repos/AFK-surf/still.fail/actions/runs/#{prior.fetch('id')}/artifacts?per_page=100")
        artifacts_req = Net::HTTP::Get.new(artifacts_uri)
        artifacts_req['Authorization'] = req['Authorization']
        artifacts_req['Accept'] = req['Accept']
        artifacts_response = http.request(artifacts_req)
        check(artifacts_response.code == '200', 'Cannot verify prior upload boundary')
        artifacts = JSON.parse(artifacts_response.body)
        check(artifacts.fetch('total_count') <= 100, 'Ambiguous prior artifact history')
        check(Time.parse(prior.fetch('created_at')) > Time.now - 90 * 86400, 'Old unresolved release needs owner reconciliation')
        check(prior_safe_to_supersede?(prior, artifacts.fetch('artifacts')), 'Prior release crossed upload boundary: reconcile/rerun that reservation before a new release')
        # Artifact deletion/expiry is not evidence that upload never happened.
        # Inspect every attempt; require both boundary steps explicitly skipped.
        jobs_uri = URI("https://api.github.com/repos/AFK-surf/still.fail/actions/runs/#{prior.fetch('id')}/jobs?filter=all&per_page=100")
        jobs_req = Net::HTTP::Get.new(jobs_uri)
        jobs_req['Authorization'] = req['Authorization']
        jobs_req['Accept'] = req['Accept']
        jobs_response = http.request(jobs_req)
        check(jobs_response.code == '200' && jobs_prove_preupload?(JSON.parse(jobs_response.body)), 'Prior attempts do not prove preupload failure; owner reconciliation required')
      end
      count = command('git', 'rev-list', '--count', 'HEAD').strip.to_i
      n = next_number(api.builds, count, Integer(ENV.fetch('GITHUB_RUN_NUMBER')))
      stamp = { 'sha' => ENV.fetch('GITHUB_SHA'), 'run' => ENV.fetch('GITHUB_RUN_ID'), 'build' => n, 'version' => "0.1.#{n}" }
      File.write(stamp_path, JSON.pretty_generate(stamp))
    end
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
    keys = File.join(private_dir, 'private_keys')
    FileUtils.mkdir_p(keys, mode: 0700)
    key = OpenSSL::PKey.read(Base64.strict_decode64(ENV.fetch('MBUI_ASC_PRIVATE_KEY_BASE64')))
    File.write(File.join(keys, "AuthKey_#{ENV.fetch('MBUI_ASC_KEY_ID')}.p8"), key.private_to_pem, mode: 'w', perm: 0600)
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
    check(ENV.fetch('GITHUB_RUN_ATTEMPT') == '1', 'Packaging is first-attempt only')
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

  def self.release(api, private_dir, safe_dir, group)
    stamp = JSON.parse(File.read(File.join(safe_dir, 'stamp.json')))
    check(stamp.values_at('sha', 'run') == ENV.values_at('GITHUB_SHA', 'GITHUB_RUN_ID'), 'Release receipt identity mismatch')
    identity_path = File.join(safe_dir, 'build-identity.json')
    check(File.file?(identity_path), 'Missing durable IPA identity receipt')
    identity = JSON.parse(File.read(identity_path))
    check(identity.values_at('sha', 'run', 'build', 'version') == stamp.values_at('sha', 'run', 'build', 'version') && identity['ipa_sha256'].to_s.match?(/\A[0-9a-f]{64}\z/), 'IPA identity receipt mismatch')
    stamp['ipa_sha256'] = identity.fetch('ipa_sha256')
    existing = api.builds(stamp.fetch('build'))
    check(existing.size <= 1, 'Ambiguous existing build')
    unless existing.any?
      check(ENV.fetch('GITHUB_RUN_ATTEMPT') == '1', 'No Apple build visible on rerun; upload status ambiguous. Owner reconciliation required; no duplicate upload attempted')
      ipa = File.join(safe_dir, 'mbui-testflight.ipa')
      check(Digest::SHA256.file(ipa).hexdigest == stamp.fetch('ipa_sha256'), 'Approved IPA hash mismatch')
      ENV['API_PRIVATE_KEYS_DIR'] = File.join(private_dir, 'private_keys')
      command('xcrun', 'altool', '--upload-package', ipa, '--api-key', ENV.fetch('MBUI_ASC_KEY_ID'), '--api-issuer', ENV.fetch('MBUI_ASC_ISSUER_ID'))
    end
    id = api.distribute(stamp, group)
    manifest = stamp.merge('app' => APP, 'bundle' => BUNDLES.first, 'team' => TEAM, 'apple_build' => id, 'group' => group, 'result' => 'VALID and assigned only to authorized internal group', 'workflow' => ENV.fetch('GITHUB_WORKFLOW_REF'), 'workflow_sha' => ENV.fetch('GITHUB_WORKFLOW_SHA'))
    File.write(File.join(safe_dir, 'release.json'), JSON.pretty_generate(manifest))
    # Xcode's distribution logs are never an artifact.
    Dir.children(safe_dir).each { |f| FileUtils.rm_rf(File.join(safe_dir, f)) unless f.end_with?('.ipa') || %w[stamp.json build-identity.json release.json].include?(f) }
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
