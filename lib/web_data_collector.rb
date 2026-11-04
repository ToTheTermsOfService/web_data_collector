# frozen_string_literal: true

# Точка підключення бібліотеки: require "web_data_collector".
require_relative "errors"
require_relative "item"
require_relative "item_collection"
require_relative "normalizers"
require_relative "field_definition"
require_relative "configurator"
require_relative "app_logger"
require_relative "simple_website_parser"
require_relative "database_connector"
require_relative "exporters"
require_relative "engine"
require_relative "dsl/pipeline"
require_relative "dsl/pipeline_builder"
require_relative "dsl/pipeline_runner"
require_relative "dsl/loader"

module WebDataCollector
  VERSION = "1.0.0"
  ROOT = File.expand_path("..", __dir__)
end
