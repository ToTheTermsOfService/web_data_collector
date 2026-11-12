# frozen_string_literal: true

module WebDataCollector
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class NetworkError < Error; end
  class ParseError < Error; end
  class DatabaseError < Error; end
  class ExportError < Error; end
  class ValidationError < Error; end
end
