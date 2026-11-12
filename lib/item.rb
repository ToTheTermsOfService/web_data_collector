# frozen_string_literal: true

require "time"

module WebDataCollector
  class Item
    include Comparable

    class << self
      def attribute_names
        @attribute_names ||= []
      end

      def readonly_attributes
        @readonly_attributes ||= []
      end

      def normalizers
        @normalizers ||= {}
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@attribute_names, attribute_names.dup)
        subclass.instance_variable_set(:@readonly_attributes, readonly_attributes.dup)
        subclass.instance_variable_set(:@normalizers, normalizers.dup)
      end

      def attribute(name, readonly: false, normalize: nil)
        name = name.to_sym
        raise ValidationError, "attribute '#{name}' clashes with a built-in Item method" if reserved_name?(name)

        define_accessors(self, name, readonly: readonly)
        attribute_names << name unless attribute_names.include?(name)
        readonly_attributes << name if readonly && !readonly_attributes.include?(name)
        normalizers[name] = normalize if normalize
        name
      end

      def define_schema(fields)
        fields = Array(fields)
        Class.new(self) do
          fields.each do |field|
            if field.is_a?(FieldDefinition)
              attribute(field.name, readonly: field.readonly?, normalize: field.normalize || :text)
            else
              attribute(field)
            end
          end
        end
      end

      def schema?
        attribute_names.any?
      end

      def reserved_name?(name)
        name = name.to_sym
        Item.method_defined?(name) || Item.private_method_defined?(name)
      end

      def from_h(hash)
        hash = hash.transform_keys(&:to_sym)
        scraped = hash.delete(:scraped_at)
        scraped = Time.parse(scraped) if scraped.is_a?(String)
        new(hash, scraped_at: scraped || Time.now)
      end

      def inspect
        name || "WebDataCollector::Item[#{attribute_names.join(', ')}]"
      end
      alias to_s inspect

      def define_accessors(owner, name, readonly: false)
        owner.define_method(name) { @attributes[name] }
        owner.define_method(:"#{name}?") { present?(@attributes[name]) }
        return if readonly

        owner.define_method(:"#{name}=") { |value| write_attribute(name, value) }
      end
    end

    attr_reader :scraped_at

    def initialize(attributes = {}, scraped_at: Time.now, **keyword_attributes)
      raise ArgumentError, "attributes must be a Hash" unless attributes.is_a?(Hash)

      @attributes = self.class.attribute_names.to_h { |name| [name, nil] }
      @scraped_at = scraped_at
      attributes.merge(keyword_attributes).each { |key, value| assign(key.to_sym, value) }
    end

    def attributes
      @attributes.dup.freeze
    end

    def [](name)
      @attributes[name.to_sym]
    end

    def []=(name, value)
      name = name.to_sym
      raise ValidationError, "attribute '#{name}' is read-only" if readonly?(name)

      write_attribute(name, value)
    end

    def key?(name)
      @attributes.key?(name.to_sym)
    end

    def fields
      @attributes.keys
    end

    def readonly?(name)
      self.class.readonly_attributes.include?(name.to_sym)
    end

    def merge(changes)
      self.class.new(@attributes.merge(changes.transform_keys(&:to_sym)), scraped_at: scraped_at)
    end

    def to_h
      @attributes.merge(scraped_at: scraped_at.iso8601)
    end

    def <=>(other)
      return nil unless other.is_a?(Item)

      identity.to_s <=> other.identity.to_s
    end

    def ==(other)
      other.is_a?(Item) && @attributes == other.attributes
    end
    alias eql? ==

    def hash
      @attributes.hash
    end

    def identity
      self[:url] || @attributes.values.join("|")
    end

    def to_s
      parts = @attributes.map { |k, v| "#{k}: #{v}" }
      "Item(#{parts.join(', ')})"
    end

    def inspect
      "#<#{self.class.inspect} #{@attributes.inspect}>"
    end

    private

    def write_attribute(name, value)
      normalizer = self.class.normalizers[name]
      value = Normalizers.apply(normalizer, value) if normalizer && value.is_a?(String)
      assign(name, value)
    end

    def assign(name, value)
      unless self.class.attribute_names.include?(name) || singleton_class.method_defined?(name) ||
             self.class.reserved_name?(name)
        self.class.define_accessors(singleton_class, name)
      end
      @attributes[name] = value
    end

    def present?(value)
      !(value.nil? || value == false || (value.respond_to?(:empty?) && value.empty?))
    end
  end
end
