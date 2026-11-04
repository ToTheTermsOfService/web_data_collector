# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe WebDataCollector::Item do
  subject(:item) { described_class.new(title: "Dune", price: 9.99, url: "https://x.test/dune") }

  it "provides access to attributes by method, symbol and string" do
    expect(item.title).to eq("Dune")
    expect(item[:price]).to eq(9.99)
    expect(item["url"]).to eq("https://x.test/dune")
  end

  it "raises NoMethodError for unknown attributes" do
    expect { item.author }.to raise_error(NoMethodError)
    expect(item.respond_to?(:title)).to be(true)
    expect(item.respond_to?(:author)).to be(false)
  end

  it "converts to a hash with scraped_at timestamp" do
    expect(item.to_h).to include(title: "Dune", price: 9.99)
    expect(item.to_h[:scraped_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
  end

  it "is immutable; merge returns a new item" do
    changed = item.merge(price: 5)
    expect(changed.price).to eq(5)
    expect(item.price).to eq(9.99)
    expect { item.attributes[:price] = 1 }.to raise_error(FrozenError)
  end

  it "restores from a hash" do
    copy = described_class.from_h(item.to_h)
    expect(copy).to eq(item)
  end

  it "has a readable string representation" do
    expect(item.to_s).to eq("Item(title: Dune, price: 9.99, url: https://x.test/dune)")
  end

  it "rejects non-hash input" do
    expect { described_class.new("oops") }.to raise_error(ArgumentError)
  end
end
