# frozen_string_literal: true

require_relative "../errors"
require_relative "pipeline_builder"

module WebDataCollector
  module DSL
    # Завантажує DSL-файл і повертає список описаних у ньому конвеєрів.
    #
    # Файл підключається через Kernel#load з модулем-обгорткою (Ruby >= 3.1):
    # верхній рівень файлу отримує метод pipeline з модуля TopLevel, а
    # константи файлу не потрапляють у глобальний простір імен.
    # Рядки DSL не передаються в eval - файл виконується як звичайний Ruby-код,
    # так само як Rakefile чи Gemfile.
    module Loader
      module TopLevel
        def pipeline(name, &block)
          Loader.register(PipelineBuilder.build(name, root: Loader.root, &block))
        end
      end

      def self.load_file(path, root: nil)
        raise ValidationError, "DSL file not found: #{path}" unless File.file?(path)
        raise ValidationError, "DSL file must have .rb extension: #{path}" unless File.extname(path) == ".rb"

        Thread.current[:wdc_dsl_pipelines] = []
        Thread.current[:wdc_dsl_root] = root || Dir.pwd
        Kernel.load(File.expand_path(path), TopLevel)
        pipelines = Thread.current[:wdc_dsl_pipelines]
        raise ValidationError, "DSL file #{path} does not define any pipeline" if pipelines.empty?

        pipelines
      rescue SyntaxError => e
        raise ValidationError, "syntax error in DSL file #{path}: #{e.message.lines.first&.strip}"
      rescue NoMethodError, NameError, ArgumentError => e
        location = e.backtrace&.find { |l| l.start_with?(File.expand_path(path)) || l.include?(File.basename(path)) }
        raise ValidationError, "error in DSL file #{path}#{" (#{location})" if location}: #{e.message}"
      ensure
        Thread.current[:wdc_dsl_root] = nil
      end

      # Опис конвеєра прямо в Ruby-коді (без окремого файлу).
      def self.define(name, root: Dir.pwd, &block)
        PipelineBuilder.build(name, root: root, &block)
      end

      def self.register(pipeline)
        (Thread.current[:wdc_dsl_pipelines] ||= []) << pipeline
        pipeline
      end

      def self.root
        Thread.current[:wdc_dsl_root] || Dir.pwd
      end
    end
  end
end
