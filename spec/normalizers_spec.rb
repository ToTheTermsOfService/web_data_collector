# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe WebDataCollector::Normalizers do
  def norm(name, value, ctx = {})
    described_class.apply(name, value, ctx)
  end

  it "normalizes prices in different formats" do
    expect(norm(:price, "£51.77")).to eq(51.77)
    expect(norm(:price, "1 299,50 грн")).to eq(1299.5)
    expect(norm(:price, "free")).to be_nil
  end

  it "converts star-rating classes to numbers" do
    expect(norm(:rating, "star-rating Three")).to eq(3)
    expect(norm(:rating, "rating-5")).to eq(5)
  end

  it "squishes whitespace in text" do
    expect(norm(:text, "\n   In   stock \n")).to eq("In stock")
  end

  it "resolves relative URLs" do
    expect(norm(:url, "../x/index.html", base_url: "https://a.test/b/c/page.html")).to eq("https://a.test/b/x/index.html")
  end

  it "accepts custom callables" do
    expect(norm(->(v) { v.upcase }, "abc")).to eq("ABC")
  end
end

RSpec.describe WebDataCollector::FieldDefinition do
  it "validates name, selector, scope and normalizer" do
    expect { described_class.new("Bad Name", selector: "a") }.to raise_error(WebDataCollector::ValidationError, /name/)
    expect { described_class.new(:a, selector: "") }.to raise_error(WebDataCollector::ValidationError, /selector/)
    expect { described_class.new(:a, selector: "a[") }.to raise_error(WebDataCollector::ValidationError, /invalid CSS/)
    expect { described_class.new(:a, selector: "a", scope: :site) }.to raise_error(WebDataCollector::ValidationError, /scope/)
    expect { described_class.new(:a, selector: "a", normalize: :magic) }.to raise_error(WebDataCollector::ValidationError, /normalizer/)
  end
end
