# frozen_string_literal: true

require "time"

module WebDataCollector
  # Один запис, отриманий із вебресурсу.
  #
  # Набір атрибутів не зашитий у клас. Гетери й сетери генеруються
  # динамічно (define_method) з опису полів у YAML-конфігурації або DSL:
  #
  #   BookItem = Item.define_schema(config.fields)
  #   book = BookItem.new(title: "Dune", price: 9.99, url: "...")
  #   book.title            # гетер
  #   book.price = "£12.50" # сетер; рядок проходить через нормалізатор поля -> 12.5
  #   book.price?           # предикат: чи є значення
  #   book.url = "..."      # NoMethodError, якщо поле readonly: true
  #
  # Для кожного поля генеруються три методи: name, name= і name?.
  # Звичайний Item.new(title: "...") теж отримує ці методи, але лише для
  # власних ключів (як синглтон-методи конкретного об'єкта).
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

      # Підклас успадковує вже оголошені атрибути.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@attribute_names, attribute_names.dup)
        subclass.instance_variable_set(:@readonly_attributes, readonly_attributes.dup)
        subclass.instance_variable_set(:@normalizers, normalizers.dup)
      end

      # Макрос класу: оголошує атрибут і генерує для нього методи доступу.
      #   attribute :price, normalize: :price
      #   attribute :url, readonly: true
      def attribute(name, readonly: false, normalize: nil)
        name = name.to_sym
        raise ValidationError, "attribute '#{name}' clashes with a built-in Item method" if reserved_name?(name)

        define_accessors(self, name, readonly: readonly)
        attribute_names << name unless attribute_names.include?(name)
        readonly_attributes << name if readonly && !readonly_attributes.include?(name)
        normalizers[name] = normalize if normalize
        name
      end

      # Створює підклас Item з методами для кожного поля конфігурації.
      # fields - FieldDefinition (з YAML/DSL) або просто імена полів.
      def define_schema(fields)
        fields = Array(fields)
        Class.new(self) do
          fields.each do |field|
            if field.is_a?(FieldDefinition)
              # як і в парсері: поле без normalize очищується як текст
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

      # Ім'я, яке не можна давати полю, бо воно перекриє метод самого Item
      # (hash, to_h, fields, class...).
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

      # Анонімні класи-схеми показуються як Item[title, price, ...].
      def inspect
        name || "WebDataCollector::Item[#{attribute_names.join(', ')}]"
      end
      alias to_s inspect

      # Генерує гетер, предикат і (якщо поле не readonly) сетер.
      # owner - клас (для схеми) або singleton_class об'єкта (для ad-hoc ключів).
      def define_accessors(owner, name, readonly: false)
        owner.define_method(name) { @attributes[name] }
        owner.define_method(:"#{name}?") { present?(@attributes[name]) }
        return if readonly

        owner.define_method(:"#{name}=") { |value| write_attribute(name, value) }
      end
    end

    attr_reader :scraped_at

    # Item.new({ title: "..." }) або Item.new(title: "...")
    def initialize(attributes = {}, scraped_at: Time.now, **keyword_attributes)
      raise ArgumentError, "attributes must be a Hash" unless attributes.is_a?(Hash)

      @attributes = self.class.attribute_names.to_h { |name| [name, nil] }
      @scraped_at = scraped_at
      attributes.merge(keyword_attributes).each { |key, value| assign(key.to_sym, value) }
    end

    # Копія атрибутів лише для читання; змінювати - через сетери або []=.
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

    # Новий Item того самого класу зі зміненими/доданими атрибутами.
    def merge(changes)
      self.class.new(@attributes.merge(changes.transform_keys(&:to_sym)), scraped_at: scraped_at)
    end

    def to_h
      @attributes.merge(scraped_at: scraped_at.iso8601)
    end

    # Порівняння за ідентичністю запису (URL), а якщо його немає - за всіма атрибутами.
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

    # Сетер: рядок проходить через нормалізатор поля з конфігурації.
    def write_attribute(name, value)
      normalizer = self.class.normalizers[name]
      value = Normalizers.apply(normalizer, value) if normalizer && value.is_a?(String)
      assign(name, value)
    end

    # Записує значення; для ключа, якого немає в схемі, створює методи
    # доступу саме для цього об'єкта.
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
