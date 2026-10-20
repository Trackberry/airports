# Build inputs

Files here feed `rake airports:refresh` and are not shipped in the gem; only the table they help build is.

## subdivision_overrides.csv

Reviewed ISO 3166-2 subdivisions for airports that neither OurAirports nor Natural Earth's map places, as `iata,subdivision,note`. An override wins over every other source, so a row should be removed once a source places the airport itself; each refresh lists the rows that have reached that point.

It is empty: every airport left unplaced is in a country whose holidays do not differ by region. Add a row when that stops being true.

## served_cities.csv

The city each airport serves, as `iata,city,lat,lng`, extracted once from OpenFlights' `airports.dat` by `script/extract_served_cities.rb`. OpenFlights stopped updating in 2019, so the file is not refreshed; the position lets the build skip a city whose code now belongs to another airport. A code OpenFlights lists twice is left out.

© OpenFlights contributors, available under the [Open Database License](https://opendatacommons.org/licenses/odbl/1-0/).
