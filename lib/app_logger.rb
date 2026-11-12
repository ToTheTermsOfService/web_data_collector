# frozen_string_literal: true

require "logger"
require "fileutils"

module WebDataCollector
  module AppLogger
    LEVELS = %w[debug info warn error fatal].freeze

    class MultiIO
      def initialize(*targets)
        @targets = targets
      end

      def write(*args)
        @targets.each { |t| t.write(*args) }
      end

      def close
        @targets.each { |t| t.close unless [$stdout, $stderr].include?(t) }
      end
    end

    def self.build(level: "info", file: nil, stdout: true, progname: "web_data_collector")
      level = level.to_s.downcase
      raise ConfigurationError, "unknown log level '#{level}'" unless LEVELS.include?(level)

      targets = []
      targets << $stdout if stdout
      if file
        FileUtils.mkdir_p(File.dirname(file))
        log_file = File.open(file, "a")
        log_file.sync = true
        targets << log_file
      end
      device = targets.empty? ? File::NULL : MultiIO.new(*targets)

      logger = Logger.new(device, progname: progname)
      logger.level = Logger.const_get(level.upcase)
      logger.formatter = proc do |severity, time, prog, msg|
        "[#{time.strftime('%Y-%m-%d %H:%M:%S')}] #{severity.ljust(5)} #{prog}: #{msg}\n"
      end
      logger
    end

    def self.null
      Logger.new(File::NULL)
    end
  end
end
