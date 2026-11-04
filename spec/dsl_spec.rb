# frozen_string_literal: true

require_relative "spec_helper"
require "json"

RSpec.describe "Pipeline DSL", :tmpdir do
  def define(&block)
    WebDataCollector::DSL::Loader.define("Test pipeline", root: @tmpdir, &block)
  end

  def books_pipeline(&extra)
    define do
      source CATEGORY_URL, pages: 2
      extract each: "article.product_pod", next_page: "li.next a" do
        field :title, selector: "h3 a", attribute: :title, required: true
        field :price, selector: ".price_color", normalize: :price
        field :rating, selector: "p.star-rating", attribute: :class, normalize: :rating
        field :url, selector: "h3 a", attribute: :href, normalize: :url, required: true
      end
      instance_eval(&extra) if extra
    end
  end

  def run(pipeline, agent: books_agent)
    WebDataCollector::DSL::PipelineRunner.new(pipeline, logger: null_logger, agent: agent).run
  end

  describe "building the configuration" do
    it "stores every DSL parameter in the Pipeline object" do
      pipeline = books_pipeline do
        delay 0.25
        filter(:price) { |p| p < 30 }
        filter { |item| item.rating >= 3 }
        save_to :sqlite, path: "db/books.sqlite3", table: "books"
        export :json, path: "out/books.json"
        export :csv, path: "out/books.csv"
      end

      expect(pipeline).to be_a(WebDataCollector::DSL::Pipeline)
      expect(pipeline.name).to eq("Test pipeline")
      expect(pipeline.source_url).to eq(CATEGORY_URL)
      expect(pipeline.max_pages).to eq(2)
      expect(pipeline.request_delay).to eq(0.25)
      expect(pipeline.item_selector).to eq("article.product_pod")
      expect(pipeline.next_page_selector).to eq("li.next a")
      expect(pipeline.field_names).to eq(%i[title price rating url])
      expect(pipeline.fields.first.attribute).to eq("title")
      expect(pipeline.filters.map(&:field)).to eq([:price, nil])
      expect(pipeline.storages.first.to_h).to include(type: :sqlite, table: "books", unique_key: :url,
                                                      path: File.join(@tmpdir, "db", "books.sqlite3"))
      expect(pipeline.exports.map(&:format)).to eq(%i[json csv])
      expect(pipeline).to be_valid
    end

    it "supports the short field form and custom normalizer blocks" do
      pipeline = define do
        source "https://example.org"
        extract each: ".row" do
          field :name, ".title"
          field(:upper, selector: ".title") { |v| v.upcase }
        end
      end
      expect(pipeline.fields.map(&:selector)).to eq([".title", ".title"])
      expect(pipeline.fields.last.normalize).to respond_to(:call)
    end
  end

  describe "validation" do
    it "reports a missing source and missing fields" do
      pipeline = define { save_to :sqlite }
      expect(pipeline.errors).to include(a_string_matching(/source URL is missing/), a_string_matching(/no fields/))
      expect { pipeline.validate! }.to raise_error(WebDataCollector::ValidationError)
    end

    it "rejects an invalid URL" do
      pipeline = books_pipeline { source "javascript:alert(1)" }
      expect(pipeline.errors.join).to include("not a valid http(s) URL")
    end

    it "rejects invalid selectors and field options immediately" do
      expect do
        define { extract(each: "a") { field :bad, selector: "div[" } }
      end.to raise_error(WebDataCollector::ValidationError, /invalid CSS selector/)
      expect do
        define { extract(each: "a") { field :x, selector: "a", normalize: :unknown } }
      end.to raise_error(WebDataCollector::ValidationError, /unknown normalizer/)
    end

    it "rejects unsupported storage and export formats" do
      pipeline = books_pipeline do
        save_to :mongodb, table: "x"
        export :xml, path: "out/x.xml"
      end
      expect(pipeline.errors).to include(a_string_matching(/unsupported storage :mongodb/),
                                         a_string_matching(/unsupported export format :xml/))
    end

    it "rejects incorrect export paths" do
      File.write(File.join(@tmpdir, "file"), "")
      pipeline = books_pipeline do
        export :json, path: "out/data.csv"
        export :csv, path: "file/inside.csv"
      end
      expect(pipeline.errors).to include(a_string_matching(/does not match format/), a_string_matching(/cannot be created/))
    end

    it "rejects filters on unknown fields and a unique key that is not a field" do
      pipeline = books_pipeline do
        filter(:author) { true }
        save_to :sqlite, unique_key: :isbn
      end
      expect(pipeline.errors).to include(a_string_matching(/unknown field :author/), a_string_matching(/unique key :isbn/))
    end

    it "does not run anything when the configuration is invalid" do
      agent = books_agent
      result = run(define { source "https://example.org" }, agent: agent)
      expect(result).not_to be_success
      expect(result.stage).to eq(:validate)
      expect(agent.requests).to be_empty
    end
  end

  describe "execution" do
    it "runs the existing parser, filters, saves to SQLite and exports" do
      pipeline = books_pipeline do
        filter(:price) { |price| price < 30 }
        where rating: 3..5
        save_to :sqlite, path: "data/test.sqlite3", table: "cheap_books"
        export :json, path: "output/cheap.json"
      end
      result = run(pipeline)

      expect(result).to be_success
      expect(result.collected).to eq(32)
      expect(result.items).to all(satisfy { |i| i.price < 30 && i.rating >= 3 })
      expect(result.filtered_out).to eq(32 - result.items.size)
      expect(result.db_stats.first).to include(table: "cheap_books", inserted: result.items.size)

      db = WebDataCollector::DatabaseConnector.new(path: File.join(@tmpdir, "data/test.sqlite3"), table: "cheap_books")
      expect(db.count).to eq(result.items.size)
      db.close
      expect(JSON.parse(File.read(result.exported.first)).size).to eq(result.items.size)
    end

    it "passes the whole item to two-argument filters" do
      pipeline = books_pipeline { filter(:price) { |price, item| price > 50 && item.title.start_with?("1st") } }
      expect(run(pipeline).items.map(&:title)).to eq(["1st to Die (Women's Murder Club #1)"])
    end

    it "drops a record when its filter raises, without stopping the pipeline" do
      pipeline = books_pipeline { filter(:title) { |t| raise "boom" if t.start_with?("S"); true } }
      result = run(pipeline)
      expect(result).to be_success
      expect(result.items.map(&:title)).not_to include("Sharp Objects")
    end

    it "reports the failing stage on network errors" do
      agent = FakeAgent.new({}, errors: { CATEGORY_URL => SocketError.new("offline") })
      result = run(books_pipeline, agent: agent)
      expect(result.stage).to eq(:parse)
      expect(result.error).to include("offline")
    end

    it "reports the failing stage on export errors" do
      FileUtils.mkdir_p(File.join(@tmpdir, "taken.json"))
      result = run(books_pipeline { export :json, path: "taken.json" })
      expect(result.stage).to eq(:validate)
    end
  end

  describe "loading DSL files" do
    it "loads the demo DSL file" do
      pipelines = WebDataCollector::DSL::Loader.load_file(File.expand_path("../dsl/books_pipeline.rb", __dir__), root: @tmpdir)
      expect(pipelines.size).to eq(2)
      expect(pipelines).to all(be_valid)
    end

    it "reports syntax errors and unknown DSL keywords clearly" do
      broken = File.join(@tmpdir, "broken.rb")
      File.write(broken, "pipeline 'x' do\n  source 'https://a.test'\n")
      expect { WebDataCollector::DSL::Loader.load_file(broken) }.to raise_error(WebDataCollector::ValidationError, /syntax error/)

      unknown = File.join(@tmpdir, "unknown.rb")
      File.write(unknown, "pipeline 'x' do\n  sourse 'https://a.test'\nend\n")
      expect { WebDataCollector::DSL::Loader.load_file(unknown) }.to raise_error(WebDataCollector::ValidationError, /sourse/)
    end

    it "rejects files without pipelines or with a wrong extension" do
      empty = File.join(@tmpdir, "empty.rb")
      File.write(empty, "# nothing\n")
      expect { WebDataCollector::DSL::Loader.load_file(empty) }.to raise_error(WebDataCollector::ValidationError, /does not define/)
      expect { WebDataCollector::DSL::Loader.load_file("dsl.txt") }.to raise_error(WebDataCollector::ValidationError)
    end
  end
end
