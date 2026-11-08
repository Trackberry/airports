# frozen_string_literal: true

require "test_helper"

class ShortNameTest < Minitest::Test
  ShortName = Trackberry::Airports::ShortName

  def test_drops_airport_and_keeps_the_city_the_name_already_says
    assert_equal "London Heathrow", ShortName.build("London Heathrow Airport", "London")
  end

  def test_prefixes_the_city_when_the_name_does_not_say_it
    assert_equal "Lima Jorge Chávez", ShortName.build("Jorge Chávez International Airport", "Lima")
  end

  def test_an_airport_named_for_its_city_is_just_the_city
    assert_equal "Dubai", ShortName.build("Dubai International Airport", "Dubai")
  end

  # Accents and case do not count as a difference: the table says "Sao Paulo"
  # for a name that says "São Paulo".
  def test_compares_the_city_without_accents_or_case
    assert_equal "São Paulo/Congonhas", ShortName.build("São Paulo/Congonhas Airport", "Sao Paulo")
    assert_equal "İstanbul", ShortName.build("İstanbul Airport", "Istanbul")
    assert_equal "ZÜRICH", ShortName.build("ZÜRICH Airport", "Zurich")
  end

  def test_strips_generic_words_in_other_languages_and_the_dashes_they_leave
    assert_equal "Madrid-Barajas", ShortName.build("Aeropuerto Internacional Madrid-Barajas", "Madrid")
    assert_equal "Leipzig/Halle", ShortName.build("Flughafen Leipzig/Halle", "Leipzig")
    assert_equal "Quito Mariscal Sucre", ShortName.build("Mariscal Sucre International Airport -", "Quito")
  end

  def test_falls_back_to_the_city_when_nothing_is_left
    assert_equal "Nowhere", ShortName.build("International Airport", "Nowhere")
    assert_equal "International Airport", ShortName.build("International Airport", nil)
  end

  def test_leaves_the_name_alone_without_a_city
    assert_equal "Jorge Chávez", ShortName.build("Jorge Chávez International Airport", nil)
  end

  def test_a_reviewed_override_wins
    assert_equal "Frankfurt", ShortName.build("Frankfurt Main Airport", "Frankfurt", override: "Frankfurt")
    assert_equal "Elsewhere", ShortName.build("Frankfurt Main Airport", "Frankfurt", override: "Elsewhere")
  end
end
