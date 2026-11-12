# frozen_string_literal: true

require "rspec/core/rake_task"
require "fileutils"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Run the main collection process (config/settings.yml)"
task :run do
  ruby "main.rb"
end

desc "Run pipelines from a DSL file (default: dsl/books_pipeline.rb)"
task :dsl, [:file] do |_t, args|
  ruby "main.rb", "--dsl", args[:file] || "dsl/books_pipeline.rb"
end

desc "Export collected data as CSV"
task :csv do
  ruby "main.rb", "--format", "csv"
end

namespace :db do
  desc "Show items stored in SQLite"
  task :show, [:limit] do |_t, args|
    ruby "main.rb", "--show", (args[:limit] || 10).to_s
  end

  desc "Delete SQLite databases"
  task :reset do
    FileUtils.rm_f(Dir["data/*.sqlite3"])
    puts "Databases removed"
  end
end

desc "Remove generated output and logs"
task :clean do
  FileUtils.rm_f(Dir["output/*.{json,csv,yaml}"] + Dir["logs/*.log"])
  puts "Output and logs removed"
end

namespace :autoload do
  desc "Eager-load every library class to check the autoloader mapping"
  task :check do
    require_relative "lib/web_data_collector"
    WebDataCollector.loader.eager_load!
    puts "OK: #{WebDataCollector.loader.mapping.size} constants mapped and loaded"
    WebDataCollector.loader.mapping.each { |name, target| puts "  #{name.ljust(45)} #{target == :namespace ? '(namespace)' : File.basename(target)}" }
  end
end
