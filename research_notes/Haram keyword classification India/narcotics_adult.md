# Haram keyword classification (India): intoxicants/narcotics and adult/sex

Scope: two categories only. Alcohol is out of scope here. Tags:
- **WORD** = whole-word match, Latin script, case-insensitive
- **EXACT** = whole token only, for short Indic or romanised words whose stems collide with ordinary words
- **PREFIX** = Indic stem that takes case suffixes (e.g. Malayalam കഞ്ചാവ് -> കഞ്ചാവുമായി)
- **PHRASE** = multi-word sequence. Hide only when the whole phrase matches; the single words stay visible.

Rule applied throughout, as the user asked: if a term is not clearly haram, or its main sense in Indian listings is ordinary, it is left out (DOUBTFUL or TRAP list).

## Q1. Indian drug names and slang: which are unambiguous enough to hide, which collide?

### Takeaway
Cannabis, hashish, opium, heroin, cocaine and synthetic drugs (MDMA, mephedrone, meth, LSD) are haram by scholarly consensus, because every intoxicant counts as khamr. Their formal names and the main Indian names (ganja, charas, bhang, afeem, smack, mephedrone) are safe to hide as whole words. The common slang is not safe on its own: chitta means "white" in Punjabi, maal means "goods", stuff, MD, doda, post, ice and coke all have ordinary meanings. Those must be left visible.

