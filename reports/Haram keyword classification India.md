# Hide the phrase, not the word

About 400 keywords across eight categories are clearly haram and safe to hide silently in an Indian local marketplace. They are formal product names: pork, bacon, lard, whisky, toddy, ganja, heroin, dildo, call girl, satta matka, vashikaran, meter vatti, hatha jodi, desi katta and fake Aadhaar. They also include the native words for the same things in Hindi/Urdu, Kannada, Malayalam, Tamil and Telugu. The main finding is that the bare forms of the most obvious words are false-positive traps. *Matka* is a clay pot, *handi* is a cooking pot, *chitta* is Punjabi for "white", *ham* is Hinglish for "we", Tamil கள் is a plural suffix and மது starts மதுரை (Madurai). Telugu పంది starts పందిరి (pandal), and *ivory*, *bullet*, *kidney*, *vibrator* and *escort* are everyday goods. So most hide rules must be phrases, or whole words with an exemption list of context words. Short Indic words must match as EXACT tokens and never as prefixes. Under the user's rule ("if not sure, leave it out") these stay visible: gelatin and E-numbers, perfume and medicines that contain alcohol, tobacco, CBD, condoms and sexual-health products, lucky draws, chess and cards, bank loans and chit funds, ruqyah, and bare salami/sausage/ham, which in India are mostly chicken. **No native-script spelling in this report was checked against a dictionary or against live listings.** Only the pig/pork words came from Wiktionary. Every Indic column needs a native speaker to review it before it ships. Four product decisions are still open: astrology (the sources call it haram, while the plan calls it doubtful), idols and puja goods, CBD, and non-alcoholic beer.

## Four tags and three engine rules carry the whole filter

The tags are used the same way in every table. **WORD** is a case-insensitive whole-word match on Latin text (`\bpork\b`). **EXACT** is a whole-token match with no suffixes. It is used for short words, in any script, whose letters start ordinary words. **PREFIX** matches an Indic stem plus any case or compound suffix (കഞ്ചാവ് → കഞ്ചാവുമായി). **PHRASE** hides a listing only when the listed words sit next to each other. The single words stay visible. In the gambling and illegal-goods sources, multi-word entries were tagged WORD. They are normalised to PHRASE here.

Three rules make the tables work. First, **exception context wins**: if a listing contains a hide keyword and also an exemption word from that keyword's trap row (for example "bacon" plus "chicken", or "wine" plus "colour"), it stays visible. Second, **match Indic text by exact codepoint, with no fuzzy or phonetic folding**. Several safe entries depend on one letter: Kannada ಮದ್ಯ (liquor) against ಮಧ್ಯ (middle), ಕಳ್ಳು (toddy) against ಕಲ್ಲು (stone), Telugu కల్లు (toddy) against కళ్ళు (eyes), and Hindi सट्टा (betting) against सत्ता (power). Third, **Tamil கள் must be a standalone whitespace token**, because it is also the plural suffix -கள். Peddler code words ("powder tea", "Karachi", emojis) change too fast to filter by keyword ([Onmanorama](https://www.onmanorama.com/news/kerala/2026/07/31/idukki-tea-shop-served-banned-tobacco-ganja-on-code.html); [Hindustan Times](https://www.pressreader.com/india/hindustan-times-chandigarh/20180604/281883004028042)). Leave them to moderation.

## Pork is clear in every language, but two native words for pig collide with pots and names

