# frozen_string_literal: true

require_relative "lib/trackberry/airports/version"

Gem::Specification.new do |spec|
  spec.name = "trackberry-airports"
  spec.version = Trackberry::Airports::VERSION
  spec.authors = ["Édouard Brière"]
  spec.email = ["edouard.briere@gmail.com"]

  spec.summary = "Airports by IATA code: name, city, position and ISO 3166-2 subdivision, with no network calls."
  spec.description = <<~TEXT
    Every airport OurAirports lists with an IATA code, shipped inside the gem
    as a CSV. Turns the codes in an air waybill's route into names, cities,
    map positions and the ISO 3166-2 subdivision path a holiday calendar
    matches on. A scheduled job rebuilds the table and opens a pull request
    with what changed.
  TEXT
  spec.homepage = "https://github.com/Trackberry/airports"
  # The code is MIT. The table carries OpenFlights' served cities, so it is
  # a derivative database and stays under OpenFlights' ODbL.
  spec.licenses = ["MIT", "ODbL-1.0"]

  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "data/*.csv", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  # Ruby 3.4 demoted csv out of the default gems: under Bundler it now has to
  # be asked for by name.
  spec.add_dependency "csv", "~> 3.3"
end
