pipeline "Дешеві детективи з високим рейтингом" do
  source "https://books.toscrape.com/catalogue/category/books/mystery_3/index.html", pages: 2, delay: 0.5

  extract each: "article.product_pod", next_page: "li.next a" do
    field :title,        selector: "h3 a", attribute: :title, required: true
    field :price,        selector: ".price_color", normalize: :price, required: true
    field :rating,       selector: "p.star-rating", attribute: :class, normalize: :rating
    field :availability, selector: ".availability"
    field :category,     selector: ".page-header h1", scope: :page
    field :url,          selector: "h3 a", attribute: :href, normalize: :url, required: true
    field(:in_stock, selector: ".availability") { |text| text.to_s.include?("In stock") }
  end

  filter :price do |value|
    value.to_f.positive? && value < 40
  end
  filter(:rating) { |rating| rating.to_i >= 3 }

  save_to :sqlite, path: "data/pipelines.sqlite3", table: "mystery_books"
  export :json, path: "output/mystery_books.json"
  export :csv,  path: "output/mystery_books.csv"
end

pipeline "Поезія: усі книжки, дорожчі за 20 фунтів" do
  source "https://books.toscrape.com/catalogue/category/books/poetry_23/index.html"

  extract each: "article.product_pod" do
    field :title, "h3 a", attribute: :title, required: true
    field :price, ".price_color", normalize: :price
    field :url,   "h3 a", attribute: :href, normalize: :url, required: true
  end

  where price: (20..)
  filter { |item| !item.title.empty? }

  save_to :sqlite, path: "data/pipelines.sqlite3", table: "poetry_books"
  export :yaml, path: "output/poetry_books.yaml"
end
