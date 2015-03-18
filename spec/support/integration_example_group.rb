require 'yaml'
require 'yajl'
require 'bosh/dev/sandbox/main'

module IntegrationExampleGroup
  def logger
    @logger ||= Logger.new(STDOUT)
  end

  def director
    @director ||= Bosh::Spec::Director.new(
      bosh_runner,
      waiter,
      current_sandbox.agent_tmp_path,
      current_sandbox.nats_port,
      logger,
    )
  end

  def health_monitor
    @health_monitor ||= Bosh::Spec::HealthMonitor.new(
      current_sandbox.health_monitor_process,
      logger,
    )
  end

  def bosh_runner
    @bosh_runner ||= Bosh::Spec::BoshRunner.new(
      ClientSandbox.bosh_work_dir,
      ClientSandbox.bosh_config,
      current_sandbox.cpi.method(:agent_log_path),
      current_sandbox.nats_log_path,
      current_sandbox.saved_logs_path,
      logger
    )
  end

  def bosh_runner_in_work_dir(work_dir)
    Bosh::Spec::BoshRunner.new(
      work_dir,
      ClientSandbox.bosh_config,
      current_sandbox.cpi.method(:agent_log_path),
      current_sandbox.nats_log_path,
      current_sandbox.saved_logs_path,
      logger
    )
  end

  def waiter
    @waiter ||= Bosh::Spec::Waiter.new(logger)
  end

  def target_and_login
    bosh_runner.run("target #{current_sandbox.director_url}")
    bosh_runner.run('login admin admin')
  end

  def create_and_upload_test_release
    Dir.chdir(ClientSandbox.test_release_dir) do
      bosh_runner.run_in_current_dir('create release')
      bosh_runner.run_in_current_dir('upload release')
    end
  end

  def upload_stemcell
    bosh_runner.run("upload stemcell #{spec_asset('valid_stemcell.tgz')}")
  end

  def set_deployment(options)
    manifest_hash = options.fetch(:manifest_hash, Bosh::Spec::Deployments.simple_manifest)

    # Hold reference to the tempfile so that it stays around
    # until the end of tests or next deploy.
    @deployment_manifest = yaml_file('simple', manifest_hash)
    bosh_runner.run("deployment #{@deployment_manifest.path}")
  end

  def deploy(options)
    no_track = options.fetch(:no_track, false)
    redact_diff = options.fetch(:redact_diff, false)
    bosh_runner.run("#{no_track ? '--no-track ' : ''}deploy#{redact_diff ? ' --redact-diff' : ''}", options)
  end

  def deploy_simple(options={})
    target_and_login
    create_and_upload_test_release
    upload_stemcell
    deploy_simple_manifest(options)
  end

  def deploy_simple_manifest(options={})
    set_deployment(options)
    return_exit_code = options.fetch(:return_exit_code, false)

    output, exit_code = deploy(options.merge({return_exit_code: true}))

    expect($?.success?).to_not eq(options.fetch(:failure_expected, false))

    return_exit_code ? [output, exit_code] : output
  end

  def yaml_file(name, object)
    Tempfile.new(name).tap do |f|
      f.write(Psych.dump(object))
      f.close
    end
  end

  def spec_asset(name)
    File.expand_path("../../assets/#{name}", __FILE__)
  end

  def regexp(string)
    Regexp.compile(Regexp.escape(string))
  end

  def format_output(out)
    out.gsub(/^\s*/, '').gsub(/\s*$/, '')
  end

  # forcefully suppress raising on error...caller beware
  def expect_output(cmd, expected_output)
    expect(format_output(bosh_runner.run(cmd, :failure_expected => true))).
      to eq(format_output(expected_output))
  end

  def expect_running_vms(job_name_index_list)
    vms = director.vms
    expect(vms.map(&:job_name_index)).to match_array(job_name_index_list)
    expect(vms.map(&:last_known_state).uniq).to eq(['running'])
  end
