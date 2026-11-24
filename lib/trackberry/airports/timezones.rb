# frozen_string_literal: true

require "json"

module Trackberry
  module Airports
    # Which IANA time zone a point falls in, from timezone-boundary-builder's
    # map of the world's zones (ODbL, drawn from OpenStreetMap).
    #
    # Build-time only, like the subdivision map: the 185 MB file is read when
    # the table is built, the zone each airport falls in is written into the
    # table, and the gem itself never looks a point up.
    #
    # The "with oceans" edition is used because its land zones reach out over
    # territorial waters, so a runway on reclaimed land or past the drawn
    # coastline (HKG, KIX, MLE) still lands in its country's zone. Beyond
    # territorial waters it has the nautical zones, Etc/GMT+5 and so on, which
    # no airport should get: those answer nil.
    class Timezones
      # Pinned to a release rather than "latest", so zones only move when
      # someone changes this line and reads what moved with it. 2026f is built
      # from tzdata 2026f and OpenStreetMap as of November 2026.
      SOURCE_URL = "https://github.com/evansiroky/timezone-boundary-builder/releases/download/2026f/timezones-with-oceans.geojson.zip"

      # One polygon of a zone: [outer ring, hole, …], each ring a flat array of
      # longitudes and latitudes ([lng, lat, lng, lat, …]) because the ray cast
      # below walks it nine thousand times and nested pairs are slower to walk.
      Polygon = Data.define(:tzid, :rings, :bbox)

      # The GeoJSON, unzipped. +source+ is the release's URL, or a path to the
      # .zip or the .json on disk, which is how a rebuild is debugged.
      def self.fetch(source = SOURCE_URL)
        return File.read(source) if File.exist?(source) && !source.end_with?(".zip")

        require "open3"
        require "tmpdir"
        Dir.mktmpdir do |dir|
          zip = File.join(dir, "timezones.zip")
          if File.exist?(source)
            zip = source
          else
            require "open-uri"
            File.binwrite(zip, URI.parse(source).read)
          end
          json, status = Open3.capture2("unzip", "-p", zip, binmode: true)
          raise IOError, "could not unzip #{source}" unless status.success? && !json.empty?

          json.force_encoding(Encoding::UTF_8)
        end
      end

      def self.parse(geojson)
        polygons = JSON.parse(geojson).fetch("features").flat_map do |feature|
          tzid = feature.dig("properties", "tzid").to_s
          next [] if tzid.empty?

          polygons_of(feature["geometry"]).map do |rings|
            flat = rings.map { |ring| ring.flatten.map(&:to_f) }
            Polygon.new(tzid: tzid, rings: flat, bbox: bbox(flat.first))
          end
        end
        new(polygons)
      end

      def self.polygons_of(geometry)
        case geometry&.fetch("type")
        when "Polygon" then [geometry.fetch("coordinates")]
        when "MultiPolygon" then geometry.fetch("coordinates")
        else []
        end
      end

      def self.bbox(ring)
        lngs = ring.each_slice(2).map(&:first)
        lats = ring.each_slice(2).map(&:last)
        [lngs.min, lats.min, lngs.max, lats.max]
      end

      # Whether +tzid+ is a zone (or a link to one) that +country+ keeps, by
      # tzdata's own list of zones per country. Links count as their target,
      # so Europe/Oslo is Norway's even where tzdata has folded it into
      # Europe/Berlin. A country tzdata does not list (XK, Kosovo) accepts any
      # zone: there is nothing to check it against.
      #
      # Raises for an id tzinfo-data does not know, which means the map is
      # newer than the gem's tzinfo-data and the Gemfile should be bumped.
      def self.country?(tzid, country)
        zones = country_zones(country)
        zones.nil? || zones.include?(canonical(tzid))
      end

      # The id tzdata keeps the zone under ("Asia/Kolkata" for
      # "Asia/Calcutta").
      def self.canonical(tzid)
        load_tzinfo
        TZInfo::Timezone.get(tzid).canonical_identifier
      rescue TZInfo::InvalidTimezoneIdentifier
        raise ArgumentError, "#{tzid.inspect} is not a time zone tzinfo-data #{TZInfo::Data::Version::TZDATA} knows"
      end

      def self.country_zones(country)
        load_tzinfo
        @country_zones ||= {}
        return @country_zones[country] if @country_zones.key?(country)

        @country_zones[country] = begin
          TZInfo::Country.get(country).zone_identifiers.map { |tzid| canonical(tzid) }
        rescue TZInfo::InvalidCountryCode
          nil
        end
      end
      private_class_method :country_zones

      # tzinfo is a build dependency, not a runtime one, so it is loaded only
      # when a table is being built.
      def self.load_tzinfo
        require "tzinfo"
        require "tzinfo/data"
      end
      private_class_method :load_tzinfo

      def initialize(polygons)
        @polygons = polygons
      end

      # The IANA ids of every zone containing the point, sorted by name
      # (["Europe/Madrid"]); empty for no position, open sea, or a point the
      # map does not cover.
      #
      # More than one where two clocks are kept in one place, which the map
      # draws on purpose as overlapping zones: Xinjiang is in both Asia/Urumqi
      # and Asia/Shanghai, Abkhazia in both Asia/Tbilisi and Europe/Moscow.
      # Choosing between them is the builder's call, not the map's.
      def zones_at(lat, lng)
        return [] if lat.nil? || lng.nil?

        @polygons.select { |polygon| within_bbox?(polygon.bbox, lat, lng) && contains?(polygon.rings, lat, lng) }
          .map(&:tzid).reject { |tzid| tzid.start_with?("Etc/") }.uniq.sort
      end

      private

      def within_bbox?(bbox, lat, lng)
        lng.between?(bbox[0], bbox[2]) && lat.between?(bbox[1], bbox[3])
      end

      def contains?(rings, lat, lng)
        outer, *holes = rings
        inside?(outer, lat, lng) && holes.none? { |hole| inside?(hole, lat, lng) }
      end

      # Ray casting: a point is inside a ring if a ray from it crosses the ring
      # an odd number of times. An index loop rather than each_slice, for the
      # same reason the rings are flat.
      def inside?(ring, lat, lng)
        inside = false
        i = 0
        last = ring.size - 2
        while i < last
          x1 = ring[i]
          y1 = ring[i + 1]
          x2 = ring[i + 2]
          y2 = ring[i + 3]
          if (y1 > lat) != (y2 > lat) && lng < x1 + ((lat - y1) * (x2 - x1) / (y2 - y1))
            inside = !inside
          end
          i += 2
        end
        inside
      end
    end
  end
end
