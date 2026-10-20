# frozen_string_literal: true

require "csv"

require_relative "../airports"

module Trackberry
  module Airports
    # Rebuilds the shipped table from OurAirports' airports.csv.
    #
    # The table is generated, not hand-maintained, and this is the only thing
    # that should ever write it, so a refresh is `rake airports:refresh`
    # rather than a diff someone edits by hand. OurAirports is edited by
    # volunteers every day, which is why every refresh runs through
    # Trackberry::Airports::Diff before anything ships.
    #
    # The subdivision tooling (the ISO 3166-2 hierarchy and the Natural Earth
    # map) is borrowed from the seaports gem, which needs the same thing for
    # ports. It runs here only: the gem itself depends on neither.
    class Builder
      SOURCE_URL = "https://davidmegginson.github.io/ourairports-data/airports.csv"

      HEADERS = %w[
        iata icao name city country lat lng kind scheduled
        subdivision principal_subdivision subdivision_path subdivision_source
      ].freeze

      # Reviewed subdivisions for airports neither OurAirports nor the map
      # places. Kept outside data/*.csv so it is not shipped in the gem; only
      # its result is.
      OVERRIDES_PATH = File.expand_path("../../../data/sources/subdivision_overrides.csv", __dir__)

      # When one IATA code is on several rows, the one an airline flies to
      # wins: scheduled service first, then the larger airport.
      KIND_RANK = %w[large_airport medium_airport small_airport seaplane_base heliport].freeze

      # The published file, straight off the network, or off disk if what was
      # handed over is a path, which is how a rebuild is debugged.
      def self.fetch(source = SOURCE_URL)
        return File.read(source) if File.exist?(source)

        require "open-uri"
        URI.parse(source).read
      end

      # Reads OVERRIDES_PATH (or +path+) into { iata => ISO 3166-2 code }.
      #
      # The file is typed by people, so a blank cell, a malformed code or an
      # airport listed twice stops the build with the line to fix.
      def self.overrides(path = OVERRIDES_PATH)
        return {} unless File.exist?(path)

        CSV.foreach(path, headers: true).with_index(2).each_with_object({}) do |(row, line), overrides|
          iata = row["iata"].to_s.strip.upcase
          code = row["subdivision"].to_s.strip.upcase
          raise ArgumentError, "#{path}:#{line}: #{iata.inspect} is not an IATA code" unless iata.match?(/\A[A-Z0-9]{3}\z/)
          raise ArgumentError, "#{path}:#{line}: #{iata} has no subdivision" if code.empty?
          raise ArgumentError, "#{path}:#{line}: #{iata} is listed twice" if overrides.key?(iata)

          overrides[iata] = code
        end
      end

      # Where an airport's subdivision comes from, best first:
      #
      # - +overrides+, { iata => code }, reviewed by a person;
      # - the map (+boundaries+, a Seaports::Boundaries), when the area it
      #   finds sits inside OurAirports' own code. OurAirports stops at the
      #   top level ("FR-GES" for Strasbourg), and the map knows the
      #   department below it ("FR-67", inside Alsace-Moselle), which is where
      #   some holidays are kept;
      # - OurAirports' iso_region, when the map disagrees or has nothing;
      # - the map alone, when OurAirports' code is not ISO's (China's old
      #   numeric codes, "PF-U-A" for "unassigned").
      #
      # Every code is checked against +subdivisions+ (a Seaports::Subdivisions,
      # the ISO 3166-2 list), which also gives the path above it. Without that
      # list the subdivision columns stay empty, which keeps a test about
      # something else from needing it.
      def initialize(source, subdivisions: nil, boundaries: nil, overrides: {})
        @source = source
        @subdivisions = subdivisions
        @boundaries = boundaries
        @overrides = overrides
        @superseded = []
      end

      # One row per airport, in HEADERS order, sorted by IATA code. Sorted
      # because the file is committed: a stable order means a refresh diff
      # shows what changed rather than the whole table moving.
      def rows
        @rows ||= CSV.parse(@source, headers: true)
          .select { |row| airport?(row) }
          .group_by { |row| iata_of(row) }
          .map { |iata, candidates| airport_row(iata, candidates.min_by { |row| rank(row) }) }
          .sort_by(&:first)
      end

      def write(path = Airports::TABLE_PATH)
        CSV.open(path, "w") do |csv|
          csv << HEADERS
          rows.each { |row| csv << row }
        end
        path
      end

      def subdivided_count
        rows.count { |row| !row[10].nil? }
      end

      # Overrides worth a person's attention, written the way they should read
      # in a refresh pull request. An override wins over everything, so one
      # that has outlived its reason keeps masking better data until someone
      # looks.
      def override_report
        rows # the report is a by-product of building them
        stale = (@overrides.keys - rows.map(&:first)).sort
          .map { |iata| "`#{iata}` is overridden but no longer in the table: remove its row." }
        superseded = @superseded.uniq.sort.map do |iata, own, override|
          same = own == override ? "the same code" : "#{own}, not #{override}"
          "`#{iata}` is now placed without its override (#{same}): its row can go."
        end
        stale + superseded
      end

      private

      # Only rows with an IATA code, because that is the only key a tracking
      # feed gives, and never a closed airport: IATA hands a retired code to
      # someone else, and the closed row would shadow the new one.
      def airport?(row)
        !iata_of(row).nil? && row["type"] != "closed" && !row["name"].to_s.strip.empty? &&
          row["iso_country"].to_s.strip.match?(/\A[A-Z]{2}\z/)
      end

      def iata_of(row)
        code = row["iata_code"].to_s.strip.upcase
        code.match?(/\A[A-Z0-9]{3}\z/) ? code : nil
      end

      def rank(row)
        [row["scheduled_service"] == "yes" ? 0 : 1, KIND_RANK.index(row["type"]) || KIND_RANK.size, row["ident"].to_s]
      end

      def airport_row(iata, row)
        country = row["iso_country"].strip
        lat = coordinate(row["latitude_deg"])
        lng = coordinate(row["longitude_deg"])
        subdivision, source = subdivision_for(iata, country, row["iso_region"], lat, lng)
        path = @subdivisions&.path(subdivision) || []
        subdivision = source = nil if path.empty?
        [iata, presence(row["icao_code"]), row["name"].strip, city(row["municipality"]), country, lat, lng,
          row["type"], row["scheduled_service"] == "yes" ? "yes" : "no",
          subdivision, path.last, path.empty? ? nil : path.join(" "), source]
      end

      # [code, source], or [nil, nil] when no source has a valid one.
      def subdivision_for(iata, country, region, lat, lng)
        return [nil, nil] if @subdivisions.nil?

        own = @subdivisions.code(country, region.to_s.strip.upcase.delete_prefix("#{country}-"))
        mapped = mapped(country, lat, lng)

        if (override = @overrides[iata])
          code = @subdivisions.code(country, override.delete_prefix("#{country}-"))
          raise ArgumentError, "#{iata}: override #{override} is not an ISO 3166-2 code of #{country}" if code.nil?

          @superseded << [iata, own || mapped, code] if own || mapped
          return [code, "override"]
        end

        return [mapped, "boundaries"] if mapped && own && mapped != own && @subdivisions.path(mapped).include?(own)
        return [own, "ourairports"] if own
        return [mapped, "boundaries"] if mapped

        [nil, nil]
      end

      # The first code the map gives for the point that ISO recognises.
      def mapped(country, lat, lng)
        return nil if @boundaries.nil? || lat.nil? || lng.nil?

        @boundaries.codes_at(country, lat, lng).lazy
          .filter_map { |candidate| @subdivisions.code(country, candidate.delete_prefix("#{country}-")) }.first
      end

      # Four decimal places is about ten metres, finer than any use here, and
      # it keeps a volunteer nudging a runway threshold out of the refresh.
      def coordinate(value)
        text = value.to_s.strip
        text.empty? ? nil : text.to_f.round(4)
      end

      # OurAirports sometimes adds a note in brackets after the town:
      # "Helsinki (Vantaa)", "Köln (Cologne)". The town is what a person, a
      # carrier or a geocoder names, so the trailing note is dropped.
      def city(value)
        presence(value.to_s.sub(/\s*\([^()]*\)\s*\z/, ""))
      end

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
