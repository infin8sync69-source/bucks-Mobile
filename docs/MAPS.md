# Maps, location and routes

| Piece | What Bucks uses now | Key needed | Limit |
|---|---|---|---|
| Map tiles | OpenStreetMap standard tiles through osmdroid (`ui/components/BucksMap.kt`) | No | Light use only under the OSM tile policy |
| Place search and "what's here" | Photon, photon.komoot.io (`data/MapServices.kt`) | No | Fair use |
| Road route, distance, time | OSRM public server, router.project-osrm.org (`data/MapServices.kt`) | No | Demo server, light use |
| Turn-by-turn for drivers | The phone's Google Maps app (`openNavigation` in `DriverScreens.kt`) | No | Needs Google Maps installed |
| Live positions | Phone GPS (fused location); drivers stream theirs to Supabase, riders follow it | No | Already built |

Everything above is fine for the pilot. Before a public launch, move search, routes and tiles to a paid provider with an
Indian address base (Ola Maps, Google Maps Platform or Mappls). Replace the three functions in `MapServices.kt`
(`search`, `label`, `route`) and the tile source in `BucksMap.kt`. No screen changes. Check each provider's current pricing
and free tier when choosing.

Every map call fails soft. When offline, Bucks draws straight lines, uses straight-line distance for the fare, and offers
the built-in list of places.

## The Recommended layer on Home

Home's map has a "Recommended" layer (Android `ui/screens/RecommendedMap.kt`, iOS `Screens/Home/RecommendedMap.swift`). It shows places,
never people: Bucks pages and locality centres that posts are tagged to, read through `map_places` and `map_place_posts`
(`supabase/migrations/map_recommended.sql`, built on the guardrails in `map_guardrails.sql`). Places are ranked by the Wilson lower bound of
recommend votes. The top ten get numbered labels and a matching strip in the sheet; tapping a pin opens a card with See posts, Directions,
Open page and Share. The layer loads for the area on screen, then again only on "Search this area" or a chip change.

Both apps' maps centre on you once (after the first real location fix) and then stay where the person puts them; the My location button
brings them back.
