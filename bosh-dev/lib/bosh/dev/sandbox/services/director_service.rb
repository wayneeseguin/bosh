require 'bosh/dev/sandbox/database_migrator'

module Bosh::Dev::Sandbox
  class DirectorService

    REPO_ROOT = File.expand_path('../../../../../../', File.dirname(__FILE__))

    ASSETS_DIR = File.expand_path('bosh-dev/assets/sandbox', REPO_ROOT)
    DIRECTOR_UUID = 'deadbeef'

    DIRECTOR_CONFIG = 'director_test.yml'
    DIRECTOR_CONF_TEMPLATE = File.join(ASSETS_DIR, 'director_test.yml.erb')

    DIRECTOR_PATH = File.expand_path('bosh-director', REPO_ROOT)

    def initialize(port_provider, base_log_path, director_tmp_path, director_config, logger)
      @port_provider = port_provider
      @logger = logger
      @director_tmp_path = director_tmp_path
      @director_config = director_config

      @process = Service.new(
        %W[bosh-director -c #{@director_config}],
        {output: "#{base_log_path}.director.out"},
        @logger,
      )

      @socket_connector = SocketConnector.new('director', 'localhost', @port_provider.get_port(:director_ruby), @logger)

      @worker_processes = 3.times.map do |index|
        Service.new(
          %W[bosh-director-worker -c #{@director_config}],
          {output: "#{base_log_path}.worker_#{index}.out", env: {'QUEUE' => '*'}},
          @logger,
        )
      end

      @database_migrator = DatabaseMigrator.new(DIRECTOR_PATH, @director_config, @logger)
    end

    def start(config)
      write_config(config)

      migrate_database

      reset

      @process.start

      start_workers

      begin
        # CI does not have enough time to start bosh-director
        # for some parallel tests; increasing to 60 secs (= 300 tries).
        @socket_connector.try_to_connect(300)
      rescue
        output_service_log(@process)
        raise
      end
    end

    def stop
      stop_workers
      @process.stop
    end

    private

    def migrate_database
      unless @database_migrated
        @database_migrator.migrate
      end

      @database_migrated = true
    end

    def start_workers
      @worker_processes.each(&:start)
      until resque_is_ready?
        @logger.debug('Waiting for Resque workers to start')
        sleep 0.5
      end
    end

    def stop_workers
      @logger.debug('Waiting for Resque queue to drain...')
      sleep 0.1 until resque_is_done?
      @logger.debug('Resque queue drained')

      Redis.new(host: 'localhost', port: @port_provider.get_port(:redis)).flushdb

      # wait for resque workers in parallel for fastness
      @worker_processes.map { |worker_process| Thread.new { worker_process.stop } }.each(&:join)
    end

    def reset
      FileUtils.rm_rf(@director_tmp_path)
      FileUtils.mkdir_p(@director_tmp_path)
      File.open(File.join(@director_tmp_path, 'state.json'), 'w') do |f|
        f.write(Yajl::Encoder.encode('uuid' => DIRECTOR_UUID))
      end
    end

    def write_config(config)
      contents = config.render(DIRECTOR_CONF_TEMPLATE)
      File.open(@director_config, 'w+') do |f|
        f.write(contents)
      end
    end

    def resque_is_ready?
      info = Resque.info
      info[:workers] == @worker_processes.size
    end

    def resque_is_done?
      info = Resque.info
      info[:pending] == 0 && info[:working] == 0
    end

    DEBUG_HEADER = '*' * 20

    def output_service_log(service)
      @logger.error("#{DEBUG_HEADER} start #{service.description} stdout #{DEBUG_HEADER}")
      @logger.error(service.stdout_contents)
      @logger.error("#{DEBUG_HEADER} end #{service.description} stdout #{DEBUG_HEADER}")

      @logger.error("#{DEBUG_HEADER} start #{service.description} stderr #{DEBUG_HEADER}")
      @logger.error(service.stderr_contents)
      @logger.error("#{DEBUG_HEADER} end #{service.description} stderr #{DEBUG_HEADER}")
    end
  end
end
