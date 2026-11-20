# Pork and alcohol: clear-haram keyword classification for Indian marketplace search

Tag legend (used in every table):
- **WORD**: whole-word match, Latin script, case-insensitive (`\bpork\b`).
- **EXACT**: whole word only, never as a stem. Used for short Indic words whose letters start other ordinary words.
- **PREFIX**: Indic stem. Match the stem plus any suffix (case endings, compounds).
- **PHRASE**: match only when the listed context word sits next to it. The bare word is a false-positive trap.

Provenance note: the pig/pork words for Hindi, Urdu, Kannada, Malayalam, Tamil and Telugu come from Wiktionary (cited). The native-script compounds and the alcohol words in Indic scripts were **not** checked against a dictionary page in this research. They come from general language knowledge and are marked "(unverified)". A native speaker of each language should check them before they ship.

## Q1. Pork: words for pig/pork and pork dishes sold in India

### Takeaway
"Pork", "pig meat", "wild boar", the regional dish names (sorpotel, chouriço / Goa sausage, pandi curry) and the native words for pig are safe clear-haram keywords. But two of the native words for pig collide with everyday words:
- Kannada ಹಂದಿ *handi* collides with the Hindi cooking pot "handi".
- Telugu/Kodava *pandi* collides with Tamil personal and shop names like Pandi or Pandian.

So the romanised forms of these two words need a context word next to them, while the native script can match on its own.

