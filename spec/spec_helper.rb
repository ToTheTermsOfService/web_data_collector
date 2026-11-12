# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "mechanize"
require_relative "../lib/web_data_collector"

FIXTURES = File.expand_path("fixtures", __dir__)
CATEGORY_URL = "https://books.toscrape.com/catalogue/category/books/mystery_3/index.html"
PAGE2_URL = "https://books.toscrape.com/catalogue/category/books/mystery_3/page-2.html"

class FakeAgent
  FakePage = Struct.new(:parser, :uri)

  attr_reader :requests

  def initialize(pages = {}, errors: {})
    @pages = pages
    @errors = errors
    @requests = []
  end

  def get(url)
    @requests << url
    raise @errors[url] if @errors.key?(url)
    raise Mechanize::ResponseCodeError.new(Struct.new(:code).new("404"), "not found") unless @pages.key?(url)

    FakePage.new(Nokogiri::HTML(@pages[url]), URI(url))
  end
end

def fixture(name)
  File.read(File.join(FIXTURES, name), encoding: "UTF-8")
end

def books_agent
  FakeAgent.new({ CATEGORY_URL => fixture("mystery_page1.html"), PAGE2_URL => fixture("mystery_page2.html") })
end

def book_fields
  [
    WebDataCollector::FieldDefinition.new(:title, selector: "h3 a", attribute: "title", required: true),
    WebDataCollector::FieldDefinition.new(:price, selector: ".price_color", normalize: :price, required: true),
    WebDataCollector::FieldDefinition.new(:rating, selector: "p.star-rating", attribute: "class", normalize: :rating),
    WebDataCollector::FieldDefinition.new(:category, selector: ".page-header h1", scope: :page),
    WebDataCollector::FieldDefinition.new(:url, selector: "h3 a", attribute: "href", normalize: :url, required: true)
  ]
end

def null_logger
  WebDataCollector::AppLogger.null
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random

  config.around(:each, :tmpdir) do |example|
    Dir.mktmpdir("wdc-spec") do |dir|
      @tmpdir = dir
      example.run
    end
  end
end