The pig and pork words come from Wiktionary ([pig](https://en.wiktionary.org/wiki/pig); [pork](https://en.wiktionary.org/wiki/pork)). The regional dishes are documented: **pandi curry** is the Kodava pork dish of Coorg ([Karnataka Tourism](https://karnatakatourism.org/experiences/pandi-curry-kodava-pork-curry)), and **sorpotel and chouriço** are Goan pork ([Goan cuisine](https://Www.Wikipedia.org/wiki/Goan_cuisine)). Processed meats are the main trap. **Venky's, Zorabian, Prasuma and others sell chicken salami and sausages widely**, and BigBasket files these words under mixed categories ([BigBasket](https://www.bigbasket.com/pc/eggs-meat-fish/sausages-bacon-salami/chicken-sausages/)). So hide salami, sausage, ham and pepperoni only when "pork" sits next to them. **No E-number is unambiguously porcine.** Gelatin (E441), E471 and E920 can all come from non-pig sources, and halal bodies list them as doubtful ([HalalSpy](https://halalspy.com/halal-knowledge/ingredients/e-numbers-halal/)). Only explicit wording such as "porcine" or "pork gelatin" is clear.

| Keyword | Lang | Tag | Exempt / note |
|---|---|---|---|
| pork, porky, porkchop, swine, piggery, porcine, lard | English | WORD | Exempt "pork masala" and other spice mixes (halal). Send "porcine heparin" and other medicines to a review rule |
| bacon | English | WORD | Exempt with chicken, turkey, veg, vegan, plant |
| pancetta, prosciutto, gammon, guanciale, lardo, jamón, speck | English / Italian | WORD | Always pork |
| chorizo, chouriço, chourico | English / Portuguese | WORD | Exempt "chicken chorizo" |
| boar, wild boar, hog | English | WORD | — |
| pig meat, pig fat, pigskin, pork gelatin, porcine gelatin, pork sausage, pork salami, pork ham, pork pepperoni, pork vindaloo, goa sausage | English | PHRASE | Bare "pig", "ham", "sausage", "salami" and "vindaloo" are traps |
| piglet + for sale/farm/live | English | PHRASE | Bare "piglet" is the Winnie-the-Pooh toy |
| boar bristle, pig bristle, hog hair | English | PHRASE | Pig-hair brushes. Put these in a separate rule (open decision) |
| sorpotel, sarapatel, sorpatel | Konkani | WORD | Exempt "sorpotel masala" |
| pandi curry, pandi fry, pandi meat, coorg pork; pork balchao | Kodava / Konkani | PHRASE | Bare "pandi" is a Tamil name (Pandian Stores) |
| suar, suwar, suar ka gosht, khinzir, khanzir | Rom. Hindi / Urdu | WORD | **Never** "soor" or "sur" (music notes, Surdas) |
| सूअर, सुअर, शूकर | Hindi | PREFIX | Leave out **वराह** (Varaha, a Vishnu avatar) |
| خنزیر / خنزير | Urdu | PREFIX | — |
| سور کا گوشت | Urdu | PHRASE | Bare سور is close to سورہ (Quran chapter) |
| डुक्कर, डुकर | Konkani / Marathi | PREFIX | For Goa and Maharashtra sellers |
| ಹಂದಿ (ಹಂದಿ ಮಾಂಸ) | Kannada | PREFIX | Romanised "handi" alone = Hindi pot |
| handi mamsa, handi mansa, handi meat | Rom. Kannada | PHRASE | — |
| పంది, పంది మాంసం | Telugu | EXACT / PHRASE | **Never PREFIX**: పందిరి = pandal |
| pandi mamsam, pandi kura | Rom. Telugu | PHRASE | — |
| പന്നി, പന്നിയിറച്ചി | Malayalam | PREFIX | — |
| panniyirachi, panni erachi, panni fry/curry | Rom. Malayalam | PHRASE | Bare "panni" = Tamil "did/made" (பண்ணி) |
| பன்றி (பன்றிக்கறி) | Tamil | PREFIX | — |
| panri, pandri, panri kari | Rom. Tamil | WORD | No common collision found |

| Pork trap | Halal context words that exempt it |
|---|---|
| pig | iron, guinea, peppa, piggy bank, toy, plush, ceramic |
| ham | hum, hai, ham log, radio, Hamdard; no meat word nearby |
| handi | chicken, mutton, paneer, veg, biryani, dum, clay, matka |
| vindaloo, balchao | chicken, fish, prawn, shrimp, mutton, veg |
| bacon, chorizo, sausage | chicken, turkey, veg, vegan, plant, mock |

## Alcohol words hide cleanly in English but need EXACT tokens in South Indian scripts

Every intoxicating drink is haram under the hadith principle that "whatever intoxicates in large quantities is haram in small quantities" ([IslamQA 9056](https://islamqa.info/en/answers/9056)). That covers beer, wine, spirits, toddy, arrack and feni. **Neera must stay visible.** It is unfermented palm sap, and Kerala and Telangana sell it as a packaged non-alcoholic drink. Toddy is the same sap fermented to about 4–8% alcohol ([Wikipedia: Neera](https://en.wikipedia.org/wiki/Neera); [The News Minute](https://www.thenewsminute.com/article/telangana-s-neera-why-govt-promoting-local-unfermented-toddy-130594)). The state liquor retailers are safe shop-name keywords: **TASMAC** (Tamil Nadu monopoly), **BEVCO** (Kerala) and **TSBCL** (Telangana) ([TASMAC](https://Www.wikipedia.org/wiki/TASMAC); [BEVCO](https://bevco.in/bevco-kerala-state-beverages-corporation/); [TSBCL](https://en.wikipedia.org/wiki/Telangana_State_Beverages_Corporation)). **MSIL** needs liquor context because it also runs non-liquor businesses ([Deccan Herald](https://www.deccanherald.com/india/karnataka/mysuru/msil-outlets-see-liqour-sales-almost-double-on-new-years-eve-earn-rs-1811-crore-3848905)). Royal Stag and McDowell's are India's top whisky brands ([Drinks International](https://drinksint.com/news/fullstory.php/aid/12339/The_Millionaires_92_Club_2026:_the_world_92s_bestselling_Indian_whisky_brands.html)). Like Kingfisher and Imperial Blue, they share their names with soda, water or music products, or with ordinary words, so they are PHRASE only. The surrogate-product claims are unverified.

| Keyword | Lang | Tag | Exempt / note |
|---|---|---|---|
| liquor, liqueur, whisky, whiskey, vodka, brandy, tequila, mezcal, absinthe, cognac, soju, sake, sangria, mead, lager, pilsner, IMFL | English | WORD | Exempt "Brandy" as a name (rare) |
| beer, beers, wine, wines, rum, scotch, champagne, bourbon | English | WORD | Exemption list required (see trap table) |
| pub, brewery, brewpub, microbrewery, taproom, distillery | English | WORD | — |
| BEVCO, TASMAC, TSBCL, APSBCL, KSBCL | English | WORD | Shop names |
| alcoholic beverage/drink, wine shop, wine store, wines & spirits, hard cider, dry gin, gin & tonic, stout beer, single malt, bacardi breezer, bar & restaurant, bar and grill, MSIL + liquor/outlet, MRP liquor outlet | English | PHRASE | Bare "alcohol", "gin", "cider", "breezer", "bar" and "beverages" are traps |
| Smirnoff, Bacardi, Johnnie Walker, Jack Daniel's, Glenfiddich, Chivas, Jameson, Budweiser, Heineken, Carlsberg, Tuborg, Haywards, Old Monk, Bagpiper, Romanov, Black Dog | Brands | WORD | Liquor-only names. Exempt "Heineken 0.0" (open decision) |
| McDowell's, Royal Stag, Imperial Blue, Officer's Choice, Blenders Pride, Kingfisher, Magic Moments, Mansion House, Honey Bee, Amrut, Corona, 8PM | Brands | PHRASE | Hide only with whisky, rum, brandy, beer, vodka, ml, bottle, peg, quarter |
| daru, daaru, sharab, sharaab, arrack, arak, saraya, charayam, urrak, toddy, tadi, taadi | Rom. Hindi / South | WORD | Exempt "dawa daru". "tari" alone = gravy |
| desi daru, country liquor, angrezi sharab, desi/angrezi theka, cashew/coconut/goa feni, mahua daru, handia rice beer, toddy shop, kallu shop/shaap/kadai/angadi/dukanam | Rom. | PHRASE | Bare "theka", "feni", "mahua", "handia" and "kallu" are traps |
| शराब | Hindi | PREFIX | — |
| दारू, मदिरा, मद्य, बीयर, बियर, व्हिस्की, वोडका, ब्रांडी, रम, ताड़ी | Hindi | EXACT | रम starts रमेश, रमज़ान; never PREFIX मद (मदद = help) |
| شراب | Urdu | EXACT | شربت (sharbat) is a different word |
| ಮದ್ಯ | Kannada | PREFIX | Differs from ಮಧ್ಯ (middle) by one letter |
| ಸಾರಾಯಿ, ಹೆಂಡ, ಕಳ್ಳು, ಬಿಯರ್, ವಿಸ್ಕಿ, ಬ್ರಾಂದಿ | Kannada | EXACT | ಹೆಂಡತಿ = wife; ಕಳ್ಳ = thief |
| മദ്യ, ചാരായം | Malayalam | PREFIX | — |
| കള്ള്, കള്ളുഷാപ്പ്, ബിയർ, വിസ്കി, ബ്രാണ്ടി, റം | Malayalam | EXACT | കള്ളൻ = thief, കള്ളം = lie |
| சாராயம், டாஸ்மாக் | Tamil | PREFIX | — |
| மது, மதுபானம், கள்ளுக்கடை, பீர் | Tamil | EXACT | மதுரை, பீர்க்கங்காய் (ridge gourd) |
| கள் | Tamil | EXACT standalone | Plural suffix |
| మద్య | Telugu | PREFIX | — |
| కల్లు, సారా, సారాయి, బీరు, బీర్, విస్కీ, బ్రాందీ | Telugu | EXACT | బీరకాయ (ridge gourd), సారాంశం (summary), the name Sara |
| apong, zutho, chhang, rakshi | Northeast / Himalayan | WORD | Unverified spellings |

| Alcohol trap | Halal context words that exempt it |
|---|---|
| wine, champagne | colour, color, red, shade, saree, kurta, lipstick, maroon, gold, beige; "wine vinegar" |
| beer, ale | root beer, ginger beer, ginger ale, non-alcoholic, 0.0 |
| bourbon, scotch | biscuit, Britannia, cream; scotch brite, scotch tape, scotch egg |
| rum, gin | essence, flavour, cake, raisin; cotton gin, ginning mill, ginti |
| alcohol, cider | free, sanitiser, isopropyl, swab, wipes; apple cider vinegar, ACV |
| toddy palm, neera | nungu, ice apple, tadgola, munjalu, palm jaggery, karupatti, neera (always exempt) |
| kallu (romanised) | sakkare, sugar, ural, grinder, chakki, stone (Kannada); jodu, spectacles, eye (Telugu) |
| madhu | Madurai, honey, Madhubani, personal names |
| bar | chocolate, soap, TMT, steel, juice, salad, council, crowbar |
| feni, mahua, theka, tari | pheni sweet, Feni district; flower, oil, laddoo; contract; gravy |

## Narcotics have clean formal names, but nearly all street slang must stay visible

Hashish and every other intoxicant take the ruling of khamr, and the ban on hashish **rests on the consensus of Muslims** ([IslamQA 66227](https://islamqa.info/en/answers/66227); [IslamQA 176545](https://islamqa.info/en/answers/176545/is-marijuana-prohibited-in-islam)). These names are safe whole words: ganja, charas, bhang, afeem, heroin, smack, cocaine and mephedrone. Mephedrone has been banned under NDPS since 2015 ([DNA India](https://www.dnaindia.com/mumbai/report-m-cat-finally-banned-under-narcotic-act-2063021)). The slang is not safe. **Chitta** is Punjab's word for heroin ([Tribune](https://www.tribuneindia.com/news/himachal/chitta-reaching-hp-via-punjab-more-lethal-386393)) but also means "white". **Maal** and **stuff** are dealers' code words ([DNA India](https://www.dnaindia.com/mumbai/report-affluent-class-in-pune-saying-hi-to-high-1662664/amp); [Free Press Journal](https://www.freepressjournal.in/amp/bhopal/drug-firearms-syndicate-dark-web-social-media-code-words-used)) but mean "goods". **MD** and **ice** are just as ambiguous ([ThePrint](https://theprint.in/statedraft/is-ice-becoming-the-new-chitta-hit-hard-by-talibans-opium-ban-punjab-is-breaking-bad/2206281)). Use only phrase forms of the poppy-husk words *doda* and *bhukki* ([BloombergQuint](https://www.bloombergquint.com/politics/why-does-punjab-have-a-drug-problem-the-untold-story); [Dawn](https://www.dawn.com/news/752645)).

| Keyword | Lang | Tag | Exempt / note |
|---|---|---|---|
| ganja, ganjaa, gaanja, marijuana, marihuana, charas, hashish, bhang, bhaang, afeem, afim, aphim, heroin, smack, cocaine, mephedrone, mdma, methamphetamine, meth, lsd, psilocybin, shrooms | English / Rom. Hindi | WORD | Whole-word matching protects heroine, bhangra and methi |
| cannabis | English | WORD | Hides CBD listings that say "cannabis" (open decision) |
| opium | English | WORD | Exempt with perfume, EDP, YSL, fragrance, ml; homeopathy, 30C, 200C, SBL, Reckeweg (homeopathy exemption is inference) |
| hash oil, malana cream, hybrid ganja, poppy husk, poppy straw, doda post, ecstasy pills, crystal meth, magic mushroom, lsd blot, brown sugar | English | PHRASE | Exempt "brown sugar" with organic, jaggery, kg, baking |
| bhukki | Punjabi rom. | EXACT | bhukhi = hungry |
| kanjav, kanjavu, kanchavu (Mal.); ganjayi, nallamandu (Tel.); kanja (Tam.) | Rom. South | WORD / EXACT | — |
| गांजा, गाँजा, अफीम, अफ़ीम | Hindi | PREFIX | — |
| चरस, भांग, हेरोइन, स्मैक, कोकीन | Hindi | EXACT | भांगड़ा shares a stem. हीरोइन (film heroine) is spelled differently |
| डोडा पोस्त | Hindi | PHRASE | — |
| گانجا، چرس، افیون، افیم، ہیروئن، بھنگ | Urdu | EXACT | — |
| ਗਾਂਜਾ, ਅਫੀਮ, ਹੈਰੋਇਨ, ਭੁੱਕੀ | Punjabi | EXACT | — |
| ಗಾಂಜಾ, ಅಫೀಮು | Kannada | PREFIX | Never ಭಂಗಿ (= pose) |
| ಹೆರಾಯಿನ್, ಚರಸ್ | Kannada | EXACT | — |
| കഞ്ചാവ, ഹാഷിഷ്, ഓപ്പിയം | Malayalam | PREFIX | Never കറുപ്പ് (= black) |
| ഹെറോയിൻ, എംഡിഎംഎ | Malayalam | EXACT | — |
| கஞ்சா | Tamil | PREFIX, full stem only | கஞ்சி (gruel), கஞ்சன் (miser) |
| அபின், ஹெராயின் | Tamil | EXACT | — |
| గంజాయ, నల్లమందు | Telugu | PREFIX | Never గంజ (గంజి = starch) |
| హెరాయిన్ | Telugu | EXACT | — |

| Narcotics trap (never hide alone) | Halal context words |
|---|---|
| weed | killer, remover, trimmer, garden, herbicide, mat |
| poppy, khus khus, posto, post, doda | seeds, dana, masala; post office; doda barfi, Doda district |
| hash, coke, pot, joint, grass, ice | brown, tag; cola, pet coke; flower, pressure; pain, pipe; lawn, artificial; cream, cube |
| chitta, maal, stuff, MD, high, kush, Afghani, molly, acid, special K | universal ordinary meanings |
| mcat, meow meow | MCAT exam, cat toy, kitten |
| abin; whitener, fevicol | Malayali given name; stationery |

## Adult services hide only as phrases, because "massage", "spa" and "escort" are mostly halal

Police describe Indian spa-front prostitution as sold through **"body to body massage"**, **"extra services"** and **"spa at your home"** ([Gujarat Samachar](https://english.gujaratsamachar.com/news/gujarat/ahmedabad-crime-branch-busts-illegal-prostitution-racket-at-spa-in-bodakdev-15354351192.html); [Free Press Journal](https://www.freepressjournal.in/amp/mumbai/mira-bhayandar-cops-raid-spa-offering-extra-services-in-kashimira); [Business Standard](https://business-standard.com/article/pti-stories/sex-racket-operating-in-guise-of-spa-service-busted-6-held-119071801374_1.html)). Meta's ad policy draws the same line this filter needs. It bans sexual-arousal products such as sex toys but **allows family planning, erectile-dysfunction and reproductive-health products** ([Meta](https://transparency.meta.com/policies/ad-standards/content-specific-restrictions/adult-products-or-services)). Over-blocking has a real cost: women's health ads were wrongly rejected over the word "vaginal" ([The Swaddle](https://theswaddle.com/womens-sexual-health-ads-were-censored-on-facebook-finds-report/)). Profanity belongs to a profanity filter, not to this category.

| Keyword | Lang | Tag | Exempt / note |
|---|---|---|---|
| dildo, dildos, fleshlight, masturbator, porn, porno, pornography, xxx, prostitute, prostitution, gigolo, callgirl | English | WORD | "xxl" is protected by whole-word matching |
| sex toy(s), adult toy(s), butt plug, anal plug, anal beads, sex doll, love doll, pocket pussy, rabbit/g-spot/clit/sex vibrator, vibrator for women | English | PHRASE | Bare "vibrator" and "doll" are traps |
| blue film, adult video, sex video, nude video call, sex chat, call girl(s), call boy job, escort service(s), escort girl, female/independent escort, playboy job, sex service, sex racket | English | PHRASE | — |
| body to body massage, body2body, b2b massage, nuru massage, erotic massage, cross massage, happy ending + massage, extra service + spa/massage, full service massage, spa at home + girls | English | PHRASE | Bare massage, spa and massager stay visible |
| randi, chudai | Rom. Hindi | EXACT | — |
| वेश्या | Hindi | PREFIX | Not वैश्य (caste) |
| रंडी | Hindi | EXACT | — |
| देह व्यापार, कॉल गर्ल | Hindi | PHRASE | — |
| जिस्मफरोशी | Hindi | PREFIX | — |
| جسم فروشی | Urdu | PHRASE | — |
| طوائف | Urdu | EXACT | — |
| ವೇಶ್ಯ | Kannada | PREFIX | ವೇಶ್ಯೆ, ವೇಶ್ಯಾವಾಟಿಕೆ |
| വേശ്യ, പെൺവാണിഭം | Malayalam | PREFIX | — |
| விபச்சார, விலைமாது | Tamil | PREFIX | — |
| பாலியல் தொழில் | Tamil | PHRASE | — |
| వ్యభిచార, వేశ్య | Telugu | PREFIX | — |

| Adult trap | Halal context words |
|---|---|
| vibrator | concrete, needle, poker, motor, compactor, mobile |
| escort | Escorts Kubota, tractor, Farmtrac, Ford |
| massager, spa | foot, neck, back, electric, pain relief; hair spa, salon, pedicure |
| adult, nude, sexy, hot | diaper, cycle, size; lipstick, shade, heels; dress, saree; water, deal |
| hookup, stripper | wire, cable, AWG, tool |
| Kamasutra, Playboy | condom or deo brand; clothing, perfume |
| doll, MMS, vaishya | children's toys; messaging; caste name |

## Gambling and sorcery hide on result, market and "baba" wording, never on the base noun

Paid-entry lotteries and all betting are maysir. **Giving lottery money to charity does not make it lawful** ([IslamQA 98151](https://islamqa.info/en/answers/98151); [aliftaa.jo](https://aliftaa.jo/en-fatwas/4000/rss.aspx)). A free-entry prize draw is allowed ([IslamQA 20993](https://islamqa.info/en/answers/20993)), and scholars split on shop lucky draws ([IslamQA 97648](https://islamqa.info/en/answers/97648)). State lotteries are legal in Kerala, Nagaland and seven other states ([PW OnlyIAS](https://pwonlyias.com/current-affairs/lotteries-in-india-regulation-gst-constitutional-framework/)), but that does not make them halal. **The Online Gaming Act 2025 bans all real-money online games**, rummy and fantasy cricket included ([YourStory](https://yourstory.com/2025/08/india-moves-to-outlaw-real-money-gaming-with-sweeping-ban); [Bar & Bench](https://www.barandbench.com/law-firms/view-point/legal-gamechanger-what-the-online-gaming-act-2025-means-for-indias-gaming-industry)). Satta matka networks keep being raided ([Free Press Journal](https://www.freepressjournal.in/mumbai/mumbais-matka-queen-jaya-chheda-arrested-in-goa-gambling-crackdown)). Sistani forbids chess and backgammon, and treats card games as gambling games even without a bet. Other Shia jurists tie the chess ban to betting ([sistani.org](https://www.sistani.org/english/qa/01161); [WikiShia](https://en.wikishia.net/view/Chess)). So bare cards and chess are not consensus, but teen patti and andar bahar, which in India are played for money, are hidden.

Sorcery advertising is also illegal. **Karnataka's 2017 Act bans advertising black magic and scheduled practices** ([India Code](https://www.indiacode.nic.in/handle/123456789/7807)), and the Drugs and Magic Remedies Act 1954 bans magic-remedy ads, including tantrik "vashikaran" promises ([India Code PDF](https://www.indiacode.nic.in/indiacode/bitstream/123456789/1412/1/A1954-21.pdf); [Indian Kanoon](https://future.indiankanoon.org/doc/190898482/)). Kerala police treat *koodothram* as black magic ([The News Minute](https://www.thenewsminute.com/amp/story/kerala/kerala-cops-arrest-man-who-posed-temple-priest-steal-gold-money-devotees-112180)). **Ruqyah with Qur'an and understood du'a is permitted by consensus** ([IslamQA 7874](https://islamqa.info/en/ref/7874)), so "ruqyah", "dam" and "jinn removal" stay visible.

| Gambling keyword | Lang | Tag | Note |
|---|---|---|---|
| sattamatka, sattaking, dpboss, betting, bettings, bookie, bookies, casino, casinos, roulette, lottery, lotteries, lotto, teenpatti, andarbahar, ottanumber | English / Rom. | WORD | Exempt "casino" with hotel; exempt "lottery" with book/novel |
| satta matka, satta king, satta result/bazar/number, kalyan/mumbai/milan/rajdhani/sridevi/madhur/main bazar matka, time bazar, matka result/chart/number/guessing/tips/king, dp boss, kolkata fatafat, gujarat ff, gali/disawar/faridabad/ghaziabad satta | Rom. | PHRASE | Bare "matka" and "satta" are traps |
| teen patti, 3 patti, andar bahar, cricket/ipl/online betting, betting id/app/tips, bet id, cricket id, online/live casino, slot machine, jackpot slot, online poker, poker chips/table/cash, online rummy, rummy cash/app, real money rummy/game/gaming, earn money game, fantasy cash | Rom. | PHRASE | Bare "rummy", "poker", "fantasy", "dream11" and "bet" stay visible |
| lottery ticket/result/agent/shop/sambad, kerala/nagaland/sikkim/punjab/dear/state/bumper lottery, onam/vishu/christmas/pooja/monsoon/summer bumper, otta number, ezhuthu lottery | Rom. | PHRASE | Bare "bumper" = car part |
| jua khana, juaa, juwa, kodi pandalu, kodi pandem, cock fight betting | Rom. | WORD / PHRASE | Bare "jua" is risky |
| सट्टा, सट्टेबाज, लॉटरी, लाटरी, बेटिंग, जुआरी | Hindi | PREFIX | सट्टा (ट्ट) ≠ सत्ता (power) |
| जुआ | Hindi | EXACT | Also = yoke; drop it if farm listings exist |
| सट्टा मटका, मटका नंबर, मटका रिजल्ट, तीन पत्ती, अंदर बाहर + गेम/खेल | Hindi | PHRASE | — |
| سٹہ, سٹے بازی, لاٹری | Urdu | PREFIX | — |
| جوا, قمار | Urdu | EXACT | — |
| ಲಾಟರಿ, ಬೆಟ್ಟಿಂಗ್, ಜೂಜು | Kannada | PREFIX | — |
| ಮಟ್ಕಾ, ಸಟ್ಟಾ | Kannada | EXACT | A clay pot is ಮಡಕೆ |
| ലോട്ടറി, ഒറ്റനമ്പർ, ബെറ്റിംഗ്, ചൂതാട്ട | Malayalam | PREFIX | — |
| മട്ക | Malayalam | EXACT | Low confidence |
| லாட்டரி, பெட்டிங், சூதாட்ட | Tamil | PREFIX | Never சூது alone (= deceit) |
| மட்கா | Tamil | EXACT | Low confidence |
| లాటరీ, బెట్టింగ్, జూద, కోడి పందె, కోడిపందె | Telugu | PREFIX | — |
| మట్కా | Telugu | EXACT | Low confidence |

| Sorcery keyword | Lang | Tag | Note |
|---|---|---|---|
| vashikaran, vasikaran, vashikaram, vasheekaran, koodothram, kudothram, mantravadam, durmantravadam, abhicharam, seivinai, maanthreegam, chetabadi, banamati, hamzad, hamzaad | Rom. | WORD | — |
| black magic (+ removal/specialist), kala jadu, kala jaadu, kala ilm, jadu tona, tona totka, sifli ilm/amal/jadu, jinn hazir/hazri, jinn ka amal, jinn summoning, love problem solution/specialist, lost/get/ex love back, love back specialist, husband wife problem solution baba, love marriage specialist baba, bengali/aghori/tantrik baba, tantrik vidya, tantra mantra specialist/totka, maran/uchatan/mohini mantra, maata mantra, billi sooniyam, sei vinai, vasiya mai, vasiyam mantra, kshudra puja/pooja, siyar singhi | Rom. | PHRASE | Bare magic, tantrik, totka, mata and love marriage stay visible |
| वशीकरण, उच्चाटन | Hindi | PREFIX | — |
| काला जादू, जादू टोना, टोना टोटका, मारण मंत्र, मोहिनी मंत्र, सियार सिंगी | Hindi | PHRASE | — |
| وشیکرن | Urdu | PREFIX | — |
| کالا جادو, کالا علم, سفلی علم, سفلی عمل, جن حاضر | Urdu | PHRASE | — |
| ہمزاد | Urdu | EXACT | — |
| ವಶೀಕರಣ, ಮಾಟಗಾರ, ಮಾಟಗಾತಿ | Kannada | PREFIX | Never ಮಾಟ alone (ಮೈಮಾಟ = physique) |
| ಮಾಟ ಮಂತ್ರ, ಬ್ಲಾಕ್ ಮ್ಯಾಜಿಕ್ | Kannada | PHRASE | — |
| കൂടോത്ര, ദുർമന്ത്രവാദ, ആഭിചാര, മന്ത്രവാദ | Malayalam | PREFIX | Review മന്ത്രവാദ (folk exorcism use) |
| വശീകരണ മന്ത്രം, വശീകരണ യന്ത്രം | Malayalam | PHRASE | വശീകരണം alone = charm |
| சூனிய, செய்வினை, மாந்திரீக | Tamil | PREFIX | — |
| வசிய மை, வசிய மந்திரம் | Tamil | PHRASE | வசியம் alone = charm |
| వశీకరణ, చేతబడి, బాణామతి, క్షుద్ర | Telugu | PREFIX | — |

| Gambling / sorcery trap | Halal context words | Haram only with |
|---|---|---|
| matka, मटका | pot, clay, mitti, water, kulfi, biryani, terracotta | result, chart, number, satta, kalyan, jodi, panel |
| satta, सत्ता | party, sarkar, election, chunav | matka, king, result, bazar |
| rummy, poker | cards, deck, tiles, board game; fireplace, concrete vibrator | cash, real money, online, app, chips |
| bumper, jackpot, casino | car, bike, guard; restaurant, toy, snack; hotel, Kochi | lottery, onam, vishu; slot; online, live |
| jua, totka, magic, tantra | plough, kheti; gharelu, beauty; mop, cube, show, tricks; book, yoga, shastra | khana, juari; tona, jadu; black, kala; baba, specialist |
| sihr/سحر, bandish, eval, jinn | sehri, ramzan; raag, rules; job, errand; movie, Aladdin toy | jadu, amal; todna; billi sooniyam; hazir, hamzad |

## Riba hides only for private interest-lending ads, and illegal goods only with material or sale context

Deoband's Darul Ifta rules that **"both giving and taking interest is haram"** for Muslims in India too ([Deoband 27943](https://islamqa.org/hanafi/darulifta-deoband/27943/is-a-bank-loan-permissible-in-india-for-a-business-purpose/)). In practice, though, ordinary banking touches many Indian Muslims, and fatwas about it draw open disagreement ([Business Standard](https://www.business-standard.com/article/news-ani/muslims-divided-over-fatwa-against-marrying-bankers-118010500221_1.html)). The clear target is the private moneylender. Tamil Nadu's 2003 Act names **"daily vatti, hourly vatti, kandhu vatti, meter vatti and thandal"** as exorbitant-interest forms, and meter vatti can reach about 10% a day ([TN Act](https://www.cra.tn.gov.in/tnscs/Files/act/012_The%20Tamil%20Nadu%20Prohibition%20of%20Charging%20Exorbitant%20Interest%20Act%202003.pdf); [Scroll](https://scroll.in/article/855716/tamil-nadu-has-stringent-laws-against-moneylending-at-exorbitant-rates-why-does-it-persist-then)). Kerala's "blade" lender slang was not confirmed by any source.

For illegal goods, the items are crimes in themselves. **Hatha jodi** is the hemipenis of a Schedule I monitor lizard and has been seized from Flipkart and Amazon sellers ([Down To Earth](https://www.downtoearth.org.in/amp/story/wildlife-biodiversity/traders-arrested-for-selling-illegal-wildlife-parts-like-hatha-jodi-on-flipkart-amazon)). Pangolin scales, ivory and tiger parts are seized regularly ([WCS India](https://india.wcs.org/Newsroom/News/ID/24261/Illegal-Wildlife-Trade-Newsletter-February-2025)). Country-made pistols are advertised on Facebook with home delivery ([Deccan Herald](https://www.deccanherald.com/india/madhya-pradesh/facebook-page-advertises-pistols-for-sale-with-promise-of-home-delivery-2892161)). The organ law **punishes publishing paid organ ads with 5–10 years' imprisonment** ([THOA 1994](https://www.indiacode.nic.in/bitstream/123456789/19260/1/thoa_act_1994.pdf)). The rice-puller / copper-iridium scam has cost victims crores ([Business Standard](https://www.business-standard.com/article/pti-stories/three-held-in-mumbai-for-copper-iridium-scam-119122500819_1.html)). Selling weapons is not haram in itself, so licensed-dealer words stay visible.

| Riba keyword | Lang | Tag |
|---|---|---|
| interest loan, loan on interest, money on interest, private finance on interest, meter vatti/vaddi, kandu/kandhu vatti, daily/hourly/thandal vatti, vattiku panam, vatti ku panam, vatti kadan, byaj par paisa/loan/rupaye, sood par paisa/karz, baddi saala, baddige hana, meter/dina baddi, vaddi ki dabbulu, vaddiki dabbulu, vaddi appu, rojuvari vaddi, palisakku/palishakku panam, blade palisha, blade company | Rom. | PHRASE |
| ब्याज पर पैसा/लोन/कर्ज, सूद पर पैसा; सूदखोर | Hindi | PHRASE; PREFIX |
| سود پر قرض, سود پر پیسے; سودخور | Urdu | PHRASE; PREFIX |
| ಬಡ್ಡಿ ಸಾಲ, ಬಡ್ಡಿಗೆ ಹಣ, ಮೀಟರ್ ಬಡ್ಡಿ, ದಿನ ಬಡ್ಡಿ | Kannada | PHRASE |
| പലിശയ്ക്ക് പണം, പലിശ വായ്പ, ബ്ലേഡ് പലിശ, ബ്ലേഡ് കമ്പനി | Malayalam | PHRASE |
| வட்டிக்கு பணம், வட்டி கடன், மீட்டர் வட்டி, கந்து வட்டி; கந்துவட்டி, தண்டல் | Tamil | PHRASE; PREFIX |
| వడ్డీకి డబ్బులు, వడ్డీ అప్పు, మీటర్ వడ్డీ, రోజువారీ వడ్డీ | Telugu | PHRASE |
| `\d+%\s?(per|/)\s?(day|week|month)` with loan/finance/money (not EMI or p.a.) | Regex hint | PHRASE |

| Illegal-goods keyword | Lang | Tag | Note |
|---|---|---|---|
| hatha jodi, hattha jodi, hathajodi, siyar singhi, pangolin scale/shell, real ivory, ivory tusk/bangle/carving, elephant tusk/ivory, hathi dant, tiger/leopard skin, tiger/leopard claw, tiger nail/tooth/teeth, bagh nakh original, huli uguru, puli nakham/nagam/goru, deer skin, mrigchala, deer horn/antler, sambar horn, rhino horn, bear bile, shark fin, star tortoise, shahtoosh, shahtush, mongoose hair/brush, monitor lizard, ghorpad, snake/cobra venom, snake skin, sanda oil real | Rom. | WORD / PHRASE | Bare ivory, tiger, leopard and sanda oil stay visible |
| desi/deshi katta, katta pistol, country made pistol/gun, tamancha, live cartridge(s), live bullets, zinda kartoos, pistol/gun without licence, 9mm pistol for sale, nattu thuppakki, nadan thokku | Rom. | PHRASE / WORD (tamancha) | Bare katta, bullet, cartridge, gun stay visible |
| gelatin sticks, gelignite, detonator(s), rdx, tnt explosive, country bomb, naatu bomb, nattu vedi, panni padakkam | Rom. | PHRASE / WORD | Bare gelatin and tnt stay visible. panni padakkam unsourced |
| fake currency/notes, fake indian currency, ficn, counterfeit currency, duplicate notes, nakli note, fake aadhaar/aadhar/pan card/passport/driving licence/dl/rc book/marksheet/degree/certificate, buy degree, degree without exam | Rom. | PHRASE / WORD (ficn) | Bare fake, duplicate, nakli stay visible |
| kidney/liver/organ for sale, sell kidney/organ, buy kidney, kidney donor paid/money | Rom. | PHRASE | Altruistic donor appeals stay visible |
| rice puller, rice pulling, rp copper, copper iridium, red mercury, money doubling, double money, paisa double, double your money, black money exchange, black dollar cleaning, ssd chemical, nagmani, naagmani, snake pearl | Rom. | PHRASE / WORD | red mercury unsourced in India |
| हत्था जोड़ी, हाथी दांत, बाघ नाखून, बाघ की खाल, देसी कट्टा, जिंदा कारतूस, नकली नोट, जाली नोट, फर्जी डिग्री, फर्जी आधार, नकली मार्कशीट, पैसा डबल; मृगछाला, किडनी बेच; तमंचा, नागमणि | Hindi | PHRASE; PREFIX; EXACT | — |
| ಆನೆ ದಂತ, ಹುಲಿ ಉಗುರು, ಖೋಟಾ ನೋಟು | Kannada | PHRASE | — |
| ആനക്കൊമ്പ്, പുലിനഖം, കള്ളനോട്ട്; നാടൻ തോക്ക് | Malayalam | PREFIX; PHRASE | — |
| யானை தந்தம், புலி நகம், நாட்டு துப்பாக்கி, நாட்டு வெடிகுண்டு, கள்ள நோட்டு | Tamil | PHRASE | Never வெடி alone (crackers) |
| ఏనుగు దంతం, పులి గోరు, దొంగ నోట్లు, నకిలీ నోట్లు | Telugu | PHRASE | — |

| Riba / illegal trap | Halal context words |
|---|---|
| vatti / வட்டி / ಬಡ್ಡಿ / വട്ടി | bank, FD, savings, 0%; Malayalam വട്ടി = basket |
| sood, blade | Punjabi surname; razor, cutter, fan, mixer |
| ivory, tiger, leopard, deer, owl | colour, saree, tiles; print, balm, biscuit, cement, toy; statue, showpiece |
| gun, pistol, bullet, cartridge, AK47 | toy, water, glue, spray, massage, nail; Royal Enfield, CCTV, chilli; HP, ink, RO filter; poster |
| fake, duplicate, kidney, copper, mercury, double | jewellery, plants, nails, key, RTO; rajma, beans, stone, tray; bottle, wire; thermometer; bed, door |

## Doubtful items stay visible, and seven of them need a product decision

These items are excluded under the user's rule. In each case scholars disagree, the use is medicinal or external, or the main Indian meaning is ordinary. **Pure CBD without THC is ruled halal**, and so is hemp seed oil ([Darul Iftaa Birmingham](https://islamqa.org/hanafi/daruliftaa-birmingham/170702/is-cbd-oil-halal/); [AskImam](https://islamqa.org/hanafi/askimam/127500/are-we-allowed-to-use-or-sell-hemp-oil/)). Indian Hanafi scholars hold **tobacco to be makruh**, not haram ([IslamQA.org](https://islamqa.org/hanafi/qibla-hanafi/34446/consuming-niswar-a-drug/)). Deoband allows alcohol in Indian medicines and homeopathy when it does not come from grapes or dates ([Deoband 27240](https://islamqa.org/hanafi/darulifta-deoband/27240/is-it-halal-or-haram-to-drink-alcohol-in-medicines/)). Wine vinegar is halal by transformation (istihala) under Hanafi fatwas ([IslamQA 2283](https://islamqa.info/en/answers/2283/ruling-on-vinegar-made-from-wine)). Codeine syrups, tramadol and alprazolam are Schedule H/H1/X pharmacy items ([Rajya Sabha PQ 266](https://rsdebate.nic.in/bitstream/123456789/753706/1/PQ_266_11122024_U1833_p238_p243.pdf)). Courts even split on whether Phensedyl falls under NDPS ([Bar & Bench](https://www.barandbench.com/news/phensedyl-codeine-ndps-calcutta)).

| Category | Doubtful: do NOT hide |
|---|---|
| Pork-adjacent | gelatin, E441, E471, E472, E920, L-cysteine, E120/carmine, glycerin, collagen, rennet, enzymes, marshmallow, gummies; bare ham, salami, sausage, pepperoni, cold cuts, vindaloo; vegan/mock pork; pork, sorpotel and bafat masala, vindaloo paste |
| Alcohol-adjacent | perfume, attar, deodorant, sanitiser, isopropyl, mouthwash, cough syrup, homeopathic mother tincture, arishta/asava (incl. Drakshasava), wine/balsamic/cider vinegar, vanilla extract, soy sauce, kombucha, kefir, rum essence, rum & raisin, mirin/cooking wine, kallappam; non-alcoholic/0.0 beer, alcohol-free wine, mocktails; beer mugs, wine glasses, decanters, bar stools, openers |
| Intoxicant-adjacent | tobacco, cigarette, beedi, gutka, khaini, zarda, paan masala, hookah, chillum, rolling paper, vape, paan, supari; khat, kratom; CBD, hemp; codeine syrups (Corex, Phensedyl), tramadol, tapentadol, alprazolam, nitrazepam, buprenorphine, Spasmo-Proxyvon, ketamine, GHB, morphine; nasha (nasha mukti) |
| Adult-adjacent | condoms, lubricant, contraceptives, pregnancy tests, ED/"timing" tablets, sildenafil, shilajit; lingerie, bikini, nightwear; massage, spa, physiotherapy, Ayurvedic and tantric massage; dating; Kamasutra book; mujra |
| Gambling-adjacent | lucky draw, prize draw, buy-and-win, charity raffle; chess, carrom, ludo, playing cards/taash, pekata, jodi; bare rummy, poker, fantasy, dream11 |
| Sorcery-adjacent | astrology, horoscope, jathakam, kundli, panchang, jyotish, vastu, palmistry, numerology, tarot; ruqyah, dam, hijama, taweez, nazar, jinn removal, amil; magic shows and trick kits; idols, murti, puja items, agarbatti, rudraksha, navaratna gems |
| Riba-adjacent | bank, home, personal and gold loans, EMI, credit cards, pawn/girvi, insurance, FD; chit fund, kuri, chitty, bhishi, committee/BC |
| Illegal-adjacent | air guns, licensed gun shops, rifle clubs, knives, swords, khukri, talwar; herbal sanda oil, red sandalwood, peacock feathers, coral/moonga, pet birds; "Children Bank of India" toy notes; anatomy skull models |

| Open product decision | Evidence | Default under the rule |
|---|---|---|
| **Astrology / fortune-telling** | IslamQA, Islamweb and al-islam.org (Shia) all call predictive astrology unlawful ([IslamQA 22445](https://islamqa.info/en/22445); [Islamweb](https://islamweb.net/en/women/article/88495/islam-and-fortune-telling); [al-islam.org](https://al-islam.org/node/127622)). That is closer to clear than doubtful. Indian listings, though, are mostly Hindu wedding kundli matching and panchang calendars | Keep visible. "love problem astrologer" and "baba" ads are already hidden under sorcery |
| **Idols, murti, puja goods** | Lawful trade for non-Muslim buyers, not a sorcery service | Keep visible. Hatha jodi and siyar singhi are hidden as wildlife parts |
| **CBD** | Pure CBD is ruled halal, but the WORD rule on "cannabis" will hide CBD listings that mention cannabis | Add a "CBD/hemp seed" exemption to "cannabis" if CBD should stay visible |
| **Non-alcoholic / 0.0% beer** | MUIS and SeekersGuidance say haram. Ibn Uthaymeen, the Saudi Permanent Committee and DUAI say permissible if truly non-intoxicating ([MUIS](https://ask.gov.sg/muis/questions/clks0tqi900pbl90fmlhim02d); [DUAI](https://duai.org.za/?p=6772)) | Keep visible; exempt "0.0" and "non-alcoholic" from the beer rule |
| Boar-bristle brushes | A pig product, but some consumers don't know that | Separate rule the brand can switch on |
| Card games and chess (Shia) | Sistani forbids them; the Sunni majority allows them without a bet | Keep visible; hide only named betting games |
| Fantasy sports / rummy apps | Illegal for money under the 2025 Act, but free-to-play and merchandise exist. Whether the Act is in force and how court challenges stand as of November 2026 is unconfirmed | Hide only the cash phrases |

## Conclusion

The hard part of this filter is not knowing what is haram. That is settled for every category here, from the khamr principle to the hadith of Jabir on riba. The hard part is that India's languages reuse the same syllables for pots, stones, eyes, gourds, wives, cities and plural endings. A filter that hides "matka", "kallu" or "மது" would silently remove water pots, rock sugar and every Madurai listing. That is a worse outcome for a local marketplace than letting a rare satta ad through. The design that follows is phrase-first matching with exemption context, and it is cheap to extend: each new term needs only a hide pattern and a list of context words.

Two risks remain before launch. First, **every native-script cell is unverified**. The least certain are the Telugu, Tamil and Malayalam spellings of "matka", ഒറ്റനമ്പർ, the pork compounds (ಹಂದಿ ಮಾಂಸ, పంది మాంసం, പന്നിയിറച്ചി, பன்றிக்கறி) and all the alcohol words in Indic scripts. A native speaker of each language should review them, then test them against a sample of real listings, before the rules go live. Second, the astrology decision cuts against the stated rule. The sources lean haram, but the Indian listing mix leans cultural. Whichever way the product owner chooses, the choice should be recorded explicitly rather than left to a default.
