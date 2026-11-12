# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe WebDataCollector::Autoloader, :tmpdir do
  # Окремий маленький "проєкт" у тимчасовому каталозі, щоб перевіряти
  # саме ліниве завантаження, незалежно від уже завантажених класів бібліотеки.
  def write(path, code)
    full = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, code)
  end

  let(:messages) { [] }
  let(:loader) do
    described_class.new(root: @tmpdir, namespace: "AutoloadDemo", logger: ->(m) { messages << m })
  end

  before do
    Object.const_set(:AutoloadDemo, Module.new)
    write("greeter.rb", "module AutoloadDemo; class Greeter; def hi = Formatter.new.call('hi'); end; end")
    write("formatter.rb", "module AutoloadDemo; class Formatter; def call(s) = s.upcase; end; end")
    write("reports/daily_report.rb", "module AutoloadDemo; module Reports; class DailyReport; end; end; end")
    write("dsl/json_api.rb", "module AutoloadDemo; module DSL; class JsonApi; end; end; end")
    write("broken.rb", "module AutoloadDemo; class Wrong; end; end")
    loader.setup
  end

  after do
    loader.teardown
    Object.send(:remove_const, :AutoloadDemo)
  end

  it "maps file paths to constant names" do
    expect(loader.mapping).to include(
      "AutoloadDemo::Greeter" => File.join(@tmpdir, "greeter.rb"),
      "AutoloadDemo::Reports" => :namespace,
      "AutoloadDemo::Reports::DailyReport" => File.join(@tmpdir, "reports/daily_report.rb"),
      "AutoloadDemo::DSL::JsonApi" => File.join(@tmpdir, "dsl/json_api.rb")
    )
  end

  it "camelizes with inflections" do
    expect(loader.constant_name_for("exporters/json_exporter.rb")).to eq("AutoloadDemo::Exporters::JsonExporter")
    expect(loader.constant_name_for("dsl/pipeline_builder.rb")).to eq("AutoloadDemo::DSL::PipelineBuilder")
  end

  it "loads a class lazily on first reference" do
    expect(AutoloadDemo.const_defined?(:Greeter, false)).to be(false)
    expect(AutoloadDemo::Greeter).to be_a(Class)
    expect(loader.loaded?("AutoloadDemo::Greeter")).to be(true)
    expect(loader.loaded?("AutoloadDemo::Formatter")).to be(false)
  end

  it "resolves constants referenced from inside other classes" do
    expect(AutoloadDemo::Greeter.new.hi).to eq("HI")
    expect(loader.loaded).to eq(%w[AutoloadDemo::Greeter AutoloadDemo::Formatter])
    expect(messages.first).to include("loaded AutoloadDemo::Greeter from greeter.rb")
  end

  it "creates modules for directories without a file (implicit namespaces)" do
    expect(AutoloadDemo::Reports).to be_a(Module)
    expect(AutoloadDemo::Reports::DailyReport).to be_a(Class)
  end

  it "raises a clear error when a file does not define the expected constant" do
    expect { AutoloadDemo::Broken }.to raise_error(NameError, /expected broken.rb to define AutoloadDemo::Broken/)
  end

  it "keeps the standard NameError for unknown constants" do
    expect { AutoloadDemo::Missing }.to raise_error(NameError, /uninitialized constant AutoloadDemo::Missing/)
  end

  it "does not interfere with other namespaces" do
    expect { NoSuchTopLevelThing }.to raise_error(NameError)
  end
end

RSpec.describe "WebDataCollector autoloading" do
  it "maps every library file to a constant and eager-loads without errors" do
    loader = WebDataCollector.loader
    expect(loader.mapping.keys).to include("WebDataCollector::Engine", "WebDataCollector::DSL",
                                           "WebDataCollector::DSL::PipelineRunner",
                                           "WebDataCollector::Exporters::CsvExporter")
    expect { loader.eager_load! }.not_to raise_error
  end
end