### Cited Findings
- Pig translations: Hindi सूअर (sūar); Urdu سُؤَر (suar), خِنْزِیر (xinzīr), خُوک (xūk); Kannada ಹಂದಿ (handi); Malayalam പന്നി (panni), കിടി (kiṭi); Tamil பன்றி (paṉṟi); Telugu పంది (pandi), సూకరము (sūkaramu); Konkani डुक्कर (ḍukkar); Marathi डुकर (ḍukar); Bengali শূকর / শুয়োর — [Wiktionary: pig](https://en.wiktionary.org/wiki/pig)
- Pork translations: Hindi सुअर का मांस (suar kā māns), सुअर का गोश्त (suar kā gośt); Urdu سُؤَر کا گوشْت — [Wiktionary: pork](https://en.wiktionary.org/wiki/pork)
- Pandi curry is the traditional Kodava (Coorg, Karnataka) pork dish, made with pork, pepper and kachampuli. It was originally made with wild boar, and country pork is used now — [Karnataka Tourism](https://karnatakatourism.org/experiences/pandi-curry-kodava-pork-curry); [The South First](https://thesouthfirst.com/featured/pandi-curry-a-culinary-triumph-from-coorg)
- Goan pork dishes:
  - Sorpotel (sarapatel) is pork cooked in a spicy, vinegary sauce, often with offal and blood.
  - Chouriço are spicy Goan pork sausages, sold wet or dried.
  - Other pork dishes: assado, kailitulem, amsol, bafad, balchao.
  - Vindaloo comes from Portuguese *carne de vinha d'alhos* ("meat, usually pork"), but in Goa it is also made with fish, prawns and squid.
  - Xacuti is usually chicken or lamb, not pork.
  — [Goan cuisine, Wikipedia](https://Www.Wikipedia.org/wiki/Goan_cuisine); [Gomantak Times](https://www.gomantaktimes.com/ampstories/web-stories/beyond-sausages-fiery-and-flavourful-pork-delicacies-of-goa); [Asia Society](https://asiasociety.org/node/98)

### Inferences — PORK clear-haram table

| Keyword | Script / lang | Tag | Notes |
|---|---|---|---|
| pork | English | WORD | Covers "pork fry", "pork curry", "pork ribs", "pork belly", "pork chop", "pork pickle" |
| porky, porkchop | English | WORD | Listing spellings |
| pig meat, pig fat, pig skin, pigskin | English | WORD / PHRASE | Bare "pig" is a trap (see Q7) |
| piglet, piglets (with "for sale", "farm", "live") | English | PHRASE | Live pig sale. Bare "piglet" collides with the Winnie-the-Pooh toy |
| pig farm, piggery, swine | English | WORD | "piggery" and "swine" have no common halal meaning |
| boar, wild boar | English | WORD | Exception: "boar bristle brush" is still a pig product, so hide it too (see below) |
| boar bristle, pig bristle, hog hair | English | PHRASE | Pig-hair brushes. Selling pig parts is haram under the mainstream view. Put this in a separate brush rule so the brand can decide |
| hog, hogs | English | WORD | Trap: "Harley hog" is rare; acceptable risk |
| lard, pork lard, pork fat | English | WORD | In Indian retail, "lard" means pig fat by default |
| bacon | English | WORD | Pork by default. **Exception context**: "chicken bacon", "turkey bacon", "veg/vegan bacon" (see Q2) |
| pancetta, prosciutto, gammon, guanciale, lardo, jamón, speck | English / Italian | WORD | Always pork |
| chorizo, chouriço, chourico, choriz | English / Portuguese | WORD | Goan chorizo is pork. "chicken chorizo" exists, so exempt the "chicken" context |
| goa sausage, goan sausage, goan sausages | English | PHRASE | A Goan sausage is pork chouriço |
| sorpotel, sarapatel, sorpatel | English / Konkani | WORD | Exception: "sorpotel masala" (spice mix, see Q6) |
| pork vindaloo | English | PHRASE | Bare "vindaloo" is doubtful (chicken vindaloo is common) |
| pandi curry, pandi fry, pandi meat, pandhi curry, coorg pork | English / Kodava | PHRASE | Bare "pandi" is a trap (Tamil names: Pandi, Pandian, Pandi Stores) |
| balchao (with "pork") | English / Konkani | PHRASE | Prawn balchão is common, so bare "balchao" is a trap |
| suar, suwar, suar ka gosht, suar ka mans | Romanised Hindi / Urdu | WORD | Do **not** add "soor" or "sur": they are music notes and the name Surdas |
| सूअर, सुअर, शूकर | Hindi (Devanagari) | PREFIX | Covers सूअर का मांस |
| خنزیر, خنزير | Urdu / Arabic | PREFIX | Covers خنزیر کا گوشت |
| سؤر / سور | Urdu | EXACT | Bare سور is close to سورہ / سورۃ (Quran chapter) and سُور (trumpet). Better: only "سور کا گوشت" as a PHRASE |
| khinzir, khanzir | Romanised Urdu | WORD | |
| ಹಂದಿ | Kannada | PREFIX | Covers ಹಂದಿಮಾಂಸ / ಹಂದಿ ಮಾಂಸ (unverified compound). I know of no common Kannada word that starts with ಹಂದಿ. (ಹಂದರ "pandal" stops at ಹಂದ and is not matched) |
| handi mamsa, handi mansa, handi meat | Romanised Kannada | PHRASE | Bare "handi" = Hindi pot ("chicken handi", "Handi restaurant"). Never match it alone |
| పంది మాంసం, పందిమాంసం | Telugu | PHRASE / EXACT | **Do not PREFIX పంది**: పందిరి (*pandiri*, pandal/canopy) starts with it. Use EXACT పంది plus the compound (unverified compound) |
| pandi mamsam, pandi kura | Romanised Telugu | PHRASE | |
| പന്നി, പന്നിയിറച്ചി | Malayalam | PREFIX | പന്നിയിറച്ചി (*panniyirachi* = pork, unverified compound). Check that place names like "Panniyur" don't over-match (low risk) |
| panni erachi, panniyirachi, panni fry, panni curry | Romanised Malayalam | PHRASE | Bare "panni" = colloquial Tamil "did/made" (பண்ணி). Never match it alone |
| பன்றி | Tamil | PREFIX | Covers பன்றிக்கறி (*panri kari*, unverified compound) |
| panri, pandri, panri kari, pandri kari | Romanised Tamil | WORD | No common collision found |
| डुक्कर, डुकर | Konkani / Marathi | PREFIX | Useful for Goa and Maharashtra sellers |
| वराह | Hindi / Sanskrit | — | **Leave out**: Varaha is a Vishnu avatar (temple and puja items) |

Northeast pork (Nagaland "smoked pork with bamboo shoot", Assam "pork with axone") is matched by the word "pork". No separate tribal-language words were researched (see Gaps).

### Gaps
- No dictionary was fetched for the native-script compounds (ಹಂದಿಮಾಂಸ, పందిమాంసం, പന്നിയിറച്ചി, பன்றிக்கறி). They are unverified spellings.
- No source was found for the Nagamese, Khasi, Mizo or Garo words for pork (e.g. Garo *wak*). They were left out.
- The etymology of Kodava "pandi" was not confirmed by any source found.

## Q2. Processed meats: pork by default vs commonly chicken in India

### Takeaway
In Indian retail, salami, sausage, ham and pepperoni are very often chicken, so these words must not be hidden on their own. Hide them only when "pork" (or a pork-only word) appears next to them. Bacon, lard and Goan chouriço are pork by default and can be hidden, with chicken/turkey/veg as the exception context.

### Cited Findings
- Major Indian brands sell chicken versions widely: Venky's chicken sausages and chicken spicy salami; Zorabian, Meatzza, Prasuma, Monsa, Punjab Maratha and Total all sell chicken salami — [BigBasket Venky's](https://www.bigbasket.com/pd/254562/venkys-cold-cut-chicken-sausages-300-g-pouch); [BigBasket Zorabian](https://bigbasket.com/pd/40020424/zorabian-chicken-salami-250-g-pouch); [BigBasket Prasuma](https://bigbasket.com/pd/40089040/prasuma-chicken-chilli-salami-200-g)
- BigBasket groups these under a "sausages-bacon-salami" category with a separate chicken sub-category. That shows the bare words are mixed categories — [BigBasket chicken sausages](https://www.bigbasket.com/pc/eggs-meat-fish/sausages-bacon-salami/chicken-sausages/)
- Vegan "chicken" and "pork" sausages also exist in India (Blue Tribe) — [Green Queen](https://www.greenqueen.com.hk/?p=53924)

### Inferences

| Item | Default in India | Rule |
|---|---|---|
| bacon | pork | WORD hide. Exempt when "chicken", "turkey", "veg", "vegan" or "plant" is next to it |
| lard | pork | WORD hide |
| chouriço / Goa sausage | pork | WORD / PHRASE hide. Exempt "chicken chorizo" |
| ham | mixed. Hinglish "ham" = "we" | **Do not hide bare**. Hide "pork ham", "smoked ham", "ham slices", "honey ham", "ham sandwich"? → only "pork ham" is clear. Others are doubtful because chicken ham is sold |
| salami | mostly chicken | Hide only "pork salami" |
| sausage | mostly chicken | Hide only "pork sausage" / "pork sausages" |
| pepperoni | mostly chicken in Indian pizza chains (unverified) | Hide only "pork pepperoni" |
| cold cuts, deli meats | mixed | Do not hide |
| vegan / mock pork | plant-based | Exempt when "vegan", "veg", "plant-based" or "mock" is next to it. Some scholars dislike the name; the product itself is halal → doubtful, do not hide |

Matching rule for the engine: if a listing has a pork-only word (`pork|bacon|lard|chorizo|…`) AND an exception word (`chicken|turkey|mutton|veg|vegan|plant|mock|eggless`), do not hide it.

### Gaps
- I found no source confirming what meat is used in pepperoni at specific Indian pizza chains (Domino's or Pizza Hut India).

## Q3. Unambiguously porcine E-numbers and ingredients

### Takeaway
No E-number is unambiguously porcine. Every animal-derived E-number has plant, bovine, fish or synthetic sources. Halal bodies list gelatin (E441), E471, E920 (L-cysteine) and similar as "conditional" or "mashbooh" (doubtful). Only an explicit porcine wording is clear-haram, for example "pork gelatin", "porcine gelatin", "pig fat", "lard" or "porcine enzyme".

### Cited Findings
- Gelatin (E441) is haram when porcine and halal when it comes from properly slaughtered cattle. E471 can be plant- or animal-derived, and labels don't say which. E631 can come from meat, sardines or fermentation. Some certifiers want proof of non-porcine sourcing for E920 (L-cysteine). — [HalalSpy E-numbers](https://halalspy.com/halal-knowledge/ingredients/e-numbers-halal/); [IslamQA.org Mufti Says](https://islamqa.org/hanafi/muftisays/9412/can-you-provide-a-list-of-halal-doubtful-and-haram-e-codes-for-food-ingredients/)
- E120 (carmine/cochineal) is listed as haram by HFA (UK) and JAKIM, but it is an insect product, not a porcine one, and some schools permit it — [HalalSpy](https://halalspy.com/halal-knowledge/ingredients/e-numbers-halal/)
- An IslamQA.org (AskImam) answer is titled as a response to a viral list claiming that many E-numbers (E100, E110, E120, E140, …) "contain pig fat". Lists like that are known to be unreliable rumours — [IslamQA.org AskImam 17401](https://islamqa.org/hanafi/askimam/17401/e-numbers-e100-e110-e120-e-140-e141-e153-e210-e213-e214-e216-e234-and-many-more-contain-pig-fat/)
- An ISA Halal ingredient blog also treats E-codes as source-dependent — [ISA Halal](https://isahalal.com/news-events/blog/know-your-ingredients-halal-food-science-101-and-e-codes)

### Inferences
- CLEAR-HARAM, as PHRASE: "pork gelatin", "porcine gelatin", "pig gelatin", "porcine", "pork extract", "pork fat", "lard".
- "porcine" can be a WORD: it has no halal commercial meaning. A medical "porcine heparin" or "porcine collagen" listing is still a pig derivative, but medicine is a necessity case, so put medicines in a separate review rule.
- DOUBTFUL, do not hide: gelatin, gelatine, E441, E471, E472, E920, L-cysteine, E120, carmine, cochineal, E904 (shellac), E542, E631, E627, rennet, enzymes, glycerin/glycerol (E422), collagen, marshmallow, gummies.

### Gaps
- The JAKIM and HFA master lists were not fetched directly. Their wording above comes through a secondary aggregator (HalalSpy).

## Q4. Alcohol: drink types and words across languages

### Takeaway
All intoxicating drinks are clear haram:
- beer, wine, whisky, rum, vodka, gin, brandy, scotch, liqueur, toddy, arrack, feni, IMFL, country liquor, daru, sharab and their native-script forms.

Neera (unfermented palm sap) is **not** alcoholic and must not be hidden. Toddy (kallu/tadi) is fermented and alcoholic.

Many of these words collide with ordinary words:
- Tamil கள் *kal* is also the plural suffix *-gal*.
- Tamil மது *madhu* is the first part of மதுரை (Madurai).
- Telugu బీర and Tamil பீர் start the word for ridge gourd.
- Kannada and Telugu romanised "kallu" means stone in Kannada, and is close to the Telugu for eyes.

### Cited Findings
- Neera is the fresh sap from the coconut palm's flower. Kerala describes it as "a non-alcoholic nutritious drink" made with anti-fermentation technology. Toddy is the naturally fermented sap at about 4–8% alcohol. Officials said neera should not be classed as toddy because it has no alcohol. — [Wikipedia: Neera](https://en.wikipedia.org/wiki/Neera); [GKToday on Kerala neera](https://www.gktoday.in/benefit-coconut-sector-tapping-unfermented-sap-neera-coconut-approved-kerala-government/); [Onmanorama](https://www.onmanorama.com/news/kerala/2021/02/26/neera-loses-fizz-after-initial-buzz-kerala-coconut-products-crisis.html)
- Telangana sells neera as a packaged non-alcoholic drink — [The News Minute](https://www.thenewsminute.com/article/telangana-s-neera-why-govt-promoting-local-unfermented-toddy-130594); [inkl](https://www.inkl.com/news/palm-tree-nectar-to-be-sold-as-packaged-drink-in-telangana)
- Toddy-shop names: Malayalam *kallu shaap*, Tamil *kallu kadai*, Telugu *kallu dukanam*, Kannada *kallu angadi*. Telugu has *tati kallu* (palmyra) and *eeta kallu* (date palm) — [Tuak / palm wine, Wikipedia mirror](https://www.wikipedia.com/wiki/Tuak)
- In Kerala the alcoholic drink is called *kallu*, distinct from neera. Toddy shops need an excise licence — [Lonely Planet](https://www.lonelyplanet.com/articles/palm-wine-kerala-toddy-shops)
- English "toddy" comes from Hindi *tadi* — [Unsobered](https://unsobered.com/?p=33238)
- Ruling basis: "whatever intoxicates in large quantities is haram in small quantities" (hadith cited) — [IslamQA 9056](https://islamqa.info/en/answers/9056)

### Inferences — ALCOHOL clear-haram table (English / Latin)

| Keyword | Tag | Traps / exempt context (see Q7) |
|---|---|---|
| alcohol, alcoholic | PHRASE | Hide only with drink words: "alcoholic beverage", "alcoholic drink". Exempt: "alcohol-free", "non-alcoholic", "isopropyl", "sanitiser", "rubbing", "ethyl alcohol (lab)" |
| liquor, liquors, liqueur | WORD | Rare traps. "liquor" also = stock in cooking (Indian use is rare) |
| beer, beers | WORD | Exempt: "root beer", "ginger beer", "non-alcoholic beer", "beer mug/glass" (glassware is doubtful) |
| craft beer, draught beer, lager, ale, stout, IPA, pilsner | WORD | "ale" has a collision risk with "Ginger ale" → exempt "ginger ale". "stout" = "stout build" (rare). Better as PHRASE "stout beer" |
| wine, wines | WORD | Exempt: "wine red", "wine colour/color", "wine vinegar", "wine glass", "wine rack" (doubtful). Indian liquor stores are often named "X Wines" |
| wine shop, wine store, wine mart, wines & spirits | PHRASE | Clear |
| whisky, whiskey | WORD | |
| rum | WORD | Exempt: "rum essence", "rum flavour", "rum & raisin" (doubtful, Q6) |
| vodka | WORD | |
| gin | WORD | Exempt: "cotton gin", Hinglish "gin" (= count). Hide only with "gin & tonic", "dry gin", "london dry", "ml/bottle" |
| brandy | WORD | Exempt: personal name "Brandy" (rare in India) |
| scotch, single malt | WORD / PHRASE | Exempt: "scotch brite", "scotch tape", "scotch egg", "butterscotch" (whole-word match already avoids this) |
| champagne, prosecco, sake, soju, tequila, mezcal, absinthe, sangria, mead, cognac, bourbon (drink) | WORD | Exempt: "champagne colour/gold", "bourbon biscuit" |
| cider (alcoholic) | PHRASE | Exempt: "apple cider vinegar", "ACV". Hide only "hard cider" or "cider" + "ml/beer/alcohol" |
| breezer, bacardi breezer | PHRASE | Bare "breezer" = vehicle/air cooler; use "bacardi breezer" |
| IMFL, country liquor, desi daru, desi sharab, angrezi sharab, deshi madira | WORD / PHRASE | |
| daru, daaru, dhaaru | WORD | Exempt: "dawa daru" (colloquial for medicine), Sanskrit *devadaru* (cedar), ayurvedic "daruharidra" (whole-word match already avoids this) |
| sharab, sharaab | WORD | Arabic *sharab* = drink in general, e.g. "sharbat" (different word). Urdu/Hindi usage = alcohol |
| theka (with "desi" / "angrezi" / "sharab") | PHRASE | Bare "theka" = contract |
| toddy, tadi, taadi, tari | WORD / PHRASE | "tari" = gravy in Hindi ("chicken tari") → do not match "tari" alone. Exempt: "toddy palm fruit", "ice apple", "nungu", "palm jaggery", "toddy palm sugar", "neera" |
| toddy shop, kallu shop, kallu shaap, kallu kadai, kallu dukanam, kallu angadi | PHRASE | Clear |
| arrack, arak, saraya, sarayi, charayam, saarayam | WORD | |
| feni, fenny, cashew feni, coconut feni, urrak | PHRASE / WORD | Bare "feni" collides with Odia/Bengali *pheni* (a vermicelli sweet) and Feni district. Use "cashew feni", "coconut feni", "goa feni". "urrak" (first-distil cashew) is WORD |
| mahua daru, mahua liquor, mahua wine | PHRASE | Bare "mahua" = flower, oil, laddoo, and a girl's name → do not hide |
| handia, hadiya (rice beer) | PHRASE | Use "handia rice beer", "haria". Bare "handi" = pot |
| apong, zutho, chhang, lugdi, sulai, rakshi | WORD | Northeast and Himalayan rice/millet beers. Low collision risk (unverified spellings) |
| bar (with "bar & restaurant", "bar and grill", "pub") | PHRASE | Bare "bar" = chocolate bar, soap bar, crowbar, juice bar, Bar Council |
| pub, brewery, brewpub, microbrewery, taproom, distillery | WORD | "pub" also short for PUBG/publication (rare); acceptable |

### Inferences — ALCOHOL in Indic scripts (all unverified spellings)

| Keyword | Lang | Tag | Notes |
|---|---|---|---|
| शराब | Hindi | PREFIX | Covers शराबी (drunkard), शराबखाना |
| شراب | Urdu | EXACT | In Urdu = alcohol. Arabic/Urdu شربت (sharbat) is a different word |
| दारू | Hindi / Marathi | EXACT | Exempt "दवा-दारू" |
| मदिरा, मद्य | Hindi | EXACT | मद्य... also starts मद्यपान (drinking), which is fine. Do not PREFIX मद: मदद = help |
| बीयर, बियर, व्हिस्की, वोडका, ब्रांडी, रम | Hindi | EXACT | रम is short; रमेश, रमज़ान start with it → EXACT only |
| ताड़ी, ठेका देसी | Hindi | EXACT / PHRASE | |
| ಮದ್ಯ | Kannada | PREFIX | Covers ಮದ್ಯಪಾನ, ಮದ್ಯದಂಗಡಿ. ಮಧ್ಯ (*madhya*, middle) is spelled differently (ಧ vs ದ) and does not collide, as long as the matching is exact by codepoint |
| ಸಾರಾಯಿ, ಹೆಂಡ | Kannada | EXACT | ಹೆಂಡ (*henda*) = arrack/toddy; ಹೆಂಡತಿ (*hendati*, wife) starts with it → EXACT, never PREFIX |
| ಕಳ್ಳು | Kannada | EXACT | Toddy. ಕಳ್ಳ (*kalla*, thief) shares the stem → no PREFIX. ಕಲ್ಲು (stone) is a different letter (ಲ vs ಳ) |
| ಬಿಯರ್, ವಿಸ್ಕಿ, ಬ್ರಾಂದಿ | Kannada | EXACT | |
| മദ്യം | Malayalam | PREFIX on മദ്യ | |
| കള്ള്, കള്ളുഷാപ്പ് | Malayalam | EXACT | കള്ളൻ (*kallan*, thief) and കള്ളം (lie) share the stem → EXACT |
| ചാരായം, ബിയർ, വിസ്കി, ബ്രാണ്ടി | Malayalam | EXACT / PREFIX | റം (rum) → EXACT only |
| மது, மதுபானம் | Tamil | EXACT | **Never PREFIX மது**: மதுரை (Madurai), மதுமிதா (name) |
| கள் | Tamil | EXACT, standalone token only | கள் is also the plural suffix (-கள்) → must be a separate whitespace token |
| கள்ளுக்கடை | Tamil | EXACT | Toddy shop |
| சாராயம் | Tamil | PREFIX | |
| பீர் | Tamil | EXACT | **Never PREFIX**: பீர்க்கங்காய் (*peerkangai*, ridge gourd) |
| டாஸ்மாக் | Tamil | PREFIX | TASMAC |
| మద్యం | Telugu | PREFIX on మద్య | |
| కల్లు | Telugu | EXACT | Toddy. కళ్ళు (*kaḷḷu*, eyes) is a different letter. Romanised "kallu" is ambiguous with both |
| సారా, సారాయి | Telugu | EXACT | సారా is also a girl's name (Sara) and "సారాంశం" (summary) starts with సారా → EXACT |
| బీరు, బీర్ | Telugu | EXACT | **Never PREFIX**: బీరకాయ (*beerakaya*, ridge gourd) |
| విస్కీ, బ్రాందీ | Telugu | EXACT | |

### Gaps
- No Indic-script alcohol word was checked against a dictionary page in this research.
- No source was found for "sendhi" (Hindi-belt date-palm toddy).

## Q5. State liquor retail names and unambiguous brand names

### Takeaway
State retail and wholesale corporation names are safe WORD keywords for shop names (BEVCO, TASMAC, TSBCL, APSBCL, KSBCL, MSIL when liquor context is present), as is "MRP outlet". Brands: only brands that are used for nothing except liquor should be hidden. Most big Indian whisky brands (McDowell's, Royal Stag, Imperial Blue, Officer's Choice, Blenders Pride, Kingfisher) also sell surrogate soda, water or music products, or are generic words. They need PHRASE handling or must be left out.

### Cited Findings
- **TASMAC** (Tamil Nadu) has a monopoly on wholesale and retail alcohol and has been the sole retailer since 2003 — [Wikipedia: TASMAC](https://Www.wikipedia.org/wiki/TASMAC)
- **BEVCO**, the Kerala State Beverages (M&M) Corporation (founded 1984), controls IMFL and beer retail in Kerala — [BEVCO](https://bevco.in/bevco-kerala-state-beverages-corporation/); [Wikipedia](https://en.Wikipedia.com/wiki/Kerala_State_Beverages_Corporation)
- **TSBCL** (Telangana State Beverages Corporation, 2014) has a monopoly on wholesale and retail vending in Telangana — [Wikipedia: TSBCL](https://en.wikipedia.org/wiki/Telangana_State_Beverages_Corporation)
- **APSBCL** (Andhra Pradesh State Beverages Corporation) handles liquor procurement and distribution in AP — [PrivateCircle](https://blog.privatecircle.co/?p=58200494); [CAG audit](https://cag.gov.in/uploads/download_audit_report/2021/Chapter%203%20State%20Excise%20Duties-060a7b7d269c024.59900548.pdf)
- **MSIL** (Mysore Sales International Ltd, Karnataka) runs about 1,038–1,066 liquor retail outlets and sells stock sourced from KSBCL (Karnataka State Beverages Corporation). MSIL also has non-liquor businesses (e.g. chit funds, paper), so "MSIL" alone is ambiguous — [Deccan Herald NYE 2025](https://www.deccanherald.com/india/karnataka/mysuru/msil-outlets-see-liqour-sales-almost-double-on-new-years-eve-earn-rs-1811-crore-3848905); [inkl](https://www.inkl.com/news/msil-liquor-shops-face-challenges-as-163-outlets-in-karnataka-encounter-losses); [The News Minute](https://www.thenewsminute.com/karnataka/k-taka-govt-open-900-liquor-stores-make-revenue-loss-due-sc-s-500m-rule-65724)
- Best-selling Indian whisky brands, 2025, in million cases:

  | Brand | Cases (m) |
  |---|---|
  | Royal Stag | 32.6 |
  | McDowell's | 31.9 |
  | Officer's Choice | 20.7 |
  | Imperial Blue | 20.3 |
  | Royal Challenge | 10.6 |
  | Iconiq White | 9.7 |
  | After Dark | 3.0 |
  | Oaksmith | 1.5 |

  — [Drinks International Millionaires' Club 2026](https://drinksint.com/news/fullstory.php/aid/12339/The_Millionaires_92_Club_2026:_the_world_92s_bestselling_Indian_whisky_brands.html)
- Mansion House is India's largest-selling brandy. Courrier Napoleon is another Tilaknagar brandy — [HDFC Sky](https://hdfcsky.com/news/mansion-house-brandy-tops-indian-charts-again-courrier-napoleon)
- Old Monk and Officer's Choice are among India's top liquor brands — [NewsX](https://www.newsx.com/photos/from-old-monk-to-officers-choice-top-five-liquor-brands-in-india-62074)
- Radico Khaitan has seven "millionaire" brands (e.g. 8PM, Magic Moments — names not shown in the snippet) — [Drinks Intel](https://drinks-intel.com/intel/market-intel/how-radico-khaitan-has-grown-into-indias-spirits-powerhouse-market-intel/)

### Inferences

| Keyword | Tag | Status |
|---|---|---|
| BEVCO, TASMAC, TSBCL, APSBCL, KSBCL | WORD | CLEAR (shop and outlet names) |
| MSIL | PHRASE | Hide only with "liquor", "wine", "outlet" or "MRP". MSIL also runs non-liquor businesses |
| MRP liquor outlet, elite wine shop, beverages outlet | PHRASE | CLEAR. Bare "beverages" = soft drinks |
| Smirnoff, Bacardi, Johnnie Walker, Jack Daniel's, Glenfiddich, Glenlivet, Chivas, Jameson, Ballantine's, Teacher's (whisky), Absolut (exact spelling), Jägermeister, Budweiser, Heineken, Carlsberg, Tuborg, Haywards, Old Monk, Bagpiper, Romanov, Black Dog, Antiquity, Iconiq White, Oaksmith, Courrier Napoleon | WORD / PHRASE | CLEAR. These names mean nothing but liquor in Indian retail (unverified individually) |
| McDowell's, Royal Stag, Imperial Blue, Officer's Choice, Blenders Pride, Royal Challenge, Signature, 8PM, Kingfisher, Magic Moments, Mansion House, Honey Bee, After Dark, Amrut, Corona, Knock Out | PHRASE only | Surrogate soda, water or music products ("McDowell's No.1 soda", "Royal Stag Mega Music", "Imperial Blue Superhits", "Kingfisher packaged water"), or generic/halal meanings (kingfisher bird, honey bee, mansion house, magic moments, amrut = nectar or Amrut ayurveda/dairy, Corona virus or Corona brand shoes). Hide only with "whisky", "rum", "brandy", "beer", "vodka", "ml", "bottle", "peg" or "quarter" |
| Iconiq, Royal Challenge alone | — | Low priority |

### Gaps
- Surrogate-product claims (McDowell's soda, Royal Stag music, Imperial Blue CDs, Kingfisher water) come from general knowledge. No source was fetched.
- No primary list of top beer and vodka brands for India in 2025–26 was found.
- The exact names of Radico's seven millionaire brands were not retrieved.

## Q6. Doubtful items: do NOT hide

### Takeaway
These are not to be hidden under the user's rule ("if not sure, leave it out"). Scholars disagree on them, or the alcohol is non-intoxicating, external, medicinal, transformed, or synthetic.

### Cited Findings
- **Perfume, deodorant, attar with alcohol.** IslamQA.info: common perfumes are permissible unless known to intoxicate or be impure. Low alcohol content (5% or less is given as an example) is harmless. Another IslamQA answer calls avoidance only "prudent". Hanafi view: non-grape/date (synthetic) alcohol is not impure, so external use is allowed. — [IslamQA 9056](https://islamqa.info/en/answers/9056); [IslamQA 1365](https://islamqa.info/en/downloads/answers/1365); [IslamQA 59899](https://islamqa.info/en/59899); [Darul Iftaa via IslamQA.org](https://islamqa.org/hanafi/daruliftaa/7755/alcohol-based-perfumes-deodrants-and-creams/)
- **Medicines with alcohol.** Darul Uloom Deoband: alcohol in Indian medicines is usually made from lawful (non-grape/date) sources, so it is not haram. Homeopathic medicine with alcohol is allowed. If the alcohol is from grapes, dates or raisins, the medicine is unlawful. IslamQA: external non-intoxicating medicine is fine, and the Permanent Committee allows non-intoxicating alcohol for medicine and cleaning wounds. — [Deoband 27240](https://islamqa.org/hanafi/darulifta-deoband/27240/is-it-halal-or-haram-to-drink-alcohol-in-medicines/); [Deoband 78693 homeopathy](https://islamqa.org/hanafi/darulifta-deoband/78693/is-it-lawful-to-use-homeopathic-medicine-that-contains-alcohol/); [IslamQA 105101](https://islamqa.info/en/answers/105101)
- **Ayurvedic arishta and asava.** They contain self-generated alcohol, typically about 5–10%, as a vehicle for the herbs. No specific fatwa was found. The general Deoband medicine rulings apply. — [Unacademy](https://unacademy.com/content/determination-of-alcohol-content-in-arishta-and-asava/); [Wisdomlib JAHM](https://www.wisdomlib.org/science/journal/journal-of-ayurveda-and-holistic-medicine/d/doc1476019.html)
- **Wine vinegar.** Hanafi fatwas say red and white wine vinegar are halal because istihala (transformation) removes the prohibition. IslamQA: consensus if the wine turns to vinegar on its own, disputed if the change is deliberately induced. Some consumer groups avoid it. — [IslamQA 2283](https://islamqa.info/en/answers/2283/ruling-on-vinegar-made-from-wine); [Fatwa TT via IslamQA.org](https://islamqa.org/hanafi/fatwa-tt/134100/is-vanilla-extract-essence-and-wine-vinegar-halal/); [SeekersGuidance](https://seekersguidance.org/answers/halal-and-haram/how-do-non-alcoholic-wine-and-wine-vinegar-differ/)
- **Vanilla extract.** It is made with ethyl alcohol. Permitted in the Hanafi school when the alcohol is not from grapes or dates. Alcohol-free vanilla is the cautious option. Egypt's Dar al-Ifta applies istihala/istihlak (transformation/dilution). — [Darul Iftaa Chicago](https://islamqa.org/hanafi/darul-iftaa-chicago/271098/is-vanilla-extract-halal-the-islamic-ruling-on-alcohol-in-foods/); [SeekersGuidance](https://seekersguidance.org/answers/halal-and-haram/is-vanilla-extract-permissible-if-it-was-extracted-with-non-wine-alcohol/); [Dar al-Ifta Egypt](https://dar-alifta.org/en/fatwa/details/6245/food-mixed-with-alcohol-is-it-permissible)
- **Non-alcoholic / 0.0% beer.** Scholars are split:
  - Haram: Singapore MUIS Fatwa Committee; SeekersGuidance scholars; IslamOnline.
  - Permissible if non-intoxicating: Ibn Uthaymeen; Saudi Permanent Committee.
  - DUAI (South Africa, 2024): "alcohol-free" (true 0.0%) is permissible.
  — [MUIS](https://ask.gov.sg/muis/questions/clks0tqi900pbl90fmlhim02d); [SeekersGuidance](https://seekersguidance.org/answers/halal-and-haram/is-it-permissible-to-drink-de-alcoholized-beer-with-0-0-alcohol-content/); [Islamweb 299059](https://islamweb.net/en/fatwa/299059/ruling-on-beer-with-05-alcohol); [DUAI](https://duai.org.za/?p=6772); [IslamOnline](https://fiqh.islamonline.net/en/non-alcoholic-beer/)

### Inferences — DOUBTFUL list (do not hide)

| Category | Items |
|---|---|
| Alcohol, external / medicinal | perfume, attar, deodorant, body spray, hand sanitiser, isopropyl/rubbing alcohol, surgical spirit, mouthwash, cough syrup, tinctures, homeopathy (mother tincture), arishta (e.g. Dashmularishta, Ashokarishta), asava (Drakshasava, Kumaryasava). Note: Drakshasava is grape-based, so it is stricter under Hanafi fiqh, but still medicine → doubtful |
| Alcohol, transformed or trace | wine vinegar, balsamic vinegar, apple cider vinegar, vanilla extract/essence, soy sauce (trace alcohol from fermentation), kombucha, rum essence/flavour, "rum and raisin" ice cream, mirin/cooking wine (**lean doubtful**: these are real drinkable wines in some cases; leave out per rule), kefir, idli/dosa batter, toddy-fermented *appam/kallappam* (the bread itself) |
| De-alcoholised | non-alcoholic beer, 0.0% beer, alcohol-free wine, mocktails, "beer-flavoured" drinks, Bira 0.0, Heineken 0.0 |
| Bar / drinking accessories | beer mug, wine glass, whisky glass, decanter, cocktail shaker, bar stool, bottle opener, wine rack. These are not alcohol. Some scholars dislike them, but they are not clearly haram |
| Pork, doubtful | gelatin, E441, E471, E920, L-cysteine, glycerin, collagen, rennet, enzymes, marshmallows, gummies, "vindaloo" (bare), "ham" (bare), "salami", "sausage", "pepperoni", "cold cuts", vegan/mock pork, "pork masala", "sorpotel masala", "bafat masala", "vindaloo paste" (spice mixes, halal in themselves), E120/carmine (insect, not porcine) |

### Gaps
- No Indian halal body (Jamiat Ulama-i-Hind Halal Trust, Halal India) page on arishta or vanilla was found. The Indian rulings come only through Deoband medicine fatwas.

## Q7. False-positive traps with halal context words

### Takeaway
Most English keywords can be matched as whole words safely, but each one needs an exception list of context words. The Indic short words need EXACT or standalone-token matching. The worst traps:
- Kannada/Hindi "handi"
- Tamil கள் and மது
- Telugu పంది (because of పందిరి)
- the ridge-gourd collisions బీర / பீர்
- romanised "kallu", "panni" and "pandi"

### Cited Findings
- Toddy-palm products (nungu / ice apple, palm jaggery) come from the same palms but are not fermented drinks. Neera is non-alcoholic — [Wikipedia: Neera](https://en.wikipedia.org/wiki/Neera); [Paticheri palm sugar](https://www.paticheri.com/2025/03/12/a-palm-sugar-for-every-region/)
- In Tamil, "kallu" can mean freshly tapped sweet sap, not only the fermented drink — [Danish National Museum](https://samlinger.natmus.dk/es/asset/322475)
- Vindaloo and balchão are also made with seafood, so they are not pork-only — [Goan cuisine, Wikipedia](https://Www.Wikipedia.org/wiki/Goan_cuisine)

### Inferences — trap table

| Keyword | Halal meaning in Indian commerce | Context words that show the halal meaning (exempt) |
|---|---|---|
| ham | Hinglish "we" (ham, hum); ham radio; Hamdard | hum, hai, ham log, radio, hamdard; lack of meat words |
| hamburger | beef/chicken burger | already safe with whole-word "ham" |
| pig | pig iron, guinea pig, Peppa Pig, piggy bank, pig toy, "pig" plushie | iron, guinea, peppa, piggy, bank, toy, plush, soft toy, ceramic, mould |
| pandi | Tamil names Pandi, Pandian, "Pandi Stores", Pandiyan | absence of curry/meat/fry/mamsam |
| handi | Hindi clay pot, "chicken handi", "Handi restaurant", "dum handi" | chicken, mutton, paneer, veg, biryani, dum, pot, clay, matka |
| panni | Tamil colloquial "did/made" (பண்ணி) | absence of erachi/curry/fry |
| balchao | prawn balchão | prawn, shrimp, fish |
| vindaloo | chicken/fish vindaloo | chicken, fish, prawn, mutton, veg |
| bacon | chicken/turkey/veg bacon | chicken, turkey, veg, vegan, plant |
| wine (colour) | "wine red saree", "wine colour kurta", "wine shade lipstick" | colour, color, red, shade, saree, kurta, lipstick, dress, maroon |
| wine vinegar | condiment | vinegar |
| champagne | colour (gold/champagne saree, champagne beige) | colour, gold, beige, saree, shade, paint |
| bourbon | Britannia Bourbon biscuit | biscuit, cookie, cream, Britannia |
| root beer, ginger beer, ginger ale | soft drinks | root, ginger, soda, soft drink |
| butterscotch | ice cream/flavour | whole-word "scotch" won't match; also exempt "scotch brite", "scotch tape", "scotch egg" |
| gin | cotton gin; Hinglish "gin" (count, *ginna*); "gin" in "ginning mill" | cotton, ginning, mill, count, ginti |
| rum | rum essence, rum flavour; Rumi | essence, flavour, flavor, cake, raisin |
| cider | apple cider vinegar | vinegar, ACV |
| alcohol | sanitiser, isopropyl, alcohol-free, alcohol swab | free, sanitiser, sanitizer, isopropyl, swab, wipes, non-alcoholic |
| toddy palm / nungu / ice apple / tadgola / thati munjalu | fresh palm fruit | palm, fruit, nungu, ice apple, tadgola, munjalu, jaggery, karupatti, neera |
| neera | unfermented palm sap | always exempt |
| kallu (Kannada ಕಲ್ಲು) | stone: "kallu sakkare" (rock sugar), stone grinder "kallu ural/kallu chakki" | sakkare, sugar, ural, grinder, chakki, stone, rock. Hide only "kallu shop/shaap/kadai/angadi/dukanam" |
| kallu (Telugu కళ్ళు) | eyes; "kalla jodu" (spectacles) | jodu, spectacles, eye |
| madhu / மது | Madurai, the name Madhu, honey (Sanskrit *madhu*, "Madhu honey", Madhubani art) | Madurai, honey, madhubani, name contexts. Hide only "madhu kadai", "madhubanam" |
| கள் | plural suffix -கள் | standalone token only |
| பீர் / బీర | ridge gourd (பீர்க்கங்காய், బీరకాయ) | kai, kaya, gourd |
| ಹೆಂಡ | ಹೆಂಡತಿ (wife) | EXACT only |
| సారా | name Sara; సారాంశం | EXACT only |
| theka | contract | desi, angrezi, sharab |
| tari | Hindi "gravy" (chicken tari) | chicken, mutton, gravy |
| feni | pheni sweet (Odisha/Bengal), Feni district | sweet, mithai, vermicelli, pheni |
| mahua | mahua flower, oil, laddoo; personal name | flower, oil, laddoo, dried, seeds |
| handia | pot | rice beer, haria |
| bar | chocolate bar, soap bar, TMT bar, crowbar, juice bar, salad bar, Bar Council | chocolate, soap, TMT, steel, juice, salad, council, iron |
| daru | "dawa daru" (medicine), devadaru (cedar), daruharidra | dawa, deva, haridra |
| sharab / sharbat | sharbat = soft syrup (Rooh Afza) | different word; whole-word match avoids it |
| Kingfisher, Honey Bee, Magic Moments, Mansion House, Amrut, Corona | bird, honey, generic phrase, real estate, ayurveda/dairy, virus/shoes | absence of whisky/beer/brandy/rum/vodka/ml/bottle |
| McDowell's, Royal Stag, Imperial Blue, Officer's Choice | surrogate soda, water, music CDs | soda, water, music, CD, superhits |
| वराह (Varaha) | Vishnu avatar, temple items | always exempt |

### Gaps
- No source was fetched for most of the native-script collisions above (పందిరి, பீர்க்கங்காய், ಹೆಂಡತಿ, கள் suffix, மதுரை). They come from general language knowledge and need native-speaker review.
- Surrogate-advertising product names were not source-verified.
