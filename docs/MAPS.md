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
