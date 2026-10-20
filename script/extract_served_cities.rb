# frozen_string_literal: true

# Writes data/sources/served_cities.csv from OpenFlights' airports.dat: the
# city each airport serves, with OpenFlights' position for it so the build can
# tell a reassigned code from the same airport.
#
# OpenFlights stopped updating in 2019, so this runs once, against the pinned
# file below, rather than on every refresh.
#
#   ruby script/extract_served_cities.rb [airports.dat]

require "csv"
require "open-uri"

SOURCE_URL = "https://raw.githubusercontent.com/jpatokal/openflights/e3bc6dedbcceb8b7b74248a00dcd6207254da6bd/data/airports.dat"
TARGET = File.expand_path("../data/sources/served_cities.csv", __dir__)

source = ARGV[0] ? File.read(ARGV[0]) : URI.parse(SOURCE_URL).read
seen = {}

# airports.dat has no header: id, name, city, country, IATA, ICAO, latitude,
# longitude, …, with \N for a missing value.
CSV.parse(source, liberal_parsing: true).each do |row|
  iata = row[4].to_s.strip.upcase
  city = row[2].to_s.strip
  next unless iata.match?(/\A[A-Z0-9]{3}\z/) && !city.empty? && city != "\\N"

  # Two rows for one code: neither can be trusted to be the airport that
  # holds it, so neither is kept.
  seen[iata] = seen.key?(iata) ? :ambiguous : [iata, city, row[6].to_f.round(4), row[7].to_f.round(4)]
end

CSV.open(TARGET, "w") do |csv|
  csv << %w[iata city lat lng]
  seen.values.reject { |value| value == :ambiguous }.sort_by(&:first).each { |row| csv << row }
end

puts "#{File.foreach(TARGET).count - 1} served cities written to #{TARGET}"
