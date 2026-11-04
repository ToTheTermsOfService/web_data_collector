# frozen_string_literal: true

require "json"
require_relative "base_exporter"

module WebDataCollector
  module Exporters
    class JsonExporter < BaseExporter
      def self.extensions = %w[json]

      def serialize(collection)
        JSON.pretty_generate(collection.to_export)
      end
    end
  end
end
