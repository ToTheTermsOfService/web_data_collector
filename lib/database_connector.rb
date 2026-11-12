# frozen_string_literal: true

require "sqlite3"
require "fileutils"
require "logger"
require "time"

module WebDataCollector
  class DatabaseConnector
    IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/
    SERVICE_COLUMNS = %w[id scraped_at created_at updated_at].freeze

    attr_reader :path, :table, :unique_key

    def initialize(path:, table: "items", unique_key: :url, logger: nil)
      raise DatabaseError, "database path is required" if path.nil? || path.to_s.strip.empty?

      @path = path
      @table = identifier!(table, "table")
      @unique_key = identifier!(unique_key, "unique key")
      @logger = logger || Logger.new(File::NULL)
      @db = nil
      @columns = nil
    end

    def connect
      return self if @db

      FileUtils.mkdir_p(File.dirname(path)) unless path == ":memory:"
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = true
      @db.busy_timeout = 5000
      @logger.debug("Connected to SQLite database #{path}")
      self
    rescue SQLite3::Exception, SystemCallError => e
      raise DatabaseError, "cannot open database #{path}: #{e.message}"
    end

    def close
      @db&.close
      @db = nil
      @columns = nil
    end

    def prepare_schema(field_names)
      columns = field_names.map { |f| identifier!(f, "column") }.uniq - SERVICE_COLUMNS
      raise DatabaseError, "unique key '#{unique_key}' is not among fields: #{columns.join(', ')}" unless columns.include?(unique_key)

      with_errors("prepare schema") do
        definitions = columns.map { |c| c == unique_key ? "#{quote(c)} TEXT NOT NULL" : quote(c) }
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS #{quote(table)} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            #{definitions.join(",\n  ")},
            scraped_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        SQL
        (columns - table_columns).each do |column|
          @logger.info("Adding column '#{column}' to table '#{table}'")
          db.execute("ALTER TABLE #{quote(table)} ADD COLUMN #{quote(column)}")
        end
        db.execute("CREATE UNIQUE INDEX IF NOT EXISTS #{quote("idx_#{table}_#{unique_key}")} " \
                   "ON #{quote(table)} (#{quote(unique_key)})")
        @columns = table_columns - SERVICE_COLUMNS
      end
      self
    end

    def save(collection)
      stats = { inserted: 0, updated: 0, skipped: 0 }
      return stats if collection.empty?

      prepare_schema(collection.fields.map(&:to_s) | [unique_key])
      with_errors("save items") do
        db.transaction do
          collection.each { |item| stats[save_item(item)] += 1 }
        end
      end
      @logger.info("Database #{File.basename(path)}/#{table}: #{stats[:inserted]} inserted, " \
                   "#{stats[:updated]} updated, #{stats[:skipped]} skipped")
      stats
    end

    def all(limit: nil, order_by: "id")
      return ItemCollection.new unless table_exists?

      sql = "SELECT * FROM #{quote(table)} ORDER BY #{quote(identifier!(order_by, 'order column'))}"
      params = []
      if limit
        sql += " LIMIT ?"
        params << Integer(limit)
      end
      rows = with_errors("read items") { db.execute(sql, params) }
      item_class = stored_item_class
      ItemCollection.define_schema(item_class).new(rows.map { |row| row_to_item(row, item_class) })
    end

    def stored_item_class
      Item.define_schema(table_columns - SERVICE_COLUMNS)
    end

    def find(key_value)
      return nil unless table_exists?

      row = with_errors("find item") do
        db.get_first_row("SELECT * FROM #{quote(table)} WHERE #{quote(unique_key)} = ?", [key_value.to_s])
      end
      row && row_to_item(row)
    end

    def count
      return 0 unless table_exists?

      with_errors("count items") { db.get_first_value("SELECT COUNT(*) FROM #{quote(table)}") }
    end

    def table_exists?
      with_errors("check table") do
        !db.get_first_value("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", [table]).nil?
      end
    end

    private

    def db
      connect unless @db
      @db
    end

    def save_item(item)
      key = item[unique_key]
      if key.nil? || key.to_s.strip.empty?
        @logger.warn("Skipping item without '#{unique_key}': #{item}")
        return :skipped
      end

      data_columns = @columns - [unique_key]
      values = data_columns.map { |c| db_value(item[c]) }
      now = Time.now.iso8601
      exists = db.get_first_value("SELECT 1 FROM #{quote(table)} WHERE #{quote(unique_key)} = ?", [key.to_s])

      if exists
        assignments = data_columns.map { |c| "#{quote(c)} = ?" } + ["scraped_at = ?", "updated_at = ?"]
        db.execute("UPDATE #{quote(table)} SET #{assignments.join(', ')} WHERE #{quote(unique_key)} = ?",
                   values + [item.scraped_at.iso8601, now, key.to_s])
        :updated
      else
        cols = [unique_key] + data_columns + %w[scraped_at created_at updated_at]
        placeholders = Array.new(cols.size, "?").join(", ")
        db.execute("INSERT INTO #{quote(table)} (#{cols.map { |c| quote(c) }.join(', ')}) VALUES (#{placeholders})",
                   [key.to_s] + values + [item.scraped_at.iso8601, now, now])
        :inserted
      end
    end

    def row_to_item(row, item_class = stored_item_class)
      attrs = row.reject { |k, _| k.is_a?(Integer) || SERVICE_COLUMNS.include?(k) }
      scraped = row["scraped_at"] ? Time.parse(row["scraped_at"]) : Time.now
      item_class.new(attrs, scraped_at: scraped)
    end

    def db_value(value)
      case value
      when nil, Integer, Float then value
      when true, false then value ? 1 : 0
      else value.to_s
      end
    end

    def table_columns
      db.execute("PRAGMA table_info(#{quote(table)})").map { |r| r["name"] }
    end

    def identifier!(name, what)
      name = name.to_s
      raise DatabaseError, "invalid #{what} name '#{name}'" unless IDENTIFIER.match?(name)

      name
    end

    def quote(name)
      %("#{name}")
    end

    def with_errors(action)
      yield
    rescue SQLite3::Exception => e
      raise DatabaseError, "failed to #{action}: #{e.class}: #{e.message}"
    end
  end
end
