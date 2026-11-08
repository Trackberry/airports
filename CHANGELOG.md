# Changelog

Data refreshes are minor versions, opened as pull requests by the monthly refresh workflow. Code changes are written here by hand.

## 0.3.0 — 2026-11-08

Added `Trackberry::Airports.short_name(iata)`: a compact label such as "London Heathrow" or "Lima Jorge Chávez", built into a new `short_name` column of the table, with nine reviewed overrides in `data/sources/short_name_overrides.csv`. No existing method or `Airport` field changed.

## 0.2.0 — 2026-11-03

OurAirports as of 2026-11-03. 9052 airports (9051 before): 2 added, 1 removed, 3 renamed, 0 with a new city, 7 repositioned, 0 with a new subdivision (0 moved to another principal one).

Removed: TDT.

## 0.1.1 — 2026-10-26

Published on rubygems.org instead of GitHub Packages. The table is licensed under the ODbL, as a derivative of OpenFlights' database; the code stays MIT.

## 0.1.0 — 2026-10-20

First release: every OurAirports airport with an IATA code, with the city it serves (from OpenFlights), the town it stands in, its position and its ISO 3166-2 subdivision path, and the monthly refresh.
