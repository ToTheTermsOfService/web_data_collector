# frozen_string_literal: true

require_relative "spec_helper"
require "json"
require "csv"

RSpec.describe WebDataCollector::Exporters, :tmpdir do
  let(:collection) do
    WebDataCollector::ItemCollection.new([
      WebDataCollector::Item.new(title: "Кобзар", price: 10.0, url: "u1"),
      WebDataCollector::Item.new(title: "B, \"quoted\"", price: 2.5, url: "u2")
    ])
  end

  it "exports JSON" do
    path = described_class.for(:json).export(collection, File.join(@tmpdir, "out", "items.json"))
    data = JSON.parse(File.read(path, encoding: "UTF-8"))
    expect(data.map { |r| r["title"] }).to eq(["Кобзар", "B, \"quoted\""])
  end

  it "exports CSV with headers and proper quoting" do
    path = described_class.for("csv").export(collection, File.join(@tmpdir, "items.csv"))
    rows = CSV.read(path, headers: true, encoding: "UTF-8")
    expect(rows.headers).to include("title", "price", "url")
    expect(rows[1]["title"]).to eq("B, \"quoted\"")
  end

  it "exports YAML" do
    path = described_class.for(:yaml).export(collection, File.join(@tmpdir, "items.yaml"))
    expect(YAML.safe_load_file(path).first["price"]).to eq(10.0)
  end

  it "rejects unsupported formats" do
    expect { described_class.for(:xml) }.to raise_error(WebDataCollector::ExportError, /unsupported/)
  end

  it "rejects paths with a mismatched extension or pointing to a directory" do
    exporter = described_class.for(:json)
    expect { exporter.export(collection, File.join(@tmpdir, "x.csv")) }.to raise_error(WebDataCollector::ExportError)
    expect { exporter.export(collection, @tmpdir) }.to raise_error(WebDataCollector::ExportError)
    expect { exporter.export(collection, "") }.to raise_error(WebDataCollector::ExportError)
  end
end
