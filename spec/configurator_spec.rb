# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe WebDataCollector::Configurator do
  let(:settings_path) { File.expand_path("../config/settings.yml", __dir__) }
  let(:base) { YAML.safe_load_file(settings_path) }

  def build(data, env: {})
    described_class.new(data, root: "/project", env: env)
  end

  it "loads the project configuration" do
    config = described_class.load(settings_path, env: {})
    expect(config.source_url).to start_with("https://books.toscrape.com")
    expect(config.fields.map(&:name)).to include(:title, :price, :url)
    expect(config.output_format).to eq("json")
  end

  it "resolves relative paths against the project root" do
    expect(build(base).database_path).to eq(File.expand_path("data/items.sqlite3", "/project"))
  end

  it "allows overriding values via environment variables" do
    config = build(base, env: { "WDC_SOURCE_URL" => "https://example.org/list" })
    expect(config.source_url).to eq("https://example.org/list")
  end

  it "reports all missing or invalid parameters" do
    data = base.merge("source" => { "url" => "not a url" }, "output" => { "format" => "xml" })
    expect { build(data) }.to raise_error(WebDataCollector::ConfigurationError) do |e|
      expect(e.message).to include("http(s) URL", "output.format 'xml'")
    end
  end

  it "rejects a configuration without fields" do
    data = base.merge("selectors" => { "item" => "article" })
    expect { build(data) }.to raise_error(WebDataCollector::ConfigurationError, /at least one field/)
  end

  it "rejects unsupported database adapters" do
    data = base.merge("database" => base["database"].merge("adapter" => "oracle"))
    expect { build(data) }.to raise_error(WebDataCollector::ConfigurationError, /oracle/)
  end

  it "rejects invalid field definitions" do
    data = Marshal.load(Marshal.dump(base))
    data["selectors"]["fields"]["price"]["normalize"] = "magic"
    expect { build(data) }.to raise_error(WebDataCollector::ConfigurationError, /unknown normalizer/)
  end

  it "fails clearly for a missing file" do
    expect { described_class.load("nope.yml") }.to raise_error(WebDataCollector::ConfigurationError, /not found/)
  end
end
