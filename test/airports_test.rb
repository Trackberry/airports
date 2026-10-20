# frozen_string_literal: true

require "test_helper"

# Against the shipped table, so a refresh that broke a well-known airport
# fails here before it fails in an application.
class AirportsTest < Minitest::Test
  def test_finds_an_airport_by_its_iata_code
    airport = Trackberry::Airports.find("FRA")

    assert_equal "FRA", airport.iata
    assert_equal "EDDF", airport.icao
    assert_equal "DE", airport.country
    assert_equal "Frankfurt am Main", airport.city
    assert_equal "large_airport", airport.kind
    assert airport.scheduled
  end

  def test_tolerates_case_and_padding
    assert_equal "FRA", Trackberry::Airports.find(" fra ").iata
  end

  def test_answers_nil_for_anything_it_does_not_hold
    assert_nil Trackberry::Airports.find("ZZZ")
    assert_nil Trackberry::Airports.find(nil)
    assert_nil Trackberry::Airports.find("")
    assert_nil Trackberry::Airports.find("EDDF")
    assert_nil Trackberry::Airports.city("ZZZ")
    assert_equal [], Trackberry::Airports.subdivision_path("ZZZ")
  end

  def test_gives_coordinates_with_string_keys
    point = Trackberry::Airports.coordinates("LHR")

    assert_in_delta 51.47, point["lat"], 0.05
    assert_in_delta(-0.46, point["lng"], 0.05)
  end

  def test_drops_the_note_in_brackets_after_a_city
    assert_equal "Helsinki", Trackberry::Airports.city("HEL")
  end

  # OurAirports stops at Grand Est; the map adds the department and
  # Alsace-Moselle, where Good Friday is a holiday.
  def test_places_an_airport_below_the_level_ourairports_gives
    assert_equal %w[FR-67 FR-6AE FR-GES], Trackberry::Airports.subdivision_path("SXB")
    assert_equal "FR-67", Trackberry::Airports.subdivision("SXB")
    assert_equal "FR-GES", Trackberry::Airports.principal_subdivision("SXB")
  end

  def test_places_airports_where_holidays_differ_by_region
    assert_equal %w[DE-HH], Trackberry::Airports.subdivision_path("HAM")
    assert_equal "DE-BY", Trackberry::Airports.principal_subdivision("MUC")
    assert_equal "ES-VC", Trackberry::Airports.principal_subdivision("VLC")
    assert_equal "GB-ENG", Trackberry::Airports.principal_subdivision("LHR")
    assert_equal "US-FL", Trackberry::Airports.principal_subdivision("MIA")
  end

  def test_the_table_is_whole
    assert_operator Trackberry::Airports.count, :>=, Trackberry::Airports::Diff::MINIMUM_COUNT
    Trackberry::Airports::Diff::ANCHORS.each { |iata| refute_nil Trackberry::Airports.find(iata), iata }
  end

  def test_all_hands_out_a_copy
    all = Trackberry::Airports.all
    all.clear

    refute_empty Trackberry::Airports.all
  end

  def test_says_how_fresh_the_data_is
    assert_match(/\A\d{4}-\d{2}-\d{2}\z/, Trackberry::Airports.data_fetched_on)
  end
end
