# frozen_string_literal: true

require "test_helper"

class DiffTest < Minitest::Test
  Diff = Trackberry::Airports::Diff

  # A table that passes every gate, every airport placed, so each test can
  # break exactly one thing and know that is what it is reading.
  def healthy(extra = {})
    airports = (Diff::ANCHORS | Diff::ANCHOR_REGIONS.keys).to_h { |iata| [iata, anchor(iata)] }
    filler = Diff::MINIMUM_COUNT + 100 - airports.size - extra.size
    filler.times { |index| airports[format("%03d", index).tr("0-9", "A-J")] = airport("Filler #{index}") }
    airports.merge(extra)
  end

  def airport(name, point: [1.0, 2.0], path: "DE-HH", city: "City")
    { name: name, city: city, point: point, path: path }
  end

  def test_a_city_change_ships
    diff = Diff.new(healthy("ZZ1" => airport("A", city: "Zaventem")), healthy("ZZ1" => airport("A", city: "Brussels")))

    assert_equal [%w[ZZ1 A Zaventem Brussels]], diff.recitied
    assert_predicate diff, :changed?
    assert_includes diff.summary, "`ZZ1` A: Zaventem → Brussels"
  end

  def anchor(iata)
    airport(iata, path: Diff::ANCHOR_REGIONS.fetch(iata, "DE-HH"))
  end

  def test_refuses_a_table_that_moved_an_anchor_out_of_its_region
    after = healthy("FRA" => airport("FRA", path: "DE-BY"))
    lost = healthy("MUC" => airport("MUC", path: ""))

    assert(Diff.new(healthy, after).failures.any? { |line| line.include?("`FRA` is now in DE-BY, not DE-HE") })
    assert(Diff.new(healthy, lost).failures.any? { |line| line.include?("`MUC` is now in no subdivision") })
  end

  def test_a_table_that_did_not_move_reports_no_change
    diff = Diff.new(healthy, healthy)

    refute_predicate diff, :changed?
    assert_predicate diff, :ok?
  end

  def test_names_what_a_refresh_added_and_took_away
    diff = Diff.new(healthy("ZZ1" => airport("Gone")), healthy("ZZ2" => airport("New")))

    assert_equal ["ZZ2"], diff.added
    assert_equal ["ZZ1"], diff.removed
    assert_predicate diff, :ok?
    assert_includes diff.summary, "`ZZ1` Gone"
  end

  def test_lists_renames_and_moves
    diff = Diff.new(healthy("ZZ1" => airport("Old")), healthy("ZZ1" => airport("New", point: [1.5, 2.0])))

    assert_equal [%w[ZZ1 Old New]], diff.renamed
    assert_equal [["ZZ1", "New", :moved]], diff.repositioned
  end

  def test_a_county_change_inside_the_same_nation_still_ships
    diff = Diff.new(healthy("ZZ1" => airport("A", path: "GB-SFK GB-ENG")), healthy("ZZ1" => airport("A", path: "GB-NFK GB-ENG")))

    assert_equal [["ZZ1", "A", "GB-SFK GB-ENG", "GB-NFK GB-ENG"]], diff.resubdivided
    assert_empty diff.reassigned
    assert_predicate diff, :changed?
    assert_includes diff.summary, "GB-SFK › GB-ENG → GB-NFK › GB-ENG"
  end

  def test_refuses_a_table_below_the_floor
    small = healthy.first(Diff::MINIMUM_COUNT - 1).to_h

    refute_predicate Diff.new(small, small), :ok?
  end

  def test_refuses_a_table_that_shrank_too_far
    before = healthy
    anchors = (Diff::ANCHORS | Diff::ANCHOR_REGIONS.keys).to_h { |iata| [iata, anchor(iata)] }
    after = before.except(*anchors.keys).first((before.size * 0.97).floor).to_h.merge(anchors)

    assert(Diff.new(before, after).failures.any? { |line| line.include?("shrank") })
  end

  def test_refuses_a_table_that_lost_an_anchor
    after = healthy
    after.delete("FRA")

    assert(Diff.new(healthy, after).failures.any? { |line| line.include?("`FRA`") })
  end

  def test_refuses_a_table_that_lost_its_subdivisions
    after = healthy.transform_values { |row| row.merge(path: "") }

    assert(Diff.new(healthy, after).failures.any? { |line| line.include?("with a subdivision fell") })
  end

  def test_refuses_a_table_that_moved_many_airports_to_another_region
    after = healthy.transform_values { |row| row.merge(path: "DE-NI") }

    assert(Diff.new(healthy, after).failures.any? { |line| line.include?("another principal subdivision") })
  end

  def test_reads_a_written_table
    Dir.mktmpdir do |dir|
      path = File.join(dir, "airports.csv")
      File.write(path, "#{Trackberry::Airports::Builder::HEADERS.join(',')}\nSXB,LFST,Strasbourg,Strasbourg,Entzheim,FR,48.5383,7.6282,large_airport,yes,FR-67,FR-GES,FR-67 FR-6AE FR-GES,boundaries\n")

      assert_equal({ "SXB" => { name: "Strasbourg", city: "Strasbourg", point: [48.5383, 7.6282], path: "FR-67 FR-6AE FR-GES" } },
                   Diff.read(path))
    end
  end
end
