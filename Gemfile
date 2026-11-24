# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "minitest", "~> 5.25"
gem "rake", "~> 13.2"
gem "rubocop-rails-omakase", require: false

# Only `rake airports:refresh` uses it, for the ISO 3166-2 hierarchy and the
# Natural Earth map lookup that place a port and an airport the same way.
gem "seaports", "~> 1.2", require: false

# Only `rake airports:refresh` and the tests use them, to check each airport's
# zone against its country and that every zone and override is one tzdata
# knows. tzinfo-data rather than the system's zoneinfo, so a build on a Mac and
# one in CI agree.
gem "tzinfo", "~> 2.0", require: false
gem "tzinfo-data", require: false
