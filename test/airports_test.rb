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
    assert_equal "Frankfurt", airport.city
    assert_equal "Frankfurt am Main", airport.municipality
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

  # The city a courier names, not the town the runway is in.
  def test_names_the_city_an_airport_serves
    assert_equal "Brussels", Trackberry::Airports.city("BRU")
    assert_equal "Zaventem", Trackberry::Airports.find("BRU").municipality
    assert_equal "Athens", Trackberry::Airports.city("ATH")
  end

  # "London" is five airports, so the label says which.
  def test_short_name_keeps_the_city_the_name_already_says
    assert_equal "London Heathrow", Trackberry::Airports.short_name("LHR")
    assert_equal "London Gatwick", Trackberry::Airports.short_name("LGW")
  end

  def test_short_name_puts_the_city_in_front_of_a_name_that_lacks_it
    assert_equal "Lima Jorge Chávez", Trackberry::Airports.short_name("LIM")
    assert_equal "Bogota El Dorado", Trackberry::Airports.short_name("BOG")
  end

  def test_short_name_of_an_airport_named_for_its_city_is_the_city
    assert_equal "Dubai", Trackberry::Airports.short_name("DXB")
    assert_equal "Miami", Trackberry::Airports.short_name("MIA")
  end

  # The name says "São Paulo", the city is stored as "Sao Paulo"; the official
  # name is too long, so it is a reviewed label that keeps the accent.
  def test_short_name_compares_an_accented_city_without_its_accent
    assert_equal "Sao Paulo", Trackberry::Airports.city("GRU")
    assert_equal "São Paulo Guarulhos", Trackberry::Airports.short_name("GRU")
    assert_equal "Istanbul Sabiha Gökçen", Trackberry::Airports.short_name("SAW")
  end

  def test_short_name_uses_the_reviewed_override
    assert_equal "Frankfurt", Trackberry::Airports.short_name("FRA")
    assert_equal "Paris Orly", Trackberry::Airports.short_name("ORY")
    assert_equal "New York JFK", Trackberry::Airports.short_name("JFK")
  end

  def test_short_name_tolerates_case_and_answers_nil_for_an_unknown_code
    assert_equal "London Heathrow", Trackberry::Airports.short_name(" lhr ")
    assert_nil Trackberry::Airports.short_name("ZZZ")
    assert_nil Trackberry::Airports.short_name("LON")
    assert_nil Trackberry::Airports.short_name(nil)
  end

  def test_short_name_leaves_the_airport_alone
    assert_equal "London Heathrow Airport", Trackberry::Airports.name("LHR")
    refute_respond_to Trackberry::Airports.find("LHR"), :short_name
  end

  def test_every_airport_has_a_short_name
    Trackberry::Airports.all.each { |airport| refute_nil Trackberry::Airports.short_name(airport.iata), airport.iata }
  end

  # OurAirports stops at Grand Est; the map adds the department and, for
  # Strasbourg, the European Collectivity of Alsace above it. Moselle (Metz)
  # sits directly in Grand Est: ISO has no Alsace-Moselle code.
  def test_places_an_airport_below_the_level_ourairports_gives
    assert_equal %w[FR-67 FR-6AE FR-GES], Trackberry::Airports.subdivision_path("SXB")
    assert_equal "FR-67", Trackberry::Airports.subdivision("SXB")
    assert_equal "FR-GES", Trackberry::Airports.principal_subdivision("SXB")
    assert_equal %w[FR-57 FR-GES], Trackberry::Airports.subdivision_path("ETZ")
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
    Trackberry::Airports::Diff::ANCHOR_REGIONS.each do |iata, region|
      assert_equal region, Trackberry::Airports.principal_subdivision(iata), iata
    end
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
