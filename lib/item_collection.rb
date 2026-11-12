# frozen_string_literal: true

module WebDataCollector
  # Набір об'єктів Item. Підключає Enumerable, тож map/select/sort_by/
  # group_by тощо доступні "з коробки"; методи, що повертають підмножину,
  # обгорнуті так, щоб результатом знову була ItemCollection.
  #
  # Для колекції теж генеруються методи з полів конфігурації
  # (ItemCollection.define_schema), наприклад для поля price:
  #   books.price_values           # гетер: [47.82, 51.33, ...]
  #   books.price_values = 10.0    # сетер: усім записам (або масив - по порядку)
  #   books.find_by_price(47.82)   # перший запис із таким значенням
  #   books.where_price(0..30)     # відбір (Range, Regexp, значення або блок)
  class ItemCollection
    include Enumerable

    class << self
      def item_class
        @item_class || Item
      end

      # Підклас колекції для конкретної схеми Item (див. Item.define_schema).
      def define_schema(item_class)
        Class.new(self) do
          @item_class = item_class
          item_class.attribute_names.each do |name|
            define_method(:"#{name}_values") { map { |item| item[name] } }
            define_method(:"find_by_#{name}") { |value| find { |item| item[name] == value } }
            define_method(:"where_#{name}") { |matcher = nil, &block| where(name => block || matcher) }
            next if item_class.readonly_attributes.include?(name)

            define_method(:"#{name}_values=") do |value|
              values = value.is_a?(Array) ? value : Array.new(size, value)
              raise ArgumentError, "expected #{size} values, got #{values.size}" unless values.size == size

              each_with_index { |item, i| item.public_send(:"#{name}=", values[i]) }
            end
          end
        end
      end

      def inspect
        name || "WebDataCollector::ItemCollection[#{item_class.attribute_names.join(', ')}]"
      end
      alias to_s inspect
    end

    def initialize(items = [])
      @items = []
      items.each { |item| add(item) }
    end

    def item_class
      self.class.item_class
    end

    # Створює запис класу цієї колекції і додає його.
    def build(attributes = {})
      item = item_class.new(attributes)
      add(item)
      item
    end

    # Значення одного поля з усіх записів.
    def pluck(field)
      map { |item| item[field] }
    end

    def add(item)
      raise ArgumentError, "expected Item, got #{item.class}" unless item.is_a?(Item)

      @items << item
      self
    end
    alias << add

    def concat(other)
      other.each { |item| add(item) }
      self
    end

    def remove(item)
      @items.delete(item)
      self
    end

    def each(&block)
      return enum_for(:each) unless block

      @items.each(&block)
      self
    end

    def size
      @items.size
    end
    alias count_items size
    alias length size

    def empty?
      @items.empty?
    end

    def [](index)
      @items[index]
    end

    def first(n = nil)
      n ? @items.first(n) : @items.first
    end

    def last
      @items.last
    end

    # Пошук першого запису: за блоком або за точною відповідністю атрибутів.
    #   find_by(title: "Sharp Objects")
    def find_by(conditions = nil, &block)
      block ||= ->(item) { conditions.all? { |k, v| item[k] == v } }
      @items.find(&block)
    end

    # Фільтрація: блок, хеш умов або обидва.
    # Значенням умови може бути Range, Regexp, Proc або точне значення.
    #   where(rating: 4..5) { |i| i.price < 30 }
    def where(conditions = {}, &block)
      result = @items.select do |item|
        conditions.all? { |field, expected| match?(item[field], expected) } &&
          (block.nil? || block.call(item))
      end
      self.class.new(result)
    end

    def reject(&block)
      self.class.new(@items.reject(&block))
    end

    def select(&block)
      self.class.new(@items.select(&block))
    end
    alias filter select

    def sort_by_field(field, direction: :asc)
      sorted = @items.sort_by { |item| sort_key(item[field]) }
      self.class.new(direction == :desc ? sorted.reverse : sorted)
    end

    # Прибирає повтори за атрибутом (за замовчуванням - url).
    def uniq_by(field = :url)
      self.class.new(@items.uniq { |item| item[field] })
    end

    def to_a
      @items.dup
    end

    # Формат, придатний для експорту (JSON/CSV/YAML).
    def to_export
      @items.map(&:to_h)
    end

    def fields
      @items.flat_map(&:fields).uniq
    end

    def to_s
      "ItemCollection(#{size} items)"
    end

    def inspect
      "#<#{self.class.name} size=#{size}>"
    end

    private

    def match?(value, expected)
      case expected
      when Range then !value.nil? && expected.cover?(value)
      when Regexp then expected.match?(value.to_s)
      when Proc then expected.call(value)
      when Array then expected.include?(value)
      else value == expected
      end
    end

    # nil йдуть у кінець; числа і рядки сортуються кожні за своїми правилами.
    def sort_key(value)
      case value
      when nil then [2, ""]
      when Numeric then [0, value]
      else [1, value.to_s]
      end
    end
  end
end
