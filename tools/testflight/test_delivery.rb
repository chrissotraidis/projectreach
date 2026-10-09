require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require_relative 'deliver'

class DeliveryTest < Minitest::Test
  Group = Struct.new(:id, :name, :is_internal_group)
  App = Struct.new(:id, :bundle_id, :get_beta_groups)
  Release = Struct.new(:version, :platform)
  Build = Struct.new(:id, :app, :pre_release_version, :version, :expired, :processing_state) do
    def app_version = pre_release_version.version
  end
  class Recorder
    attr_reader :calls
    def initialize = @calls = []
    def upload(options) = @calls << [:upload, options]
    def distribute(options, build:) = @calls << [:distribute, options, build]
  end

  def setup
    @folder = Dir.mktmpdir('halopad-delivery-test-')
    @ipa = File.join(@folder, 'fixture.ipa')
    @key = File.join(@folder, 'fixture.p8')
    File.write(@ipa, 'verified fixture')
    File.write(@key, 'private fixture')
    @request = { 'ipa' => @ipa, 'sha256' => Digest::SHA256.file(@ipa).hexdigest, 'version' => '0.3.8',
                 'build' => '1020', 'engine' => { 'release' => 'build-155' }, 'channel' => 'external',
                 'groups' => ['Preview'], 'uses_non_exempt_encryption' => true, 'resume' => false }
    @env = { 'HALOPAD_API_KEY_ID' => 'ABCDE12345', 'HALOPAD_API_ISSUER' => '11111111-2222-3333-4444-555555555555',
             'HALOPAD_API_KEY_PATH' => @key }
    @group = Group.new('group-id', 'Preview', false)
    @app = App.new('app-id', HaloPadTestFlight::BUNDLE_ID, [@group])
    @build = Build.new('build-id', @app, Release.new('0.3.8', 'IOS'), '1020', false, 'VALID')
    @manager = Recorder.new
    @queries = []
  end

  def teardown = FileUtils.remove_entry(@folder)

  def run_delivery(builds: [], ready: @build)
    lookup = lambda do |**query|
      @queries << query
      builds
    end
    Spaceship::ConnectAPI::Token.stub(:create, :fixture) do
      Spaceship::ConnectAPI.stub(:token=, nil) do
        Spaceship::ConnectAPI::App.stub(:find, @app) do
          Spaceship::ConnectAPI::Build.stub(:all, lookup) do
            FastlaneCore::BuildWatcher.stub(:wait_for_build_processing_to_be_complete, ready) do
              HaloPadTestFlight.run(@request, @env, manager: @manager)
            end
          end
        end
      end
    end
  end

  def test_external_upload_uses_actual_fastlane_configuration_and_exact_identity
    run_delivery
    kind, options = @manager.calls.fetch(0)
    assert_equal :upload, kind
    assert_equal ['group-id'], options[:groups]
    assert_equal '0.3.8', options[:app_version]
    assert_equal '1020', options[:build_number]
    assert options[:distribute_external]
    assert options[:submit_beta_review]
    assert options[:uses_non_exempt_encryption]
    refute options[:skip_submission]
    refute options[:skip_waiting_for_build_processing]
    refute options[:expire_previous_builds]
    refute options[:reject_build_waiting_for_review]
    assert_equal({ app_id: 'app-id', version: '0.3.8', build_number: '1020', platform: 'IOS' }, @queries.fetch(0))
  end

  def test_internal_channel_cannot_request_external_distribution_or_review
    @request['channel'] = 'internal'
    @request['uses_non_exempt_encryption'] = false
    @group.is_internal_group = true
    run_delivery
    options = @manager.calls.fetch(0)[1]
    refute options[:distribute_external]
    refute options[:submit_beta_review]
    refute options[:notify_external_testers]
    refute options[:uses_non_exempt_encryption]
  end

  def test_missing_ambiguous_or_wrong_audience_groups_cannot_upload
    [[], [@group, @group], [Group.new('internal', 'Preview', true)]].each do |groups|
      @app.get_beta_groups = groups
      assert_raises(RuntimeError) { run_delivery }
      assert_empty @manager.calls
    end
  end

  def test_existing_build_requires_explicit_resume_and_does_not_reupload
    assert_raises(RuntimeError) { run_delivery(builds: [@build]) }
    assert_empty @manager.calls
    @request['resume'] = true
    run_delivery(builds: [@build])
    assert_equal :distribute, @manager.calls.fetch(0)[0]
    assert_same @build, @manager.calls.fetch(0)[2]
  end

  def test_resume_stops_for_missing_failed_expired_or_changed_build
    @request['resume'] = true
    assert_raises(RuntimeError) { run_delivery }
    @build.processing_state = 'INVALID'
    assert_raises(RuntimeError) { run_delivery(builds: [@build]) }
    @build.processing_state = 'VALID'; @build.expired = true
    assert_raises(RuntimeError) { run_delivery(builds: [@build]) }
    @build.expired = false
    different = @build.dup; different.id = 'wrong-id'
    assert_raises(RuntimeError) { run_delivery(builds: [@build], ready: different) }
    assert_empty @manager.calls
  end

  def test_corrupt_export_and_missing_declaration_stop_before_api
    File.write(@ipa, 'changed')
    assert_raises(RuntimeError) { HaloPadTestFlight.options(@request, @env) }
    @request['sha256'] = Digest::SHA256.file(@ipa).hexdigest
    @request['uses_non_exempt_encryption'] = nil
    assert_raises(RuntimeError) { HaloPadTestFlight.options(@request, @env) }
  end

  def test_wrong_apple_result_cannot_reach_distributor
    manager = HaloPadTestFlight::ExactBuildManager.new
    options = { app_version: '0.3.8', build_number: '1020' }
    @build.version = '9999'
    assert_raises(RuntimeError) { manager.distribute(options, build: @build) }
    @build.version = '1020'; @app.bundle_id = 'other.app'
    assert_raises(RuntimeError) { manager.distribute(options, build: @build) }
    @app.bundle_id = HaloPadTestFlight::BUNDLE_ID; @build.pre_release_version.platform = 'MAC_OS'
    assert_raises(RuntimeError) { manager.distribute(options, build: @build) }
    @build.pre_release_version.platform = 'IOS'; @build.pre_release_version.version = '0.3.9'
    assert_raises(RuntimeError) { manager.distribute(options, build: @build) }
  end
end
