# frozen_string_literal: true

# Точка входу.
#
#   ruby main.rb                              # основний процес за config/settings.yml
#   ruby main.rb --config other.yml --format csv
#   ruby main.rb --dsl dsl/books_pipeline.rb  # запуск конвеєрів, описаних у DSL
#   ruby main.rb --show 5                     # показати збережені записи

require "optparse"
require_relative "lib/web_data_collector"

module WebDataCollector
  class CLI
    def initialize(argv)
      @options = { config: File.join(ROOT, "config", "settings.yml") }
      parser.parse!(argv)
    rescue OptionParser::ParseError => e
      warn e.message
      warn parser
      exit 2
    end

    def run
      return run_dsl if @options[:dsl]
      return show if @options[:show]

      run_engine
    rescue ConfigurationError => e
      warn "Configuration error: #{e.message}"
      1
    rescue Error => e
      warn "Error: #{e.message}"
      1
    rescue Interrupt
      warn "Interrupted"
      130
    end

    private

    def parser
      @parser ||= OptionParser.new do |o|
        o.banner = "Usage: ruby main.rb [options]"
        o.on("-c", "--config PATH", "YAML configuration file") { |v| @options[:config] = v }
        o.on("-f", "--format FORMAT", "Export format: json, csv, yaml") { |v| @options[:format] = v }
        o.on("-p", "--pages N", Integer, "Max pages to crawl") { |v| @options[:pages] = v }
        o.on("-d", "--dsl FILE", "Run pipelines described in a DSL file") { |v| @options[:dsl] = v }
        o.on("-s", "--show [N]", Integer, "Print N items stored in the database") { |v| @options[:show] = v || 10 }
        o.on("-h", "--help", "Show this help") do
          puts o
          exit
        end
      end
    end

    def config
      data = YAML.safe_load_file(@options[:config])
      data["output"]["format"] = @options[:format] if @options[:format]
      data["source"]["max_pages"] = @options[:pages] if @options[:pages]
      Configurator.new(data, root: ROOT, env: ENV)
    rescue Errno::ENOENT
      raise ConfigurationError, "configuration file not found: #{@options[:config]}"
    rescue Psych::SyntaxError => e
      raise ConfigurationError, "invalid YAML: #{e.message}"
    end

    def run_engine
      result = Engine.new(config: config).run
      puts
      puts result.summary
      result.success? ? 0 : 1
    end

    def run_dsl
      cfg = config
      logger = AppLogger.build(level: cfg.log_level, file: cfg.log_file, progname: "dsl")
      pipelines = DSL::Loader.load_file(@options[:dsl], root: ROOT)
      logger.info("Loaded #{pipelines.size} pipeline(s) from #{@options[:dsl]}")
      results = pipelines.map { |p| DSL::PipelineRunner.new(p, logger: logger).run }
      puts
      results.each { |r| puts r.summary }
      results.all?(&:success?) ? 0 : 1
    end

    def show
      cfg = config
      db = DatabaseConnector.new(path: cfg.database_path, table: cfg.table, unique_key: cfg.unique_key)
      items = db.all(limit: @options[:show])
      puts "#{db.count} rows in #{cfg.table} (#{cfg.database_path}); showing #{items.size}:"
      items.each { |item| puts "  #{item}" }
      db.close
      0
    end
  end
end

exit(WebDataCollector::CLI.new(ARGV).run) if $PROGRAM_NAME == __FILE__
