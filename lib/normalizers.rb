# frozen_string_literal: true

require "uri"

module WebDataCollector
  module Normalizers
    RATING_WORDS = { "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5 }.freeze

    REGISTRY = {
      text: ->(value, _ctx) { value.to_s.gsub(/\s+/, " ").strip },
      strip: ->(value, _ctx) { value.to_s.strip },
      integer: ->(value, _ctx) { value.to_s[/-?\d+/]&.to_i },
      float: ->(value, _ctx) { value.to_s.tr(",", ".")[/-?\d+(\.\d+)?/]&.to_f },
      price: lambda do |value, _ctx|
        digits = value.to_s.gsub(/[[:space:]]/, "").tr(",", ".")[/\d+(\.\d+)?/]
        digits&.to_f
      end,
      rating: lambda do |value, _ctx|
        word = value.to_s.downcase.split.find { |w| RATING_WORDS.key?(w) }
        word ? RATING_WORDS[word] : value.to_s[/\d+/]&.to_i
      end,
      url: lambda do |value, ctx|
        raw = value.to_s.strip
        next nil if raw.empty?

        base = ctx[:base_url]
        base ? URI.join(base.to_s, raw).to_s : raw
      rescue URI::Error
        raw
      end
    }.freeze

    def self.names
      REGISTRY.keys
    end

    def self.known?(name)
      REGISTRY.key?(name.to_sym)
    end

    def self.apply(normalizer, value, context = {})
      return value if normalizer.nil?

      fn = normalizer.respond_to?(:call) ? normalizer : REGISTRY.fetch(normalizer.to_sym)
      fn.arity == 1 ? fn.call(value) : fn.call(value, context)
    end
  end
end
