# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe WebDataCollector::ItemCollection do
  let(:items) do
    [
      WebDataCollector::Item.new(title: "B", price: 20.0, rating: 4, url: "u2"),
      WebDataCollector::Item.new(title: "A", price: 10.0, rating: 5, url: "u1"),
      WebDataCollector::Item.new(title: "C", price: 30.0, rating: 1, url: "u3")
    ]
  end
  let(:collection) { described_class.new(items) }

  it "adds items and reports size" do
    expect(collection.size).to eq(3)
    collection << WebDataCollector::Item.new(title: "D", url: "u4")
    expect(collection.size).to eq(4)
  end

  it "rejects objects that are not Item" do
    expect { collection.add("not an item") }.to raise_error(ArgumentError, /expected Item/)
  end

  it "is Enumerable" do
    expect(collection.map(&:title)).to eq(%w[B A C])
    expect(collection.sum(&:price)).to eq(60.0)
  end

  it "finds by conditions or block" do
    expect(collection.find_by(title: "A").url).to eq("u1")
    expect(collection.find_by { |i| i.price > 25 }.title).to eq("C")
    expect(collection.find_by(title: "Z")).to be_nil
  end

  it "filters with ranges, regexps and blocks, returning a collection" do
    result = collection.where(rating: 4..5) { |i| i.price < 15 }
    expect(result).to be_a(described_class)
    expect(result.map(&:title)).to eq(["A"])
    expect(collection.where(title: /[BC]/).size).to eq(2)
  end

  it "sorts by field in both directions" do
    expect(collection.sort_by_field(:price).map(&:title)).to eq(%w[A B C])
    expect(collection.sort_by_field(:price, direction: :desc).map(&:title)).to eq(%w[C B A])
  end

  it "removes duplicates by key" do
    collection << WebDataCollector::Item.new(title: "A again", url: "u1")
    expect(collection.uniq_by(:url).size).to eq(3)
  end

  it "removes items" do
    collection.remove(items.first)
    expect(collection.size).to eq(2)
  end

  it "converts to an export-ready array of hashes" do
    expect(collection.to_export.first).to include(title: "B", price: 20.0)
  end

  it "handles an empty collection" do
    empty = described_class.new
    expect(empty).to be_empty
    expect(empty.to_export).to eq([])
    expect(empty.where(price: 1..2).size).to eq(0)
    expect(empty.first).to be_nil
    expect(empty.fields).to eq([])
  end
end
