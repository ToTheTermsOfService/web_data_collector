# web_data_collector

Ruby-застосунок для збору даних із вебресурсу, їх обробки, збереження в SQLite та експорту в JSON/CSV/YAML,
а також власна DSL для декларативного опису конвеєра обробки.

Лабораторна робота №1 з дисципліни «Мережеві інформаційні технології».

- **Частина I** — основний застосунок: `Item`, `ItemCollection`, `SimpleWebsiteParser`, `DatabaseConnector`,
  `Configurator`, `Engine`, логування, тести.
- **Частина II** — DSL (`pipeline … do … end`), що використовує компоненти Частини I.
- **Додаткові розширення** — експорт у CSV та YAML, окремий компонент `Configurator`, розширена модель
  (`Comparable`, `Enumerable`, фільтри з `Range`/`Regexp`).

## Швидкий старт

```bash
git clone <url-репозиторію> && cd web_data_collector
bundle install                                   # залежності (Ruby 3.1+)
bundle exec ruby main.rb                         # збір → SQLite → output/items.json
bundle exec ruby main.rb --dsl dsl/books_pipeline.rb   # конвеєри з DSL
bundle exec ruby main.rb --show 5                # що лежить у базі
bundle exec rspec                                # 77 тестів, офлайн
```

Результати: `output/` (JSON/CSV/YAML), `data/*.sqlite3` (бази), `logs/app.log` (журнал).

## Короткий аналіз

### Результати збору (категорія Mystery, 2 сторінки)

| Показник | Значення |
|----------|----------|
| Зібрано книжок | 32 (20 + 12), пропущено некоректних — 0 |
| Час запуску | ≈ 1.9 с (з паузою 0.5 с між запитами) |
| Ціна: мін / медіана / середня / макс | £10.69 / £25.40 / £31.72 / £59.48 |
| Розподіл цін | < £20 — 10, £20–40 — 11, ≥ £40 — 11 |
| Рейтинг (1★…5★) | 7 / 5 / 8 / 7 / 5 |
| Наявність | усі 32 «In stock» |
| Повторний запуск | 0 нових, 32 оновлено — дублікатів немає |

Найдешевша — *Tastes Like Fear* (£10.69), найдорожча — *Boar Island* (£59.48).
Зв'язку «дорожче = краще» немає: середня ціна книжок з 5★ (£32.27) майже така сама, як з 2★ (£32.26),
а найдорожчі в середньому книжки з 4★ (£43.74). Серед п'ятизіркових є і *The Girl You Lost* за £12.29.

DSL-конвеєри на тих самих даних:

| Конвеєр | Зібрано | Відфільтровано | Лишилось | Куди |
|---------|---------|----------------|----------|------|
| Детективи: ціна < £40 і рейтинг ≥ 3 | 32 | 21 | 11 | SQLite `mystery_books`, JSON + CSV |
| Поезія: ціна ≥ £20 | 19 | 4 | 15 | SQLite `poetry_books`, YAML |

### Що вдалося і які рішення прийнято

- **Поля не зашиті в код.** `Item` зберігає довільний набір атрибутів, а що саме витягати, описано в
  `config/settings.yml` або DSL. Інший сайт чи інше поле означає лише зміну конфігу.
- **Повторні запуски безпечні**, бо дублікати не з'являються: на `url` стоїть `UNIQUE`-індекс, а збереження
  працює як upsert в одній транзакції. Усі значення передаються в SQL параметрами.
- **Збої обробляються без падіння.** Мережеві помилки повторюються до 2 разів, зламана верстка дає
  попередження й порожній результат, некоректні записи пропускаються. Користувач бачить коротке
  повідомлення, а деталі пише журнал.
- **DSL не дублює логіку.** `PipelineRunner` використовує ті самі парсер, базу й експортери, що й `Engine`.
  Конфігурація конвеєра повністю перевіряється до першого HTTP-запиту, а `eval` рядків не використовується.
- **Тести не залежать від мережі.** Mechanize підмінюється `FakeAgent` зі збереженими сторінками.

### Обмеження

- Обхід сторінок послідовний; для великих каталогів варто додати паралельне завантаження.
- Збереження спершу перевіряє, чи є запис (SELECT, потім INSERT або UPDATE). Це дає точну статистику
  «нові/оновлені», але на тисячах записів повільніше за `INSERT … ON CONFLICT`.
- Сховище лише SQLite (MongoDB з методички як розширення не реалізовано).

## Вебресурс

