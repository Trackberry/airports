# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

require "rubocop/rake_task"
RuboCop::RakeTask.new

task default: [:test, :rubocop]

namespace :airports do
  # Where a refresh leaves its evidence. The workflow reads these files rather
  # than parsing this task's output, so a change to the wording here cannot
  # silently break the automation.
  REFRESH_DIR = "tmp/refresh"

  desc "Rebuild the table from OurAirports and report what changed"
  task :refresh, [:source, :subdivisions, :boundaries] do |_task, args|
    require_relative "lib/trackberry/airports/builder"
    require_relative "lib/trackberry/airports/diff"
    # Build-time only: the ISO 3166-2 hierarchy and the Natural Earth map
    # lookup are seaports', and the gem itself depends on neither.
    require "seaports/subdivisions"
    require "seaports/boundaries"
    require "fileutils"

    airports = Trackberry::Airports
    FileUtils.mkdir_p(REFRESH_DIR)
    before = File.join(REFRESH_DIR, "before.csv")
    if File.exist?(airports::TABLE_PATH)
      FileUtils.cp(airports::TABLE_PATH, before)
    else
      File.write(before, "#{airports::Builder::HEADERS.join(',')}\n")
    end

    # Three downloads and a hand-edited overrides file: any of them failing is
    # a refusal for a person to read, the same as a failed gate, not a red
    # build nobody is told about.
    begin
      source = airports::Builder.fetch(args[:source] || airports::Builder::SOURCE_URL)
      subdivisions = Seaports::Subdivisions.parse(
        airports::Builder.fetch(args[:subdivisions] || Seaports::Subdivisions::SOURCE_URL)
      )
      boundaries = Seaports::Boundaries.parse(
        airports::Builder.fetch(args[:boundaries] || Seaports::Boundaries::SOURCE_URL)
      )
      builder = airports::Builder.new(source, subdivisions:, boundaries:, overrides: airports::Builder.overrides)
      builder.write(airports::TABLE_PATH)
    rescue StandardError => e
      restore(before, airports::TABLE_PATH)
      File.write(File.join(REFRESH_DIR, "summary.md"), "**Blocked**\n\nThe rebuild stopped: #{e.class}: #{e.message}\n")
      record "failed", "The rebuild stopped: #{e.class}: #{e.message}"
      next
    end

    diff = airports::Diff.between(before, airports::TABLE_PATH)
    overrides = builder.override_report
    summary = [diff.summary, overrides.empty? ? nil : "**Overrides to review**\n\n#{overrides.map { |line| "- #{line}" }.join("\n")}"]
    File.write(File.join(REFRESH_DIR, "summary.md"), "#{summary.compact.join("\n\n")}\n")
    puts overrides unless overrides.empty?

    if !diff.changed?
      record "unchanged", "The table is already current: #{diff.headline}"
    elsif !diff.ok?
      # Put the good table back. A refresh that fails its gates must leave no
      # trace in the working tree, so a later step cannot pick up half of it.
      restore(before, airports::TABLE_PATH)
      record "failed", "Refused the rebuilt table:\n#{diff.failures.map { |line| "  - #{line}" }.join("\n")}"
    else
      version = bump_version
      write_changelog(version, diff)
      record "ok", "#{diff.headline}\nVersion #{version}."
    end
  end

  def restore(before, table)
    FileUtils.cp(before, table)
  end

  def record(status, message)
    File.write(File.join(REFRESH_DIR, "status"), "#{status}\n")
    puts message
  end

  # A data refresh is a minor bump: airports appear and get renamed, which is
  # additive for anyone reading a name, and the code did not change.
  def bump_version
    require "date"

    path = "lib/trackberry/airports/version.rb"
    major, minor, = Trackberry::Airports::VERSION.split(".").map(&:to_i)
    version = "#{major}.#{minor + 1}.0"

    content = File.read(path)
      .sub(/VERSION = "[^"]*"/, %(VERSION = "#{version}"))
      .sub(/DATA_FETCHED_ON = "[^"]*"/, %(DATA_FETCHED_ON = "#{Date.today}"))
    File.write(path, content)

    File.write(File.join(REFRESH_DIR, "version"), "#{version}\n")
    version
  end

  # The headline and the removals only. Everything else belongs in the pull
  # request, where it is read once.
  def write_changelog(version, diff)
    entry = ["## #{version} — #{Date.today}", "", "OurAirports as of #{Date.today}. #{diff.headline}"]
    entry += ["", "Removed: #{diff.removed.join(', ')}."] unless diff.removed.empty?

    content = File.read("CHANGELOG.md")
    File.write("CHANGELOG.md", content.sub(/\n## /, "\n#{entry.join("\n")}\n\n## "))
  end
end
