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

  it "changes values only through setters; merge returns a new item" do
    changed = item.merge(price: 5)
    expect(changed.price).to eq(5)
    expect(item.price).to eq(9.99)
    expect { item.attributes[:price] = 1 }.to raise_error(FrozenError)
    item.price = 7
    expect(item.price).to eq(7)
  end

  it "generates accessors for its own keys without method_missing" do
    expect(item.singleton_methods).to include(:title, :title=, :title?)
    expect(described_class.instance_methods(false)).not_to include(:title)
  end

  describe ".define_schema (getters/setters from YAML fields)" do
    let(:config) { WebDataCollector::Configurator.load(File.expand_path("../config/settings.yml", __dir__), env: {}) }
    let(:book_class) { described_class.define_schema(config.fields) }

    it "creates a subclass with getter, setter and predicate for every configured field" do
      expect(book_class.superclass).to eq(described_class)
      expect(book_class.attribute_names).to eq(%i[title price rating availability category url image_url])
      expect(book_class.instance_methods(false)).to include(:title, :title=, :title?, :price, :price=, :image_url?)
      expect(book_class.inspect).to eq("WebDataCollector::Item[title, price, rating, availability, category, url, image_url]")
    end

    it "does not add methods to the base Item class" do
      book_class
      expect(described_class.method_defined?(:title)).to be(false)
    end

    it "initializes every schema field, even when no value was given" do
      book = book_class.new(title: "Dune")
      expect(book.price).to be_nil
      expect(book.price?).to be(false)
      expect(book.fields).to eq(book_class.attribute_names)
    end

    it "normalizes string values written through setters using the field's normalizer" do
      book = book_class.new(title: "Dune")
      book.price = "£12.50"
      book.rating = "star-rating Four"
      book.title = "  Dune   Messiah "
      expect([book.price, book.rating, book.title]).to eq([12.5, 4, "Dune Messiah"])
      book.price = 3
      expect(book.price).to eq(3)
    end

    it "does not generate a setter for readonly fields" do
      book = book_class.new(url: "https://x.test/dune")
      expect(book).not_to respond_to(:url=)
      expect { book.url = "other" }.to raise_error(NoMethodError)
      expect { book[:url] = "other" }.to raise_error(WebDataCollector::ValidationError, /read-only/)
      expect(book.url).to eq("https://x.test/dune")
    end

    it "builds a schema from plain field names" do
      klass = described_class.define_schema(%i[name salary])
      person = klass.new(name: "Ann")
      person.salary = 100
      expect(person.to_h).to include(name: "Ann", salary: 100)
    end

    it "rejects field names that would override Item methods" do
      expect { described_class.define_schema(%i[hash]) }.to raise_error(WebDataCollector::ValidationError, /clashes/)
      expect { described_class.define_schema(%i[to_h]) }.to raise_error(WebDataCollector::ValidationError)
    end

    it "lets subclasses inherit and extend the schema" do
      extended = Class.new(book_class) { attribute :isbn }
      expect(extended.attribute_names.last).to eq(:isbn)
      expect(book_class.attribute_names).not_to include(:isbn)
    end
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
