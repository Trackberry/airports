# trackberry-airports

Every airport with an IATA code (about 9,000), with its name, city, position, ISO 3166-2 subdivision and IANA time zone, as a table shipped inside the gem. No network calls.

```ruby
require "trackberry/airports"

Trackberry::Airports.find("FRA")              # => #<data Trackberry::Airports::Airport iata="FRA", icao="EDDF", ...>
Trackberry::Airports.city("FRA")              # => "Frankfurt"
Trackberry::Airports.short_name("LIM")        # => "Lima Jorge Chávez"
Trackberry::Airports.country("FRA")           # => "DE"
Trackberry::Airports.coordinates("FRA")       # => { "lat" => 50.0267, "lng" => 8.5584 }
Trackberry::Airports.subdivision_path("SXB")  # => ["FR-67", "FR-6AE", "FR-GES"]
Trackberry::Airports.timezone("MAD")          # => "Europe/Madrid"
```

An unknown code answers `nil` (or `[]` for a path): carriers send city codes ("LON") and codes of airports that have closed, and that is ordinary, not an error.

## Why not the `airports` gem

[`airports`](https://github.com/timrogers/airports) is the established gem for this, and it does the plain lookup well. This one exists for what it does not do:

- **Fresh data.** `airports` is built from OpenFlights, which stopped updating in 2019, and adds the airports opened since by hand (`BER`, `HYD`). This one is built from OurAirports, which is still maintained, and rebuilt every month behind checks that stop a bad download from shipping.
- **Where the airport is, inside its country.** `airports` gives the country as a name ("United Kingdom"). This one gives the ISO 3166-2 country code and subdivision path, which is what a regional holiday calendar or a customs rule keys on.
- **Numbers as numbers.** Coordinates are floats, not strings.
- **Time zones from the map, not a 2019 list.** `airports` takes OpenFlights' zone names, which often stand in a neighbouring zone for the airport's own: Anchorage for Nome, Mexico City for Matamoros, Santiago for Punta Arenas. Those agree for a while and part ways at the next daylight saving rule change, and for about fifty airports they already have. See [Time zones](#time-zones).

## Subdivisions

`subdivision_path` is the ISO 3166-2 code of the area the airport is in and every code above it, most specific first, the same shape [seaports](https://github.com/Trackberry/seaports) gives for a port. Hand it to a holiday calendar that matches a holiday at any level of the path, such as Trackberry's own (not published):

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
- **To go below OurAirports.** OurAirports stops at the top level: Grand Est for Strasbourg. When the map finds an area inside that code, the airport gets the longer path: Bas-Rhin, inside the European Collectivity of Alsace, inside Grand Est. Some rules are kept at those levels. Alsace and Moselle have two public holidays the rest of France does not, which a calendar would key on `FR-6AE` and `FR-57`; Nager.Date does not list them yet. When the map disagrees with OurAirports, OurAirports wins. The map answers with the area containing the airport, and only for an airport outside every area (built on reclaimed land, past the drawn coastline) with the nearest one within 10 km.
- **To fill a gap.** OurAirports still writes some codes ISO has replaced, such as China's pre-2017 numeric ones, and `XX-U-A` for "unassigned".

8,734 of 9,051 airports are placed. The 317 left have no subdivision because both sources still use codes ISO has retired (Poland, Norway, South Africa, Czechia, Kazakhstan) or the territory has none (French Polynesia, Puerto Rico). None of them is in a country whose public holidays differ by region, so a holiday lookup by country is complete for them.

Every code is checked against ISO 3166-2 when the table is built. The ISO hierarchy and the map lookup are seaports' `Seaports::Subdivisions` and `Seaports::Boundaries`, used by the build only: the gem itself depends on neither.

## Time zones

`timezone` is the IANA id of the zone the airport keeps time in, `"Europe/Madrid"`, so a local time read from a waybill or an email ("lands 05:30") can be turned into an instant for any date, before any feed has sent an offset, and across a daylight saving change. It is a string: hand it to `TZInfo::Timezone.get` or `ActiveSupport::TimeZone[]`. The gem has no time zone dependency.

Every airport has one. Where it comes from (the `timezone_source` column):

| Source | Airports | Example |
| --- | --- | --- |
| `override`: a reviewed list, `data/sources/timezone_overrides.csv` | 4 | Gold Coast `Australia/Brisbane` |
| `boundaries`: the airport's position on [timezone-boundary-builder](https://github.com/evansiroky/timezone-boundary-builder)'s map | 9,048 | Madrid `Europe/Madrid`, Nome `America/Nome` |

The map is the "with oceans" edition, whose zones reach over territorial waters, so an airport on reclaimed land (HKG, KIX, MLE) still falls in its country's zone. Every zone it gives is checked against tzdata's list of zones for the airport's country: a Spanish airport can be in `Europe/Madrid`, `Africa/Ceuta` or `Atlantic/Canary` and nothing else. One that fails is left without a zone and listed in the refresh pull request until an override gives it one. Guantánamo's base, inside Cuba on US Eastern time, is the case the check catches.

One rule overrides the map: Xinjiang's airports get `Asia/Shanghai`, not `Asia/Urumqi`. Xinjiang keeps a local clock two hours behind Beijing, which is what tzdata records, but its airports and airlines run on Beijing time.

### Your tzdata has to know the zone

The table is built against tzdata 2026f, and the application that reads a zone has to know it too. tzinfo, and so ActiveSupport, reads the system's zoneinfo (`/usr/share/zoneinfo`, from the OS `tzdata` package) unless the `tzinfo-data` gem is installed, in which case it reads that instead. Either can be older than the table: `America/Coyhaique`, Chile's Aysén region, has only existed since tzdata 2025b.

- In a Docker image, the base image's `tzdata` package is what counts. Current Debian and Ubuntu images carry it, and rebuilding picks up updates.
- With `tzinfo-data` in the Gemfile (Windows, JRuby, or by choice), keep the gem current.
- An unknown zone raises `TZInfo::InvalidTimezoneIdentifier`, and `ActiveSupport::TimeZone[]` answers nil. Treat that as an airport with no zone rather than an error.

## Cities

`city` is the city the airport serves, the one a carrier, a courier or a person names: "Brussels", "Athens", "Leipzig". `municipality` is the town it stands in, as OurAirports gives it: "Zaventem", "Spata-Artemida", "Schkeuditz". They are the same for most airports.

The served city comes from [OpenFlights](https://openflights.org/data) for the 6,000 airports it lists. OpenFlights stopped updating in 2019, so its cities were extracted once into `data/sources/served_cities.csv` by `script/extract_served_cities.rb`, from a pinned commit. A city carries over only when OpenFlights puts the airport within 50 km of OurAirports' position, so a code IATA has since given to another airport does not bring the old city with it. Every other airport takes its municipality, without a trailing note in brackets: "Helsinki", not "Helsinki (Vantaa)".

The subdivision always follows where the airport is, not the city it serves: Cincinnati's airport is in Kentucky (`US-KY`), not Ohio.

## Short names

`short_name` is the label to show beside a code when the city alone is not enough ("London" is five airports): "London Heathrow", "Lima Jorge Chávez", "Dubai". It is the airport's name without "Airport", "International" and their translations, with the city put in front when what is left does not already say it (compared without accents or case).

Where that reads badly (an official name that runs to eight words, a repeated word, a dotted İ), a reviewed label wins: `data/sources/short_name_overrides.csv`, as `iata,short_name,note`. Like the subdivision overrides it is a build input, not shipped; the label is built into the `short_name` column of the table, so a monthly refresh keeps it. Each refresh lists the rows whose airport has gone or that the rule now labels the same, so they can be removed. An unknown code answers `nil`.

## Data

[OurAirports](https://ourairports.com/data/) (public domain), filtered to airports with an IATA code that are not closed. When two rows share a code, the one with scheduled flights wins, then the larger airport. Coordinates are rounded to four decimal places (about ten metres).

Served cities: [OpenFlights](https://openflights.org/data), © OpenFlights contributors, available under the [Open Database License](https://opendatacommons.org/licenses/odbl/1-0/).

Time zones: [timezone-boundary-builder](https://github.com/evansiroky/timezone-boundary-builder), built from [OpenStreetMap](https://www.openstreetmap.org/copyright) data, © OpenStreetMap contributors, available under the [Open Database License](https://opendatacommons.org/licenses/odbl/1-0/).

## License

The code is MIT. The table (`data/airports.csv`) is a derivative of OpenFlights' database and of OpenStreetMap's (through the time zone map), so it is under the [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/): a database you build from it and use publicly has to credit OpenFlights and OpenStreetMap and be offered under the ODbL too. Using the gem to look airports up does not. See `LICENSE.txt`.

## Refresh

`.github/workflows/refresh.yml` runs on the 3rd of every month:

1. `rake airports:refresh` downloads OurAirports, the ISO 3166-2 list, the Natural Earth map and the time zone map, and rebuilds `data/airports.csv`. The time zone map is 185 MB unzipped: the rebuild takes about a minute and 1.5 GB of memory.
2. `Trackberry::Airports::Diff` checks the result before anything ships:
   - at least 8,500 airports;
   - the table shrinks by no more than 2%;
   - airports with a subdivision fall by no more than 2%;
   - no more than 2% move to another principal subdivision;
   - two dozen major airports (FRA, LHR, JFK, LIM…) are all present;
   - fourteen of them, in countries whose holidays differ by region, keep their principal subdivision (FRA in `DE-HE`, MUC in `DE-BY`…), because one country's codes breaking stays under the percentage caps;
   - airports with a time zone fall by no more than 2%, no more than 2% move to another zone, and seven anchors keep theirs (FRA in `Europe/Berlin`, URC in `Asia/Shanghai`…).
3. If it passes, the job opens a pull request listing every added, removed, renamed, moved, re-citied, resubdivided and rezoned airport, and starts CI on it. If it fails, or a download fails, it opens an issue instead.

Merging a refresh bumps the minor version, and `.github/workflows/release.yml` publishes it to [rubygems.org](https://rubygems.org/gems/trackberry-airports).

To rebuild from files already on disk: `bundle exec rake "airports:refresh[airports.csv,iso_3166-2.json,admin1.geojson,timezones-with-oceans.geojson.zip]"` (the time zone map can also be the unzipped `.json`). The `.zip` needs `unzip` on the path.

## Install

```ruby
gem "trackberry-airports", "~> 0.1", require: "trackberry/airports"
```
