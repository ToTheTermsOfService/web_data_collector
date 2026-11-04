# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe WebDataCollector::DatabaseConnector, :tmpdir do
  let(:db) { described_class.new(path: File.join(@tmpdir, "test.sqlite3"), table: "books", logger: null_logger) }
  let(:collection) do
    WebDataCollector::ItemCollection.new([
      WebDataCollector::Item.new(title: "A", price: 10.5, url: "https://x.test/a"),
      WebDataCollector::Item.new(title: "B", price: 20.0, url: "https://x.test/b")
    ])
  end

  after { db.close }

  it "creates the table and saves items" do
    stats = db.prepare_schema(%i[title price url]).save(collection)
    expect(stats).to eq(inserted: 2, updated: 0, skipped: 0)
    expect(db.count).to eq(2)
    expect(db.table_exists?).to be(true)
  end

  it "reads items back as an ItemCollection" do
    db.save(collection)
    stored = db.all
    expect(stored).to be_a(WebDataCollector::ItemCollection)
    expect(stored.map(&:title)).to eq(%w[A B])
    expect(stored.first.price).to eq(10.5)
    expect(db.find("https://x.test/b").title).to eq("B")
    expect(db.all(limit: 1).size).to eq(1)
  end

  it "does not duplicate records on repeated save (upsert by unique key)" do
    db.save(collection)
    changed = WebDataCollector::ItemCollection.new([
      WebDataCollector::Item.new(title: "A (2nd ed.)", price: 12.0, url: "https://x.test/a")
    ])
    expect(db.save(changed)).to eq(inserted: 0, updated: 1, skipped: 0)
    expect(db.count).to eq(2)
    expect(db.find("https://x.test/a").title).to eq("A (2nd ed.)")
  end

  it "skips items without the unique key" do
    no_url = WebDataCollector::ItemCollection.new([WebDataCollector::Item.new(title: "X", url: nil)])
    db.prepare_schema(%i[title url])
    expect(db.save(no_url)[:skipped]).to eq(1)
    expect(db.count).to eq(0)
  end

  it "adds columns for new fields" do
    db.save(collection)
    extra = WebDataCollector::ItemCollection.new([WebDataCollector::Item.new(title: "C", url: "c", rating: 5)])
    db.save(extra)
    expect(db.find("c").rating).to eq(5)
  end

  it "stores malicious-looking values safely (parameterized queries)" do
    evil = WebDataCollector::Item.new(title: "x'); DROP TABLE books; --", url: "evil")
    db.save(WebDataCollector::ItemCollection.new([evil]))
    expect(db.find("evil").title).to eq("x'); DROP TABLE books; --")
    expect(db.table_exists?).to be(true)
  end

  it "rejects unsafe identifiers" do
    expect { described_class.new(path: "x.db", table: "books; DROP") }.to raise_error(WebDataCollector::DatabaseError)
  end

  it "wraps SQLite errors in DatabaseError" do
    bad = described_class.new(path: @tmpdir, table: "t", logger: null_logger) # каталог замість файлу
    expect { bad.prepare_schema(%i[url]) }.to raise_error(WebDataCollector::DatabaseError)
  end

  it "returns empty results when the table does not exist yet" do
    expect(db.count).to eq(0)
    expect(db.all).to be_empty
  end
end