[books.toscrape.com](https://books.toscrape.com) — навчальний каталог книжок, створений спеціально для практики
веб-скрапінгу (дані вигадані, персональних даних немає). Між запитами робиться пауза (`request_delay`).

За замовчуванням збирається категорія **Mystery** (2 сторінки, 32 книжки).

### Структура даних і селектори

| Поле           | CSS-селектор             | Звідки значення        | Нормалізація                    |
|----------------|--------------------------|------------------------|---------------------------------|
| `title`        | `h3 a`                   | атрибут `title`        | текст (обов'язкове)             |
| `price`        | `.price_color`           | текст (`£51.77`)       | `price` → `51.77` (обов'язкове) |
| `rating`       | `p.star-rating`          | атрибут `class`        | `rating`: `star-rating Three` → `3` |
| `availability` | `.availability`          | текст                  | текст                           |
| `category`     | `.page-header h1`        | заголовок сторінки     | текст (`scope: page`)           |
| `url`          | `h3 a`                   | атрибут `href`         | `url` → абсолютна адреса (обов'язкове, унікальний ключ) |
| `image_url`    | `.image_container img`   | атрибут `src`          | `url`                           |

Картка товару — `article.product_pod`, наступна сторінка — `li.next a`.
Якщо структура сторінки зміниться і селектор нічого не знайде, у журнал буде записано попередження
`No items found ... The page structure may have changed`, а не аварійне завершення.

## Вимоги

- Ruby **3.1+** (перевірено на Ruby 4.0.7, Windows x64)
- Bundler
- Доступ до інтернету для реального запуску (тести працюють офлайн)

## Встановлення

```bash
bundle install
```

## Конфігурація — `config/settings.yml`

| Секція        | Параметр                                  | Опис |
|---------------|-------------------------------------------|------|
| `application` | `name`, `log_level`, `log_file`            | назва, рівень (`debug`…`fatal`), файл журналу |
| `source`      | `url`, `timeout`, `max_pages`, `request_delay`, `user_agent` | адреса, тайм-аут, кількість сторінок, пауза між запитами |
| `selectors`   | `item`, `next_page`, `fields`              | селектор картки, пагінації та опис полів |
| `database`    | `adapter` (`sqlite`), `path`, `table`, `unique_key` | параметри SQLite і ключ для захисту від дублікатів |
| `output`      | `directory`, `format` (`json`/`csv`/`yaml`), `filename` | експорт |

Опис поля: `selector` (обов'язково), `attribute` (інакше береться текст), `normalize`
(`text`, `strip`, `integer`, `float`, `price`, `rating`, `url`), `required`, `scope` (`item`/`page`).

Під час завантаження конфігурація перевіряється (URL, наявність полів, підтримуваний адаптер і формат,
коректність селекторів). Відносні шляхи рахуються від кореня проєкту.
Параметри, специфічні для середовища, можна перевизначити змінними оточення без зміни файлу:
`WDC_SOURCE_URL`, `WDC_DATABASE_PATH`, `WDC_LOG_LEVEL`. Секретів у репозиторії немає.

## Запуск

```bash
ruby main.rb                              # основний процес за config/settings.yml
ruby main.rb --format csv --pages 1       # інший формат / кількість сторінок
ruby main.rb --show 5                     # показати записи з бази
ruby main.rb --dsl dsl/books_pipeline.rb  # конвеєри з DSL-файлу
ruby main.rb --help
```

Завдання Rake:

```bash
rake run          # основний процес
rake dsl          # DSL-конвеєри (rake "dsl[path/to/file.rb]")
rake csv          # експорт у CSV
rake db:show      # записи з бази
rake db:reset     # видалити бази
rake clean        # видалити output і logs
rake spec         # тести (rake за замовчуванням)
```

Каталоги `data/`, `output/`, `logs/` створюються автоматично.

## Приклад результату

```
[2026-10-29 18:40:04] INFO  web_data_collector: === web_data_collector: run started ===
[2026-10-29 18:40:04] INFO  web_data_collector: Source: https://books.toscrape.com/catalogue/category/books/mystery_3/index.html (max pages: 3)
[2026-10-29 18:40:05] INFO  web_data_collector: Page 1: .../mystery_3/index.html -> 20 items
[2026-10-29 18:40:06] INFO  web_data_collector: Page 2: .../mystery_3/page-2.html -> 12 items
[2026-10-29 18:40:06] INFO  web_data_collector: Collected 32 items (0 skipped as invalid)
[2026-10-29 18:40:06] INFO  web_data_collector: Saved to SQLite: 32 inserted, 0 updated (total rows in 'items': 32)
[2026-10-29 18:40:06] INFO  web_data_collector: Exported 32 items to .../output/items.json

Collected 32 items from 2 page(s) (0 skipped), 32 after processing; DB: 32 new, 0 updated; exported to .../output/items.json in 1.87s
```

Повторний запуск не створює дублікатів: `DB: 0 new, 32 updated`.

`output/items.json`:

```json
[
  {
    "category": "Mystery",
    "title": "1st to Die (Women's Murder Club #1)",
    "price": 53.98,
    "rating": 1,
    "availability": "In stock",
    "url": "https://books.toscrape.com/catalogue/1st-to-die-womens-murder-club-1_2/index.html",
    "image_url": "https://books.toscrape.com/media/cache/2b/41/2b4161c5b72a4ae386b644682361b34a.jpg",
    "scraped_at": "2026-10-29T18:40:15+02:00"
  }
]
```

## Архітектура

```
main.rb (CLI)
  ├── Engine ───────────── координує основний процес
  │     ├── Configurator ─ YAML + перевірка + FieldDefinition
  │     ├── SimpleWebsiteParser ─ Mechanize + Nokogiri → ItemCollection<Item>
  │     ├── DatabaseConnector ─── SQLite, upsert за unique_key
  │     └── Exporters ─────────── JSON / CSV / YAML
  └── DSL::Loader → PipelineBuilder → Pipeline → PipelineRunner
                                                   └── ті самі компоненти Частини I
```

| Файл | Призначення |
|------|-------------|
| `lib/item.rb` | запис із довільним набором атрибутів; доступ `item.title`, `item[:title]`, `to_h`; `Comparable` |
| `lib/item_collection.rb` | колекція з `Enumerable`: `add`, `find_by`, `where`, `sort_by_field`, `uniq_by`, `to_export` |
| `lib/field_definition.rb` | опис поля (селектор, атрибут, нормалізатор, обов'язковість) з перевіркою |
| `lib/normalizers.rb` | перетворення сирих рядків (ціна, рейтинг, URL…) |
| `lib/simple_website_parser.rb` | завантаження, пагінація, повторні спроби, витяг полів |
| `lib/database_connector.rb` | схема, збереження, читання; параметризовані SQL-запити |
| `lib/configurator.rb` | завантаження і валідація YAML |
| `lib/app_logger.rb` | Logger у файл + консоль |
| `lib/engine.rb` | основний процес і підсумок |
| `lib/exporters/` | експортери JSON, CSV, YAML |
| `lib/dsl/` | DSL: `PipelineBuilder`, `Pipeline`, `PipelineRunner`, `Loader` |

### Обробка помилок

Усі власні винятки успадковуються від `WebDataCollector::Error`:
`ConfigurationError`, `NetworkError`, `ParseError`, `DatabaseError`, `ExportError`, `ValidationError`.

- мережа: тайм-аути, DNS, HTTP 5xx/429 — до 2 повторних спроб; 4xx — одразу помилка;
  збій на наступній сторінці не втрачає вже зібрані дані;
- некоректна HTML-структура / відсутні елементи — запис без обов'язкового поля пропускається, решта полів → `nil`;
- база даних — винятки SQLite обгортаються в `DatabaseError`, збереження йде в транзакції;
- конфігурація — перелік усіх проблем одразу.

Користувач бачить коротке повідомлення, технічні подробиці пишуться в `logs/app.log`.

## Частина II — DSL

Файл `dsl/books_pipeline.rb`:

```ruby
pipeline "Дешеві детективи з високим рейтингом" do
  source "https://books.toscrape.com/catalogue/category/books/mystery_3/index.html", pages: 2, delay: 0.5

  extract each: "article.product_pod", next_page: "li.next a" do
    field :title,    selector: "h3 a", attribute: :title, required: true
    field :price,    selector: ".price_color", normalize: :price, required: true
    field :rating,   selector: "p.star-rating", attribute: :class, normalize: :rating
    field :category, selector: ".page-header h1", scope: :page
    field :url,      selector: "h3 a", attribute: :href, normalize: :url, required: true
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
```

### Конструкції

| Конструкція | Опис |
|-------------|------|
| `pipeline "назва" do … end` | новий конвеєр; у файлі їх може бути кілька |
| `source url, pages:, delay:, timeout:` | джерело; URL перевіряється до запуску |
| `pages n`, `delay s`, `next_page "css"` | окремі параметри обходу |
| `extract each: "css", next_page: "css" do … end` | селектор картки і блок полів |
| `field :name, selector:, attribute:, normalize:, required:, scope:` | поле; скорочено `field :name, "css"`; власний нормалізатор — блок |
| `filter(:field) { \|value\| … }` | фільтр за значенням поля |
| `filter(:field) { \|value, item\| … }` | те саме з доступом до всього запису |
| `filter { \|item\| … }` | фільтр на рівні запису |
| `filter :field, matcher` / `where field: matcher` | без блоку: `Range`, `Regexp`, `Array` або точне значення |
| `save_to :sqlite, path:, table:, unique_key:` | збереження через `DatabaseConnector` Частини I |
| `export :json \| :csv \| :yaml, path:` | експорт; можна кілька |

### Як працює фільтрація

Фільтри застосовуються послідовно, у порядку оголошення (логічне «І»). На наступний етап
(збереження, експорт) потрапляють лише записи, для яких **усі** фільтри повернули істинне значення.
Польовий фільтр отримує значення поля (уже нормалізоване, наприклад `price` — число), а
`nil`, якщо поле не знайдено. Якщо блок фільтра кидає виняток, цей запис відкидається,
а попередження пишеться в журнал — конвеєр не зупиняється. У журналі видно, скільки записів пройшло
кожен фільтр: `Filter 'filter on :price': 32 -> 19`.

### Виконання

`DSL::Loader` підключає файл через `Kernel#load` з модулем-обгорткою: на верхньому рівні файлу
доступний метод `pipeline`, а блоки виконуються через `instance_eval(&block)` на об'єкті-будівнику.
**`eval` для рядків не використовується.**

`PipelineRunner` виконує етапи `validate → parse → filter → save → export` і використовує
`SimpleWebsiteParser`, `ItemCollection`, `DatabaseConnector` та `Exporters` з Частини I.
Помилка етапу зупиняє конвеєр, а в результаті вказано, на якому саме етапі вона сталася.

### Валідація

Перед запуском перевіряються: наявність і коректність URL, селектор картки, наявність полів, дублікати
полів, синтаксис CSS-селекторів, відомі нормалізатори, фільтри лише на наявні поля, підтримуваний тип
сховища, коректна назва таблиці, унікальний ключ серед полів, формат експорту, відповідність розширення
формату, шлях експорту (не каталог, батьківський шлях можна створити). Усі помилки виводяться одним списком.

### Результат запуску

```
$ ruby main.rb --dsl dsl/books_pipeline.rb
Pipeline 'Дешеві детективи з високим рейтингом': 32 collected, 21 filtered out, 11 kept; saved [mystery_books: +11 new / 0 updated]; exported [output/mystery_books.json, output/mystery_books.csv]
Pipeline 'Поезія: усі книжки, дорожчі за 20 фунтів': 19 collected, 4 filtered out, 15 kept; saved [poetry_books: +15 new / 0 updated]; exported [output/poetry_books.yaml]
```

## Тести

```bash
bundle exec rspec        # або: rake
```

77 тестів (RSpec). Тести не ходять у мережу: `FakeAgent` підміняє Mechanize і віддає збережені сторінки
з `spec/fixtures/`. Покрито:

- `Item`, `ItemCollection` — доступ до атрибутів, фільтрація, сортування, порожня колекція, некоректні об'єкти;
- `Normalizers`, `FieldDefinition` — формати цін/рейтингів/URL, некоректні селектори;
- `SimpleWebsiteParser` — парсинг, пагінація, `max_pages`, відсутні поля, мережеві та HTTP-помилки;
- `DatabaseConnector` — збереження, читання, захист від дублікатів, SQL-ін'єкції, нові колонки, помилки SQLite;
- `Configurator` — завантаження, змінні оточення, некоректна конфігурація;
- `Exporters` — JSON/CSV/YAML, некоректні шляхи й формати;
- `Engine` — повний цикл, повторний запуск, мережеві помилки, журнал;
- DSL — побудова конфігурації, усі правила валідації, фільтрація, запуск парсера, збереження й експорт,
  помилки етапів, синтаксичні помилки DSL-файлу.

## Структура проєкту

```
web_data_collector/
├── Gemfile, Gemfile.lock, Rakefile, README.md, main.rb
├── config/settings.yml
├── lib/
│   ├── web_data_collector.rb
│   ├── item.rb, item_collection.rb, field_definition.rb, normalizers.rb
│   ├── simple_website_parser.rb, database_connector.rb
│   ├── configurator.rb, app_logger.rb, engine.rb, errors.rb
│   ├── exporters.rb, exporters/{base,json,csv,yaml}_exporter.rb
│   └── dsl/{pipeline,pipeline_builder,pipeline_runner,loader}.rb
├── dsl/books_pipeline.rb
├── spec/ (+ fixtures/)
├── data/  output/  logs/   (генеруються, не в git)
```
