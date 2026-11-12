# frozen_string_literal: true

require_relative "autoloader"

module WebDataCollector
  VERSION = "1.0.0"
  ROOT = File.expand_path("..", __dir__)

  def self.loader
    @loader ||= Autoloader.new(
      root: __dir__,
      namespace: name,
      ignore: [__FILE__, File.join(__dir__, "autoloader.rb")],
      preload: [File.join(__dir__, "errors.rb")],
      logger: ENV["WDC_AUTOLOAD_DEBUG"] ? ->(msg) { warn msg } : nil
    )
  end
end

WebDataCollector.loader.setup
