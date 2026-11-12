# frozen_string_literal: true

require "logger"

module WebDataCollector
  module DSL
    # Виконує описаний у DSL конвеєр, використовуючи компоненти Частини I:
    #   validate -> parse (SimpleWebsiteParser) -> filter (ItemCollection)
    #   -> save (DatabaseConnector) -> export (Exporters) -> log.
    # Помилка на будь-якому етапі зупиняє конвеєр; у результаті вказується,
    # на якому саме етапі вона сталася.
    class PipelineRunner
      STAGES = %i[validate parse filter save export].freeze

      Result = Struct.new(:pipeline, :status, :stage, :error, :collected, :filtered_out,
                          :items, :db_stats, :exported, :duration, keyword_init: true) do
        def success? = status == :success

        def summary
          return "Pipeline '#{pipeline}' FAILED at stage '#{stage}': #{error}" unless success?

          saved = db_stats.map { |s| "#{s[:table]}: +#{s[:inserted]} new / #{s[:updated]} updated" }
          "Pipeline '#{pipeline}': #{collected} collected, #{filtered_out} filtered out, #{items.size} kept; " \
            "saved [#{saved.join('; ')}]; exported [#{exported.join(', ')}] in #{format('%.2f', duration)}s"
        end
      end

      class StageError < Error
        attr_reader :stage

        def initialize(stage, message)
          @stage = stage
          super(message)
        end
      end

      def initialize(pipeline, logger: Logger.new(File::NULL), agent: nil)
        @pipeline = pipeline
        @logger = logger
        @agent = agent
      end

      def run
        started = Time.now
        @logger.info("=== Pipeline '#{@pipeline.name}' started ===")

        stage(:validate) { @pipeline.validate! }
        collection = stage(:parse) { parser.parse(@pipeline.source_url) }
        collected = collection.size
        filtered = stage(:filter) { apply_filters(collection) }
        db_stats = stage(:save) { save(filtered) }
        exported = stage(:export) { export(filtered) }

        result = Result.new(pipeline: @pipeline.name, status: :success, collected: collected,
                            filtered_out: collected - filtered.size, items: filtered,
                            db_stats: db_stats, exported: exported, duration: Time.now - started)
        @logger.info(result.summary)
        result
      rescue StageError => e
        @logger.error("Pipeline '#{@pipeline.name}' failed at stage '#{e.stage}': #{e.message}")
        Result.new(pipeline: @pipeline.name, status: :failed, stage: e.stage, error: e.message,
                   items: ItemCollection.new, db_stats: [], exported: [], duration: Time.now - started)
      end

      # Фільтри застосовуються послідовно (логічне І). Запис проходить далі,
      # лише якщо всі фільтри повернули істинне значення. Якщо блок фільтра
      # кидає виняток, запис відкидається, а помилка логується.
      def apply_filters(collection)
        return collection if @pipeline.filters.empty?

        @pipeline.filters.reduce(collection) do |current, filter|
          kept = current.select { |item| passes?(filter, item) }
          @logger.info("Filter '#{filter}': #{current.size} -> #{kept.size}")
          kept
        end
      end

      private

      def stage(name)
        @logger.debug("Stage '#{name}'")
        yield
      rescue StageError
        raise
      rescue Error, SystemCallError => e
        raise StageError.new(name, e.message)
      end

      def parser
        SimpleWebsiteParser.new(
          item_selector: @pipeline.item_selector,
          fields: @pipeline.fields,
          next_page_selector: @pipeline.next_page_selector,
          max_pages: @pipeline.max_pages,
          request_delay: @pipeline.request_delay,
          timeout: @pipeline.timeout,
          user_agent: @pipeline.user_agent,
          logger: @logger,
          agent: @agent
        )
      end

      def passes?(filter, item)
        if filter.record_level?
          filter.block.call(item)
        else
          value = item[filter.field]
          filter.block.arity == 2 || filter.block.arity < -1 ? filter.block.call(value, item) : filter.block.call(value)
        end
      rescue StandardError => e
        @logger.warn("Filter '#{filter}' raised #{e.class}: #{e.message} for #{item.identity}; record dropped")
        false
      end

      def save(collection)
        @pipeline.storages.map do |storage|
          db = DatabaseConnector.new(path: storage.path, table: storage.table,
                                     unique_key: storage.unique_key, logger: @logger)
          begin
            db.prepare_schema(@pipeline.field_names)
            db.save(collection).merge(table: storage.table, total: db.count)
          ensure
            db.close
          end
        end
      end

      def export(collection)
        @pipeline.exports.map do |export|
          Exporters.for(export.format, logger: @logger).export(collection, export.path)
        end
      end
    end
  end
end
