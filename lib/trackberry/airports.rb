# frozen_string_literal: true

require "csv"

require_relative "airports/version"

module Trackberry
  # Airports by IATA code: a code in, a name, a city, a position and the ISO
  # 3166-2 subdivision out.
  #
  # Air tracking speaks in three-letter codes. A waybill's route is "LIM CDG
  # FRA", and everything a person reads (the city, the map, which public
  # holidays close the airport's warehouses) has to be looked up from them.
  #
  # The table ships inside the gem rather than being fetched: it is reference
  # data, and a city name should not depend on a network. It is built from
  # OurAirports (public domain), filtered to the airports with an IATA code.
  # `rake airports:refresh` regenerates it; nothing else should write it.
  #
  #   Trackberry::Airports.find("FRA")              # => #<data Trackberry::Airports::Airport iata="FRA", ...>
  #   Trackberry::Airports.city("FRA")              # => "Frankfurt"
  #   Trackberry::Airports.coordinates("FRA")       # => { "lat" => 50.0267, "lng" => 8.5584 }
  #   Trackberry::Airports.subdivision_path("SXB")  # => ["FR-67", "FR-6AE", "FR-GES"]
  module Airports
    TABLE_PATH = File.expand_path("../../data/airports.csv", __dir__)

    # +city+ is the city the airport serves, the one a carrier or a person
    # names: "Brussels" for Brussels Airport. +municipality+ is the town it
    # stands in: "Zaventem". They are the same for most airports.
    #
    # +kind+ is OurAirports' type: "large_airport", "medium_airport",
    # "small_airport", "seaplane_base" or "heliport". +scheduled+ is whether
    # airlines fly there on a timetable, which is what separates a city's
    # airport from its flying club.
    #
    # +subdivision+ is the ISO 3166-2 code of the area the airport is in, at
    # the most specific level known: "DE-HE" for Frankfurt, "FR-67" (Bas-Rhin)
    # for Strasbourg. +subdivision_path+ is that code and every ISO
    # subdivision above it, most specific first: ["FR-67", "FR-6AE",
    # "FR-GES"], where FR-6AE is the European Collectivity of Alsace.
    # +principal_subdivision+ is the last of them, ISO's top level.
    # Hand the path to a holiday calendar that matches on any level:
    # Trackberry::Holidays.holiday?(date, path). Nil, and an empty path, for
    # an airport nothing places.
    Airport = Data.define(:iata, :icao, :name, :city, :municipality, :country, :coordinates, :kind, :scheduled,
      :subdivision, :principal_subdivision, :subdivision_path)

    class << self
      # Nil for anything the table does not hold. An unknown code is the
      # ordinary case rather than an error: carriers send city codes ("LON",
      # "NYC") and codes for airports that have since closed.
      def find(iata)
        key = normalize(iata)
        return nil if key.nil?

        table[key]
      end

      def name(iata)
        find(iata)&.name
      end

      # The city the airport serves: "Brussels", "Athens". Nil when no source
      # names one. See Airport.
      def city(iata)
        find(iata)&.city
      end

      # The ISO 3166-1 alpha-2 code of the airport's country, "DE".
      def country(iata)
        find(iata)&.country
      end

      # { "lat" => Float, "lng" => Float }, or nil. String keys because the
      # usual destination is JSON on its way to a map.
      def coordinates(iata)
        find(iata)&.coordinates
      end

      # "FR-67" for Strasbourg, or nil. See Airport.
      def subdivision(iata)
        find(iata)&.subdivision
      end

      # "FR-GES" for Strasbourg, or nil. See Airport.
      def principal_subdivision(iata)
        find(iata)&.principal_subdivision
      end

      # ["FR-67", "FR-6AE", "FR-GES"] for Strasbourg, [] for an airport
      # nothing places or a code the table does not hold.
      def subdivision_path(iata)
        find(iata)&.subdivision_path || []
      end

      # Every airport in the table, ordered by IATA code. A new array on each
      # call, so a caller cannot reorder the one everyone else reads.
      def all
        table.values.dup
      end

      def count
        table.size
      end

      def data_fetched_on
        DATA_FETCHED_ON
      end

      private

      # An IATA airport code is three letters. A handful are letters and
      # digits, so digits are let through too.
      def normalize(iata)
        key = iata.to_s.strip.upcase
        key.match?(/\A[A-Z0-9]{3}\z/) ? key : nil
      end

      # Read once, on the first lookup rather than at require time: most
      # processes never look an airport up.
      def table
        @table || LOAD_LOCK.synchronize { @table ||= load_table }
      end

      LOAD_LOCK = Mutex.new

      def load_table
        CSV.foreach(TABLE_PATH, headers: true).each_with_object({}) do |row, airports|
          iata = normalize(row["iata"])
          next if iata.nil? || blank?(row["name"])

          airports[iata] = Airport.new(iata: iata, icao: presence(row["icao"]), name: row["name"],
            city: presence(row["city"]), municipality: presence(row["municipality"]), country: row["country"], coordinates: point(row), kind: row["kind"],
            scheduled: row["scheduled"] == "yes", subdivision: presence(row["subdivision"]),
            principal_subdivision: presence(row["principal_subdivision"]),
            subdivision_path: row["subdivision_path"].to_s.split.freeze)
        end.freeze
      end

      def point(row)
        return nil if blank?(row["lat"]) || blank?(row["lng"])

        { "lat" => row["lat"].to_f, "lng" => row["lng"].to_f }.freeze
      end

      def blank?(value)
        value.to_s.strip.empty?
      end

      def presence(value)
        blank?(value) ? nil : value.strip
      end
    end
  end
end
