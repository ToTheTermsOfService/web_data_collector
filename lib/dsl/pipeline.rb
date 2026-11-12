# frozen_string_literal: true

module WebDataCollector
  module DSL
    # Об'єкт конфігурації конвеєра: лише дані + перевірка, без виконання.
    # Його будує PipelineBuilder, а виконує PipelineRunner.
    class Pipeline
      # Фільтр: field = nil означає фільтр на рівні всього запису.
      Filter = Struct.new(:field, :block, :description) do
        def record_level? = field.nil?

        def to_s
          description || (record_level? ? "record filter" : "filter on :#{field}")
        end
      end

      Storage = Struct.new(:type, :path, :table, :unique_key, keyword_init: true)
      Export = Struct.new(:format, :path, keyword_init: true)

      SUPPORTED_STORAGES = %i[sqlite].freeze

      attr_accessor :name, :source_url, :item_selector, :next_page_selector,
                    :max_pages, :request_delay, :timeout, :user_agent
      attr_reader :fields, :filters, :storages, :exports

      def initialize(name)
        @name = name.to_s
        @fields = []
        @filters = []
        @storages = []
        @exports = []
        @max_pages = 1
        @request_delay = 0
        @timeout = 15
      end

      def add_field(field)
        @fields << field
      end

      def add_filter(filter)
        @filters << filter
      end

      def add_storage(storage)
        @storages << storage
      end

      def add_export(export)
        @exports << export
      end

      def field_names
        fields.map(&:name)
      end

      # Повертає масив повідомлень про помилки (порожній - конфігурація коректна).
      def errors
        errors = []
        errors << "pipeline name is empty" if name.strip.empty?
        validate_source(errors)
        validate_fields(errors)
        validate_filters(errors)
        validate_storages(errors)
        validate_exports(errors)
        errors
      end

      def valid?
        errors.empty?
      end

      def validate!
        list = errors
        return self if list.empty?

        raise ValidationError, "pipeline '#{name}' is invalid:\n  - #{list.join("\n  - ")}"
      end

      def to_h
        {
          name: name, source: source_url, items: item_selector, next_page: next_page_selector,
          max_pages: max_pages, request_delay: request_delay,
          fields: fields.map(&:to_h), filters: filters.map(&:to_s),
          storages: storages.map(&:to_h), exports: exports.map(&:to_h)
        }
      end

      private

      def validate_source(errors)
        if source_url.to_s.strip.empty?
          errors << "source URL is missing (use: source \"https://...\")"
        elsif !Configurator.valid_http_url?(source_url)
          errors << "source URL '#{source_url}' is not a valid http(s) URL"
        end
        errors << "item selector is missing (use: extract each: \"css\" do ... end)" if item_selector.to_s.strip.empty?
        errors << "pages must be a positive integer" unless max_pages.is_a?(Integer) && max_pages.positive?
        errors << "delay must be a non-negative number" unless request_delay.is_a?(Numeric) && request_delay >= 0
      end

      def validate_fields(errors)
        errors << "no fields defined (add field definitions inside extract)" if fields.empty?
        duplicates = field_names.tally.select { |_, n| n > 1 }.keys
        errors << "duplicate field(s): #{duplicates.join(', ')}" if duplicates.any?
      end

      def validate_filters(errors)
        filters.each do |filter|
          next if filter.record_level? || field_names.include?(filter.field)

          errors << "filter refers to unknown field :#{filter.field}"
        end
      end

      def validate_storages(errors)
        storages.each do |storage|
          unless SUPPORTED_STORAGES.include?(storage.type)
            errors << "unsupported storage :#{storage.type} (supported: #{SUPPORTED_STORAGES.join(', ')})"
            next
          end
          errors << "storage path is empty" if storage.path.to_s.strip.empty?
          errors << "table name '#{storage.table}' is invalid" unless Configurator::IDENTIFIER.match?(storage.table.to_s)
          unless field_names.include?(storage.unique_key)
            errors << "unique key :#{storage.unique_key} must be one of the fields (#{field_names.join(', ')})"
          end
        end
      end

      def validate_exports(errors)
        exports.each do |export|
          unless Exporters.supported?(export.format)
            errors << "unsupported export format :#{export.format} (supported: #{Exporters.formats.join(', ')})"
            next
          end
          path = export.path.to_s
          if path.strip.empty?
            errors << "export :#{export.format} has no path"
          elsif File.directory?(path)
            errors << "export path '#{path}' is a directory"
          elsif !Exporters::REGISTRY[export.format].extensions.include?(File.extname(path).delete(".").downcase)
            errors << "export path '#{path}' does not match format :#{export.format}"
          elsif blocked_parent?(path)
            errors << "export path '#{path}' cannot be created (a parent is a file)"
          end
        end
      end

      def blocked_parent?(path)
        dir = File.dirname(File.expand_path(path))
        dir = File.dirname(dir) until File.exist?(dir) || dir == File.dirname(dir)
        File.exist?(dir) && !File.directory?(dir)
      end
    end
  end
end
