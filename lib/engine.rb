# frozen_string_literal: true

require_relative "errors"
require_relative "configurator"
require_relative "app_logger"
require_relative "simple_website_parser"
require_relative "database_connector"
require_relative "exporters"

module WebDataCollector
  # Координує основний процес:
  #   1. завантаження конфігурації;
  #   2. запуск парсера;
  #   3. отримання колекції;
  #   4. перевірка та обробка (дедуплікація, сортування);
  #   5. збереження в SQLite;
  #   6. експорт і підсумкова інформація.
  # Сам Engine не парсить і не пише в базу - він лише викликає окремі
  # компоненти, які можна підмінити (наприклад, у тестах).
  class Engine
    Result = Struct.new(:status, :source, :pages, :collected, :skipped, :processed,
                        :db_stats, :export_path, :duration, :error, keyword_init: true) do
      def success? = status == :success

      def summary
        return "FAILED: #{error}" unless success?

        "Collected #{collected} items from #{pages} page(s) (#{skipped} skipped), " \
          "#{processed} after processing; DB: #{db_stats[:inserted]} new, #{db_stats[:updated]} updated; " \
          "exported to #{export_path || '-'} in #{format('%.2f', duration)}s"
      end
    end

    attr_reader :config, :logger, :collection

    def initialize(config: nil, config_path: nil, logger: nil, parser: nil, database: nil)
      @config = config || Configurator.load(config_path || default_config_path)
      @logger = logger || AppLogger.build(level: @config.log_level, file: @config.log_file, progname: @config.app_name)
      @parser = parser
      @database = database
    end

    def run(export: true)
      started = Time.now
      logger.info("=== #{config.app_name}: run started ===")
      logger.info("Source: #{config.source_url} (max pages: #{config.max_pages})")

      @collection = parser.parse(config.source_url)
      stats = parser.stats
      logger.info("Collected #{@collection.size} items (#{stats[:skipped]} skipped as invalid)")

      processed = process(@collection)
      logger.info("#{processed.size} items after processing")

      db_stats = database.save(processed)
      logger.info("Saved to SQLite: #{db_stats[:inserted]} inserted, #{db_stats[:updated]} updated " \
                  "(total rows in '#{config.table}': #{database.count})")

      export_path = export ? export_items(processed) : nil

      result = Result.new(status: :success, source: config.source_url, pages: stats[:pages],
                          collected: @collection.size, skipped: stats[:skipped], processed: processed.size,
                          db_stats: db_stats, export_path: export_path, duration: Time.now - started)
      logger.info(result.summary)
      result
    rescue Error => e
      logger.error("#{e.class.name.split('::').last}: #{e.message}")
      logger.debug(e.backtrace&.first(5)&.join("\n"))
      Result.new(status: :failed, source: config.source_url, error: e.message, duration: Time.now - started)
    ensure
      @database&.close
      logger.info("=== run finished ===")
    end

    # Перевірка та обробка результатів: прибрати повтори за унікальним
    # ключем і впорядкувати записи.
    def process(collection)
      unique = collection.uniq_by(config.unique_key)
      dropped = collection.size - unique.size
      logger.info("Removed #{dropped} duplicate(s) by '#{config.unique_key}'") if dropped.positive?
      unique.sort_by_field(config.fields.first.name)
    end

    def parser
      @parser ||= SimpleWebsiteParser.from_config(config, logger: logger)
    end

    def database
      @database ||= DatabaseConnector.new(path: config.database_path, table: config.table,
                                          unique_key: config.unique_key, logger: logger)
                                     .prepare_schema(config.fields.map(&:name))
    end

    private

    def export_items(collection)
      Exporters.for(config.output_format, logger: logger).export(collection, config.output_path)
    end

    def default_config_path
      File.expand_path("../config/settings.yml", __dir__)
    end
  end
end
