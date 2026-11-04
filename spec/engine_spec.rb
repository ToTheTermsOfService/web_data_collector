# frozen_string_literal: true

require_relative "spec_helper"
require "json"

RSpec.describe WebDataCollector::Engine, :tmpdir do
  let(:config) do
    data = YAML.safe_load_file(File.expand_path("../config/settings.yml", __dir__))
    WebDataCollector::Configurator.new(data, root: @tmpdir, env: {})
  end

  def engine(agent: books_agent)
    described_class.new(config: config, logger: null_logger).tap do |e|
      e.instance_variable_set(:@parser, WebDataCollector::SimpleWebsiteParser.from_config(config, logger: null_logger, agent: agent))
    end
  end

  it "runs the full process: parse, save, export" do
    result = engine.run
    expect(result).to be_success
    expect(result.collected).to eq(32)
    expect(result.db_stats[:inserted]).to eq(32)

    exported = JSON.parse(File.read(result.export_path))
    expect(exported.size).to eq(32)
    expect(exported.first.keys).to include("title", "price", "url", "scraped_at")
    expect(File).to exist(File.join(@tmpdir, "data", "items.sqlite3"))
  end

  it "does not create duplicates on a second run" do
    engine.run
    second = engine.run
    expect(second.db_stats).to include(inserted: 0, updated: 32)
  end

  it "returns a failed result instead of crashing on network errors" do
    agent = FakeAgent.new({}, errors: { config.source_url => SocketError.new("no network") })
    result = engine(agent: agent).run
    expect(result).not_to be_success
    expect(result.error).to include("no network")
  end

  it "writes a log file with run details" do
    log_path = File.join(@tmpdir, "run.log")
    logger = WebDataCollector::AppLogger.build(file: log_path, stdout: false)
    e = described_class.new(config: config, logger: logger,
                            parser: WebDataCollector::SimpleWebsiteParser.from_config(config, logger: logger, agent: books_agent))
    e.run
    logger.close
    log = File.read(log_path)
    expect(log).to include("run started", config.source_url, "Collected 32 items", "inserted", "run finished")
  end
end
