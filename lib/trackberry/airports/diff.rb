# frozen_string_literal: true

require "csv"

module Trackberry
  module Airports
    # What a refresh actually changed, and whether it is safe to ship.
    #
    # The failure worth designing for is not a missed airport. It is a bad
    # upstream file (truncated, a renamed column, a vandalised edit) landing
    # in a gem every air shipment's map and holiday count trusts. Nobody can
    # eyeball 9,000 rows in a pull request, so the gates below are the
    # reading, and the summary is what is left to judge.
    class Diff
      # Airports large enough that their disappearance means the source broke,
      # not that the world changed. Spread across continents so a regional
      # truncation cannot slip through.
      ANCHORS = %w[
        AMS ATL BOG CDG CPT DXB FRA GRU HKG JFK JNB LAX LHR LIM MEX MIA NBO NRT
        ORD PEK PVG SCL SIN SYD
      ].freeze

      # Where some of them must stay, at the principal level, in countries
      # whose holidays differ by region. The percentage gates below cannot see
      # one country's codes breaking (Germany is about 1% of the table), and a
      # holiday count can.
      ANCHOR_REGIONS = {
        "BCN" => "ES-CT", "FRA" => "DE-HE", "GRU" => "BR-SP", "HAM" => "DE-HH", "JFK" => "US-NY",
        "LHR" => "GB-ENG", "MAD" => "ES-MD", "MIA" => "US-FL", "MUC" => "DE-BY", "SXB" => "FR-GES",
        "SYD" => "AU-NSW", "VIE" => "AT-9", "YYZ" => "CA-ON", "ZRH" => "CH-ZH"
      }.freeze

      MINIMUM_COUNT = 8_500

      # OurAirports adds and closes a handful of IATA airports a month. Losing
      # two percent of the table in one go is a broken source.
      MAXIMUM_SHRINKAGE = 0.02

      # A real refresh moves a few airports between regions, when someone
      # corrects an entry or ISO redraws a country. Moving more than this share
      # of the placed airports at once means a source reshuffled its codes.
      MAXIMUM_REASSIGNMENT = 0.02

      def self.between(before_path, after_path)
        new(read(before_path), read(after_path))
      end

      def self.read(path)
        CSV.foreach(path, headers: true).each_with_object({}) do |row, airports|
          iata = row["iata"].to_s.strip.upcase
          next if iata.empty?

          airports[iata] = { name: row["name"].to_s.strip, city: row["city"].to_s.strip, point: point(row),
                             path: row["subdivision_path"].to_s.split.join(" ") }
        end
      end

      def self.point(row)
        lat = row["lat"].to_s.strip
        lng = row["lng"].to_s.strip
        return nil if lat.empty? || lng.empty?

        [lat.to_f, lng.to_f]
      end

      def initialize(before, after)
        @before = before
        @after = after
      end

      def changed?
        !(added.empty? && removed.empty? && renamed.empty? && recitied.empty? && repositioned.empty? && resubdivided.empty?)
      end

      # [iata, name, was, now] for an airport whose city changed: what a
      # tracking page shows next to the code, and what a courier geocoder
      # matches on.
      def recitied
        @recitied ||= common.filter_map do |iata|
          was = @before[iata][:city].to_s
          now = @after[iata][:city].to_s
          [iata, @after[iata][:name], was, now] if was != now
        end
      end

      def added
        @added ||= (@after.keys - @before.keys).sort
      end

      def removed
        @removed ||= (@before.keys - @after.keys).sort
      end

      # [iata, was, now] for an airport that kept its code and changed its name.
      def renamed
        @renamed ||= common.filter_map do |iata|
          was = @before[iata][:name]
          now = @after[iata][:name]
          [iata, was, now] if was != now
        end
      end

      # [iata, name, kind] for an airport whose position appeared, went, or
      # moved.
      def repositioned
        @repositioned ||= common.filter_map do |iata|
          was = @before[iata][:point]
          now = @after[iata][:point]
          next if was == now

          [iata, @after[iata][:name], (was.nil? ? :located : (now.nil? ? :unlocated : :moved))]
        end
      end

      # [iata, name, was, now] for an airport whose subdivision path changed
      # at any level, each path a space-separated string ("" for none). Each
      # can move an airport onto another holiday calendar, so all are listed,
      # though none is a failure on its own.
      def resubdivided
        @resubdivided ||= common.filter_map do |iata|
          was = @before[iata][:path].to_s
          now = @after[iata][:path].to_s
          [iata, @after[iata][:name], was, now] if was != now
        end
      end

      # The subset of resubdivided whose principal subdivision went from one
      # code to another. Gaining or losing a code is not in it.
      def reassigned
        @reassigned ||= resubdivided.select do |_, _, was, now|
          !was.empty? && !now.empty? && was.split.last != now.split.last
        end
      end

      # Empty means the refresh may ship. Anything here is a reason it may
      # not, written the way it should read in an issue.
      def failures
        [count_failure, shrinkage_failure, region_failure, reassignment_failure, *anchor_failures, *anchor_region_failures].compact
      end

      def ok?
        failures.empty?
      end

      def summary
        [
          headline,
          failures.empty? ? nil : "**Blocked**\n\n#{failures.map { |line| "- #{line}" }.join("\n")}",
          section("Removed", removed.map { |iata| "`#{iata}` #{@before[iata][:name]}" }, limit: nil),
          section("Added", added.map { |iata| "`#{iata}` #{@after[iata][:name]}" }),
          section("Renamed", renamed.map { |iata, was, now| "`#{iata}` #{was} → #{now}" }),
          section("City", recitied.map { |iata, name, was, now| "`#{iata}` #{name}: #{was.empty? ? 'none' : was} → #{now.empty? ? 'none' : now}" }),
          section("Coordinates", repositioned.map { |iata, name, kind| "`#{iata}` #{name}: #{POSITION_WORDS.fetch(kind)}" }),
          section("Subdivision", resubdivided.map { |iata, name, was, now| "`#{iata}` #{name}: #{path_words(was)} → #{path_words(now)}" })
        ].compact.join("\n\n")
      end

      POSITION_WORDS = {
        located: "position published for the first time",
        unlocated: "position withdrawn",
        moved: "position moved"
      }.freeze

      # The one-line version, for a changelog entry.
      def headline
        "#{@after.size} airports (#{@before.size} before): " \
          "#{added.size} added, #{removed.size} removed, " \
          "#{renamed.size} renamed, #{recitied.size} with a new city, #{repositioned.size} repositioned, " \
          "#{resubdivided.size} with a new subdivision (#{reassigned.size} moved to another principal one)."
      end

      private

      def common
        @common ||= (@before.keys & @after.keys).sort
      end

      def path_words(path)
        path.empty? ? "none" : path.split.join(" › ")
      end

      def count_failure
        return nil if @after.size >= MINIMUM_COUNT

        "Only #{@after.size} airports in the rebuilt table, below the floor of #{MINIMUM_COUNT}."
      end

      def shrinkage_failure
        return nil if @before.empty?

        shrinkage = (@before.size - @after.size).to_f / @before.size
        return nil if shrinkage <= MAXIMUM_SHRINKAGE

        "The table shrank by #{(shrinkage * 100).round(1)}%, past the #{(MAXIMUM_SHRINKAGE * 100).round}% limit."
      end

      # Losing subdivisions in bulk means the ISO 3166-2 list or the map failed
      # to load, not that airports moved country.
      def region_failure
        was = placed_count(@before)
        return nil if was.zero?

        now = placed_count(@after)
        shrinkage = (was - now).to_f / was
        return nil if shrinkage <= MAXIMUM_SHRINKAGE

        "Airports with a subdivision fell from #{was} to #{now}, past the #{(MAXIMUM_SHRINKAGE * 100).round}% limit."
      end

      def reassignment_failure
        placed = placed_count(@before)
        return nil if placed.zero?

        share = reassigned.size.to_f / placed
        return nil if share <= MAXIMUM_REASSIGNMENT

        "#{reassigned.size} airports moved to another principal subdivision, past the " \
          "#{(MAXIMUM_REASSIGNMENT * 100).round}% limit: a source reshuffled its codes."
      end

      def placed_count(airports)
        airports.count { |_, airport| !airport[:path].to_s.empty? }
      end

      def anchor_failures
        ANCHORS.reject { |iata| @after.key?(iata) }
          .map { |iata| "`#{iata}` is gone, and an airport that large does not disappear." }
      end

      def anchor_region_failures
        ANCHOR_REGIONS.filter_map do |iata, region|
          airport = @after[iata]
          next if airport.nil? # already a failure above

          principal = airport[:path].to_s.split.last
          next if principal == region

          "`#{iata}` is now in #{principal || 'no subdivision'}, not #{region}: its country's codes broke."
        end
      end

      # Removals are listed in full: they are the changes that break a caller.
      # Everything else is capped, so a month that adds four hundred airports
      # does not bury the four that were taken away.
      def section(title, lines, limit: 40)
        return nil if lines.empty?

        shown = limit.nil? ? lines : lines.first(limit)
        body = shown.map { |line| "- #{line}" }.join("\n")
        body += "\n- …and #{lines.size - shown.size} more" if lines.size > shown.size
        "**#{title}** (#{lines.size})\n\n#{body}"
      end
    end
  end
end
