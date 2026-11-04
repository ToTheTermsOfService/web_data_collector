# frozen_string_literal: true

require "mechanize"
require "nokogiri"
require "uri"
require_relative "errors"
require_relative "item"
require_relative "item_collection"
require_relative "normalizers"
require_relative "configurator"

module WebDataCollector
  # Завантажує сторінки вебресурсу (Mechanize), знаходить елементи за
  # CSS-селекторами (Nokogiri) і перетворює їх на ItemCollection.
  #
  # Алгоритм:
  #   1. перевірити URL;
  #   2. завантажити сторінку (з повторними спробами при мережевих збоях);
  #   3. знайти всі "картки" за item_selector;
  #   4. для кожної картки витягти поля згідно з FieldDefinition;
  #   5. відкинути записи без обов'язкових полів;
  #   6. перейти за посиланням next_page_selector (до max_pages сторінок).
  class SimpleWebsiteParser
    NETWORK_ERRORS = [
      Mechanize::ResponseCodeError, Mechanize::RedirectLimitReachedError,
      SocketError, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout,
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      OpenSSL::SSL::SSLError, Net::HTTP::Persistent::Error
    ].freeze

    attr_reader :item_selector, :fields, :stats

    def self.from_config(config, logger:, agent: nil)
      new(
        item_selector: config.item_selector,
        fields: config.fields,
        next_page_selector: config.next_page_selector,
        max_pages: config.max_pages,
        timeout: config.timeout,
        request_delay: config.request_delay,
        user_agent: config.user_agent,
        logger: logger,
        agent: agent
      )
    end

    def initialize(item_selector:, fields:, logger:, next_page_selector: nil, max_pages: 1,
                   timeout: 15, request_delay: 0, user_agent: nil, retries: 2, agent: nil)
      raise ArgumentError, "item_selector is required" if item_selector.to_s.strip.empty?
      raise ArgumentError, "at least one field is required" if fields.nil? || fields.empty?

      @item_selector = item_selector
      @fields = fields
      @next_page_selector = next_page_selector
      @max_pages = max_pages
      @request_delay = request_delay
      @retries = retries
      @logger = logger
      @agent = agent || build_agent(timeout, user_agent)
      reset_stats
    end

    # Повертає ItemCollection. Кидає NetworkError/ParseError, якщо не вдалося
    # отримати навіть першу сторінку; збої на наступних сторінках лише
    # логуються, а вже зібрані дані повертаються.
    def parse(url)
      raise NetworkError, "invalid source URL: '#{url}'" unless Configurator.valid_http_url?(url)

      reset_stats
      collection = ItemCollection.new
      visited = {}
      current = url

      while current && @stats[:pages] < @max_pages && !visited[current]
        visited[current] = true
        doc = begin
          fetch(current)
        rescue NetworkError, ParseError => e
          raise if @stats[:pages].zero?

          @logger.warn("Stopping pagination at #{current}: #{e.message}")
          break
        end
        @stats[:pages] += 1
        page_items = extract_items(doc, current)
        @logger.info("Page #{@stats[:pages]}: #{current} -> #{page_items.size} items")
        collection.concat(page_items)
        current = next_page_url(doc, current)
        sleep(@request_delay) if current && @request_delay.positive?
      end

      @logger.warn("No items found at #{url} (selector '#{item_selector}'). The page structure may have changed.") if collection.empty?
      collection
    end

    # Розбір уже завантаженого HTML (зручно для тестів та офлайн-обробки).
    def parse_html(html, base_url: nil)
      reset_stats
      @stats[:pages] = 1
      extract_items(Nokogiri::HTML(html), base_url)
    end

    private

    def build_agent(timeout, user_agent)
      Mechanize.new do |agent|
        agent.open_timeout = timeout
        agent.read_timeout = timeout
        agent.user_agent = user_agent if user_agent
        agent.max_history = 1
        agent.robots = false
      end
    end

    def fetch(url)
      attempts = 0
      begin
        attempts += 1
        @logger.debug("GET #{url} (attempt #{attempts})")
        page = @agent.get(url)
        raise ParseError, "response from #{url} is not an HTML page" unless page.respond_to?(:parser) && page.parser

        page.parser
      rescue *NETWORK_ERRORS => e
        if attempts <= @retries && retryable?(e)
          @logger.warn("Network error on #{url}: #{e.class}: #{e.message}. Retrying...")
          sleep(0.5 * attempts)
          retry
        end
        raise NetworkError, "failed to load #{url}: #{e.class}: #{e.message}"
      end
    end

    # 4xx (крім 429) повторювати немає сенсу.
    def retryable?(error)
      return true unless error.is_a?(Mechanize::ResponseCodeError)

      code = error.response_code.to_i
      code == 429 || code >= 500
    end

    def extract_items(doc, base_url)
      nodes = doc.css(item_selector)
      page_values = page_scope_values(doc, base_url)
      items = ItemCollection.new

      nodes.each do |node|
        attrs = page_values.dup
        fields.reject(&:page_scope?).each { |field| attrs[field.name] = extract_value(node, field, base_url) }
        missing = fields.select { |f| f.required? && blank?(attrs[f.name]) }.map(&:name)
        if missing.any?
          @stats[:skipped] += 1
          @logger.warn("Skipping element: missing required field(s) #{missing.join(', ')}")
          next
        end
        items << Item.new(attrs)
      end
      @stats[:items] += items.size
      items
    end

    def page_scope_values(doc, base_url)
      fields.select(&:page_scope?).to_h { |field| [field.name, extract_value(doc, field, base_url)] }
    end

    def extract_value(node, field, base_url)
      element = node.at_css(field.selector)
      return nil unless element

      raw = field.attribute ? element[field.attribute] : element.text
      value = Normalizers.apply(field.normalize || :text, raw, base_url: base_url)
      value.is_a?(String) && value.empty? ? nil : value
    rescue StandardError => e
      @logger.warn("Failed to extract field '#{field.name}': #{e.class}: #{e.message}")
      nil
    end

    def next_page_url(doc, current)
      return nil unless @next_page_selector

      href = doc.at_css(@next_page_selector)&.[]("href")
      href && URI.join(current, href).to_s
    rescue URI::Error
      nil
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def reset_stats
      @stats = { pages: 0, items: 0, skipped: 0 }
    end
  end
end
