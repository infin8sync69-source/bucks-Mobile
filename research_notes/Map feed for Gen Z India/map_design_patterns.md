# Interaction and Ranking Design Patterns for User-Generated Local Content on a Map (Bucks)

Scope: how to show trending or most-recommended Bucks posts (recommend / not-recommend votes) as points on a map, where tapping a point opens the post in the "For you" feed. It has to work on low-end Android and for older or low-literacy users.
Research date: 2026-11-09. About 17 search and fetch calls. Several primary design write-ups (Zomato, Swiggy, Zillow, Yelp, Citymapper) did not turn up; the Gaps sections list them.

## 1. Clustering vs heatmaps vs pins vs thumbnails-as-pins (legibility and low-end performance)

### Takeaway
Use native style-layer points with built-in clustering, not per-point marker objects or view annotations. Show a heat or activity layer only as an optional "where it's busy" overview. Show a few large thumbnail or labelled pins only at street zoom, for the top-ranked items. None of the sources gives an official marker-count threshold, so profile on a real low-end device.

### Cited Findings
- Google's clustering guidance says clustering helps when markers crowd together, even with "fewer than 25 locations". It recommends clustering for maps with "dozens or more markers". Defaults: 2 markers form a cluster (`minimumClusterSize`); grid cell is 60x60 px (`gridSize`); the cluster centre is the average position of its markers; tapping a cluster zooms to reveal its markers (`zoomOnClick`, on by default); `maxZoom` sets the level beyond which individual markers always show. The page gives no performance benchmarks and does not compare clustering with heatmaps. — [Google Maps Platform blog: How to cluster map markers](https://mapsplatform.google.com/resources/blog/how-cluster-map-markers/); [Marker Clustering article](https://developers.google.com/maps/articles/toomanymarkers)
- The Android Maps Utils clustering utility exists to keep many markers readable at different zoom levels. Its demo app includes a 2,000-marker demo. — [Google Maps Android Marker Clustering Utility](https://developers.google.com/maps/documentation/android-sdk/utility/marker-clustering)
- Field reports on Android performance are mixed. An android-maps-compose GitHub issue reported skipped frames in a release build on a physical device with 10 clusters of 400 markers each. A r/androiddev thread reported >10k clustered points working, with some clustering delay and frame drops but no ANRs. These are anecdotes, not benchmarks. — [android-maps-compose issue #525](https://github-redirect.dependabot.com/googlemaps/android-maps-compose/issues/525); [r/androiddev thread (mirror)](https://reddit.birdcat.cafe/r/androiddev/comments/1c8jo9k/google_maps_poor_performance_in_jetpack_compose)
- Third-party, low-authority thresholds: StoreLocatorWidgets suggests clustering above about 1,000 markers. ZeeMaps says 100 markers is no longer a meaningful limit for Google Maps. — [StoreLocatorWidgets](https://www.storelocatorwidgets.com/blogpost/20465/index); [ZeeMaps](https://www.zeemaps.com/blog/?p=108)
- MapLibre: the official MapLibre Flutter docs compare annotations with style layers. Annotations offer no clustering; style layers do. The docs recommend style layers when performance matters (large datasets) or clustering is needed. — [MapLibre Flutter: Annotations vs Layers](https://maplibre.org/flutter-maplibre-gl/concepts/annotations-vs-layers/)
- The MapLibre Native Android docs show clustering by creating a GeoJsonSource with clustering options and rendering it through a CircleLayer. — [MapLibre Native Android: circle layer example](https://maplibre.org/maplibre-native/android/examples/styling/circle-layer/)
- Mapbox Android docs (the API MapLibre forked from) render cluster counts in a SymbolLayer by reading the `point_count` property of a clustered GeoJSON source. — [Mapbox Android: Data clustering](https://docs.mapbox.com/android/legacy/maps/guides/clustering.md); [SymbolLayer clustering example](https://docs.mapbox.com/android/legacy/maps/examples/symbol-layer-clustering)
- Geoapify (web context) warns that each HTML marker is a DOM element, so you should avoid thousands of them. Use a symbol layer when many points share an image or need filtering or clustering. A third-party Mapbox web guide suggests symbol layers beyond about 100 markers; these are web heuristics, not Android numbers. — [Geoapify: How to add markers](https://apidocs.geoapify.com/how-to/maps/add-map-markers/); [Mapbox web performance patterns (third-party)](https://mcpservers.org/ru/agent-skills/mapbox/mapbox-web-performance-patterns)
- Snap Map uses a heat map, the "Explore" layer, to show the volume of public Snap activity in an area. Busy places show as icons that open into a combined story of public Snaps. With Explore on, those icons become larger and animated. Snap's web map shows only public stories, never individual users' locations. — [TechCrunch: Snap Map layers](https://techcrunch.com/?p=2235313); [Engadget](https://www.engadget.com/snapchat-map-layers-memories-explore-snap-map-160648193.html); [TechCrunch 2018: Snap Map on web](https://techcrunch.com/2018/02/12/snapchats-snap-map-comes-to-the-web-including-in-embeddable-form)
- Vendor and practitioner observation: maps become cluttered when they show many results. — [TravelTime blog](https://traveltime.com/blog/how-to-convert-visitors-map-view)

### Inferences
- For Bucks the safest stack on low-end Android is one GeoJSON source (MapLibre) or the Maps Utils ClusterManager (Google Maps) with clustering on. Render plain coloured circles with a count and a category glyph, as SymbolLayer or CircleLayer, rather than bitmap thumbnails for every point. Thumbnails-as-pins cost an image decode and a texture each. Limit them to the top N (around 10–20) posts in the current viewport at high zoom, and show them as the "hero" points.
- A heatmap does not suit the core job ("tap a point, open that post"), because a heat blob has nothing specific to tap. Snap uses heat to answer "where is it busy" and places icons to open content. Bucks could copy that split: heat at city zoom (optional layer), clusters at neighbourhood zoom, and individual tappable pins at street zoom.
- Cluster badges should show a number and a dominant-category icon (food, shop, ride, event), plus a short text label for low-literacy users. A count alone tells a user little.
- Since none of the sources gives a hard ceiling, set a client cap (for example, the server returns at most a few hundred ranked points per viewport) and test frame rate on a 2–3 GB RAM device. This is a design suggestion, not a sourced number.

### Gaps
- I found no official Google, MapLibre, or osmdroid benchmark of marker counts against frame rate on low-end Android. osmdroid limits were not researched; I found no reliable source.
- Vector vs raster tile cost on low-RAM devices: no primary source found in this pass.

## 2. Map + list/sheet hybrid patterns; map-first vs feed-first

### Takeaway
Evidence favours list-first, with the map as a secondary view linked to it. Lists beat maps on task speed and preference in user studies. Big local apps put map-sourced content into a feed, as Google Maps does with its Explore and Updates feeds. When Bucks uses a sheet over the map, follow NN/g's bottom-sheet rules: a visible Close button, Back closes the sheet, never gesture-only, no stacked sheets.

### Cited Findings
- A peer-reviewed empirical comparison of mobile interfaces for location-based information found the list interface performed best on all tasks for completion time. AR came second and the map interface was worst. — [Interfaces for accessing location-based information on mobile devices: An empirical evaluation (NTU)](https://nanyangtechnologicaluniv.demo.elsevierpure.com/en/publications/interfaces-for-accessing-location-based-information-on-mobile-dev)
- In a small prototype study (Medium, practitioner), users preferred the simplicity of a vertical list over the richer information of a map interface. — [Interactive Prototype + User Study: Maps vs Lists](https://medium.com/theuxblog/interactive-prototype-user-study-maps-vs-lists-c551edeccf68)
- A heuristic evaluation of an event app recommended numbering map markers to match their list entries, so users can link items across both views. — [Berkeley i213 heuristic evaluation](https://courses.ischool.berkeley.edu/i213/s07/projects/naturalist/trac.inaturalist.org/wiki/UIAssignment6.html)
- NN/g (Laubheimer, June 2023) on bottom sheets:
  - Use them for short, contextual information when users need to keep referring to the background, which here is the map.
  - Nonmodal sheets let users keep interacting with the background; expandable sheets typically start nonmodal and become modal at full height.
  - Problems: no clear way to dismiss, confusion when sheets stack, hidden background content, and full-screen sheets that look like pages while Back does nothing.
  - Swipe-down dismissal is easy to miss, conflicts with system panels, and is hard for users with limited dexterity.
  - Recommendations: Back must dismiss the sheet, show a visible X or Close, never rely on the grab handle alone, avoid stacking, and don't use sheets for long content or for page-to-page flows such as detail pages.
  - The "thumb reachability" argument for bottom sheets is largely wrong, because the middle of the screen is easiest to tap.
  - [NN/g: Bottom Sheets](https://www.nngroup.com/articles/bottom-sheet/)
- Airbnb: a secondary analysis says Airbnb found map pins have no inherent "top" ranking, unlike a list. It changed map ranking so that pins reflect ML-predicted booking likelihood, and the change came from studying user behaviour rather than new technology. — [TechScoop: How Airbnb Made Map Search Smarter](https://techscoop.substack.com/p/how-airbnb-made-map-search-smarter)
- Google Maps' 2020 redesign added a Contribute tab and renamed "For you" to "Updates", a feed of trending, must-see spots from Local Guides and publishers. A late-2020 Community feed inside Explore shows the latest reviews, photos and posts from local experts, followed people, and food and drink merchants. — [Google blog: Community feed](https://blog.google/products/maps/discover-more-with-google-maps-community-feed); [9to5Google 2020](https://9to5google.com/2020/02/12/new-google-maps-available/)

### Inferences
- For Bucks, the map is best as an entry point *into* the "For you" feed, as the brief already specifies, rather than as the home screen. Tapping a point should open a small nonmodal preview card first: photo, one-line title, recommend %, distance, a large "Open post" button and a visible X. A further tap jumps to the full post in the feed, so the map is never a dead end.
- A horizontal carousel of the top posts in the viewport, synced with the highlighted pins, gives users with low map literacy a list-style way to browse. List-first evidence supports keeping that path.
- Auto-refreshing as the user pans is costly on slow networks and can feel unstable. A "Search this area" button gives the user control. This pattern is common (Google Maps, Airbnb), but I found no primary write-up with metrics.
- Airbnb's point applies directly: pins have no visible rank, so show rank in the visual itself. Top 3 get a larger pin or thumbnail with a "Top" or "Trending" tag; the rest are plain dots.

### Gaps
- No primary design write-ups were found from Zillow, Yelp, Zomato, Swiggy or Citymapper on map+list hybrids, and no NN/g article specifically on map vs list. No conversion or engagement numbers for map-first vs feed-first home screens.

## 3. Freshness, ranking (recency + votes + distance), anti-domination, cold start

### Takeaway
Use the Wilson lower bound to rate quality from recommend / not-recommend votes, a gravity-style time decay (as in Hacker News) for freshness, and a distance term. Add per-author caps for diversity. The vote and time formulas are well documented. Diversity caps and cold-start seeding are mostly design inference, with only thin sourcing.

### Cited Findings
- Wilson lower bound (Evan Miller, 2009, updated 2016). Sort by the lower bound of the Wilson score interval, not by net score or average:
  - Formula: `(p̂ + z²/2n − z·√[(p̂(1−p̂) + z²/4n)/n]) / (1 + z²/n)`, with z = 1.96 for 95% confidence.
  - Net score fails: 600 up / 400 down (60%) ranks below 5,500 / 4,500 (55%).
  - Average fails: 2 / 0 (100%) ranks above 100 / 1 (~99%).
  - [Evan Miller: How Not To Sort By Average Rating](https://www.evanmiller.org/how-not-to-sort-by-average-rating.html)
- Caveat: a Wilson score is 0 for an item with no ratings or no positive ratings, so new items need separate handling. — [Medium: Wilson lower bound and Bayesian approximation](https://medium.com/tech-that-works/wilson-lower-bound-score-and-bayesian-approximation-for-k-star-scale-rating-to-rate-products-c67ec6e30060)
- Reddit "hot" (as commonly documented from Reddit's open-source code): `sign·log10(max(|ups−downs|,1)) + (t − 1134028003)/45000`.
  - The log means the first 10 votes weigh as much as the next 100.
  - Scores do not decay. Newer posts simply get a time bonus, roughly +1 order of magnitude of votes per 12.5 hours.
  - [Medium: How Reddit ranking algorithms work](https://medium.com/hacking-and-gonzo/how-reddit-ranking-algorithms-work-ef111e33d0d9); [Lemmy ranking docs](https://git.join-lemmy.org/asonix/lemmy/src/branch/master/docs/ranking.md)
- Hacker News: `(points − 1) / (hours + 2)^G` with gravity G = 1.8 by default. Scores decrease as time passes, and there is no log term. Sources are secondary gists and blogs, so verify constants against the original source. — [Medium: How Reddit ranking algorithms work](https://medium.com/hacking-and-gonzo/how-reddit-ranking-algorithms-work-ef111e33d0d9); [Lemmy ranking docs](https://git.join-lemmy.org/asonix/lemmy/src/branch/master/docs/ranking.md)
- Strava's Global Heatmap shows no heat unless multiple people have done activities in an area, which is a minimum-contributor threshold. — [Malwarebytes on Strava heatmap](https://www.malwarebytes.com/blog/news/2023/06/strava-heatmap-loophole-may-reveal-users-home-addresses)
- Google Maps mixes several content sources in its local feed (Local Guides, followed users, merchants, publishers such as The Infatuation). It does not rely on user posts alone. — [Google blog: Community feed](https://blog.google/products/maps/discover-more-with-google-maps-community-feed)

### Inferences (proposed formula, not sourced as a whole)
- Suggested map score: `score = wilson_lb(recommends, not_recommends) × freshness × proximity`.
  - `freshness = 1/(hours+2)^G`, with G around 1.2–1.8, tuned per category. Events and "happening now" decay fast; shops and services decay slowly or not at all.
  - `proximity` is a gentle falloff, for example `1/(1 + d/d0)` with d0 around 2–5 km in cities and larger in small towns.
  - Use Wilson for "Most recommended" (time-insensitive) and the decay-weighted version for "Trending".
- Use time chips as filters ("Now", "Today", "This week") rather than hidden decay alone. Users with low literacy understand explicit time windows better than an opaque "hot" score.
- Anti-domination:
  - Cap the number of pins per author per viewport (for example, at most 1–2).
  - Damp votes from repeat voter–author pairs and from new or low-trust accounts.
  - Require a minimum number of distinct voters before a post can show as "Trending". This mirrors Strava's minimum-contributor rule.
- Cold start for empty towns:
  - Use Google's mixed-source approach. Seed the map with Bucks' own business listings (shops, services), events and ride hubs as base pins.
  - Show user posts on top of those base pins.
  - When a viewport has fewer than about 5 posts, show a "Be the first to recommend a place here" card instead of an empty map.
  - Give new posts a short exploration boost, because Wilson scores them at 0. Alternatively, use a Bayesian prior: add pseudo-votes, for example 2 recommends and 1 not-recommend.

### Gaps
- I found no published ranking write-up from Swiggy, Zomato, Yelp or Nextdoor on mixing distance and votes for local UGC. No data on per-author diversity caps. No sourced cold-start playbook for hyperlocal maps in small Indian towns.

## 4. Engagement mechanics that are not dark patterns; gamification fatigue

### Takeaway
Foursquare is the cautionary example. Points, badges and mayorships drove early check-ins, but users took them more seriously than intended. Extrinsic rewards wore off, and badges "couldn't be used for anything". Foursquare split check-ins out into Swarm in 2014 and later partly brought the playfulness back. Favour mechanics that have a use (saved collections or trails, "been there" that improves your recommendations, events and "happening now") over status points.

### Cited Findings
- In 2014 Foursquare moved check-ins into Swarm and refocused the main app on local discovery, dropping badges and mayorships. — [Search Engine Land](https://searchengineland.com/foursquare-abandons-check-ins-better-compete-yelp-google-190298); [VentureBeat](https://venturebeat.com/ai/foursquares-new-swarm-app-means-the-death-of-badges-mayors/); [TheNextWeb](https://thenextweb.com/apps/2014/05/15/can-foursquares-new-swarm-app-save-check/)
- Dennis Crowley later admitted Swarm had lost much of its playfulness. One of his complaints was that badges couldn't be used for anything, so Swarm replaced them with stickers that users can post or send. — [TechCrunch](https://techcrunch.com/?p=1151888)
- Commentary (lower quality, partly AI-generated research outlines): the founders were surprised how seriously users took points and badges, and the extrinsic rewards gave only temporary engagement. — [AskWonder](https://askwonder.com/research/foursquare-gamification-lessons-learned-6f0an6dsn); [Centrical](https://centrical.com/resources/with-swarm-foursquare-goes-full-circle-with-its-gamification-mechanics/)
- Users who wanted a reason to check in were disappointed when nothing happened afterward. — [Le Chic Geek](https://lechicgeek.boardingarea.com/foursquare-to-bring-back-gamification-to-platform/)
- Google Maps has a Contribute tab and the Local Guides programme as its contributor engagement layer. The Updates and Community feeds surface contributions from followed people and local experts. — [9to5Google 2020](https://9to5google.com/2020/02/12/new-google-maps-available/); [Google blog](https://blog.google/products/maps/discover-more-with-google-maps-community-feed)
- Snap Map added a private Memories layer and an Explore layer of public activity. The map works as a personal history as well as a discovery surface. — [Social Media Today](https://www.socialmediatoday.com/news/snapchat-adds-new-layers-option-to-snap-map-to-highlight-memories-popula/610169/); [Engadget](https://www.engadget.com/snapchat-map-layers-memories-explore-snap-map-160648193.html)

### Inferences
- For Bucks, low-risk mechanics:
  - "Save to my list" collections ("Best chai near college", "Weekend plan"), shareable to WhatsApp.
  - A "Been there" tick, which feeds both the user's recommend vote and their personal map. The tick has a clear use, unlike badges.
  - A "Happening now / Today" layer for events and offers that expire.
  - A neighbourhood-level "Top recommenders this month" shown as recognition, with no points economy.
- Notifications should fire only on concrete local value: a saved place has a new offer, an event you saved starts in an hour, or your post got X recommends. Avoid generic "see what's trending" pushes and streaks.
- Avoid streaks, loss-framed reminders and leaderboards that reward volume, since volume-rewarding leaderboards encourage spam votes and conflict with the anti-domination goal.

### Gaps
- I found no peer-reviewed 2018–2026 study quantifying gamification fatigue in location apps, no engagement metrics for Google Local Guides, and no evidence on local leaderboards in India.

## 5. Accessibility, older and low-literacy users, first-time smartphone users

### Takeaway
Use 48×48 dp minimum touch targets (Material). WCAG 2.2 sets 24×24 CSS px as the AA floor. Use literal icons with text labels, never icons alone, and no gesture-only actions; NN/g's bottom-sheet guidance supports this. Keep navigation shallow and add in-context guidance. Evidence on low-literacy smartphone use is thin and partly dated.

### Cited Findings
- Material Design minimum touch target: 48×48 dp. WCAG 2.2 SC 2.5.8 Target Size (Minimum, AA) requires 24×24 CSS px or equivalent spacing; SC 2.5.5 (AAA) asks for 44×44. An Android accessibility guide says targets *should* be ≥48dp and *must* be ≥24dp. — [CVS Health Android accessibility techniques](https://github.com/cvs-health/android-view-accessibility-techniques/blob/main/doc/basics/MinimumTouchTargetSize.md); [W3C Understanding 2.5.8 (draft copy)](https://raw.githack.com/w3c/wcag/Issue2431-target-size/understanding/22/target-size-minimum.html); [Deque: Android touch target spacing](https://docs.deque.com/devtools-mobile/2024.9.18/en/android-touch-target-spacing)
- NN/g: swipe-only dismissal is hard for users with limited dexterity and easy to miss. Provide a visible Close and support the Back button. — [NN/g: Bottom Sheets](https://www.nngroup.com/articles/bottom-sheet/)
- IDEO.org fieldwork in Dhaka: when testing "Send Money" icons, every user chose the most literal one, an envelope with a banknote flying out. Abstract icons such as a paper plane need reinforcement that new users lack. — [IDEO.org: Designing for today's behaviors and tomorrow's potential](https://www.ideo.org/perspective/designing-for-todays-behaviors-and-tomorrows-potential)
- "Text is not the enemy" (Knoche & Huang, illiterate phone users; older, feature-phone era):
  - Culturally unadapted icons were a recurring problem.
  - Illiterate users used phones with text partly through recognition and memorisation, so text plus icon is better than removing text.
  - [Knoche & Huang, Text is not the enemy](https://researchgate.net/profile/Hendrik-Knoche/publication/266595198_Text_is_not_the_enemy_How_illiterates'_use_their_mobile_phones/links/5849ac7508ae5038263d88aa/Text-is-not-the-enemy-How-illiterates-use-their-mobile-phones.pdf)
- Google and practitioner guidance for new internet users recommends:
  - In-the-moment guidance about the next step.
  - Avoiding deep nesting and hierarchy, which is disorienting.
  - Visual metaphors drawn from users' everyday lives.
  - [Medium: Designing for New Internet Users](https://medium.com/last-mile-money/designing-for-new-internet-users-26d1f7d842dc); [Google I/O '17 Designing for the Next Billion Users (video)](https://echai.ventures/startingup/r/designing-for-the-next-billion-users-google-i-o-17--bc-r217)
- A 2019 UCL study notes that few studies examine how low-literate users interact with smartphones. — [Skarlatidou et al., ECSCW 2019](https://discovery.ucl.ac.uk/10078615/1/ecscw2019_Skarlatidou_ep02.pdf)

### Inferences
- Map-specific:
  - Pins of at least 48 dp tap area, even when the visual dot is smaller. When pins overlap, tapping should open a small list rather than demand precision.
  - Category icon plus a colour that is not the only cue (WCAG "use of color").
  - Short labels in the user's language (Hindi or regional) on top pins and cluster badges.
  - "Recommended by 23 people" in words, not just a % or a thumbs icon.
  - "+ / −" zoom buttons and a "My location" button as alternatives to pinch.
  - Voice search for the search bar.
  - Always provide a "Show as list" toggle.
- Avoid map-only affordances such as long-press to drop a pin or two-finger tilt as the only route to a feature.

### Gaps
- I found no source specifically on map literacy among first-time smartphone users in India, and no study comparing icon-only and icon+label pins on maps. Colour-contrast requirements for map pins over varied basemaps were not researched in depth. WCAG 1.4.11 non-text contrast of 3:1 is the likely standard but was not fetched in this pass.

## 6. Content-on-map privacy (venue snapping, delay, fuzzing, opt-in)

### Takeaway
Aggregation alone does not protect people. In a 2023 NC State study, Strava's aggregated heatmap still exposed home addresses, with about 37.5% accuracy for very active users and better results in sparse areas. Industry practice is to show public content tied to *places* or *areas* rather than people: Snap Map's web version shows only public stories, Nextdoor shows neighbourhood but not address, and Android 12 offers "approximate" location of about 3 km². For Bucks, snap posts to a venue or locality by default, never plot exact GPS from homes, and enforce minimum-density thresholds that are stricter in small towns.

### Cited Findings
- NC State researchers (IEEE ConPro 2023) matched Strava heatmap activity endpoints with public profile data to infer home addresses. With a 100 m threshold and a victim posting 308 activities, the likelihood of discovery was 37.5%, checked against voter registration data. Results were stronger for highly active users and in sparsely populated areas.
  - Data inside users' hidden privacy zones could still feed the aggregate heatmap.
  - The researchers proposed heatmap-level privacy zones and excluding a few metres around homes.
  - Strava responded that heat appears only where multiple people have been active, and that users can opt out of contributing.
  - [Childs et al., ConPro 2023 (PDF)](https://conpro23.ieee-security.org/papers/childs-conpro23.pdf); [Malwarebytes](https://www.malwarebytes.com/blog/news/2023/06/strava-heatmap-loophole-may-reveal-users-home-addresses); [BleepingComputer](https://www.bleepingcomputer.com/news/security/strava-heatmap-feature-can-be-abused-to-find-home-addresses/)
- Snap Map on web shows only public stories, not individual users' locations, and Snap said privacy was "top of mind". The Memories layer is private. — [TechCrunch 2018](https://techcrunch.com/2018/02/12/snapchats-snap-map-comes-to-the-web-including-in-embeddable-form); [Engadget](https://www.engadget.com/snapchat-map-layers-memories-explore-snap-map-160648193.html)
- Nextdoor (privacy-policy summary): your neighbourhood name is visible to members, but your specific address is not shared by default. Location tags on posts (events, pickups) are optional. — [ConductAtlas summary of Nextdoor Privacy Policy](https://conductatlas.com/platform/nextdoor/nextdoor-privacy-policy/neighborhood-verification-and-address-data/); [location data added to posts](https://conductatlas.com/platform/nextdoor/nextdoor-privacy-policy/location-data-added-to-posts-by-user/)
- Android 12 added a per-app choice of precise or approximate location; approximate places the device in an area of about 3 km². — [Android Central](https://www.androidcentral.com/whats-difference-between-precise-and-approximate-location-android-12); [How-To Geek](https://www.howtogeek.com/763227/what-are-precise-and-approximate-locations-on-android/)
- Instagram says it never shares precise location publicly. Location tags are user-chosen places and work whatever the device's precise-location setting, so what a user tags is what gets exposed. — [Fox61 Verify](https://fox61.com/article/news/verify/social-media/instagram-doesnt-share-precise-location-publicly/536-14a75f19-84a6-433c-830a-3854d9ede146); [TechRadar](https://www.techradar.com/how-to/instagrams-precise-location-tracking-is-nothing-new-heres-how-to-turn-it-off)

### Inferences
- Bucks defaults:
  1. A post appears on the map only if it is tagged to a venue (a Bucks business or a public POI) or to a locality centroid. Untagged posts made from GPS snap to the locality or ward centroid, never to raw coordinates.
  2. Location tagging is opt-in per post, with a clear preview ("Will show at: Sharma Sweets, Lajpat Nagar").
  3. Users can set a home privacy radius; posts made inside it never get map placement.
  4. Use a small publishing delay for "live" content from individuals. Snapping to venues makes this less necessary.
  5. Hide author identity on the map pin itself; the post page can show it.
  6. Small towns need stronger area snapping, per the sparse-area finding: show posts only once an area has a minimum number of distinct contributors.
- Ride posts and anything showing a user's route should never be plotted as points on the public layer.

### Gaps
- No primary source on Snap Map's location fuzzing internals. No quantitative guidance on minimum k-anonymity thresholds for UGC map pins. Indian legal context (DPDP Act 2023 rules on location as personal data) was not researched in this pass.
