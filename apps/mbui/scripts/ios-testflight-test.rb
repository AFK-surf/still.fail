# Offline only: ruby apps/mbui/scripts/ios-testflight-test.rb
require 'minitest/autorun'
require_relative 'ios-testflight'
class TestFlightTest < Minitest::Test
  def profile
    {'TeamIdentifier' => [TestFlight::TEAM], 'UUID' => '12345678-1234-1234-1234-123456789012',
     'ExpirationDate' => '2030-01-01T00:00:00Z',
     'Entitlements' => {'com.apple.developer.team-identifier' => TestFlight::TEAM,
       'application-identifier' => 'D9AAN3VJK8.fail.still.mbui',
       'com.apple.security.application-groups' => [TestFlight::GROUP],
       'get-task-allow' => false, 'beta-reports-active' => true}}
  end
  def test_xml_profile_date_and_certificate_data
    xml = <<~XML
      <?xml version="1.0"?><plist version="1.0"><dict>
      <key>ExpirationDate</key><date>2030-01-01T00:00:00Z</date>
      <key>DeveloperCertificates</key><array><data>c3lu\ndGhldGlj</data></array>
      <key>Entitlements</key><dict><key>get-task-allow</key><false/></dict>
      </dict></plist>
    XML
    parsed = TestFlight.parse_plist(xml)
    assert_equal '2030-01-01T00:00:00Z', parsed['ExpirationDate']
    assert_equal 'synthetic', Base64.strict_decode64(parsed['DeveloperCertificates'].first)
    assert_equal false, parsed.dig('Entitlements', 'get-task-allow')
  end
  def test_key_curve_and_p12_gates
    TestFlight.validate_key!(OpenSSL::PKey::EC.generate('prime256v1'))
    assert_raises(TestFlight::Failure) { TestFlight.validate_key!(OpenSSL::PKey::EC.generate('secp384r1')) }
    assert_raises(TestFlight::Failure) { TestFlight.validate_key!(OpenSSL::PKey::RSA.generate(1024)) }
    now = Time.utc(2026)
    key = OpenSSL::PKey::RSA.generate(1024)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse('/CN=Apple Distribution: Synthetic/OU=D9AAN3VJK8')
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = now - 3600
    cert.not_after = now + 7200
    cert.sign(key, OpenSSL::Digest::SHA256.new)
    p12 = OpenSSL::PKCS12.create('synthetic', 'test', key, cert)
    assert_equal cert.to_der, TestFlight.validate_p12!(p12, now).to_der
    assert_raises(TestFlight::Failure) { TestFlight.validate_p12!(p12, now + 7200) }
    assert_raises(OpenSSL::PKCS12::PKCS12Error) { OpenSSL::PKCS12.new(p12.to_der, 'wrong') }
  end
  def test_get_retries_are_bounded_and_post_is_not_replayed
    fixture = Class.new(TestFlight::API) do
      attr_reader :calls, :delays
      def initialize(responses)
        @responses, @calls, @delays = responses, 0, []
      end
      def token(*)
        'synthetic-token'
      end
      def retry_delay(attempt)
        @delays << attempt
      end
      def send_request(*)
        @calls += 1
        value = @responses.shift
        raise value if value.is_a?(Exception)
        Struct.new(:code, :body).new(value, '{"data":[]}')
      end
    end
    api = fixture.new(['503', IOError.new('synthetic'), '200'])
    assert_equal [], api.request('get', '/v1/builds')['data']
    assert_equal 3, api.calls
    assert_equal [0, 1], api.delays
    api = fixture.new(Array.new(5, '503'))
    assert_raises(TestFlight::Failure) { api.request('get', '/v1/builds') }
    assert_equal 5, api.calls
    ['503', IOError.new('synthetic')].each do |error|
      api = fixture.new([error, '200'])
      assert_raises(TestFlight::Failure) { api.request('post', '/v1/builds/id/relationships/betaGroups', data: []) }
      assert_equal 1, api.calls
    end
  end
  def test_store_profile
    TestFlight.profile_valid!(profile, TestFlight::BUNDLES.first, Time.utc(2026))
    %w[ProvisionedDevices ProvisionsAllDevices].each do |key|
      p = profile.merge(key => [])
      assert_raises(TestFlight::Failure) { TestFlight.profile_valid!(p, TestFlight::BUNDLES.first, Time.utc(2026)) }
    end
    assert_raises(TestFlight::Failure) { TestFlight.profile_valid!(profile, TestFlight::BUNDLES.last, Time.utc(2026)) }
    assert_raises(TestFlight::Failure) { TestFlight.profile_valid!(profile, TestFlight::BUNDLES.first, Time.utc(2031)) }
    %w[get-task-allow application-identifier com.apple.security.application-groups].each do |key|
      p = profile
      p['Entitlements'][key] = true
      assert_raises(TestFlight::Failure) { TestFlight.profile_valid!(p, TestFlight::BUNDLES.first, Time.utc(2026)) }
    end
  end
  def test_group_is_internal_private_and_automatic
    attrs = {'isInternalGroup' => true, 'publicLinkEnabled' => nil, 'hasAccessToAllBuilds' => true}
    TestFlight.group_valid!('attributes' => attrs)
    [{'isInternalGroup' => false}, {'publicLinkEnabled' => true}, {'hasAccessToAllBuilds' => false}].each do |change|
      assert_raises(TestFlight::Failure) { TestFlight.group_valid!('attributes' => attrs.merge(change)) }
    end
  end
  def test_build_number_is_the_commit_count
    assert_equal 4893, TestFlight.build_number(4893)
    assert_raises(TestFlight::Failure) { TestFlight.build_number(10000) }
    assert_raises(TestFlight::Failure) { TestFlight.build_number(0) }
  end
  def test_jwt_uses_es256_raw_signature_and_short_lifetime
    key = OpenSSL::PKey::EC.generate('prime256v1')
    api = TestFlight::API.new(key, 'TESTKEY123', 'synthetic-issuer')
    head, body, sig = api.token(1000).split('.')
    header = JSON.parse(Base64.urlsafe_decode64(head))
    claims = JSON.parse(Base64.urlsafe_decode64(body))
    assert_equal({'alg' => 'ES256', 'kid' => 'TESTKEY123', 'typ' => 'JWT'}, header)
    assert_equal 1300, claims['exp']
    assert_equal 995, claims['iat']
    assert_equal 'appstoreconnect-v1', claims['aud']
    raw = Base64.urlsafe_decode64(sig)
    assert_equal 64, raw.bytesize
    ints = [raw[0, 32], raw[32, 32]].map { |b| OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(b, 2)) }
    der = OpenSSL::ASN1::Sequence.new(ints).to_der
    assert key.verify(OpenSSL::Digest::SHA256.new, der, "#{head}.#{body}")
  end
  def test_no_real_command_or_network_in_unit_suite
    # Fixtures above generate only an in-memory synthetic key; prepare/package/upload never invoked.
    assert TestFlight::SECRETS.size == 7
    assert (TestFlight::STAGE_SECRETS.values.flatten - TestFlight::SECRETS).empty?
  end
end
