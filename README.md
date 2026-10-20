# trackberry-airports

Every airport with an IATA code (about 9,000), with its name, city, position and ISO 3166-2 subdivision, as a table shipped inside the gem. No network calls.

```ruby
require "trackberry/airports"

Trackberry::Airports.find("FRA")              # => #<data Trackberry::Airports::Airport iata="FRA", icao="EDDF", ...>
Trackberry::Airports.city("FRA")              # => "Frankfurt am Main"
Trackberry::Airports.country("FRA")           # => "DE"
Trackberry::Airports.coordinates("FRA")       # => { "lat" => 50.0267, "lng" => 8.5584 }
Trackberry::Airports.subdivision_path("SXB")  # => ["FR-67", "FR-6AE", "FR-GES"]
```

An unknown code answers `nil` (or `[]` for a path): carriers send city codes ("LON") and codes of airports that have closed, and that is ordinary, not an error.

## Subdivisions

`subdivision_path` is the ISO 3166-2 code of the area the airport is in and every code above it, most specific first, the same shape [seaports](https://github.com/Trackberry/seaports) gives for a port. Hand it to [trackberry-holidays](https://github.com/Trackberry/holidays), which matches a holiday at any level of the path:

```ruby
Trackberry::Holidays.holiday?(Date.new(2027, 5, 27), Trackberry::Airports.subdivision_path("MUC"))  # => true, Corpus Christi in Bavaria
Trackberry::Holidays.holiday?(Date.new(2027, 5, 27), Trackberry::Airports.subdivision_path("HAM"))  # => false, not in Hamburg
```

Where the code comes from, best first (the `subdivision_source` column says which):

| Source | Airports | Example |
| --- | --- | --- |
| `override`: a reviewed list, `data/sources/subdivision_overrides.csv` | 0 | |
| `boundaries`: the airport's position on Natural Earth's states-and-provinces map | 831 | Strasbourg `FR-67`, Beijing `CN-BJ` |
| `ourairports`: OurAirports' `iso_region` | 7,903 | Frankfurt `DE-HE`, Hamburg `DE-HH` |

The map is used two ways:
- **To go below OurAirports.** OurAirports stops at the top level: Grand Est for Strasbourg. When the map finds an area inside that code (Bas-Rhin, inside Alsace-Moselle, inside Grand Est), the airport gets the longer path, because some rules are kept at that level (Alsace-Moselle has two public holidays the rest of France does not, though Nager.Date does not list them yet). When the map disagrees with OurAirports, OurAirports wins.
- **To fill a gap.** OurAirports still writes some codes ISO has replaced, such as China's pre-2017 numeric ones, and `XX-U-A` for "unassigned".

8,734 of 9,051 airports are placed. The 317 left have no subdivision because both sources still use codes ISO has retired (Poland, Norway, South Africa, Czechia, Kazakhstan) or the territory has none (French Polynesia, Puerto Rico). None of them is in a country whose public holidays differ by region, so a holiday lookup by country is complete for them.

Every code is checked against ISO 3166-2 when the table is built. The ISO hierarchy and the map lookup are seaports' `Seaports::Subdivisions` and `Seaports::Boundaries`, used by the build only: the gem itself depends on neither.

## Cities

`city` is OurAirports' municipality without a trailing note in brackets: "Helsinki", not "Helsinki (Vantaa)". It is the town the airport serves, which is not always the one it stands in.

## Data

[OurAirports](https://ourairports.com/data/) (public domain), filtered to airports with an IATA code that are not closed. When two rows share a code, the one with scheduled flights wins, then the larger airport. Coordinates are rounded to four decimal places (about ten metres).

## Refresh

`.github/workflows/refresh.yml` runs on the 3rd of every month:

1. `rake airports:refresh` downloads OurAirports, the ISO 3166-2 list and the Natural Earth map, and rebuilds `data/airports.csv`.
2. `Trackberry::Airports::Diff` checks the result before anything ships:
   - at least 8,500 airports;
   - the table shrinks by no more than 2%;
   - airports with a subdivision fall by no more than 2%;
   - no more than 2% move to another principal subdivision;
   - two dozen major airports (FRA, LHR, JFK, LIM…) are all present.
3. If it passes, the job opens a pull request listing every added, removed, renamed, moved and resubdivided airport. If it fails, or a download fails, it opens an issue instead.

Merging a refresh bumps the minor version, and `.github/workflows/release.yml` publishes it to Trackberry's GitHub Packages registry.

To rebuild from files already on disk: `bundle exec rake "airports:refresh[airports.csv,iso_3166-2.json,admin1.geojson]"`.

## Install

```ruby
source "https://rubygems.pkg.github.com/trackberry" do
  gem "trackberry-airports", "~> 0.1", require: "trackberry/airports"
end
```
