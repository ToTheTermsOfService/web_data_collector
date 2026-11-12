# frozen_string_literal: true

require "monitor"

module WebDataCollector
  class Autoloader
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

      def resolve(scope, name)
        candidates(scope, name).each do |full_name|
          loader = @loaders.find { |l| l.manages?(full_name) }
          return @lock.synchronize { loader.load_constant(full_name) } if loader
        end
        yield
      end

      def candidates(scope, name)
        parts = scope.equal?(Object) ? [] : scope.name.to_s.split("::")
        parts.size.downto(0).map { |i| (parts.first(i) + [name.to_s]).join("::") }
      end
    end

    attr_reader :root, :namespace, :mapping, :loaded

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

    def eager_load!
      @mapping.keys.sort_by { |name| name.count(":") }.each { |name| Object.const_get(name) }
      self
    end

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
