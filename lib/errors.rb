# frozen_string_literal: true

module WebDataCollector
  # Базова помилка застосунку. Усі власні винятки успадковуються від неї,
  # щоб точку входу можна було захистити одним rescue.
  class Error < StandardError; end

  class ConfigurationError < Error; end
  class NetworkError < Error; end
  class ParseError < Error; end
  class DatabaseError < Error; end
  class ExportError < Error; end
  class ValidationError < Error; end
end
