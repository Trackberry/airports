# Build inputs

Files here feed `rake airports:refresh` and are not shipped in the gem; only the table they help build is.

## subdivision_overrides.csv

Reviewed ISO 3166-2 subdivisions for airports that neither OurAirports nor Natural Earth's map places, as `iata,subdivision,note`. An override wins over every other source, so a row should be removed once a source places the airport itself; each refresh lists the rows that have reached that point.

It is empty: every airport left unplaced is in a country whose holidays do not differ by region. Add a row when that stops being true.

## timezone_overrides.csv

Reviewed IANA time zones for airports the time zone map gets wrong or places in a zone that is not its country's, as `iata,timezone,note`: an airport on a zone border, a base that keeps another country's time. An override wins over the map and is not checked against the airport's country, so a row should be removed once the map gives the same zone and that zone passes the check; each refresh lists those rows, the ones whose airport has gone, and every airport left without a zone.

## served_cities.csv

The city each airport serves, as `iata,city,lat,lng`, extracted once from OpenFlights' `airports.dat` by `script/extract_served_cities.rb`. OpenFlights stopped updating in 2019, so the file is not refreshed; the position lets the build skip a city whose code now belongs to another airport. A code OpenFlights lists twice is left out.

© OpenFlights contributors, available under the [Open Database License](https://opendatacommons.org/licenses/odbl/1-0/).

## short_name_overrides.csv

Reviewed labels for `Trackberry::Airports.short_name`, as `iata,short_name,note`, for the airports the rule (the name without "Airport" and "International", the city in front when the name lacks it) gets wrong: an official name that is too long, a repeated word. An override wins over the rule, so a row should be removed once the rule gives the same label; each refresh lists those rows and the ones whose airport has gone.
