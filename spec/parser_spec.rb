# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe WebDataCollector::SimpleWebsiteParser do
  def build_parser(agent: books_agent, max_pages: 3, fields: book_fields, item_selector: "article.product_pod")
    described_class.new(item_selector: item_selector, fields: fields, next_page_selector: "li.next a",
                        max_pages: max_pages, logger: null_logger, agent: agent, retries: 0)
  end

  it "parses items from the page and follows pagination" do
    parser = build_parser
    items = parser.parse(CATEGORY_URL)
    expect(items.size).to eq(32)
    expect(parser.stats).to include(pages: 2, items: 32, skipped: 0)
  end

  it "normalizes values and resolves relative URLs" do
    item = build_parser.parse(CATEGORY_URL).first
    expect(item.title).to eq("Sharp Objects")
    expect(item.price).to eq(47.82)
    expect(item.rating).to eq(4)
    expect(item.category).to eq("Mystery")
    expect(item.url).to eq("https://books.toscrape.com/catalogue/sharp-objects_997/index.html")
  end

  it "respects max_pages" do
    agent = books_agent
    expect(build_parser(agent: agent, max_pages: 1).parse(CATEGORY_URL).size).to eq(20)
    expect(agent.requests).to eq([CATEGORY_URL])
  end

  it "returns an empty collection when the selector matches nothing" do
    items = build_parser(item_selector: "div.no-such-thing").parse(CATEGORY_URL)
    expect(items).to be_empty
  end

  it "skips records with missing required fields" do
    fields = book_fields + [WebDataCollector::FieldDefinition.new(:isbn, selector: ".isbn", required: true)]
    parser = build_parser(fields: fields, max_pages: 1)
    expect(parser.parse(CATEGORY_URL)).to be_empty
    expect(parser.stats[:skipped]).to eq(20)
  end

  it "sets missing optional fields to nil" do
    fields = book_fields + [WebDataCollector::FieldDefinition.new(:author, selector: ".author")]
    expect(build_parser(fields: fields).parse(CATEGORY_URL).first.author).to be_nil
  end

  it "raises NetworkError when the first page cannot be loaded" do
    agent = FakeAgent.new({}, errors: { CATEGORY_URL => SocketError.new("getaddrinfo failed") })
    expect { build_parser(agent: agent).parse(CATEGORY_URL) }
      .to raise_error(WebDataCollector::NetworkError, /getaddrinfo/)
  end

  it "raises NetworkError on HTTP errors" do
    expect { build_parser(agent: FakeAgent.new).parse(CATEGORY_URL) }
      .to raise_error(WebDataCollector::NetworkError, /404/)
  end

  it "keeps already collected items when a later page fails" do
    agent = FakeAgent.new({ CATEGORY_URL => fixture("mystery_page1.html") },
                          errors: { PAGE2_URL => Net::ReadTimeout.new })
    expect(build_parser(agent: agent).parse(CATEGORY_URL).size).to eq(20)
  end

  it "rejects invalid URLs before any request" do
    agent = books_agent
    expect { build_parser(agent: agent).parse("ftp://nope") }.to raise_error(WebDataCollector::NetworkError, /invalid/)
    expect(agent.requests).to be_empty
  end

  it "parses raw HTML" do
    items = build_parser.parse_html(fixture("mystery_page2.html"), base_url: PAGE2_URL)
    expect(items.size).to eq(12)
  end
end
