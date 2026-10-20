# frozen_string_literal: true

require "test_helper"

class BuilderTest < Minitest::Test
  HEADERS = "id,ident,type,name,latitude_deg,longitude_deg,elevation_ft,continent,iso_country,iso_region," \
            "municipality,scheduled_service,icao_code,iata_code,gps_code,local_code,home_link,wikipedia_link,keywords"

  # Shaped like OurAirports' file, small enough to reason about. Each row is
  # here to prove one rule, and the order is deliberately wrong so the sort
  # has something to do.
  SOURCE = <<~CSV
    #{HEADERS}
    1,LFST,large_airport,Strasbourg Airport,48.538299,7.62823,505,EU,FR,FR-GES,Strasbourg,yes,LFST,SXB,,,,,
    2,EDDH,large_airport,Hamburg Airport,53.630402,9.98823,53,EU,DE,DE-HH,Hamburg,yes,EDDH,HAM,,,,,
    3,EFHK,large_airport,Helsinki Vantaa Airport,60.3172,24.963301,179,EU,FI,FI-18,Helsinki (Vantaa),yes,EFHK,HEL,,,,,
    4,AOLD,closed,Old Hamburg Field,53.6,9.9,0,EU,DE,DE-HH,Hamburg,yes,,HAM,,,,,
    11,XBIG,large_airport,Unscheduled Base,50.0,8.0,0,EU,DE,DE-HE,Somewhere,no,,SCH,,,,,
    12,XSMA,small_airport,Scheduled Strip,50.1,8.1,0,EU,DE,DE-HE,Somewhere,yes,,SCH,,,,,
    13,EBBR,large_airport,Brussels Airport,50.901402,4.48444,175,EU,BE,BE-VBR,Zaventem,yes,EBBR,BRU,,,,,
    5,ZBAA,large_airport,Beijing Capital,40.0801,116.584999,116,AS,CN,CN-11,Beijing,yes,ZBAA,PEK,,,,,
    6,XHEL,heliport,Hamburg Heliport,53.55,10.0,0,EU,DE,DE-HH,Hamburg,no,,HHP,,,,,
    7,XDUP,small_airport,Duplicate Field,53.0,9.0,0,EU,DE,DE-NI,Somewhere,no,,HHP,,,,,
    8,XNOI,small_airport,No Code Field,53.0,9.0,0,EU,DE,DE-HH,Hamburg,no,,,,,,,
    9,NTAA,large_airport,Tahiti Faa'a,-17.5537,-149.606995,5,OC,PF,PF-U-A,Papeete,yes,NTAA,PPT,,,,,
    10,LFSB,large_airport,EuroAirport Basel-Mulhouse,47.59,7.529167,885,EU,FR,FR-GES,Mulhouse,yes,LFSB,MLH,,,,,
  CSV

  LIST = {
    "3166-2" => [
      { "code" => "DE-HH", "name" => "Hamburg", "type" => "Land" },
      { "code" => "DE-NI", "name" => "Niedersachsen", "type" => "Land" },
      { "code" => "FI-18", "name" => "Uusimaa", "type" => "Region" },
      { "code" => "FR-GES", "name" => "Grand Est", "type" => "Metropolitan region" },
      { "code" => "FR-6AE", "name" => "Alsace", "type" => "European collectivity", "parent" => "FR-GES" },
      { "code" => "FR-67", "name" => "Bas-Rhin", "type" => "Metropolitan department", "parent" => "FR-6AE" },
      { "code" => "FR-68", "name" => "Haut-Rhin", "type" => "Metropolitan department", "parent" => "FR-6AE" },
      { "code" => "CH-BS", "name" => "Basel-Stadt", "type" => "Canton" },
      { "code" => "CN-BJ", "name" => "Beijing Shi", "type" => "Municipality" }
    ]
  }.freeze

  def square(min_lng, min_lat, size = 1.0)
    [[min_lng, min_lat], [min_lng + size, min_lat], [min_lng + size, min_lat + size], [min_lng, min_lat + size], [min_lng, min_lat]]
  end

  def feature(code, ring)
    { "type" => "Feature", "properties" => { "iso_3166_2" => code }, "geometry" => { "type" => "Polygon", "coordinates" => [ring] } }
  end

  # Bas-Rhin around Strasbourg, Beijing, and a square that puts Hamburg's
  # airport in Lower Saxony, the way a map that disagrees with OurAirports
  # would.
  def boundaries
    Seaports::Boundaries.parse(JSON.dump(
      "type" => "FeatureCollection",
      "features" => [
        feature("FR-67", square(7.0, 48.0)),
        feature("CN-BJ", square(116.0, 39.5)),
        feature("DE-NI", square(9.5, 53.2))
      ]
    ))
  end

  def subdivisions
    Seaports::Subdivisions.parse(JSON.dump(LIST))
  end

  def rows(**options)
    Trackberry::Airports::Builder.new(SOURCE, **options).rows
  end

  def row(iata, rows)
    Trackberry::Airports::Builder::HEADERS.zip(rows.find { |row| row.first == iata }).to_h
  end

  def test_keeps_one_row_per_iata_code_sorted
    assert_equal %w[BRU HAM HEL HHP MLH PEK PPT SCH SXB], rows.map(&:first)
  end

  # IATA hands a retired code to someone else, so a closed airport must not
  # shadow the one that holds it now, even one that once had airlines and
  # sorts first.
  def test_ignores_closed_airports
    assert_equal "Hamburg Airport", row("HAM", rows)["name"]
  end

  def test_prefers_the_airport_an_airline_flies_to
    assert_equal "Scheduled Strip", row("SCH", rows)["name"]
  end

  def test_then_prefers_the_larger_airport
    assert_equal "Duplicate Field", row("HHP", rows)["name"] # neither is scheduled, and an airfield outranks a heliport
  end

  def test_drops_the_note_in_brackets_after_the_municipality
    assert_equal "Helsinki", row("HEL", rows)["municipality"]
    assert_equal "Helsinki", row("HEL", rows)["city"]
  end

  # OurAirports puts Brussels Airport in Zaventem; a courier says Brussels.
  def test_takes_the_served_city_for_the_same_airport
    served = { "BRU" => ["Brussels", 50.9014, 4.4844] }
    brussels = row("BRU", rows(served_cities: served))

    assert_equal "Brussels", brussels["city"]
    assert_equal "Zaventem", brussels["municipality"]
  end

  # The code has since gone to an airport on the other side of the world.
  def test_ignores_a_served_city_for_an_airport_somewhere_else
    served = { "BRU" => ["Bruny Island", -43.3, 147.3] }

    assert_equal "Zaventem", row("BRU", rows(served_cities: served))["city"]
  end

  def test_reads_the_shipped_served_cities
    served = Trackberry::Airports::Builder.served_cities

    assert_equal "Brussels", served.fetch("BRU").first
    assert_operator served.size, :>, 5_000
  end

  def test_rounds_coordinates_to_about_ten_metres
    hamburg = row("HAM", rows)

    assert_in_delta 53.6304, hamburg["lat"], 1e-9
    assert_in_delta 9.9882, hamburg["lng"], 1e-9
  end

  def test_leaves_subdivisions_empty_without_the_iso_list
    assert_nil row("HAM", rows)["subdivision_path"]
  end

  def test_takes_ourairports_region_when_iso_knows_it
    hamburg = row("HAM", rows(subdivisions:, boundaries:))

    assert_equal "DE-HH", hamburg["subdivision_path"]
    assert_equal "ourairports", hamburg["subdivision_source"]
  end

  # OurAirports says Grand Est; the map says Bas-Rhin, which sits inside it.
  def test_refines_ourairports_region_with_the_map_when_they_agree
    strasbourg = row("SXB", rows(subdivisions:, boundaries:))

    assert_equal "FR-67", strasbourg["subdivision"]
    assert_equal "FR-67 FR-6AE FR-GES", strasbourg["subdivision_path"]
    assert_equal "FR-GES", strasbourg["principal_subdivision"]
    assert_equal "boundaries", strasbourg["subdivision_source"]
  end

  def test_keeps_ourairports_region_when_the_map_disagrees
    hamburg = row("HAM", rows(subdivisions:, boundaries:))

    assert_equal "DE-HH", hamburg["subdivision_path"]
    assert_equal "ourairports", hamburg["subdivision_source"]
  end

  # OurAirports still writes China's pre-2017 numeric codes.
  def test_falls_back_to_the_map_when_ourairports_code_is_not_iso
    beijing = row("PEK", rows(subdivisions:, boundaries:))

    assert_equal "CN-BJ", beijing["subdivision_path"]
    assert_equal "boundaries", beijing["subdivision_source"]
  end

  def test_leaves_an_airport_nothing_places_empty
    tahiti = row("PPT", rows(subdivisions:, boundaries:))

    assert_nil tahiti["subdivision"]
    assert_nil tahiti["subdivision_source"]
  end

  def test_an_override_wins_and_is_reported_once_something_else_places_the_airport
    builder = Trackberry::Airports::Builder.new(SOURCE, subdivisions:, boundaries:, overrides: { "HAM" => "DE-NI", "ZZZ" => "DE-HH" })

    assert_equal "DE-NI", Trackberry::Airports::Builder::HEADERS.zip(builder.rows.find { |r| r.first == "HAM" }).to_h["subdivision"]
    assert_equal 2, builder.override_report.size
    assert_match(/`HAM` is now placed at DE-HH without its override, which says DE-NI: check/, builder.override_report.join("\n"))
    assert_match(/`ZZZ`.*no longer in the table/, builder.override_report.join("\n"))
  end

  def test_an_override_that_agrees_with_the_sources_can_go
    builder = Trackberry::Airports::Builder.new(SOURCE, subdivisions:, overrides: { "HAM" => "DE-HH" })

    assert_equal ["`HAM` is now placed at DE-HH without its override: its row can go."], builder.override_report
  end

  def test_an_override_iso_does_not_know_stops_the_build
    builder = Trackberry::Airports::Builder.new(SOURCE, subdivisions:, overrides: { "HAM" => "DE-XX" })

    assert_raises(ArgumentError) { builder.rows }
  end

  def test_an_override_whose_iso_chain_breaks_stops_the_build
    broken = Seaports::Subdivisions.parse(JSON.dump("3166-2" => LIST["3166-2"] + [{ "code" => "DE-XX", "parent" => "DE-GONE" }]))
    builder = Trackberry::Airports::Builder.new(SOURCE, subdivisions: broken, overrides: { "HAM" => "DE-XX" })

    assert_raises(ArgumentError) { builder.rows }
  end

  def test_reads_overrides_and_rejects_rows_a_person_mistyped
    Dir.mktmpdir do |dir|
      path = File.join(dir, "overrides.csv")
      File.write(path, "iata,subdivision,note\nham,de-hh,fine\n")
      assert_equal({ "HAM" => "DE-HH" }, Trackberry::Airports::Builder.overrides(path))

      ["HAMB,DE-HH,", "HAM,,", "HAM,DE-HH,\nHAM,DE-HH,"].each do |body|
        File.write(path, "iata,subdivision,note\n#{body}\n")
        error = assert_raises(ArgumentError) { Trackberry::Airports::Builder.overrides(path) }
        assert_match(/overrides\.csv:\d+/, error.message)
      end
    end
  end

  def test_shipped_overrides_are_valid
    Trackberry::Airports::Builder.overrides
  end

  def test_writes_the_table_with_its_headers
    Dir.mktmpdir do |dir|
      path = Trackberry::Airports::Builder.new(SOURCE).write(File.join(dir, "airports.csv"))

      assert_equal Trackberry::Airports::Builder::HEADERS, CSV.read(path).first
    end
  end
end
