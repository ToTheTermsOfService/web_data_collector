# frozen_string_literal: true

require_relative "../errors"
require_relative "../field_definition"
require_relative "pipeline"

module WebDataCollector
  module DSL
    # Приймає виклики DSL усередині блоку pipeline і заповнює об'єкт Pipeline.
    #
    #   pipeline "Детективи" do
    #     source "https://books.toscrape.com/..."
    #     pages 2
    #     extract each: "article.product_pod" do
    #       field :title, selector: "h3 a", attribute: :title, required: true
    #     end
    #     filter(:price) { |price| price < 30 }
    #     save_to :sqlite, table: "books"
    #     export :json, path: "output/books.json"
    #   end
    #
    # Блоки виконуються через instance_eval(&block) - це звичайні Ruby-блоки,
    # а не рядки коду, тож eval довільного тексту не використовується.
    class PipelineBuilder
      DEFAULT_DB_PATH = "data/pipelines.sqlite3"

      def self.build(name, root: Dir.pwd, &block)
        raise ValidationError, "pipeline '#{name}' needs a block" unless block

        builder = new(name, root: root)
        builder.instance_eval(&block)
        builder.pipeline
      end

      attr_reader :pipeline

      def initialize(name, root: Dir.pwd)
        @pipeline = Pipeline.new(name)
        @root = root
      end

      # --- джерело ---
      def source(url, pages: nil, delay: nil, timeout: nil, user_agent: nil)
        pipeline.source_url = url.to_s.strip
        pages(pages) if pages
        delay(delay) if delay
        pipeline.timeout = timeout if timeout
        pipeline.user_agent = user_agent if user_agent
      end

      def pages(count)
        pipeline.max_pages = count
      end

      def delay(seconds)
        pipeline.request_delay = seconds
      end

      def next_page(selector)
        pipeline.next_page_selector = selector
      end

      # --- поля ---
      # each: CSS-селектор "картки" запису; next_page: селектор пагінації.
      def extract(each: nil, next_page: nil, &block)
        raise ValidationError, "extract needs a block with field definitions" unless block

        pipeline.item_selector = each if each
        pipeline.next_page_selector = next_page if next_page
        FieldsBuilder.new(pipeline).instance_eval(&block)
      end

      # --- фільтрація ---
      #   filter(:price) { |price| price < 30 }            # за значенням поля
      #   filter(:price) { |price, item| ... }             # з доступом до запису
      #   filter { |item| item.title.include?("Murder") }  # на рівні запису
      #   filter :rating, 4..5                             # без блоку: Range/Regexp/Array/значення
      def filter(field = nil, matcher = nil, description: nil, &block)
        block ||= matcher_block(field, matcher)
        pipeline.add_filter(Pipeline::Filter.new(field&.to_sym, block, description))
      end

      # Скорочення для кількох умов: where price: 0..30, rating: 4..5
      def where(**conditions)
        conditions.each { |field, matcher| filter(field, matcher, description: "#{field} matches #{matcher.inspect}") }
      end

      # --- збереження та експорт ---
      def save_to(type, table: "items", path: DEFAULT_DB_PATH, unique_key: :url)
        pipeline.add_storage(Pipeline::Storage.new(type: type.to_sym, path: expand(path),
                                                   table: table.to_s, unique_key: unique_key.to_sym))
      end

      def export(format, path:)
        pipeline.add_export(Pipeline::Export.new(format: format.to_s.downcase.to_sym, path: expand(path)))
      end

      private

      def expand(path)
        return path if path.nil? || path.to_s.strip.empty?

        File.expand_path(path.to_s, @root)
      end

      def matcher_block(field, matcher)
        raise ValidationError, "filter needs a block or a matcher" if matcher.nil?
        raise ValidationError, "filter with a matcher needs a field name" if field.nil?

        lambda do |value|
          case matcher
          when Range then !value.nil? && matcher.cover?(value)
          when Regexp then matcher.match?(value.to_s)
          when Array then matcher.include?(value)
          else value == matcher
          end
        end
      end

      # Контекст блоку extract: тут доступний лише метод field.
      class FieldsBuilder
        def initialize(pipeline)
          @pipeline = pipeline
        end

        # field :price, selector: ".price_color", normalize: :price, required: true
        # field :title, ".product-title"   # скорочена форма
        def field(name, selector_arg = nil, selector: nil, attribute: nil, normalize: nil,
                  required: false, scope: :item, &normalizer)
          @pipeline.add_field(
            FieldDefinition.new(name, selector: selector || selector_arg, attribute: attribute,
                                      normalize: normalizer || normalize, required: required, scope: scope)
          )
        rescue ValidationError => e
          raise ValidationError, "pipeline '#{@pipeline.name}': #{e.message}"
        end
      end
    end
  end
end
