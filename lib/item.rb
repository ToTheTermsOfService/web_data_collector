# frozen_string_literal: true

require "time"

module WebDataCollector
  # Один запис, отриманий із вебресурсу.
  #
  # Набір атрибутів не зашитий у клас: він визначається конфігурацією
  # (або DSL), тому той самий Item підходить для книжок, товарів чи статей.
  # Доступ до атрибутів - через item.title, item[:title] або item.to_h.
  class Item
    include Comparable

    attr_reader :attributes, :scraped_at

    # Item.new({ title: "..." }) або Item.new(title: "...")
    def initialize(attributes = {}, scraped_at: Time.now, **keyword_attributes)
      raise ArgumentError, "attributes must be a Hash" unless attributes.is_a?(Hash)

      merged = attributes.merge(keyword_attributes)
      @attributes = merged.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }.freeze
      @scraped_at = scraped_at
    end

    def self.from_h(hash)
      hash = hash.transform_keys(&:to_sym)
      scraped = hash.delete(:scraped_at)
      scraped = Time.parse(scraped) if scraped.is_a?(String)
      new(hash, scraped_at: scraped || Time.now)
    end

    def [](name)
      attributes[name.to_sym]
    end

    def key?(name)
      attributes.key?(name.to_sym)
    end

    def fields
      attributes.keys
    end

    # Новий Item зі зміненими/доданими атрибутами (об'єкт незмінний).
    def merge(changes)
      self.class.new(attributes.merge(changes.transform_keys(&:to_sym)), scraped_at: scraped_at)
    end

    def to_h
      attributes.merge(scraped_at: scraped_at.iso8601)
    end

    # Порівняння за ідентичністю запису (URL), а якщо його немає - за всіма атрибутами.
    def <=>(other)
      return nil unless other.is_a?(Item)

      identity.to_s <=> other.identity.to_s
    end

    def ==(other)
      other.is_a?(Item) && attributes == other.attributes
    end
    alias eql? ==

    def hash
      attributes.hash
    end

    def identity
      self[:url] || attributes.values.join("|")
    end

    def to_s
      parts = attributes.map { |k, v| "#{k}: #{v}" }
      "Item(#{parts.join(', ')})"
    end

    def inspect
      "#<#{self.class.name} #{attributes.inspect}>"
    end

    def method_missing(name, *args, &block)
      return attributes[name] if args.empty? && block.nil? && attributes.key?(name)

      super
    end

    def respond_to_missing?(name, include_private = false)
      attributes.key?(name) || super
    end
  end
end
