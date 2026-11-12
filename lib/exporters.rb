# frozen_string_literal: true

module WebDataCollector
  module Exporters
    REGISTRY = {
      json: JsonExporter,
      csv: CsvExporter,
      yaml: YamlExporter,
      yml: YamlExporter
    }.freeze

    def self.formats
      REGISTRY.keys
    end

    def self.supported?(format)
      REGISTRY.key?(format.to_s.downcase.to_sym)
    end

    def self.for(format, logger: nil)
      klass = REGISTRY[format.to_s.downcase.to_sym]
      raise ExportError, "unsupported export format '#{format}' (use: #{formats.join(', ')})" unless klass

      klass.new(logger: logger)
    end
  end
end
