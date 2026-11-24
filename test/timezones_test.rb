# frozen_string_literal: true

require "test_helper"

class TimezonesTest < Minitest::Test
  Timezones = Trackberry::Airports::Timezones

  def square(min_lng, min_lat, size)
    [[min_lng, min_lat], [min_lng + size, min_lat], [min_lng + size, min_lat + size], [min_lng, min_lat + size], [min_lng, min_lat]]
  end

  # A zone with a hole in it and an island zone inside the hole, the way an
  # enclave sits in the map, plus a MultiPolygon.
  def map
    JSON.dump(
      "type" => "FeatureCollection",
      "features" => [
        { "properties" => { "tzid" => "Europe/Madrid" },
          "geometry" => { "type" => "Polygon", "coordinates" => [square(0.0, 0.0, 10.0), square(4.0, 4.0, 2.0)] } },
        { "properties" => { "tzid" => "Africa/Ceuta" },
          "geometry" => { "type" => "Polygon", "coordinates" => [square(4.5, 4.5, 1.0)] } },
        { "properties" => { "tzid" => "Atlantic/Canary" },
          "geometry" => { "type" => "MultiPolygon", "coordinates" => [[square(-20.0, 0.0, 1.0)], [square(-18.0, 0.0, 1.0)]] } },
        { "properties" => { "tzid" => "Etc/GMT+1" },
          "geometry" => { "type" => "Polygon", "coordinates" => [square(-30.0, 0.0, 5.0)] } },
        # A triangle, so a point is tested against slanted edges, overlapping
        # a square with another clock, the way the map draws Xinjiang.
        { "properties" => { "tzid" => "Asia/Urumqi" },
          "geometry" => { "type" => "Polygon", "coordinates" => [[[40.0, 0.0], [50.0, 0.0], [40.0, 10.0], [40.0, 0.0]]] } },
        { "properties" => { "tzid" => "Asia/Shanghai" },
          "geometry" => { "type" => "Polygon", "coordinates" => [square(40.0, 0.0, 10.0)] } }
      ]
    )
  end

  def test_finds_the_zone_containing_a_point
    zones = Timezones.parse(map)

    assert_equal ["Europe/Madrid"], zones.zones_at(1.0, 1.0)
    assert_equal ["Africa/Ceuta"], zones.zones_at(5.0, 5.0)
    assert_equal ["Atlantic/Canary"], zones.zones_at(0.5, -17.5)
  end

  # Either side of the triangle's slanted edge, which runs from (50, 0) to
  # (40, 10): (lng 44.9, lat 5) is inside it, (lng 45.1, lat 5) is not.
  def test_gives_every_zone_where_the_map_overlaps_and_honours_slanted_edges
    zones = Timezones.parse(map)

    assert_equal ["Asia/Shanghai", "Asia/Urumqi"], zones.zones_at(5.0, 44.9)
    assert_equal ["Asia/Shanghai"], zones.zones_at(5.0, 45.1)
  end

  def test_a_point_in_a_hole_is_not_in_the_zone_around_it
    assert_empty Timezones.parse(map).zones_at(4.2, 4.2)
  end

  def test_answers_nothing_for_open_sea_nowhere_and_no_position
    zones = Timezones.parse(map)

    assert_empty zones.zones_at(1.0, -28.0)
    assert_empty zones.zones_at(50.0, 50.0)
    assert_empty zones.zones_at(nil, 1.0)
  end

  def test_reads_an_unzipped_map_off_disk
    Dir.mktmpdir do |dir|
      path = File.join(dir, "map.json")
      File.write(path, map)

      assert_equal ["Europe/Madrid"], Timezones.parse(Timezones.fetch(path)).zones_at(1.0, 1.0)
    end
  end

  def test_checks_a_zone_against_the_country_that_keeps_it
    assert Timezones.country?("Atlantic/Canary", "ES")
    assert Timezones.country?("Europe/Oslo", "NO") # a link, counted as its target
    refute Timezones.country?("Europe/Paris", "ES")
    assert Timezones.country?("Europe/Belgrade", "XK") # tzdata lists no zones for Kosovo
  end

  def test_brings_an_old_zone_name_up_to_date
    assert_equal "Asia/Kolkata", Timezones.canonical("Asia/Calcutta")
    assert_raises(ArgumentError) { Timezones.canonical("Europe/Hamburg") }
  end
end
