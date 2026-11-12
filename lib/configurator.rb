# frozen_string_literal: true

require "yaml"
require "uri"

module WebDataCollector
  class Configurator
    SUPPORTED_ADAPTERS = %w[sqlite].freeze
    SUPPORTED_FORMATS = %w[json csv yaml].freeze
    IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/
    ENV_OVERRIDES = {
      "WDC_SOURCE_URL" => %w[source url],
      "WDC_DATABASE_PATH" => %w[database path],
      "WDC_LOG_LEVEL" => %w[application log_level]
    }.freeze

    attr_reader :root, :data

    def self.load(path, root: nil, env: ENV)
      raise ConfigurationError, "configuration file not found: #{path}" unless File.file?(path)

      raw = YAML.safe_load_file(path, aliases: false) || {}
      raise ConfigurationError, "configuration root must be a mapping" unless raw.is_a?(Hash)

      new(raw, root: root || File.expand_path("..", File.dirname(File.expand_path(path))), env: env)
    rescue Psych::SyntaxError => e
      raise ConfigurationError, "invalid YAML in #{path}: #{e.message}"
    end

    def initialize(data, root: Dir.pwd, env: {})
      @root = root
      @data = deep_stringify(data)
      apply_env_overrides(env)
      validate!
    end

    def dig(*keys)
      data.dig(*keys.map(&:to_s))
    end

    def app_name = dig(:application, :name) || "web_data_collector"
    def log_level = dig(:application, :log_level) || "info"
    def log_file = expand(dig(:application, :log_file) || "logs/app.log")
    def source_url = dig(:source, :url)
    def timeout = (dig(:source, :timeout) || 15).to_i
    def max_pages = (dig(:source, :max_pages) || 1).to_i
    def request_delay = (dig(:source, :request_delay) || 0).to_f
    def user_agent = dig(:source, :user_agent) || "web_data_collector/1.0"
    def item_selector = dig(:selectors, :item)
    def next_page_selector = dig(:selectors, :next_page)
    def fields
      @fields ||= dig(:selectors, :fields).map { |name, opts| FieldDefinition.from_config(name, opts) }
    end

    def database_path = expand(dig(:database, :path))
    def table = dig(:database, :table) || "items"
    def unique_key = (dig(:database, :unique_key) || "url").to_sym
    def output_directory = expand(dig(:output, :directory) || "output")
    def output_format = (dig(:output, :format) || "json").to_s.downcase
    def output_filename = dig(:output, :filename) || "items"
    def output_path = File.join(output_directory, "#{output_filename}.#{output_format}")
    def expand(path)
      return nil if path.nil?

      File.expand_path(path, root)
    end

    def self.valid_http_url?(url)
      uri = URI.parse(url.to_s)
      uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
    rescue URI::InvalidURIError
      false
    end

    private

    def validate!
      errors = []
      errors << "source.url is required" if blank?(source_url)
      errors << "source.url must be an http(s) URL, got '#{source_url}'" if !blank?(source_url) && !self.class.valid_http_url?(source_url)
      errors << "source.timeout must be positive" unless timeout.positive?
      errors << "source.max_pages must be >= 1" unless max_pages >= 1
      errors << "selectors.item is required" if blank?(item_selector)
      errors << "selectors.fields must define at least one field" unless dig(:selectors, :fields).is_a?(Hash) && dig(:selectors, :fields).any?
      errors << "database.adapter '#{dig(:database, :adapter)}' is not supported (use: #{SUPPORTED_ADAPTERS.join(', ')})" unless SUPPORTED_ADAPTERS.include?(dig(:database, :adapter).to_s)
      errors << "database.path is required" if blank?(dig(:database, :path))
      errors << "database.table must be a valid identifier" unless IDENTIFIER.match?(table.to_s)
      errors << "output.format '#{output_format}' is not supported (use: #{SUPPORTED_FORMATS.join(', ')})" unless SUPPORTED_FORMATS.include?(output_format)
      raise ConfigurationError, "invalid configuration:\n  - #{errors.join("\n  - ")}" if errors.any?

      fields
      return if fields.map(&:name).include?(unique_key)

      raise ConfigurationError, "database.unique_key '#{unique_key}' must be one of the configured fields"
    rescue ValidationError => e
      raise ConfigurationError, "invalid field definition: #{e.message}"
    end

    def apply_env_overrides(env)
      ENV_OVERRIDES.each do |var, path|
        value = env[var]
        next if blank?(value)

        (data[path[0]] ||= {})[path[1]] = value
      end
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def deep_stringify(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
      when Array then value.map { |v| deep_stringify(v) }
      else value
      end
    end
  end
end
