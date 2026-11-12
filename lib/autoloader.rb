# frozen_string_literal: true

require "monitor"

module WebDataCollector
  # Власний автозавантажувач класів (без Zeitwerk і без require_relative
  # між файлами бібліотеки).
  #
  # Як працює:
  #   1. setup сканує каталог lib/ і будує таблицю
  #      "повне ім'я константи" -> "файл", перетворюючи шляхи за угодою
  #      snake_case -> CamelCase:
  #        item_collection.rb          -> WebDataCollector::ItemCollection
  #        exporters/json_exporter.rb  -> WebDataCollector::Exporters::JsonExporter
  #        dsl/pipeline_builder.rb     -> WebDataCollector::DSL::PipelineBuilder
  #      Каталог без однойменного файлу (dsl/) стає "неявним" простором
  #      імен: модуль DSL створюється автоматично.
  #   2. Коли Ruby не знаходить константу, він викликає const_missing на
  #      модулі/класі, у якому стоїть звернення. Хук ConstMissingHook
  #      перебирає можливі повні імена від найглибшого простору імен до
  #      верхнього (Engine::Item, WebDataCollector::Item, ...), знаходить
  #      файл у таблиці, підключає його і повертає константу.
  #   3. Файли, що визначають кілька констант (errors.rb), підключаються
  #      одразу (preload).
  # Отже, клас завантажується лише в момент першого звернення до нього.
  class Autoloader
    # Підмішується в Module, тож спрацьовує для будь-якого класу чи модуля;
    # чужі простори імен передаються далі стандартному const_missing.
    module ConstMissingHook
      def const_missing(name)
        Autoloader.resolve(self, name) { super }
      end
    end

    DEFAULT_INFLECTIONS = { "dsl" => "DSL" }.freeze

    @loaders = []
    @lock = Monitor.new

    class << self
      attr_reader :loaders

      def register(loader)
        @lock.synchronize do
          Module.prepend(ConstMissingHook) unless Module.ancestors.include?(ConstMissingHook)
          @loaders << loader unless @loaders.include?(loader)
        end
      end

      def unregister(loader)
        @lock.synchronize { @loaders.delete(loader) }
      end

      # Повертає константу або виконує блок (стандартна поведінка - NameError).
      def resolve(scope, name)
        candidates(scope, name).each do |full_name|
          loader = @loaders.find { |l| l.manages?(full_name) }
          return @lock.synchronize { loader.load_constant(full_name) } if loader
        end
        yield
      end

      # Для Engine та :Item -> ["WebDataCollector::Engine::Item", "WebDataCollector::Item", "Item"]
      def candidates(scope, name)
        parts = scope.equal?(Object) ? [] : scope.name.to_s.split("::")
        parts.size.downto(0).map { |i| (parts.first(i) + [name.to_s]).join("::") }
      end
    end

    attr_reader :root, :namespace, :mapping, :loaded

    # root      - каталог із файлами;
    # namespace - назва кореневого модуля ("WebDataCollector");
    # ignore    - файли, які не автозавантажуються (точка входу, сам автозавантажувач);
    # preload   - файли, що підключаються одразу;
    # logger    - куди писати, що і коли завантажено (опційно).
    def initialize(root:, namespace:, ignore: [], preload: [], inflections: {}, logger: nil)
      @root = File.expand_path(root)
      @namespace = namespace.to_s
      @ignore = ignore.map { |f| File.expand_path(f, @root) }
      @preload = preload.map { |f| File.expand_path(f, @root) }
      @inflections = DEFAULT_INFLECTIONS.merge(inflections)
      @logger = logger
      @mapping = {}
      @loaded = []
    end

    def setup
      scan
      self.class.register(self)
      @preload.each { |path| require path }
      self
    end

    def teardown
      self.class.unregister(self)
    end

    def manages?(full_name)
      @mapping.key?(full_name)
    end

    def loaded?(full_name)
      @loaded.include?(full_name)
    end

    # Підключає файл константи (або створює неявний модуль) і повертає її.
    def load_constant(full_name)
      parent_name, _, const_name = full_name.rpartition("::")
      parent = parent_name.empty? ? Object : Object.const_get(parent_name)
      return parent.const_get(const_name, false) if parent.const_defined?(const_name, false)

      target = @mapping.fetch(full_name)
      if target == :namespace
        parent.const_set(const_name, Module.new)
        log("created namespace #{full_name}")
      else
        require target
        unless parent.const_defined?(const_name, false)
          raise NameError, "autoloader: expected #{relative(target)} to define #{full_name}"
        end
        log("loaded #{full_name} from #{relative(target)}")
      end
      @loaded << full_name
      parent.const_get(const_name, false)
    end

    # Завантажує все одразу - для перевірки, що кожен файл визначає
    # очікувану константу (rake autoload:check).
    def eager_load!
      @mapping.keys.sort_by { |name| name.count(":") }.each { |name| Object.const_get(name) }
      self
    end

    # Ім'я константи для шляху відносно root.
    def constant_name_for(relative_path)
      segments = relative_path.sub(/\.rb\z/, "").split("/")
      ([@namespace] + segments.map { |s| camelize(s) }).join("::")
    end

    def camelize(segment)
      @inflections.fetch(segment) { segment.split("_").map(&:capitalize).join }
    end

    private

    def scan
      @mapping.clear
      Dir.glob("**/", base: @root).each do |dir|
        dir = dir.chomp("/")
        next if dir.empty?

        @mapping[constant_name_for(dir)] = :namespace
      end
      Dir.glob("**/*.rb", base: @root).each do |file|
        path = File.join(@root, file)
        next if @ignore.include?(path) || @preload.include?(path)

        # файл має пріоритет над однойменним каталогом (exporters.rb + exporters/)
        @mapping[constant_name_for(file)] = path
      end
    end

    def relative(path)
      path.delete_prefix("#{@root}/")
    end

    def log(message)
      @logger&.call("[autoload] #{message}")
    end
  end
end
