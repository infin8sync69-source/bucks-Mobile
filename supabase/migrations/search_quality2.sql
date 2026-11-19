-- Search that stops the junk and understands everyday words (Phase 0 of docs/DISCOVERY_ALGORITHMS.md, 0.2 and 0.3).
--
-- search_listings keeps its signature and its columns, so every app build already in people's hands gets the better results at once:
--   1. Whole words only. "cab" no longer finds "USB-C Cable", "milk" no longer finds a "Milky White" vase, "medicine" no longer finds an
--      "Abstract Cat Figurine — Medium". Plurals still match ("plumbers", "batteries", "tomatoes").
--   2. Typos are forgiven only for words of 5 or more letters that nothing matched exactly ("plumbr", "electrecian"), word by word,
--      never across words, against words at most one letter shorter ("plumbr" no longer finds "Plum Cake"), on pages in range.
--      A half-typed last word of 4 or more letters matches the start of a category ("pharm" → Pharmacy).
--   3. Filler and modifiers are taken out: "i need a plumber near me", "doodh chahiye", "haalu beku". "cheap" orders matching
--      products by price, "under 500" also puts products within 500 first, "best" puts trust before online, "open now" puts online
--      pages first. Adjectives that name no need ("fresh", "pure", "special") are generic words, so "fresh fish" never lists a page
--      that is only "fresh".
--   4. Any word may match (OR), and pages that match more of the words come first. When some page nearby matches every meaningful
--      word, only pages that match every one are shown ("chicken biryani" no longer lists the chicken shop). Generic words ("shop",
--      "repair", "wala", "home") are matched but never enough on their own.
--   5. search_lexicon: words people use in every language and script → what pages are listed under. SAME rows are another way of
--      saying the same thing (a spelling, a plural, a translation), CONCEPT rows a need that a category answers (milk → grocery).
--      A match through a concept ranks below a direct match of a product, so a grocery never outranks the shop that sells the thing.
--   6. Order: pages in range first, shops that ship India-wide after them; then the share of the words found; then where they were
--      found (title, category or type > product or owner > description or area); then online; then trust (the Wilson lower bound of
--      RECOMMENDATION_ALGORITHM §3.3 instead of ↑ − ↓); then distance. Ties stay stable (id).
--
-- The earlier helpers of search_quality.sql (search_synonyms, search_variants, search_singular, search_item_match) are left in place
-- for older migrations to re-run against; nothing calls them any more. Their 72 words are carried into search_lexicon.
-- Safe to run more than once. Apply after search_quality.sql and the files after it (supabase/apply_all.sh does).
set search_path = public, extensions;

