# frozen_string_literal: true

require "csv"

module WebDataCollector
  module Exporters
    class CsvExporter < BaseExporter
      def self.extensions = %w[csv]

      def serialize(collection)
        rows = collection.to_export
        headers = rows.flat_map(&:keys).uniq
        CSV.generate do |csv|
          csv << headers
          rows.each { |row| csv << headers.map { |h| row[h] } }
        end
      end
    end
  end
end
