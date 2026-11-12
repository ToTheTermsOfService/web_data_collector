# frozen_string_literal: true

module WebDataCollector
  # Опис одного поля, яке потрібно витягнути зі сторінки:
  #   selector  - CSS-селектор;
  #   attribute - HTML-атрибут (nil - текстовий вміст елемента);
  #   normalize - ім'я нормалізатора або Proc;
  #   required  - запис без цього поля вважається некоректним і відкидається;
  #   scope     - :item (шукати всередині картки) або :page (на всій сторінці);
  #   readonly  - Item отримає для поля лише гетер, без сетера.
  # Використовується і YAML-конфігурацією, і DSL.
  class FieldDefinition
    SCOPES = %i[item page].freeze
    NAME_FORMAT = /\A[a-z_][a-z0-9_]*\z/
    OPTIONS = %i[selector attribute normalize required scope readonly].freeze

    attr_reader :name, :selector, :attribute, :normalize, :required, :scope, :readonly

    def self.from_config(name, options)
      options = (options || {}).transform_keys(&:to_sym)
      new(name, **options.slice(*OPTIONS))
    end

    def initialize(name, selector:, attribute: nil, normalize: nil, required: false, scope: :item, readonly: false)
      @name = name.to_s.to_sym
      @selector = selector.is_a?(String) ? selector.strip : selector
      @attribute = attribute&.to_s
      @normalize = normalize.is_a?(String) ? normalize.to_sym : normalize
      @required = required ? true : false
      @scope = scope.to_s.to_sym
      @readonly = readonly ? true : false
      validate!
    end

    def required?
      @required
    end

    def readonly?
      @readonly
    end

    def page_scope?
      scope == :page
    end

    def to_h
      { name: name, selector: selector, attribute: attribute,
        normalize: normalize.respond_to?(:call) ? :custom : normalize,
        required: required, scope: scope, readonly: readonly }
    end

    private

    def validate!
      raise ValidationError, "field name '#{name}' is invalid (use snake_case)" unless NAME_FORMAT.match?(name.to_s)
      raise ValidationError, "field name '#{name}' clashes with a built-in Item method" if Item.reserved_name?(name)
      raise ValidationError, "field '#{name}': selector must be a non-empty string" unless selector.is_a?(String) && !selector.empty?
      raise ValidationError, "field '#{name}': scope must be one of #{SCOPES.join(', ')}" unless SCOPES.include?(scope)

      validate_selector!
      return if normalize.nil? || normalize.respond_to?(:call) || Normalizers.known?(normalize)

      raise ValidationError, "field '#{name}': unknown normalizer '#{normalize}' (known: #{Normalizers.names.join(', ')})"
    end

    # Перевіряємо синтаксис селектора заздалегідь, а не під час парсингу.
    def validate_selector!
      require "nokogiri"
      Nokogiri::HTML("<html></html>").css(selector)
    rescue Nokogiri::CSS::SyntaxError, Nokogiri::XML::XPath::SyntaxError => e
      raise ValidationError, "field '#{name}': invalid CSS selector '#{selector}' (#{e.message.lines.first.strip})"
    end
  end
end
