# Submit the exact audited IPA; use Fastlane for Apple's upload/review APIs.
require 'json'
require 'digest'
require 'fastlane'
require 'pilot'

module HaloPadTestFlight
  BUNDLE_ID = 'dev.halopad.HaloPad'

  class ExactBuildManager < Pilot::BuildManager
    def distribute(options, build: nil)
      unless build && build.app.bundle_id == BUNDLE_ID && build.pre_release_version.platform == 'IOS' &&
             build.app_version == options[:app_version] && build.version == options[:build_number]
        raise 'Apple returned a different app/version/build; distribution stopped'
      end
      super
    end
  end

  def self.options(request, env)
    raise 'Invalid delivery channel' unless %w[internal external].include?(request.fetch('channel'))
    raise 'Exported IPA changed after audit' unless Digest::SHA256.file(request.fetch('ipa')).hexdigest == request.fetch('sha256')
    raise 'Missing exact version/build' unless request.fetch('version').match?(/\A\d+\.\d+\.\d+\z/) && request.fetch('build').match?(/\A[1-9]\d*\z/)
    raise 'Missing encryption declaration' unless [true, false].include?(request.fetch('uses_non_exempt_encryption'))
    groups = request.fetch('groups')
    raise 'Missing TestFlight groups' unless groups.is_a?(Array) && !groups.empty? && groups.all? { |g| g.is_a?(String) && !g.strip.empty? }
    {
      api_key: { key_id: env.fetch('HALOPAD_API_KEY_ID'), issuer_id: env.fetch('HALOPAD_API_ISSUER'),
                 key: File.read(env.fetch('HALOPAD_API_KEY_PATH')), in_house: false },
      app_identifier: BUNDLE_ID, app_platform: 'ios', ipa: request.fetch('ipa'),
      app_version: request.fetch('version'), build_number: request.fetch('build'),
      groups: groups, distribute_external: request.fetch('channel') == 'external',
      uses_non_exempt_encryption: request.fetch('uses_non_exempt_encryption'),
      changelog: "HaloPad #{request.fetch('version')} (#{request.fetch('build')}), OpenCE #{request.fetch('engine').fetch('release')}. Test disc import, campaign/save/resume and multiplayer.",
      skip_submission: false, skip_waiting_for_build_processing: false,
      expire_previous_builds: false, reject_build_waiting_for_review: false,
      submit_beta_review: request.fetch('channel') == 'external', notify_external_testers: request.fetch('channel') == 'external',
      wait_processing_interval: 30, wait_processing_timeout_duration: 1800
    }
  end

  def self.run(request, env, manager: ExactBuildManager.new)
    config = options(request, env)
    Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(**config.fetch(:api_key))
    app = Spaceship::ConnectAPI::App.find(BUNDLE_ID)
    raise 'Create the HaloPad App Store Connect app record first' unless app
    available = app.get_beta_groups
    config[:groups] = config.fetch(:groups).map do |name|
      matches = available.select { |group| group.id == name || group.name == name }
      raise "TestFlight group is missing or ambiguous: #{name}" unless matches.length == 1
      group = matches.first
      raise "TestFlight group has the wrong audience: #{name}" unless group.is_internal_group == (request.fetch('channel') == 'internal')
      group.id
    end
    builds = Spaceship::ConnectAPI::Build.all(app_id: app.id, version: request.fetch('version'),
                                             build_number: request.fetch('build'), platform: 'IOS')
    if request.fetch('resume')
      raise 'Resume requires exactly one existing matching build' unless builds.length == 1
      raise 'Existing build is expired or failed processing' if builds.first.expired || %w[FAILED INVALID].include?(builds.first.processing_state)
    elsif !builds.empty?
      raise 'This version/build already exists. Inspect it, then explicitly resume distribution; nothing uploaded.'
    end
    options = FastlaneCore::Configuration.create(Pilot::Options.available_options, config)
    if request.fetch('resume')
      ready = FastlaneCore::BuildWatcher.wait_for_build_processing_to_be_complete(
        app_id: app.id, platform: 'ios', app_version: request.fetch('version'), build_version: request.fetch('build'),
        poll_interval: 30, timeout_duration: 1800, select_latest: false, wait_for_build_beta_detail_processing: true
      )
      raise 'Apple returned a different build while resuming' unless ready.id == builds.first.id
      manager.distribute(options, build: ready)
    else
      raise 'Exported IPA changed before upload' unless Digest::SHA256.file(request.fetch('ipa')).hexdigest == request.fetch('sha256')
      manager.upload(options)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  HaloPadTestFlight.run(JSON.parse(File.read(ENV.fetch('HALOPAD_TESTFLIGHT_REQUEST'))), ENV)
end