end

module IntegrationSandboxHelpers
  def start_sandbox
    unless sandbox_started?
      at_exit do
        begin
          status = $! ? ($!.is_a?(::SystemExit) ? $!.status : 1) : 0
          logger.info("\n  Stopping sandboxed environment for BOSH tests...")
          current_sandbox.stop
          cleanup_sandbox_dir
        rescue => e
          logger.error "Failed to stop sandbox! #{e.message}\n#{e.backtrace.join("\n")}"
        ensure
          exit(status)
        end
      end
    end

    $sandbox_started = true

    logger.info('Starting sandboxed environment for BOSH tests...')
    current_sandbox.start
  end

  def sandbox_started?
    !!$sandbox_started
  end

  def current_sandbox
    sandbox = Thread.current[:sandbox]
    raise "call prepare_sandbox to set up this thread's sandbox" if sandbox.nil?
    sandbox
  end

  def prepare_sandbox
    cleanup_sandbox_dir
    setup_test_release_dir
    setup_bosh_work_dir
    setup_home_dir
    Thread.current[:sandbox] ||= Bosh::Dev::Sandbox::Main.from_env
  end

  def reconfigure_sandbox(options)
    current_sandbox.reconfigure(options)
  end

  def reset_sandbox
    current_sandbox.reset
    FileUtils.rm_rf(current_sandbox.cloud_storage_dir)
  end

  def setup_test_release_dir(destination_dir = ClientSandbox.test_release_dir)
    FileUtils.rm_rf(destination_dir)
    FileUtils.cp_r(TEST_RELEASE_TEMPLATE, destination_dir, :preserve => true)

    final_config_path = File.join(destination_dir, 'config', 'final.yml')
    final_config = YAML.load_file(final_config_path)
    final_config['blobstore']['options']['blobstore_path'] = ClientSandbox.blobstore_dir
    File.open(final_config_path, 'w') { |file| file.write(YAML.dump(final_config)) }

    Dir.chdir(destination_dir) do
      ignore = %w(
        blobs
        dev-releases
        config/dev.yml
        config/private.yml
        releases/*.tgz
        dev_releases
        .dev_builds
        .final_builds/jobs/**/*.tgz
        .final_builds/packages/**/*.tgz
        blobs
        .blobs
        .DS_Store
      )

      File.open('.gitignore', 'w+') do |f|
        f.write(ignore.join("\n") + "\n")
      end

      `git init;
       git config user.name "John Doe";
       git config user.email "john.doe@example.org";
       git add .;
       git commit -m "Initial Test Commit"`
    end
  end

  private

  def setup_bosh_work_dir
    FileUtils.cp_r(BOSH_WORK_TEMPLATE, ClientSandbox.bosh_work_dir, :preserve => true)
  end

  def setup_home_dir
    FileUtils.mkdir_p(ClientSandbox.home_dir)
    ENV['HOME'] = ClientSandbox.home_dir
  end

  def cleanup_sandbox_dir
    FileUtils.rm_rf(ClientSandbox.base_dir)
    FileUtils.mkdir_p(ClientSandbox.base_dir)
  end
end

module IntegrationSandboxBeforeHelpers
  def with_reset_sandbox_before_each(options={})
    before do |example|
      prepare_sandbox
      reconfigure_sandbox(options)
      if !sandbox_started?
        start_sandbox
      elsif !example.metadata[:no_reset]
        reset_sandbox
      end
    end
  end

  def with_reset_sandbox_before_all
    # `example` is not available in before(:all)
    before(:all) do
      prepare_sandbox
      if !sandbox_started?
        start_sandbox
      else
        reset_sandbox
      end
    end
  end
end

RSpec.configure do |config|
  config.include(IntegrationExampleGroup, type: :integration)
  config.include(IntegrationSandboxHelpers, type: :integration)
  config.extend(IntegrationSandboxBeforeHelpers, type: :integration)
end