### Cited Findings
- Hashish takes all the rulings of khamr; the intoxicating amount is haram by consensus, and a small amount is haram for the majority — [IslamQA 176545](https://islamqa.info/en/answers/176545/is-marijuana-prohibited-in-islam)
- Ibn Taymiyyah: anything that takes away the senses is haram even without drunkenness. The ban on hashish is by consensus of the Muslims — [IslamQA 66227 "Are Drugs Haram?"](https://islamqa.info/en/answers/66227)
- A Hanafi mufti rejects the minority view that khamr means only fermented drinks, and rules cannabis haram — [AskMufti via IslamQA.org](https://islamqa.org/hanafi/askmufti/45184/islam-and-cannabis/)
- Chitta is the Punjab/Himachal name for heroin, usually adulterated — [Tribune India](https://www.tribuneindia.com/news/himachal/chitta-reaching-hp-via-punjab-more-lethal-386393)
- Doda / phukki is opium (poppy) husk, consumed traditionally in Punjab — [BloombergQuint](https://www.bloombergquint.com/politics/why-does-punjab-have-a-drug-problem-the-untold-story)
- Bhukki is a crude opium tea-like drink made from ground poppy husk — [Dawn](https://www.dawn.com/news/752645)
- Mephedrone street names in India are meow meow, M-Cat, white magic, bubble(s) and MD. It is banned under NDPS since 2015 — [DNA India](https://www.dnaindia.com/mumbai/report-m-cat-finally-banned-under-narcotic-act-2063021); [BoomLive](https://www.boomlive.in/meow-meow-lethal-new-drug); [PressReader / India Today "MD: a fact sheet"](https://www.pressreader.com/india/india-today/20230227/282170770326975)
- Buyers ask dealers for "maal" — [DNA India, Pune](https://www.dnaindia.com/mumbai/report-affluent-class-in-pune-saying-hi-to-high-1662664/amp). A Bhopal gang used the code word "stuff" in place of "drugs" — [Free Press Journal](https://www.freepressjournal.in/amp/bhopal/drug-firearms-syndicate-dark-web-social-media-code-words-used)
- "Smack" is sold as heroin and is mostly brown sugar, which is low-grade heroin — [Hindustan Times via PressReader](https://www.pressreader.com/india/hindustan-times-st-jaipur/20171119/281852938867522); [DevDiscourse](https://www.devdiscourse.com/article/law-order/1942159-6-held-with-brown-sugar)
- Peddlers use rotating code words (e.g. "Karachi" for heroin mixed with phenobarbital) and emojis — [HT "Drugs take cover in new names"](https://www.pressreader.com/india/hindustan-times-chandigarh/20180604/281883004028042); [FPJ](https://www.freepressjournal.in/mumbai/fpj-special-international-day-against-drug-abuse-and-illicit-trafficking-cracking-the-code-of-drug-business)
- Crystal meth ("ice") is displacing chitta in Punjab — [ThePrint](https://theprint.in/statedraft/is-ice-becoming-the-new-chitta-hit-hard-by-talibans-opium-ban-punjab-is-breaking-bad/2206281)
- An Idukki tea shop sold ganja and Hans tobacco under the code "powder tea". "420" slang is common among Kerala youth — [Onmanorama 2026-07-31](https://www.onmanorama.com/news/kerala/2026/07/31/idukki-tea-shop-served-banned-tobacco-ganja-on-code.html); [Onmanorama](https://onmanorama.com/news/kerala/kerala-pot-problems-ganja-fuels-violence-youth.html)
- "Hybrid ganja" is current Kerala usage — [Onmanorama 2025](https://www.onmanorama.com/news/kerala/2025/04/27/hybrig-ganja-arrest-directors-excise-to-summon-sameer-thahir.amp.html)

### Inferences

#### Table 1A. Intoxicants: CLEAR-HARAM, hide (Latin script)
| Keyword | Tag | Note |
|---|---|---|
| ganja, ganjaa, gaanja | WORD | |
| marijuana, marihuana | WORD | |
| cannabis | WORD | Will also hide CBD listings that say "cannabis". If CBD should stay visible, use the context exemption in Table 1D |
| charas, charus | WORD | |
| hashish, hasheesh | WORD | |
| hash oil, hashish oil | PHRASE | "hash" alone is a trap |
| malana cream | PHRASE | charas brand name |
| bhang, bhaang | WORD | Includes "bhang goli" and "bhang thandai". Whole-word matching protects "bhangra" |
| hybrid ganja, ganja oil | PHRASE | already covered by ganja |
| afeem, afim, aphim, afeen | WORD | |
| opium | WORD | Exempt when it appears with perfume terms (see Table 1D) |
| poppy husk, poppy straw, doda post, dode post | PHRASE | Poppy seeds stay visible |
| bhukki | EXACT | Do not stem: "bhukhi" (hungry) is close |
| heroin | WORD | Whole-word matching protects "heroine" |
| smack | WORD | Low collision in Indian listings. "Lip Smacker" is a different token |
| brown sugar | PHRASE | Exempt when it appears with food terms (see Table 1D) |
| cocaine | WORD | |
| mephedrone | WORD | |
| mdma, ecstasy pills | WORD / PHRASE | "ecstasy" alone is used in perfume names, so match only "ecstasy pill(s)" |
| methamphetamine, crystal meth | WORD / PHRASE | |
| meth | WORD | Whole-word matching protects "methi" |
| lsd, lsd blot(s) | WORD | |
| magic mushroom(s), shrooms, psilocybin | PHRASE / WORD | |
| kanjav, kanjavu, kanchav, kanchavu | WORD | Malayalam romanised |
| ganjayi, ganjai | WORD | Telugu romanised |
| nallamandu | WORD | Telugu for opium |
| kanja | EXACT | Tamil romanised |

#### Table 1B. Intoxicants: native script, hide
Spellings come from language knowledge and are not web-verified (see Gaps).
| Language | Keyword | Meaning | Tag |
|---|---|---|---|
| Hindi | गांजा, गाँजा | ganja | PREFIX |
| Hindi | चरस | charas | EXACT |
| Hindi | भांग, भाँग | bhang | EXACT (भांगड़ा = bhangra shares the stem) |
| Hindi | अफीम, अफ़ीम | opium | PREFIX |
| Hindi | हेरोइन, हेरोईन | heroin | EXACT (हीरोइन = film heroine, spelled differently) |
| Hindi | स्मैक | smack | EXACT |
| Hindi | कोकीन | cocaine | EXACT |
| Hindi | डोडा पोस्त | poppy husk | PHRASE |
| Urdu | گانجا، چرس، افیون، افیم، ہیروئن، بھنگ | ganja, charas, opium (x2), heroin, bhang | EXACT |
| Punjabi (Gurmukhi) | ਗਾਂਜਾ, ਅਫੀਮ, ਹੈਰੋਇਨ, ਭੁੱਕੀ | ganja, opium, heroin, bhukki | EXACT |
| Kannada | ಗಾಂಜಾ | ganja | PREFIX (ಗಾಂಜಾವನ್ನು) |
| Kannada | ಅಫೀಮು, ಅಫೀಮ್ | opium | PREFIX |
| Kannada | ಹೆರಾಯಿನ್, ಚರಸ್ | heroin, charas | EXACT |
| Malayalam | കഞ്ചാവ് | ganja | PREFIX stem കഞ്ചാവ (കഞ്ചാവുമായി, കഞ്ചാവിന്റെ) |
| Malayalam | ഹാഷിഷ് | hashish | PREFIX |
| Malayalam | ഹെറോയിൻ, എംഡിഎംഎ | heroin, MDMA | EXACT |
| Tamil | கஞ்சா | ganja | PREFIX on the full stem only. Do not shorten to கஞ்ச, which collides with கஞ்சன் (miser) and is close to கஞ்சி (rice gruel) |
| Tamil | அபின் | opium | EXACT |
| Tamil | ஹெராயின் | heroin | EXACT |
| Telugu | గంజాయి | ganja | PREFIX stem గంజాయ. Do not use గంజ, which collides with గంజి (starch/gruel) |
| Telugu | నల్లమందు | opium | PREFIX |
| Telugu | హెరాయిన్ | heroin | EXACT |

#### Table 1C. Intoxicants: DOUBTFUL, do NOT hide
| Item | Why it stays visible |
|---|---|
| tobacco, cigarette, beedi, gutka, khaini, zarda, paan masala, hookah, chillum, rolling paper | Scholars differ. Indian Hanafi scholars hold tobacco makruh, not haram — [IslamQA.org niswar](https://islamqa.org/hanafi/qibla-hanafi/34446/consuming-niswar-a-drug/); [IslamQA 9083](https://islamqa.info/en/answers/9083/ruling-on-smoking-and-chewing-tobacco) |
| paan, betel, supari | Not an intoxicant ruling of consensus |
| khat / qat | Many muftis say haram — [Darul Iftaa Zambia](https://islamqa.org/hanafi/daruliftaazambia/157085/is-khat-qat-halaal-to-consume/); [IslamOnline](https://fiqh.islamonline.net/en/khat-is-haram/). It is not universal, and the word is rare in India and collides with "khat" (letter/charpai). Leave out |
| kratom | Islamweb: permissible unless used as a drug — [Islamweb 338809](https://islamweb.net/en/fatwa/338809) |
| CBD oil, hemp seed oil, hemp | Pure CBD without THC is ruled halal — [Darul Iftaa Birmingham](https://islamqa.org/hanafi/daruliftaa-birmingham/170702/is-cbd-oil-halal/); [SeekersGuidance](https://seekersguidance.org/uncategorized/is-cbd-oil-halal-to-use-for-medical-purposes/); hemp seed oil halal — [AskImam](https://islamqa.org/hanafi/askimam/127500/are-we-allowed-to-use-or-sell-hemp-oil/) |
| vape, e-cigarette | Tobacco/nicotine, so doubtful. E-cigarettes are illegal in India, but that is a legal question, not a religious one |
| prescription medicines (codeine syrup, Corex, Phensedyl, tramadol, alprazolam, nitrazepam, buprenorphine, Spasmo-Proxyvon, ketamine for vets) | Legitimate pharmacy (Schedule H/H1/X) items that are abused. Courts disagree on whether Phensedyl falls under NDPS — [Bar & Bench](https://www.barandbench.com/news/phensedyl-codeine-ndps-calcutta); [ThePrint, NCB](https://theprint.in/india/ncb-flags-second-wave-of-pharmaceutical-opioids-in-punjab/3096841/) |
| nasha | Also used in "nasha mukti" (de-addiction centre) |
| ketamine, GHB | Veterinary and anaesthetic use |

#### Table 1D. Intoxicants: FALSE-POSITIVE traps (never a standalone hide term)
| Term | Ordinary meaning | Context words that show the halal meaning |
|---|---|---|
| weed | weeds in a garden | killer, remover, cutter, trimmer, control, mat, garden, herbicide, glyphosate |
| poppy, khus khus, khas khas, posto, posta | poppy seeds (food) | seeds, dana, masala, 100g, kirana |
| post | posts, post office, poles | the only harmful case is the "doda post" phrase |
| doda | doda barfi (sweet), Doda district | barfi, sweet, mithai |
| brown sugar | food sugar | organic, jaggery, kg, baking, kirana |
| meth / methi | fenugreek | methi does not match meth as a whole word |
| hash | hash brown, hashtag | brown, potato, McCain, tag |
| coke | Coca-Cola, petroleum coke | cola, can, bottle, pet coke, coal |
| pot, matka | cooking pot, clay pot, flower pot | flower, pressure, clay, plant |
| joint | joint pain, plumbing joint | pain, oil, knee, pipe, elbow |
| maal, stuff | goods | universal; never hide |
| grass | lawn, artificial grass | lawn, artificial, carpet, seeds |
| ice | ice, ice cream, ice cube | cream, cube, box, maker |
| chitta / ਚਿੱਟਾ | "white" in Punjabi (chitta kurta) | universal; never hide |
| MD | managing director, Doctor of Medicine | universal; never hide |
| mcat, meow meow | MCAT exam, cat toys | toy, cat, kitten, exam |
| opium | YSL "Black Opium" perfume | perfume, edp, ysl, edt, fragrance, ml |
| ecstasy, molly, acid, special K, kush, Afghani, high | perfume names, given name, chemicals, cereal, Hindu Kush, nationality/dry fruit, ordinary adjective | do not hide |
| abin | common Malayali given name | do not hide |
| ಭಂಗಿ (Kannada) | "pose/posture" | do not hide |
| കറുപ്പ് (Malayalam) / கறுப்பு | "black" | do not hide |
| whitener, fevicol, dendrite | stationery and glue (inhalant abuse) | do not hide |
| bhangra, ganji / గంజి / கஞ்சி | dance, rice starch/gruel | protected by WORD/EXACT matching and full stems |

### Gaps
- No single source confirmed "post" as poppy-husk slang. It is widely known but uncited here; "doda post" is kept only as a phrase.
- No web source lists Malayalam, Tamil, Telugu or Kannada drug slang beyond the formal words. Native-script spellings in Table 1B come from language knowledge. A native-speaker review is recommended before shipping.
- Peddler code words rotate fast (celebrity names, emojis, "powder tea") and cannot be keyword-filtered without false positives.

## Q2. Native-script words for cannabis, opium and heroin

### Takeaway
See Table 1B. Each language has one clean formal word for cannabis (गांजा / ಗಾಂಜಾ / കഞ്ചാവ് / கஞ்சா / గంజాయి) and for opium (अफीम / ಅಫೀಮು / அபின் / నల్లమందు). Heroin is a transliteration in every language. Use the full stem; shortened stems collide with words for rice gruel or starch (கஞ்சி, గంజి).

### Cited Findings
- Kerala news uses "ganja", "hybrid ganja" and MDMA as the dominant drug terms — [Onmanorama](https://www.onmanorama.com/news/kerala/2025/06/21/migrant-workers-ganja-seizure-kozhikode.html); [Onmanorama dead drops 2026](https://www.onmanorama.com/news/kerala/2026/07/15/kochi-drug-sellers-embrace-breaking-bad-style-with-dead-drops-for-contactless-trade.html)

### Inferences
- The Malayalam word for opium (കറുപ്പ്) means "black", and bhang in Kannada (ಭಂಗಿ) means "pose". Neither can be used. Use the transliterations ഓപ്പിയം and ಅಫೀಮು instead.

### Gaps
- No authoritative glossary (NCB or state excise) of native-script drug terms was found online.

## Q3. How adult products, escort and "body to body massage" ads are worded, without hiding pharmacies or therapists

### Takeaway
Spa-front prostitution in India is advertised as "body to body massage", "extra services", "spa at your home" and "cross massage". Escort ads use "call girl", "escort service" and "playboy job". Sex toys use English product names. Hide these phrases, not the single words "massage", "spa", "escort" or "vibrator".

### Cited Findings
- Police say spas facilitated prostitution "in the name of body massage". Masseuses were pushed into "body to body massages" — [Gujarat Samachar, Bodakdev 2026](https://english.gujaratsamachar.com/news/gujarat/ahmedabad-crime-branch-busts-illegal-prostitution-racket-at-spa-in-bodakdev-15354351192.html); [The News Minute, Bengaluru](https://www.thenewsminute.com/article/six-women-allegedly-forced-sex-work-rescued-bengaluru-spa-manager-arrested-118520)
- A tabloid ad for "a spa at your home" fronted a Mumbai prostitution racket — [Business Standard / PTI](https://business-standard.com/article/pti-stories/sex-racket-operating-in-guise-of-spa-service-busted-6-held-119071801374_1.html)
- Spas raided for offering "extra services" — [Free Press Journal](https://www.freepressjournal.in/amp/mumbai/mira-bhayandar-cops-raid-spa-offering-extra-services-in-kashimira). UP had about 100 "Body Massage Centres" in Sadar alone — [Gulf News](https://gulfnews.com/world/asia/india/india-spa-centers-in-uttar-pradesh-raided-for-prostitution-and-sex-rackets-1.1574672214492)
- Meta bans ads for "sexual arousal products ... such as sex toys" but allows family planning, erectile dysfunction products and reproductive health — [Meta Adult Products or Services](https://transparency.meta.com/policies/ad-standards/content-specific-restrictions/adult-products-or-services)
- Google Pay prohibits prostitution, escort and companionship services — [Google Pay policies](https://pay.google.com/about/business/policy). eBay bans escort services and sexual contact — [eBay](https://www.ebay.co.uk/help/policies/prohibited-restricted-items/personal-relationships-prohibited-services-policy?id=4326)
- OLX bars services involving illegal activities or indecent descriptions (Lebanon help page; the India page was not found) — [OLX](https://help.olx.com.lb/hc/en-us/articles/8591403693583-What-are-prohibited-ads-on-OLX)
- Over-blocking risk: Meta wrongly rejected women's health ads over the word "vaginal" — [The Swaddle](https://theswaddle.com/womens-sexual-health-ads-were-censored-on-facebook-finds-report/)

### Inferences

#### Table 3A. Adult: CLEAR-HARAM, hide (Latin script)
| Keyword | Tag |
|---|---|
| sex toy, sex toys, adult toy(s) | PHRASE |
| dildo, dildos | WORD |
| fleshlight, masturbator | WORD |
| butt plug, anal plug, anal beads | PHRASE |
| sex doll, love doll, silicone doll (with "sex") | PHRASE |
| pocket pussy | PHRASE |
| rabbit vibrator, g-spot vibrator, clit vibrator, vibrator for women, sex vibrator | PHRASE |
| porn, porno, pornography, xxx | WORD |
| blue film, blue films, adult video(s), sex video(s), nude video call, sex chat, video call sex | PHRASE |
| call girl, call girls, callgirl, call boy job | PHRASE / WORD |
| escort service, escort services, escort girl(s), female escort, independent escort | PHRASE |
| gigolo, playboy job, playboy service | WORD / PHRASE |
| sex service, sex racket, sex worker for hire | PHRASE |
| prostitute, prostitution | WORD |
| body to body massage, body2body, b2b massage, nuru massage, happy ending (with massage), erotic massage, cross massage, extra service(s) (with spa/massage), full service massage | PHRASE |
| randi | EXACT |
| chudai | EXACT |

#### Table 3B. Adult: native script, hide
Spellings come from language knowledge and are not web-verified.
| Language | Keyword | Meaning | Tag |
|---|---|---|---|
| Hindi | वेश्या | prostitute | PREFIX (वेश्यावृत्ति). Not वैश्य (caste) |
| Hindi | देह व्यापार, जिस्मफरोशी | sex trade | PHRASE / PREFIX |
| Hindi | रंडी | prostitute (slur) | EXACT |
| Hindi | कॉल गर्ल | call girl | PHRASE |
| Urdu | جسم فروشی، طوائف | sex trade, courtesan | PHRASE / EXACT |
| Kannada | ವೇಶ್ಯೆ, ವೇಶ್ಯಾವಾಟಿಕೆ | prostitute, prostitution | PREFIX stem ವೇಶ್ಯ |
| Malayalam | വേശ്യ, പെൺവാണിഭം | prostitute, sex racket | PREFIX |
| Tamil | விபச்சாரம், விலைமாது | prostitution, prostitute | PREFIX |
| Tamil | பாலியல் தொழில் | sex work | PHRASE |
| Telugu | వ్యభిచారం, వేశ్య | prostitution, prostitute | PREFIX |

#### Table 3C. Adult: DOUBTFUL, do NOT hide
condoms, lubricant, KY jelly, pregnancy tests, contraceptives, ED medicines ("sex power" / "timing" tablets, sildenafil), lingerie, bra, bikini, nightwear, massage / spa / massage therapist / physiotherapy / Ayurvedic massage, sensual or tantric massage (unclear), dating, Kamasutra book, mujra, aphrodisiac or "shilajit" products. These are halal or contested uses, and Meta also allows sexual-health items.

#### Table 3D. Adult: FALSE-POSITIVE traps
| Term | Ordinary meaning | Context words that show the halal meaning |
|---|---|---|
| vibrator | concrete/needle vibrator, vibrator motor, phone vibrator | concrete, needle, poker, motor, construction, compactor, HP, mobile |
| massager | body/foot/neck massager (Dr Physio, Agaro) | foot, neck, back, leg, pain relief, electric |
| escort | Escorts Kubota tractors, Ford Escort | tractor, Kubota, Farmtrac, Powertrac, Ford, car |
| sexy | fashion adjective | dress, saree, top, heels |
| adult | adult diapers, adult cycle, adult size | diaper, pants, Friends, cycle, size, ticket |
| hot | temperature, trending | water, case, deal, sale |
| nude | lipstick shade, nude heels, skin-tone colour | lipstick, shade, matte, heels, colour |
| hookup | hookup wire (electronics) | wire, cable, AWG, gauge |
| stripper | wire stripper | wire, cable, tool |
| Kamasutra | condom/deodorant brand | condom, deo, KamaSutra (KS) |
| spa | hair spa, salon, pedicure spa | hair, salon, pedicure, facial |
| playboy | Playboy-branded clothing / deodorant | deo, perfume, cap |
| xxl, xl | clothing size | protected by WORD matching (only "xxx" is a term) |
| vaishya / वैश्य | caste name | never hide |
| doll | children's toys | protected: hide only the "sex doll" / "love doll" phrase |
| MMS | multimedia message | never hide |

### Gaps
- OLX India's and Quikr's own prohibited-items wording was not found online. Locanto India's ad wording was not checked.
- No source documented Indian-language wording for sex-toy listings. Such listings appear to use English almost entirely; this is inferred, not cited.
- Profanity and body-part slurs are left out. They belong to a profanity filter, not a product category.

## Q4. Narcotic-sounding words that are ordinary pharmacy items

### Takeaway
Keep codeine syrups (Corex, Phensedyl), tramadol, tapentadol, alprazolam, nitrazepam, buprenorphine, pentazocine, morphine (hospital), ketamine (vet/anaesthesia), Spasmo-Proxyvon and "cough syrup" visible. They are regulated Schedule H/H1/X medicines that are abused, not haram products in themselves. Courts disagree on whether codeine syrups even fall under NDPS.

### Cited Findings
- Stocking and sale of formulations containing codeine, dextropropoxyphene, diphenoxylate, pentazocine, nitrazepam, buprenorphine, and oral tramadol/tapentadol are restricted, not banned. Retail sale needs a prescription under Schedule H/H1/X — [Rajya Sabha PQ 266, 2024](https://rsdebate.nic.in/bitstream/123456789/753706/1/PQ_266_11122024_U1833_p238_p243.pdf)
- NCB seized Phensedyl, Corex and Spasmo-Proxyvon Plus from border smugglers and flagged a second wave of pharmaceutical opioid abuse in Punjab — [ThePrint](https://theprint.in/india/ncb-flags-second-wave-of-pharmaceutical-opioids-in-punjab/3096841/); [OneIndia](https://oneindia.com/india/menace-codeine-based-cough-syrups-why-are-they-controlled-2601219.html)
- Calcutta HC held Phensedyl a narcotic under NDPS. Allahabad HC held it was not — [Bar & Bench](https://www.barandbench.com/news/phensedyl-codeine-ndps-calcutta); [Allahabad HC](https://www2.allahabadhighcourt.in/ahcr/english/ILR%20Case%20Wise/PDF%20January%202022/8403%20of%202021.pdf)
- Islamic rulings allow non-intoxicating or medically necessary use: pure CBD for medical purposes — [SeekersGuidance](https://seekersguidance.org/uncategorized/is-cbd-oil-halal-to-use-for-medical-purposes/)

### Inferences
- Under the user's rule these words are DOUBTFUL, so they stay visible. Moderation, not search hiding, should handle "without prescription / bulk cough syrup" sellers.
- "Morphine" and "opium" appear in homeopathic remedy names (e.g. "Opium 30" homeopathy). Exempt "opium" when it appears with homeopathy, 30C, 200C, Dr. Reckeweg or SBL. This is an inference from common Indian homeopathy labelling and is not cited here.

### Gaps
- No current consolidated 2026 list of Schedule H1 drugs was retrieved. Check CDSCO for the latest list.
