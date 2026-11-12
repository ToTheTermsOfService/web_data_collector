# frozen_string_literal: true

require "yaml"

module WebDataCollector
  module Exporters
    class YamlExporter < BaseExporter
      def self.extensions = %w[yaml yml]
      def serialize(collection)
        collection.to_export.map { |row| row.transform_keys(&:to_s) }.to_yaml
      end
    end
  end
end
