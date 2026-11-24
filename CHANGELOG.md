# Changelog

Data refreshes are minor versions, opened as pull requests by the monthly refresh workflow. Code changes are written here by hand.

## 0.4.0 — 2026-11-24

Added `Trackberry::Airports.timezone(iata)` and `Airport#timezone`: the IANA zone each airport keeps time in, such as "Europe/Madrid", built into new `timezone` and `timezone_source` columns of the table. Every airport has one: 9,048 from timezone-boundary-builder's map (release 2026f) checked against tzdata's zones for the airport's country, and four reviewed overrides in `data/sources/timezone_overrides.csv`. Xinjiang's airports get Beijing time, which aviation keeps there. The table is now also under OpenStreetMap's ODbL. `Airport` has a new member, `timezone`, which defaults to nil, so code that builds one without it still works. No other method or field changed, and the airport data is the same as in 0.3.0.

Requires Ruby 3.3 or newer. Ruby 3.2 reached end of life on 2026-03-31 and is no longer tested.

## 0.3.0 — 2026-11-08

Added `Trackberry::Airports.short_name(iata)`: a compact label such as "London Heathrow" or "Lima Jorge Chávez", built into a new `short_name` column of the table, with nine reviewed overrides in `data/sources/short_name_overrides.csv`. No existing method or `Airport` field changed.

## 0.2.0 — 2026-11-03

OurAirports as of 2026-11-03. 9052 airports (9051 before): 2 added, 1 removed, 3 renamed, 0 with a new city, 7 repositioned, 0 with a new subdivision (0 moved to another principal one).

Removed: TDT.

## 0.1.1 — 2026-10-26

Published on rubygems.org instead of GitHub Packages. The table is licensed under the ODbL, as a derivative of OpenFlights' database; the code stays MIT.

## 0.1.0 — 2026-10-20

First release: every OurAirports airport with an IATA code, with the city it serves (from OpenFlights), the town it stands in, its position and its ISO 3166-2 subdivision path, and the monthly refresh.
