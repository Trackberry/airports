# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "minitest", "~> 5.25"
gem "rake", "~> 13.2"
gem "rubocop-rails-omakase", require: false

# Only `rake airports:refresh` uses it, for the ISO 3166-2 hierarchy and the
# Natural Earth map lookup that place a port and an airport the same way.
gem "seaports", "~> 1.2", require: false
