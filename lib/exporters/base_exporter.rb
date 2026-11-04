# frozen_string_literal: true

require "fileutils"
require_relative "../errors"

module WebDataCollector
  module Exporters
    # Спільна логіка експортерів: перевірка шляху, створення каталогу,
    # обробка помилок запису. Нащадки реалізують лише #serialize.
    class BaseExporter
      def self.extensions
        raise NotImplementedError
      end

      def initialize(logger: nil)
        @logger = logger
      end

      def export(collection, path)
        validate_path!(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, serialize(collection), encoding: "UTF-8")
        @logger&.info("Exported #{collection.size} items to #{path}")
        path
      rescue SystemCallError, IOError => e
        raise ExportError, "cannot write #{path}: #{e.message}"
      end

      def serialize(_collection)
        raise NotImplementedError
      end

      private

      def validate_path!(path)
        raise ExportError, "export path is empty" if path.nil? || path.to_s.strip.empty?
        raise ExportError, "export path '#{path}' is a directory" if File.directory?(path)

        ext = File.extname(path.to_s).delete(".").downcase
        return if self.class.extensions.include?(ext)

        raise ExportError, "export path '#{path}' must end with .#{self.class.extensions.join(' or .')}"
      end
    end
  end
end