-- ---------- 1. text → the words to compare ----------
-- Lower case, Unicode NFC, Devanagari nukta dropped and chandrabindu written as anusvara (people type both), old-style Malayalam
-- chillu letters made atomic, zero-width marks and apostrophes removed, every other punctuation mark a space. Padded with one space
-- each side so that a whole word or phrase is found with position(' word ' in text).
create or replace function public.search_clean(t text) returns text language sql immutable parallel safe set search_path = public, extensions as $$
  with a as (select lower(normalize(left(coalesce(t, ''), 2000), nfc)) s),
       b as (select replace(replace(replace(replace(replace(s,
                       chr(3378) || chr(3405) || chr(8205), chr(3453)), chr(3368) || chr(3405) || chr(8205), chr(3451)),
                       chr(3376) || chr(3405) || chr(8205), chr(3452)), chr(3379) || chr(3405) || chr(8205), chr(3454)),
                       chr(3363) || chr(3405) || chr(8205), chr(3450)) s from a),
       c as (select translate(s, chr(2305) || chr(2364) || chr(8203) || chr(8204) || chr(8205) || chr(65279) || '''’‘`´', chr(2306)) s from b)
  select ' ' || coalesce(nullif(btrim(regexp_replace(c.s, '[[:space:][:punct:]—–…।॥•·“”‐‑‒―₹€$%@#*+=<>|~^]+', ' ', 'g')), '') || ' ', '')
  from c
$$;

-- One word to the key that its singular and plural share: plumbers → plumber, batteries → battery, boxes → box, tomatoes → tomato.
-- Words ending in -ie fold to -y on both sides (movie, movies → movy), so a key is not always a real word; it is only compared.
-- Words of 3 letters or less, and anything not in plain Latin letters, are left as they are.
create or replace function public.search_key(w text) returns text language sql immutable parallel safe set search_path = public, extensions as $$
  select case
    when w is null or length(w) <= 3 or w !~ '^[a-z]+$' then w
    else (select case when length(x) > 4 and x ~ 'ie$' then left(x, -2) || 'y' else x end
          from (select case
                  when length(w) > 4 and w ~ 'ies$' then left(w, -3) || 'y'
                  when length(w) > 4 and w ~ '(ch|sh|x|ss|z)es$' then left(w, -2)
                  when length(w) > 5 and w ~ '[^aeiou]oes$' then left(w, -2)
                  when w ~ 's$' and w !~ 'ss$' then left(w, -1)
                  else w end x) y)
  end
$$;

-- search_clean, then every word to its key: ' full stack web developer '.
create or replace function public.search_norm(t text) returns text language sql immutable parallel safe set search_path = public, extensions as $$
  select ' ' || coalesce(string_agg(public.search_key(w), ' ' order by n) || ' ', '')
  from unnest(string_to_array(btrim(public.search_clean(t)), ' ')) with ordinality u(w, n) where w <> ''
$$;

-- How good a page is, until subject_scores exists: the Wilson lower bound (z = 1.28) of its share of ↑ with a prior of 3 votes at
-- 0.7 (docs/RECOMMENDATION_ALGORITHM.md §3.3). No votes 0.35, one ↑ 0.46, four ↑ 0.64; 10 ↑ and 8 ↓ (net +2) 0.45, below 2 of 2.
create or replace function public.search_trust(up int, down int) returns double precision language sql immutable parallel safe set search_path = public, extensions as $$
  select (p + z * z / (2 * n) - z * sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / (1 + z * z / n)
  from (select (u + 2.1) / (u + d + 3) p, u + d + 3 n, 1.28::float8 z
        from (select greatest(coalesce(up, 0), 0)::float8 u, greatest(coalesce(down, 0), 0)::float8 d) v) x
$$;

-- ---------- 2. the lexicon ----------
-- term: what people type or say, in any language or script. means: what pages are listed under (empty for FILLER and GENERIC; the
-- modifier's name for MODIFIER). FILLER and MODIFIER rows match the words as typed; the others match by key, so plurals count.
-- status 'proposed' rows wait for review and are not used; 'rejected' rows are kept so the learning loop never proposes them again.
-- The generated keys use search_clean and search_norm: after changing either, refresh them with  update search_lexicon set term = term;
-- (the end of this file does that on every run).
create table if not exists public.search_lexicon (
  term        text not null check (length(term) between 1 and 60),
  means       text not null default '' check (length(means) <= 60),
  kind        text not null check (kind in ('SAME', 'CONCEPT', 'GENERIC', 'FILLER', 'MODIFIER')),
  lang        text not null default 'en',
  status      text not null default 'live' check (status in ('live', 'proposed', 'rejected')),
  source      text not null default 'seed' check (source in ('seed', 'staff', 'mined')),
  note        text,
  reviewed_by text,                      -- who checked it; the native-script rows wait for a native speaker (DISCOVERY_ALGORITHMS D5)
  reviewed_at timestamptz,
  added_at    timestamptz not null default now(),
  term_raw    text generated always as (btrim(public.search_clean(term))) stored,
  term_key    text generated always as (btrim(public.search_norm(term))) stored,
  means_key   text generated always as (btrim(public.search_norm(means))) stored,
  primary key (term, means),
  check (kind in ('FILLER', 'GENERIC') or means <> '')
);
create index if not exists search_lexicon_term_key on public.search_lexicon (term_key) where status = 'live';
create index if not exists search_lexicon_term_raw on public.search_lexicon (term_raw) where status = 'live';
create index if not exists search_lexicon_means_key on public.search_lexicon (means_key) where status = 'live';
alter table public.search_lexicon enable row level security;   -- read only through search_parse (security definer); staff edit it in the SQL editor
revoke all on public.search_lexicon from public, anon, authenticated;

-- One line per kind and language: "term=means | term=means", or plain terms for FILLER and GENERIC. A reviewer reads one line per
-- language. Seed rows are refreshed on every run; rows a person added or reviewed (source staff or mined) are never touched.
with groups (kind, lang, list) as (values
  -- ----- filler: removed before matching -----
  ('FILLER', 'en', 'a|an|the|i|me|my|mine|we|us|our|you|your|is|are|am|be|was|were|to|of|in|on|at|for|from|with|by|and|or|near|nearby|nearest|nearme|around|close|closest|here|there|where|which|what|who|how|can|could|would|will|should|do|does|did|want|wants|wanted|need|needs|needed|looking|look|find|finding|search|searching|show|get|give|buy|please|pls|plz|any|all|some|someone|somebody|anyone|available|required|require|urgent|urgently|area|location|locality|town|city'),
  ('FILLER', 'hi-Latn', 'chahiye|chaiye|chahie|chaahiye|chahiyee|chahta|chahti|kahan|kaha|kidhar|kahin|hai|hain|ho|ka|ki|ke|ko|se|mein|mai|mujhe|muje|mereko|mera|meri|mere|hume|humko|koi|kuch|paas|nazdeek|nazdik|najdik|batao|bataiye|dikhao|dikhaiye|milega|milegi|milta|milti|ek|aur|ya|bhai|bhaiya|ji|jaldi|ke paas|ke pass|mere paas|mere pass|ke andar'),
  ('FILLER', 'kn-Latn', 'beku|bekagide|beekagide|bekittu|elli|yelli|ide|ideya|idya|hattira|hathira|hattra|nanna|nange|nanage|swalpa|dayavittu|sigutte|sigatte'),
  ('FILLER', 'ta-Latn', 'venum|vendum|enga|engey|enge|irukku|iruka|pakkathula|pakkathil|pakkam|arugil|enakku|konjam|thayavu'),
  ('FILLER', 'te-Latn', 'kavali|kaavali|ekkada|undi|unda|daggara|naaku|dayachesi'),
  ('FILLER', 'ml-Latn', 'venam|evide|evideya|undo|aduthu|enikku|dayavayi'),
  ('FILLER', 'mr-Latn', 'pahije|kuthe|aahe|ahe|jawal|javal|mala|krupaya'),
  ('FILLER', 'kn', 'ಬೇಕು|ಬೇಕಾಗಿದೆ|ಎಲ್ಲಿ|ಇದೆ|ಹತ್ತಿರ|ನನಗೆ|ನನ್ನ|ದಯವಿಟ್ಟು'),
  ('FILLER', 'hi', 'चाहिए|चाहिये|कहाँ|कहां|है|हैं|के|की|का|को|में|मुझे|पास|नज़दीक|कृपया|मेरे'),
  ('FILLER', 'ta', 'வேண்டும்|வேணும்|எங்கே|அருகில்|எனக்கு|பக்கத்தில்'),
  ('FILLER', 'te', 'కావాలి|ఎక్కడ|దగ్గర|నాకు|ఉంది'),
  ('FILLER', 'ml', 'വേണം|എവിടെ|അടുത്ത്|എനിക്ക്|ഉണ്ടോ'),
  ('FILLER', 'mr', 'पाहिजे|कुठे|जवळ|मला|आहे'),
  -- ----- modifiers: removed, and they change the order -----
  ('MODIFIER', 'en', 'cheap=cheap|cheapest=cheap|cheaper=cheap|budget=cheap|affordable=cheap|lowest=cheap|low price=cheap|low cost=cheap|less price=cheap|best price=cheap|discount=cheap|best=best|top=best|famous=best|popular=best|good=best|nice=best|great=best|recommended=best|trusted=best|reliable=best|open=open_now|opened=open_now|open now=open_now|now=open_now|right now=open_now|24 hours=open_now|24 hour=open_now|24x7=open_now|24 7=open_now|delivery=delivery|deliver=delivery|delivers=delivery|home delivery=delivery|door delivery=delivery|free delivery=delivery|doorstep=delivery|door step=delivery'),
  ('MODIFIER', 'hi-Latn', 'sasta=cheap|sasti=cheap|saste=cheap|kam daam=cheap|kam keemat=cheap|kam rate=cheap|accha=best|achha=best|acha=best|achchha=best|badhiya=best|abhi=open_now|khula=open_now|khuli=open_now|abhi khula=open_now'),
  ('MODIFIER', 'kn-Latn', 'agga=cheap|olle=best|olleya=best|iga=open_now'),
  ('MODIFIER', 'ta-Latn', 'malivu=cheap|nalla=best|ippo=open_now|ippove=open_now'),
  ('MODIFIER', 'te-Latn', 'chowka=cheap|manchi=best|ippudu=open_now'),
  ('MODIFIER', 'mr-Latn', 'swasta=cheap|changla=best|chhan=best|aata=open_now'),
  ('MODIFIER', 'hi', 'सस्ता=cheap|सस्ती=cheap|सस्ते=cheap|अच्छा=best|अच्छी=best|बढ़िया=best|अभी=open_now|खुला=open_now|डिलीवरी=delivery'),
  ('MODIFIER', 'kn', 'ಅಗ್ಗ=cheap|ಒಳ್ಳೆಯ=best|ಒಳ್ಳೆ=best|ಈಗ=open_now|ಡೆಲಿವರಿ=delivery'),
  ('MODIFIER', 'ta', 'மலிவு=cheap|நல்ல=best|இப்போது=open_now|டெலிவரி=delivery'),
  ('MODIFIER', 'te', 'మంచి=best|ఇప్పుడు=open_now|డెలివరీ=delivery'),
  ('MODIFIER', 'ml', 'നല്ല=best|ഇപ്പോൾ=open_now|ഡെലിവറി=delivery'),
  ('MODIFIER', 'mr', 'स्वस्त=cheap|चांगला=best|चांगले=best|आता=open_now'),
  -- ----- generic: matched, never enough on their own -----
  ('GENERIC', 'en', 'shop|store|centre|center|service|repair|home|online|new|work|works|agency|point|mart|market|bazaar|bazar|hub|corner|trader|traders|enterprise|enterprises|ltd|pvt|outlet|showroom|fresh|pure|special|quality|original|daily|local|family|hot|cold|big|small|premium|genuine|authentic'),
  ('GENERIC', 'hi-Latn', 'dukaan|dukan|dukkan|wala|wale|wali|waala|waale|waali'),
  ('GENERIC', 'kn-Latn', 'angadi'),
  ('GENERIC', 'ta-Latn', 'kadai'),
  ('GENERIC', 'te-Latn', 'kottu|dukanam'),
  ('GENERIC', 'ml-Latn', 'kada'),
  ('GENERIC', 'hi', 'दुकान|वाला|वाले|वाली'),
  ('GENERIC', 'kn', 'ಅಂಗಡಿ'),
  ('GENERIC', 'ta', 'கடை'),
  ('GENERIC', 'te', 'దుకాణం|కొట్టు|షాపు'),
  ('GENERIC', 'ml', 'കട'),
  -- ----- the words of search_quality.sql, with their kind -----
  ('SAME', 'en', 'wireman=electrician|pipe fitter=plumber|plumbing=plumber|carpentry=carpenter|tailoring=tailor|painting=painter|tuition=tutor|maid=house help|taxi=cab|salon=barber|parlour=beauty|parlor=beauty|veggies=vegetables|general store=grocery|provision=grocery|medical=pharmacy|chemist=pharmacy|mobile repair=phone repair'),
  ('SAME', 'hi-Latn', 'bijli wala=electrician|bijliwala=electrician|nal wala=plumber|nalwala=plumber|mistri=mason|raj mistri=mason|badhai=carpenter|darzi=tailor|dhobi=laundry|nai=barber|kirana=grocery|kiryana=grocery|sabzi=vegetables|sabji=vegetables|subzi=vegetables|phal=fruits|dawai=pharmacy|dawa=pharmacy|doodh=milk|mithai=sweets|halwai=sweets|dhaba=restaurant|khana=food|rangai=painter|putai=painter|bai=house help|rickshaw=auto'),
  ('CONCEPT', 'en', 'electric=electrician|construction=mason|furniture repair=carpenter|stitching=tailor|alteration=tailor|ironing=laundry|dry clean=laundry|hair cut=barber|haircut=barber|supermarket=grocery|medicine=pharmacy|dairy=milk|hotel=restaurant|tiffin=food|mess=food|ac repair=ac mechanic|ac service=ac mechanic|fridge repair=appliance repair|tv repair=appliance repair|bike repair=mechanic|garage=mechanic|puncture=mechanic|coaching=tutor|teacher=tutor|cook=house help'),
  ('CONCEPT', 'hi-Latn', 'istri=laundry'),
  -- ----- food and daily needs -----
  ('SAME', 'en', 'café=cafe|coffee shop=cafe|coffee house=cafe|vegitables=vegetables|vegetabels=vegetables|vegtables=vegetables|veggie=vegetables|vegetable shop=vegetables|grocer=grocery|grocary=grocery|grossery=grocery|provision store=grocery|departmental store=grocery|department store=grocery|super market=supermarket|supermart=supermarket|kirana store=kirana|basmathi=basmati|basumati=basmati|daal=dal|dhal=dal|lentil=dal|chiken=chicken|chikken=chicken|pure veg=veg|vegetarian=veg|nonveg=non veg|non vegetarian=non veg|bakers=bakery|baker=bakery|bakary=bakery|bekary=bakery|bakeri=bakery|cake shop=bakery|sweet shop=sweets|sweet stall=sweets|eatery=restaurant|resturant=restaurant|restaurent=restaurant|restraunt=restaurant|restorant=restaurant|tiffin service=tiffin|biriyani=biryani|briyani=biryani|biriani=biryani|biryanee=biryani|beryani=biryani|idly=idli|iddli=idli|idlee=idli|panner=paneer|panir=paneer|sea food=seafood|ice-cream=ice cream|icecream=ice cream'),
  ('SAME', 'hi-Latn', 'dudh=milk|dahi=curd|makhan=butter|ghi=ghee|kafi=coffee|chai=tea|tarkari=vegetables|sabzee=vegetables|phalon=fruits|kirane=grocery|chawal=rice|chaval=rice|tel=oil|cheeni=sugar|chini=sugar|shahad=honey|shahd=honey|haldi=turmeric|kali mirch=black pepper|anda=eggs|ande=eggs|murga=chicken|murgi=chicken|murgh=chicken|machli=fish|machhli=fish|macchi=fish|gosht=mutton|pav=bread|pao=bread|double roti=bread|khaana=food|dabba=tiffin|mithai shop=sweets|pyaz=onion|pyaaz=onion|tamatar=tomato|kela=banana|aam=mango|aloo=potato|alu=potato|phool=flowers'),
  ('SAME', 'kn-Latn', 'haalu=milk|halu=milk|mosaru=curd|benne=butter|tuppa=ghee|kaapi=coffee|kaafi=coffee|tarakari=vegetables|tarkaari=vegetables|hannu=fruits|kirani=grocery|dinasi=grocery|akki=rice|enne=oil|sakkare=sugar|jenu=honey|arishina=turmeric|menasu=pepper|motte=eggs|koli=chicken|meenu=fish|mamsa=meat|oota=food|darshini=restaurant|military hotel=restaurant|dose=dosa|sihi=sweets|eerulli=onion|baalehannu=banana|maavu=mango|aalugadde=potato|hoovu=flowers'),
  ('SAME', 'ta-Latn', 'paal=milk|thayir=curd|vennai=butter|nei=ghee|kapi=coffee|kaikari=vegetables|kaaikari=vegetables|pazham=fruits|maligai=grocery|malligai=grocery|arisi=rice|ennai=oil|sarkarai=sugar|manjal=turmeric|milagu=pepper|muttai=eggs|kozhi=chicken|meen=fish|saapadu=food|sapadu=food|dosai=dosa|vengayam=onion|thakkali=tomato'),
  ('SAME', 'te-Latn', 'paalu=milk|palu=milk|perugu=curd|venna=butter|neyyi=ghee|kooragayalu=vegetables|kuragayalu=vegetables|pandu=fruits|pandlu=fruits|biyyam=rice|nune=oil|chakkera=sugar|tene=honey|pasupu=turmeric|miriyalu=pepper|guddu=eggs|gudlu=eggs|kodi=chicken|chepa=fish|chepalu=fish|mamsam=meat|bhojanam=food|ullipaya=onion|mamidi=mango|puvvu=flowers'),
  ('SAME', 'ml-Latn', 'thairu=curd|neyy=ghee|kaappi=coffee|chaya=tea|chaaya=tea|pachakkari=vegetables|palacharakku=grocery|enna=oil|panchasara=sugar|kurumulaku=pepper|mutta=eggs|erachi=meat|irachi=meat|oonu=food|dosha=dosa|maanga=mango|poovu=flowers'),
  ('SAME', 'mr-Latn', 'tup=ghee|chaha=tea|bhajipala=vegetables|tandul=rice|sakhar=sugar|halad=turmeric|andi=eggs|kombdi=chicken|mase=fish|masa=fish|jevan=food|kanda=onion|batata=potato|amba=mango'),
  ('SAME', 'hi', 'दूध=milk|दही=curd|घी=ghee|पनीर=paneer|कॉफी=coffee|कॉफ़ी=coffee|चाय=tea|सब्जी=vegetables|सब्जियां=vegetables|फल=fruits|किराना=grocery|चावल=rice|दाल=dal|तेल=oil|चीनी=sugar|शहद=honey|हल्दी=turmeric|काली मिर्च=black pepper|अंडा=eggs|अंडे=eggs|मुर्गा=chicken|मुर्गी=chicken|चिकन=chicken|मछली=fish|मांस=meat|गोश्त=mutton|मटन=mutton|ब्रेड=bread|बेकरी=bakery|केक=cake|मिठाई=sweets|खाना=food|ढाबा=restaurant|बिरयानी=biryani|डोसा=dosa|इडली=idli|प्याज=onion|टमाटर=tomato|केला=banana|आम=mango|आलू=potato|फूल=flowers'),
  ('SAME', 'kn', 'ಹಾಲು=milk|ಮೊಸರು=curd|ಬೆಣ್ಣೆ=butter|ತುಪ್ಪ=ghee|ಪನೀರ್=paneer|ಕಾಫಿ=coffee|ಟೀ=tea|ತರಕಾರಿ=vegetables|ಹಣ್ಣು=fruits|ಹಣ್ಣುಗಳು=fruits|ದಿನಸಿ=grocery|ಕಿರಾಣಿ=grocery|ಅಕ್ಕಿ=rice|ಬೇಳೆ=dal|ಎಣ್ಣೆ=oil|ಸಕ್ಕರೆ=sugar|ಜೇನು=honey|ಜೇನುತುಪ್ಪ=honey|ಅರಿಶಿನ=turmeric|ಮೆಣಸು=pepper|ಮೊಟ್ಟೆ=eggs|ಕೋಳಿ=chicken|ಚಿಕನ್=chicken|ಮೀನು=fish|ಮಾಂಸ=meat|ಮಟನ್=mutton|ಬ್ರೆಡ್=bread|ಬೇಕರಿ=bakery|ಕೇಕ್=cake|ಸಿಹಿ=sweets|ಸಿಹಿತಿಂಡಿ=sweets|ಊಟ=food|ಬಿರಿಯಾನಿ=biryani|ದೋಸೆ=dosa|ಇಡ್ಲಿ=idli|ಈರುಳ್ಳಿ=onion|ಟೊಮೆಟೊ=tomato|ಬಾಳೆಹಣ್ಣು=banana|ಮಾವು=mango|ಆಲೂಗಡ್ಡೆ=potato|ಹೂವು=flowers|ಹೂ=flowers'),
  ('SAME', 'ta', 'பால்=milk|தயிர்=curd|வெண்ணெய்=butter|நெய்=ghee|காபி=coffee|டீ=tea|தேநீர்=tea|காய்கறி=vegetables|காய்கறிகள்=vegetables|பழம்=fruits|பழங்கள்=fruits|மளிகை=grocery|அரிசி=rice|பருப்பு=dal|எண்ணெய்=oil|சர்க்கரை=sugar|தேன்=honey|மஞ்சள்=turmeric|மிளகு=pepper|முட்டை=eggs|கோழி=chicken|சிக்கன்=chicken|மீன்=fish|இறைச்சி=meat|மட்டன்=mutton|ரொட்டி=bread|பேக்கரி=bakery|கேக்=cake|இனிப்பு=sweets|சாப்பாடு=food|உணவு=food|உணவகம்=restaurant|பிரியாணி=biryani|தோசை=dosa|இட்லி=idli|வெங்காயம்=onion|தக்காளி=tomato|வாழைப்பழம்=banana|மாம்பழம்=mango|உருளைக்கிழங்கு=potato|பூ=flowers'),
  ('SAME', 'te', 'పాలు=milk|పెరుగు=curd|వెన్న=butter|నెయ్యి=ghee|కాఫీ=coffee|టీ=tea|కూరగాయలు=vegetables|పండ్లు=fruits|కిరాణా=grocery|బియ్యం=rice|పప్పు=dal|నూనె=oil|చక్కెర=sugar|తేనె=honey|పసుపు=turmeric|మిరియాలు=pepper|గుడ్లు=eggs|గుడ్డు=eggs|కోడి=chicken|చికెన్=chicken|చేప=fish|చేపలు=fish|మాంసం=meat|మటన్=mutton|బ్రెడ్=bread|బేకరీ=bakery|కేక్=cake|స్వీట్స్=sweets|భోజనం=food|బిర్యానీ=biryani|దోశ=dosa|ఇడ్లీ=idli|ఉల్లిపాయ=onion|టమాటా=tomato|అరటిపండు=banana|మామిడి=mango|బంగాళదుంప=potato|పూలు=flowers'),
  ('SAME', 'ml', 'പാൽ=milk|തൈര്=curd|വെണ്ണ=butter|നെയ്യ്=ghee|കാപ്പി=coffee|ചായ=tea|പച്ചക്കറി=vegetables|പഴം=fruits|പലചരക്ക്=grocery|അരി=rice|പരിപ്പ്=dal|എണ്ണ=oil|പഞ്ചസാര=sugar|തേൻ=honey|മഞ്ഞൾ=turmeric|കുരുമുളക്=pepper|മുട്ട=eggs|കോഴി=chicken|ചിക്കൻ=chicken|മീൻ=fish|ഇറച്ചി=meat|മട്ടൻ=mutton|ബ്രെഡ്=bread|ബേക്കറി=bakery|കേക്ക്=cake|ഭക്ഷണം=food|ഊണ്=food|ബിരിയാണി=biryani|ദോശ=dosa|ഇഡ്ഡലി=idli|ഇഡലി=idli|ഉള്ളി=onion|തക്കാളി=tomato|മാങ്ങ=mango|ഉരുളക്കിഴങ്ങ്=potato|പൂവ്=flowers'),
  ('SAME', 'mr', 'चहा=tea|भाजीपाला=vegetables|फळे=fruits|किराणा=grocery|तांदूळ=rice|डाळ=dal|तूप=ghee|साखर=sugar|मध=honey|हळद=turmeric|अंडी=eggs|कोंबडी=chicken|मासे=fish|पाव=bread|जेवण=food|कांदा=onion|बटाटा=potato|आंबा=mango'),
  ('CONCEPT', 'en', 'milk=grocery|milk=dairy|curd=dairy|curd=grocery|coffee=cafe|tea=cafe|tea stall=cafe|tea shop=cafe|chai stall=cafe|fruits=vegetables|rice=grocery|dal=grocery|oil=grocery|sugar=grocery|honey=grocery|flour=grocery|atta=grocery|ghee=grocery|ration=grocery|ration shop=grocery|organic=organic store|seafood=fish|non veg=meat|bread=bakery|cake=bakery|biscuit=bakery|sweets=bakery|food=restaurant|meals=restaurant|lunch=restaurant|dinner=restaurant|breakfast=restaurant|canteen=restaurant|home food=tiffin|home made food=tiffin|homemade food=tiffin|chaat=street food|pani puri=street food|golgappa=street food|catering=caterer|caterer=catering|juice=juice bar'),
  ('CONCEPT', 'hi-Latn', 'atta=flour'),
  ('CONCEPT', 'hi', 'होटल=restaurant'),
  ('CONCEPT', 'kn', 'ಹೋಟೆಲ್=restaurant'),
  ('CONCEPT', 'ta', 'ஹோட்டல்=restaurant'),
  ('CONCEPT', 'te', 'హోటల్=restaurant'),
  ('CONCEPT', 'ml', 'ഹോട്ടൽ=restaurant'),
  -- ----- health -----
  ('SAME', 'en', 'medcine=medicine|medicin=medicine|madicine=medicine|medical shop=pharmacy|medical store=pharmacy|chemist shop=pharmacy|drug store=pharmacy|drugstore=pharmacy|pharmacist=pharmacy|farmacy=pharmacy|pharmecy=pharmacy|pharmasy=pharmacy|docter=doctor|dr=doctor|physician=doctor|dispensary=clinic|dentist=dental clinic|physio=physiotherapist|physiotherapy=physiotherapist|home nurse=nurse|vet=veterinarian|veterinary=veterinary clinic|animal doctor=veterinarian|optician=optical|spectacles=optical|nanny=babysitter|attendant=caregiver|blood test=diagnostic lab|lab test=diagnostic lab'),
  ('SAME', 'hi-Latn', 'dawaai=medicine|dava=medicine|daktar=doctor|aspatal=hospital|dawakhana=clinic|aaya=babysitter|chashma=spectacles'),
  ('SAME', 'kn-Latn', 'aushadhi=medicine|oushadhi=medicine|vaidya=doctor|aspatre=hospital|aaspatre=hospital'),
  ('SAME', 'ta-Latn', 'marundhu=medicine|marunthu=medicine'),
  ('SAME', 'te-Latn', 'mandulu=medicine'),
  ('SAME', 'ml-Latn', 'marunnu=medicine'),
  ('SAME', 'mr-Latn', 'aushadh=medicine'),
  ('SAME', 'hi', 'दवाई=medicine|दवा=medicine|औषधि=medicine|मेडिकल=pharmacy|डॉक्टर=doctor|डाक्टर=doctor|अस्पताल=hospital'),
  ('SAME', 'kn', 'ಔಷಧಿ=medicine|ಔಷಧ=medicine|ಮೆಡಿಕಲ್=pharmacy|ಡಾಕ್ಟರ್=doctor|ವೈದ್ಯ=doctor|ಆಸ್ಪತ್ರೆ=hospital'),
  ('SAME', 'ta', 'மருந்து=medicine|மருந்தகம்=pharmacy|மெடிக்கல்=pharmacy|டாக்டர்=doctor|மருத்துவர்=doctor|மருத்துவமனை=hospital'),
  ('SAME', 'te', 'మందులు=medicine|మెడికల్=pharmacy|డాక్టర్=doctor|ఆసుపత్రి=hospital'),
  ('SAME', 'ml', 'മരുന്ന്=medicine|മെഡിക്കൽ=pharmacy|ഡോക്ടർ=doctor|ആശുപത്രി=hospital'),
  ('SAME', 'mr', 'औषध=medicine|दवाखाना=clinic'),
  ('CONCEPT', 'en', 'doctor=clinic|hospital=clinic|nursing home=clinic|health centre=clinic|child specialist=doctor|paediatrician=doctor|pediatrician=doctor|dental=dental clinic|caretaker=caregiver|elder care=caregiver|scan=diagnostic lab|eye test=optical|eye glasses=optical|specs=optical|spectacles=eye care'),
  -- ----- home services -----
  ('SAME', 'en', 'plumbar=plumber|plumer=plumber|plamber=plumber|electrision=electrician|electricion=electrician|electritian=electrician|elecrician=electrician|electrian=electrician|carpentar=carpenter|carpinter=carpenter|wall painting=painter|house painting=painter|ac mechanic=ac technician|air conditioner=ac|aircon=ac|a c=ac|mekanik=mechanic|mecanic=mechanic|ladies tailor=tailor|istri wala=laundry|press wala=laundry|dry cleaning=laundry|dry cleaner=laundry|saloon=salon|sailoon=salon|hair salon=salon|barber=salon|barber shop=barber|beauty parlor=beauty parlour|ladies parlour=beauty parlour|parlour=beauty parlour|parlor=beauty parlour|beauty parlour=beautician|makeup artist=beautician|mehndi=mehendi|mehndi artist=mehendi artist|house maid=house help|cleaning lady=house help|house cleaning=cleaning service|home cleaning=cleaning service|cooking=cook|chef=cook|acting driver=driver|call driver=driver|chauffeur=driver|gardening=gardener|packers movers=packers and movers|movers and packers=packers and movers|movers packers=packers and movers|welding=welder|key maker=locksmith|cctv=cctv installer|cctv camera=cctv installer|handy man=handyman'),
  ('SAME', 'hi-Latn', 'darji=tailor|barhai=carpenter|naai=barber|hajam=barber|kaamwali=house help|kaam wali=house help|bawarchi=cook|mali=gardener|maali=gardener|mochi=cobbler|chabi wala=locksmith|chaabi wala=locksmith'),
  ('SAME', 'kn-Latn', 'badagi=carpenter|mestri=mason'),
  ('SAME', 'ta-Latn', 'thachar=carpenter'),
  ('SAME', 'te-Latn', 'vadrangi=carpenter'),
  ('SAME', 'ml-Latn', 'aashari=carpenter'),
  ('SAME', 'mr-Latn', 'sutar=carpenter|shimpi=tailor'),
  ('SAME', 'hi', 'प्लंबर=plumber|नल वाला=plumber|इलेक्ट्रीशियन=electrician|बिजली वाला=electrician|बढ़ई=carpenter|पेंटर=painter|मिस्त्री=mason|मैकेनिक=mechanic|दर्जी=tailor|धोबी=laundry|सैलून=salon|नाई=barber|ब्यूटी पार्लर=beauty parlour|रसोइया=cook|माली=gardener'),
  ('SAME', 'kn', 'ಪ್ಲಂಬರ್=plumber|ಎಲೆಕ್ಟ್ರಿಷಿಯನ್=electrician|ಬಡಗಿ=carpenter|ಪೇಂಟರ್=painter|ಮೇಸ್ತ್ರಿ=mason|ಮೆಕಾನಿಕ್=mechanic|ದರ್ಜಿ=tailor|ಟೈಲರ್=tailor|ಸಲೂನ್=salon'),
  ('SAME', 'ta', 'பிளம்பர்=plumber|எலக்ட்ரீஷியன்=electrician|தச்சர்=carpenter|மெக்கானிக்=mechanic|தையல்காரர்=tailor|டெய்லர்=tailor|சலூன்=salon'),
  ('SAME', 'te', 'ప్లంబర్=plumber|ఎలక్ట్రీషియన్=electrician|వడ్రంగి=carpenter|మెకానిక్=mechanic|టైలర్=tailor|దర్జీ=tailor|సెలూన్=salon'),
  ('SAME', 'ml', 'പ്ലംബർ=plumber|ഇലക്ട്രീഷ്യൻ=electrician|ആശാരി=carpenter|മെക്കാനിക്ക്=mechanic|തയ്യൽക്കാരൻ=tailor|ടെയ്ലർ=tailor|സലൂൺ=salon'),
  ('SAME', 'mr', 'सुतार=carpenter|शिंपी=tailor'),
  ('CONCEPT', 'en', 'leak=plumber|leakage=plumber|water leakage=plumber|tap repair=plumber|pipe repair=plumber|pipe leak=plumber|bathroom fitting=plumber|tank cleaning=plumber|geyser=plumber|wiring=electrician|fan repair=electrician|light fitting=electrician|inverter=electrician|switch board=electrician|switchboard=electrician|wood work=carpenter|woodwork=carpenter|door repair=carpenter|construction=builder|ac repair=ac technician|ac repair=appliance repair|ac service=ac technician|ac servicing=ac technician|ac installation=ac technician|ac fitting=ac technician|washing machine repair=appliance repair|ro service=appliance repair|ro repair=appliance repair|water purifier=appliance repair|car repair=mechanic|scooter repair=mechanic|bike service=mechanic|car service=mechanic|two wheeler=mechanic|puncture=tyre shop|bike repair=bike mechanic|blouse stitching=tailor|washing=laundry|shave=barber|hair cut=salon|haircut=salon|hair cutting=salon|beauty=beautician|makeup=beautician|make up=beautician|bridal makeup=beautician|threading=beautician|facial=beautician|mehendi=mehendi artist|housekeeping=house help|maid=cleaner|pest=pest control|termite=pest control|cockroach=pest control|mosquito=pest control|house shifting=packers and movers|shifting=packers and movers|duplicate key=locksmith|shoe repair=cobbler|tiles=tile fitter|garden=gardener|plants=nursery and plants|plant nursery=nursery and plants'),
  ('CONCEPT', 'hi-Latn', 'nal=plumber|bijli=electrician|silai=tailor'),
  ('CONCEPT', 'ta-Latn', 'thaiyal=tailor'),
  ('CONCEPT', 'hi', 'बिजली=electrician|सिलाई=tailor'),
  ('CONCEPT', 'kn', 'ಕರೆಂಟ್=electrician'),
  -- ----- learning -----
  ('SAME', 'en', 'tution=tutor|tuter=tutor|tutar=tutor|tuition classes=tutor|tution classes=tutor|home tuition=tutor|home tution=tutor|private tuition=tutor|tuition centre=tutor|tution centre=tutor|mathematics=math|play school=preschool|playschool=preschool|pre school=preschool|nursery school=preschool|kindergarten=preschool|yoga teacher=yoga instructor|yoga classes=yoga instructor|yoga class=yoga instructor|fitness trainer=gym trainer|personal trainer=gym trainer|spoken english=english tutor|internet cafe=cyber cafe|browsing centre=cyber cafe'),
  ('SAME', 'hi-Latn', 'vidyalaya=school|yog=yoga'),
  ('SAME', 'kn-Latn', 'shaale=school'),
  ('SAME', 'ta-Latn', 'palli=school'),
  ('SAME', 'te-Latn', 'badi=school'),
  ('SAME', 'mr-Latn', 'shala=school'),
  ('SAME', 'hi', 'ट्यूशन=tutor|शिक्षक=teacher|टीचर=teacher|स्कूल=school|विद्यालय=school|योग=yoga'),
  ('SAME', 'kn', 'ಟ್ಯೂಷನ್=tutor|ಶಿಕ್ಷಕ=teacher|ಮೇಷ್ಟ್ರು=teacher|ಶಾಲೆ=school|ಯೋಗ=yoga'),
  ('SAME', 'ta', 'டியூஷன்=tutor|ஆசிரியர்=teacher|பள்ளி=school'),
  ('SAME', 'te', 'ట్యూషన్=tutor|టీచర్=teacher|పాఠశాల=school|స్కూల్=school'),
  ('SAME', 'ml', 'ട്യൂഷൻ=tutor|അധ്യാപകൻ=teacher|സ്കൂൾ=school'),
  ('SAME', 'mr', 'शाळा=school'),
  ('CONCEPT', 'en', 'coaching centre=tutor|exam coaching=exam coach|gym=fitness trainer|fitness=fitness trainer|workout=fitness trainer|coding=coding instructor|music class=music teacher|dance class=dance studio'),
  -- ----- tech, shopping, work -----
  ('SAME', 'en', 'web site=website|web design=web designer|website design=web designer|web development=web developer|app developer=mobile app developer|programmer=software developer|coder=software developer|it company=it services|it firm=it services|graphic design=graphic designer|mobile=phone|mobile phone=phone|cell phone=phone|cellphone=phone|smartphone=phone|smart phone=phone|phone repair=mobile repair|mobile service=mobile repair|pc=computer|desktop=computer|laptop repair=computer repair|television=tv|led tv=tv|earphone=headphones|headset=headphones|airpods=earbuds|powerbank=power bank|smartwatch=smart watch|photography=photographer|photo studio=photography studio|cameraman=photographer|camera man=photographer|photographar=photographer|fotographer=photographer|videography=videographer|xerox=printing and xerox|photocopy=xerox|photo copy=xerox|stationary=stationery|stationer=stationery|book shop=books|book store=books|clothes=clothing|cloth=clothing|cloths=clothing|garments=clothing|sari=saree|saari=saree|tshirt=t shirt|tee shirt=t shirt|hardware store=hardware|home decoration=home decor|décor=decor|pet store=pet shop|jewelry=jewellery|jewellers=jewellery|jeweller=jewellery|jeweler=jewellery|gift shop=gifts|gift items=gifts|toy shop=toys|utensils=kitchenware|florist=flowers|flower shop=flowers|advocate=lawyer|chartered accountant=accountant|event manager=event management|event organiser=event management|event organizer=event management|disc jockey=dj|architecture=architect|interior design=interior designer|charity=ngo|non profit=ngo|nonprofit=ngo|society=association|rwa=resident association|residents association=resident association|welfare association=resident association|real estate=real estate agent|property dealer=real estate agent|property agent=real estate agent|apartment=flat|home stay=homestay|pg=paying guest|seo=seo specialist|social media marketing=digital marketing'),
  ('SAME', 'hi-Latn', 'kapde=clothing|kapda=clothing|sadi=saree|vakil=lawyer|vakeel=lawyer|bartan=kitchenware'),
  ('SAME', 'kn-Latn', 'batte=clothing|seere=saree'),
  ('SAME', 'ta-Latn', 'thuni=clothing|pudavai=saree|podavai=saree|selai=saree'),
  ('SAME', 'te-Latn', 'battalu=clothing|cheera=saree'),
  ('SAME', 'hi', 'मोबाइल=mobile|फोन=phone|कपड़े=clothing|कपड़ा=clothing|साड़ी=saree|फोटोग्राफर=photographer|वकील=lawyer'),
  ('SAME', 'kn', 'ಮೊಬೈಲ್=mobile|ಫೋನ್=phone|ಬಟ್ಟೆ=clothing|ಸೀರೆ=saree|ಫೋಟೋಗ್ರಾಫರ್=photographer|ವಕೀಲ=lawyer'),
  ('SAME', 'ta', 'மொபைல்=mobile|போன்=phone|துணி=clothing|புடவை=saree|சேலை=saree'),
  ('SAME', 'te', 'మొబైల్=mobile|ఫోన్=phone|బట్టలు=clothing|చీర=saree'),
  ('SAME', 'ml', 'മൊബൈൽ=mobile|ഫോൺ=phone|തുണി=clothing|സാരി=saree'),
  ('SAME', 'mr', 'मोबाईल=mobile|कपडे=clothing'),
  ('CONCEPT', 'en', 'website=web developer|website=software developer|web developer=software developer|app development=mobile app developer|mobile app=mobile app developer|android app=mobile app developer|developer=software developer|software=software developer|software=it services|logo design=graphic designer|mobile=electronics|phone=electronics|laptop=electronics|laptop=computer sales|computer=electronics|computer=computer sales|computer repair=electronics|printer=electronics|tv=electronics|tv=appliances|charger=electronics|power bank=electronics|fridge=appliances|washing machine=appliances|mixer=appliances|photo shoot=photographer|photoshoot=photographer|video shoot=videographer|printout=printing and xerox|print out=printing and xerox|lamination=printing and xerox|notebook=stationery|school supplies=stationery|readymade=clothing|dress=clothing|fashion=clothing|boutique=clothing|textile=clothing|saree=clothing|kurta=clothing|kurti=clothing|jeans=clothing|shoes=footwear|chappal=footwear|sandals=footwear|slippers=footwear|sanitary=hardware|tools=hardware|cement=hardware|plywood=hardware|paint shop=paint and tiles|sofa=furniture|cot=furniture|almirah=furniture|cupboard=furniture|mattress=furniture|decoration=home decor|showpiece=home decor|show piece=home decor|handicrafts=handloom and crafts|lights=lighting|pet food=pet shop|dog food=pet shop|cat food=pet shop|gold shop=jewellery|bouquet=flowers|notary=lawyer|legal advice=lawyer|ca=accountant|auditor=accountant|tax=accountant|income tax=tax consultant|gst=accountant|itr=tax consultant|tax filing=tax consultant|bookkeeping=accountant|accounts=accountant|decorators=decorator|tent house=decorator|wedding=wedding planner|sound system=dj|house plan=architect|interior=interior designer|modular kitchen=interior designer|volunteer=ngo|volunteering=ngo|donate=ngo|donation=ngo|foundation=ngo|club=association|broker=real estate agent|1bhk=flat|2bhk=flat|3bhk=flat|1 bhk=flat|2 bhk=flat|3 bhk=flat|bhk=flat|homestay=guest house|homestay=resort|homestay=lodge|guest house=homestay|lodge=homestay|lodging=lodge|resort=homestay|parcel=courier|security guard=security services|watchman=security services|tour=travel agency|ticket booking=travel agency|temple=religious place|church=religious place|mosque=religious place|masjid=religious place|mandir=religious place|gurudwara=religious place'),
  ('CONCEPT', 'hi-Latn', 'sunar=jewellery|shamiana=decorator'),
  ('CONCEPT', 'hi', 'मंदिर=religious place')
),
pairs as (
  select distinct on (term, means) g.kind, g.lang, btrim(split_part(p, '=', 1)) term, btrim(split_part(p, '=', 2)) means
  from groups g, regexp_split_to_table(g.list, '\s*\|\s*') p
  where btrim(p) <> ''
  order by term, means, g.kind
)
insert into public.search_lexicon (term, means, kind, lang)
select term, means, kind, lang from pairs
on conflict (term, means) do update set kind = excluded.kind, lang = excluded.lang
  where search_lexicon.source = 'seed';

-- Words added to search_synonyms on a live project and never written here: carried over as SAME, for a person to classify.
insert into public.search_lexicon (term, means, kind, lang, note)
select s.word, s.means, 'SAME', 'en', 'from search_synonyms'
from public.search_synonyms s
where not exists (select 1 from public.search_lexicon x where x.term_key = btrim(public.search_norm(s.word)))
on conflict (term, means) do nothing;

update public.search_lexicon set term = term;   -- recompute the generated keys with the functions above

-- ---------- 3. reading a query ----------
-- q → {"terms": [{"key", "raw", "generic", "fuzzy", "prefix", "direct": [' word ', …], "concept": [' word ', …]}], "mods": [...],
--      "price_cap": n}. The longest phrase (up to 4 words) found in the lexicon wins, so "home delivery" is a modifier before "home" is
-- a generic word, and "ac repair" a phrase before "repair". A term's direct forms are its own key and SAME rows either way, two steps
-- deep (चाय → tea → chai); its concept forms are CONCEPT rows of those, two steps deep. At most 8 terms.
create or replace function public.search_parse(q text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  s text := lower(normalize(left(coalesce(q, ''), 100), nfc));
  cap_re1 constant text := '\m(under|below|bellow|less than|within|upto|up to|max|maximum)\s*(rs\.?|inr|₹)?\s*(\d{2,6})\M\s*(rs|rupees|/-)?';
  cap_re2 constant text := '(\mrs\.?|₹)?\s*\m(\d{2,6})\s*(rs|rupees|₹|/-)?\s*(ke andar|ke andhar|ke niche|ke neeche|tak|se kam)\M';
  m text[]; cap int;
  raw text[]; keys text[]; n int; i int := 1; k int;
  ph_raw text; ph_key text; nk int; kinds text[]; mod_names text[];
  mods text[] := '{}'; terms jsonb := '[]'; nterms int := 0;
  d text[]; c text[]; is_generic boolean; plain boolean;
begin
  m := regexp_match(s, cap_re1);
  if m is not null then cap := m[3]::int; s := regexp_replace(s, cap_re1, ' ');
  else
    m := regexp_match(s, cap_re2);
    if m is not null then cap := m[2]::int; s := regexp_replace(s, cap_re2, ' '); end if;
  end if;
  if cap is not null then mods := mods || 'cheap'::text; end if;

  raw := array(select w from unnest(string_to_array(btrim(public.search_clean(s)), ' ')) with ordinality u(w, o) where w <> '' order by o);
  n := coalesce(array_length(raw, 1), 0);
  keys := array(select public.search_key(w) from unnest(raw) with ordinality u(w, o) order by o);

  while i <= n and nterms < 8 loop
    kinds := null; nk := 1;
    for k in reverse least(4, n - i + 1) .. 1 loop
      ph_raw := array_to_string(raw[i:i + k - 1], ' ');
      ph_key := array_to_string(keys[i:i + k - 1], ' ');
      select array_agg(distinct x.kind), array_agg(distinct x.means) filter (where x.kind = 'MODIFIER') into kinds, mod_names
      from public.search_lexicon x
      where x.status = 'live'
        and ((x.kind in ('FILLER', 'MODIFIER') and x.term_raw = ph_raw) or (x.kind in ('SAME', 'CONCEPT', 'GENERIC') and x.term_key = ph_key));
      if kinds is not null then nk := k; exit; end if;
    end loop;

    if kinds is not null and 'MODIFIER' = any(kinds) then
      mods := mods || mod_names;
    elsif kinds is not null and 'FILLER' = any(kinds) then
      null;
    else
      ph_key := array_to_string(keys[i:i + nk - 1], ' ');
      ph_raw := array_to_string(raw[i:i + nk - 1], ' ');
      is_generic := kinds is not null and kinds = array['GENERIC'];
      plain := kinds is null;
      -- direct: the key, SAME either way, then one more SAME step either way
      d := array[ph_key]
           || array(select x.means_key from public.search_lexicon x where x.status = 'live' and x.kind = 'SAME' and x.term_key = ph_key)
           || array(select x.term_key from public.search_lexicon x where x.status = 'live' and x.kind = 'SAME' and x.means_key = ph_key);
      d := d || array(select x.means_key from public.search_lexicon x where x.status = 'live' and x.kind = 'SAME' and x.term_key = any(d))
             || array(select x.term_key from public.search_lexicon x where x.status = 'live' and x.kind = 'SAME' and x.means_key = any(d));
      d := array(select distinct v from unnest(d) v where v <> '');
      -- concept: CONCEPT rows of the direct forms, then CONCEPT and SAME rows of those
      c := array(select x.means_key from public.search_lexicon x where x.status = 'live' and x.kind = 'CONCEPT' and x.term_key = any(d));
      c := c || array(select x.means_key from public.search_lexicon x where x.status = 'live' and x.kind in ('CONCEPT', 'SAME') and x.term_key = any(c));
      c := array(select distinct v from unnest(c) v where v <> '' and not v = any(d));
      terms := terms || jsonb_build_object(
        'key', ph_key, 'raw', ph_raw, 'generic', is_generic,
        'fuzzy', plain and nk = 1 and ph_key ~ '^[a-z]{5,}$',
        'prefix', plain and nk = 1 and ph_key ~ '^[a-z]{4,}$' and i + nk - 1 = n,
        'direct', (select coalesce(jsonb_agg(' ' || v || ' '), '[]') from unnest(d) v),
        'concept', (select coalesce(jsonb_agg(' ' || v || ' '), '[]') from unnest(c) v));
      nterms := nterms + 1;
    end if;
    i := i + nk;
  end loop;

  return jsonb_build_object('terms', terms, 'mods', (select coalesce(jsonb_agg(distinct v), '[]') from unnest(mods) v), 'price_cap', cap);
end $$;

-- ---------- 4. search ----------
create or replace function public.search_listings(q text, lat double precision, lng double precision, radius_m int default 10000, kinds text[] default null,
                                                  lim int default 40, services text[] default null)
returns table (id uuid, kind text, title text, category text, description text, photo_url text, area text, online boolean, trust_up int, trust_down int,
               details jsonb, distance_m double precision, matched_item text, min_price int, type_key text, group_key text, owner_id uuid, owner_name text,
               matched_price int)
language sql stable security definer set search_path = public, extensions as $$
  with here as (select public.geo(lat, lng) g, least(greatest(coalesce(radius_m, 10000), 0), 50000) r),
       parsed as (select public.search_parse(q) j),
       mods as (select array(select jsonb_array_elements_text(parsed.j->'mods')) m, (parsed.j->>'price_cap')::int cap from parsed),
       terms as (
         select e.o::int pos, e.t->>'key' tkey, (e.t->>'generic')::boolean generic, (e.t->>'fuzzy')::boolean fuzzy_ok, (e.t->>'prefix')::boolean prefix_ok,
                array(select jsonb_array_elements_text(e.t->'direct')) direct, array(select jsonb_array_elements_text(e.t->'concept')) concept
         from parsed, jsonb_array_elements(parsed.j->'terms') with ordinality e(t, o)),
       core as (select count(*) filter (where not generic) n_core, count(*) n_all from terms),
       cand as (
         select l.id, l.kind, l.title, l.category, l.description, l.photo_url, l.area, l.online, l.trust_up, l.trust_down, l.details,
                l.type_key, t.group_key, l.owner_id, coalesce(nullif(o.name, ''), 'Bucks member') owner_name,
                st_distance(l.location, here.g) distance_m,
                coalesce(l.location is not null and st_dwithin(l.location, here.g, here.r), false) in_range,
                public.search_trust(l.trust_up, l.trust_down) trust,
                -- the fields, normalised once (only for a typed query); a double space between fields stops a phrase running across two
                case when core.n_all > 0 then public.search_norm(l.title) || public.search_norm(l.category) || public.search_norm(t.label) end n_t,
                case when core.n_all > 0 then public.search_norm(l.category) || public.search_norm(t.label) end n_c,
                case when core.n_all > 0 then public.search_norm(o.name) end n_o,
                case when core.n_all > 0 then public.search_norm(left(l.description, 600)) || public.search_norm(l.area) end n_d
         from listings l left join listing_types t on t.key = l.type_key join profiles o on o.id = l.owner_id cross join here cross join core
         where l.status = 'LIVE'
           and not public.blocked_between(public.me(), l.owner_id)
           and (kinds is null or l.kind = any(kinds))
           and (services is null or l.service = any(services))
           and ((l.location is not null and st_dwithin(l.location, here.g, here.r))
                or (l.kind = 'BUSINESS' and lower(coalesce(l.details->>'ships_india', '')) = 'true'))),
       itn as (
         select i.listing_id, i.name, nullif(i.price, 0)::int price, i.in_stock, public.search_norm(i.name) n
         from items i where (select n_all from core) > 0 and i.listing_id in (select c.id from cand c)),
       blob as (select c.id, coalesce(string_agg(itn.n, ' '), '') n_i from cand c left join itn on itn.listing_id = c.id group by c.id),
       -- per page and term: 3 title, category or type · 2 product or owner · 1 description or area; through a concept 2 category, 1 product
       hits as (
         select c.id, tr.pos, tr.generic,
                greatest(
                  case when exists (select 1 from unnest(tr.direct) f where position(f in c.n_t) > 0) then 3
                       when exists (select 1 from unnest(tr.direct) f where position(f in b.n_i) > 0 or position(f in c.n_o) > 0) then 2
                       when exists (select 1 from unnest(tr.direct) f where position(f in c.n_d) > 0) then 1
                       else 0 end,
                  case when exists (select 1 from unnest(tr.concept) f where position(f in c.n_t) > 0) then 2
                       when exists (select 1 from unnest(tr.concept) f where position(f in b.n_i) > 0) then 1
                       else 0 end) rnk
         from cand c join blob b on b.id = c.id cross join terms tr),
       -- typos and a half-typed last word, only for plain words that nothing matched exactly. A typo is matched word by word against
       -- words at most one letter shorter ("plumbr" finds "plumber", not "plum"), and only on pages in range (a 284-item catalogue
       -- 700 km away would otherwise answer every typo).
       dead as (select tr.* from terms tr where (tr.fuzzy_ok or tr.prefix_ok) and not exists (select 1 from hits h where h.pos = tr.pos and h.rnk > 0)),
       loose as (
         select distinct c.id, d.pos from cand c join blob b on b.id = c.id cross join dead d
         where (d.fuzzy_ok and c.in_range
                and exists (select 1 from unnest(string_to_array(c.n_t || b.n_i, ' ')) w
                            where length(w) >= greatest(4, length(d.tkey) - 1) and similarity(w, d.tkey) >= 0.45))
            or (d.prefix_ok and exists (select 1 from unnest(string_to_array(c.n_c, ' ')) w where length(w) > length(d.tkey) and left(w, length(d.tkey)) = d.tkey))),
       scored as (
         select h.id,
                count(*) filter (where (h.rnk > 0 or lo.id is not null) and (not h.generic or core.n_core = 0)) n_hit,
                coalesce(sum(case when h.rnk > 0 then h.rnk when lo.id is not null then 1 else 0 end) filter (where not h.generic or core.n_core = 0), 0) fscore,
                count(*) filter (where h.rnk > 0 and h.generic and core.n_core > 0) g_hit
         from hits h left join loose lo on lo.id = h.id and lo.pos = h.pos cross join core
         group by h.id),
       pool as (
         select c.*, coalesce(s.fscore, 0) fscore, coalesce(s.g_hit, 0) g_hit,
                case when core.n_all = 0 then 1.0
                     else coalesce(s.n_hit, 0)::numeric / greatest(1, case when core.n_core > 0 then core.n_core else core.n_all end) end coverage
         from cand c left join scored s on s.id = c.id cross join core
         where core.n_all = 0 or s.n_hit > 0),
       -- when a page in range matches every meaningful word, only pages that match every one are shown
       gate as (select coalesce(max(coverage) filter (where in_range), 0) local_top from pool)
  select p.id, p.kind, p.title, p.category, p.description, p.photo_url, p.area, p.online, p.trust_up, p.trust_down, p.details, p.distance_m,
         mi.name as matched_item,
         (select min(i.price) from items i where i.listing_id = p.id and i.in_stock and i.price > 0) as min_price,
         p.type_key, p.group_key, p.owner_id, p.owner_name,
         mi.price as matched_price
  from pool p cross join gate cross join mods cross join core
  -- the product that answers the most words; in stock first, then the cheapest priced one
  left join lateral (
    select x.name, x.price from (
      select it.name, it.price, it.in_stock,
             (select count(*) from terms tr
               where (not tr.generic or core.n_core = 0)
                 and (exists (select 1 from unnest(tr.direct || tr.concept) f where position(f in it.n) > 0)
                      or (p.in_range and exists (select 1 from dead d where d.pos = tr.pos and d.fuzzy_ok)
                          and exists (select 1 from unnest(string_to_array(it.n, ' ')) w
                                      where length(w) >= greatest(4, length(tr.tkey) - 1) and similarity(w, tr.tkey) >= 0.45)))) nt
      from itn it where it.listing_id = p.id) x
    where x.nt > 0
    order by x.nt desc, (mods.cap is null or coalesce(x.price <= mods.cap, false)) desc, x.in_stock desc, x.price nulls last, x.name
    limit 1) mi on true
  where p.coverage = 1 or gate.local_top < 1
  order by p.in_range desc,
           case when 'open_now' = any(mods.m) then p.online end desc nulls last,
           p.coverage desc, p.fscore desc, p.g_hit desc,
           case when mods.cap is not null then mi.price <= mods.cap end desc nulls last,
           case when 'cheap' = any(mods.m) then mi.price end nulls last,
           case when 'best' = any(mods.m) then p.trust end desc nulls last,
           p.online desc, p.trust desc, p.distance_m nulls last, p.id
  limit greatest(1, least(coalesce(lim, 40), 100))
$$;

-- ---------- grants ----------
revoke all on function public.search_listings(text, double precision, double precision, int, text[], int, text[]) from public, anon;
grant execute on function public.search_listings(text, double precision, double precision, int, text[], int, text[]) to authenticated;
revoke all on function public.search_parse(text) from public, anon;
grant execute on function public.search_parse(text) to authenticated;
revoke all on function public.search_clean(text), public.search_key(text), public.search_norm(text), public.search_trust(int, int) from public, anon;
grant execute on function public.search_clean(text), public.search_key(text), public.search_norm(text), public.search_trust(int, int) to authenticated;
