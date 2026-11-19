-- The golden query set (docs/DISCOVERY_ALGORITHMS.md §9.1). A fixed catalogue that mirrors the live demo world at Gonikoppal (G) and
-- Whitefield (W), plus a shop 740 km away that ships India-wide and holds the junk traps of the audit ("USB-C Cable" for taxi, a
-- "Milky White" vase for milk, "Abstract Cat Figurine — Medium" for medicine, "Snowberry & Bunny Tail" for tailor).
--
-- Every case says what must be in the top 3 ("want": any one of those titles; empty = nothing at all must come back) and what must
-- not be in the top 10 ("forbid"). A case that passes today must keep passing: it prints ok, or FAIL with what came back. A case
-- marked gap is a known miss that prints "gap" and fails nothing; when it starts passing it says so, and the mark comes off.
-- The scorecard at the end (success@3, MRR, junk@10, answerable zero rate, true zeros) must stay at or above the baseline.
--
-- Adding a word to search_lexicon? Add a case here that needs it and one that it must not break (DISCOVERY_ALGORITHMS §13).
\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.as_phone(u text, ph text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'phone_number', ph)::text, false) $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when coalesce(cond, false) then 'ok ' || label else 'FAIL ' || label end $$;

set role authenticated;
select pg_temp.as_phone('gold_g', '9000000611'); select (public.ensure_profile('Gouri Nanjappa', '9000000611')).id is not null;
select pg_temp.as_phone('gold_w', '9000000612'); select (public.ensure_profile('Wasim Khan', '9000000612')).id is not null;
select pg_temp.as_phone('gold_far', '9000000613'); select (public.ensure_profile('Pallavi Desai', '9000000613')).id is not null;
select pg_temp.as_phone('gold_me', '9000000614'); select (public.ensure_profile('Sita Searcher', '9000000614')).id is not null;

-- ---------- the catalogue ----------
create temp table gold_pages (place text, kind text, title text, category text, description text, lat double precision, lng double precision,
                              up int, ships boolean, items text) on commit preserve rows;
insert into gold_pages values
  ('G', 'BUSINESS', 'Hill View Bakery', 'Bakery', 'Breads, cakes and snacks baked every morning. Custom birthday cakes on request.', 12.188, 75.901, 3, false,
   'Blueberry Muffin=60|Butter Croissant=80|Chocolate Chip Cookies=120|Chocolate Truffle Cake=650|Donut Box=240|Plum Cake=300|Samosa=20|Whole Wheat Bread=45'),
  ('G', 'BUSINESS', 'Coorg Threads', 'Clothing', 'Everyday and festive wear for the family. Easy exchange within 7 days.', 12.169, 75.902, 2, false,
   'Canvas Sneakers=1200|Cotton Dupatta=450|Embroidered Kurta=1100|Embroidered Shirt=900|Kids T-shirt=350|Leather Belt=500|Silk Saree=4500'),
  ('G', 'SKILL', 'Electrician for homes and shops', 'Electrician', 'Electrician for homes and shops. Reliable, on time, fair rates. Message me to book.', 12.172, 75.912, 0, false, ''),
  ('G', 'BUSINESS', 'Gadget Hub Gonikoppal', 'Electronics', 'Phones, audio and accessories with a one-year warranty on every item.', 12.181, 75.925, 2, false,
   'Bluetooth Speaker=1500|Camera Battery LP-E17=1200|Phone Case=299|Smart Watch=2500|USB-C Cable=199|Webcam=1800|Wired Headphones=600|Wireless Earbuds=1999'),
  ('G', 'BUSINESS', 'Kodagu Fresh Basket', 'Grocery', 'Daily groceries, staples and Coorg coffee at fair prices. Home delivery within 5 km.', 12.184, 75.911, 0, false,
   'Basmati Rice=140|Black Pepper=180|Coorg Coffee Powder=260|Cow Ghee=320|Lentils (Dal)=110|Pure Honey=250|Turmeric Powder=60'),
  ('G', 'BUSINESS', 'Home Nest Decor', 'Home decor', 'Planters, lamps and handmade decor to make a house feel like home.', 12.185, 75.912, 3, false,
   'Brass Diya=350|Ceramic Planter=400|Cushion Cover Set=700|Door Mat=250|Scented Candles=300|Table Lamp=1200'),
  ('G', 'BUSINESS', 'Coorg Chicken & Fish', 'Meat and fish', 'Hygienically cut chicken, mutton and fresh fish. Cleaned and packed on order.', 12.168, 75.913, 3, false,
   'Chicken Breast=280|Chicken Curry Cut=240|Country Eggs=90|Eggs=72|Mutton Curry Cut=750|Prawns=600|Sardines=200'),
  ('G', 'BUSINESS', 'CarePlus Pharmacy', 'Pharmacy', 'Medicines, health products and baby care. Prescription items need a valid prescription.', 12.187, 75.929, 4, false,
   'BP Monitor=1800|Digital Thermometer=250|First Aid Kit=450|Hand Sanitiser=90|Multivitamin Tablets=320'),
  ('G', 'SKILL', 'Wedding and event photographer', 'Photographer', 'Wedding and event photographer. Reliable, on time, fair rates. Message me to book.', 12.181, 75.912, 0, false, ''),
  ('G', 'SKILL', 'Plumber, leaks and fittings', 'Plumber', 'Plumber, leaks and fittings. Reliable, on time, fair rates. Message me to book.', 12.177, 75.907, 0, false, ''),
  ('G', 'BUSINESS', 'Coorg Spice Kitchen', 'Restaurant', 'Home-style South Indian and Coorg meals, cooked fresh every day. Dine in or order a tiffin.', 12.177, 75.904, 4, false,
   'Chicken Biryani=220|Filter Coffee=35|Gulab Jamun=60|Idli Sambar=60|Masala Chai=25|Masala Dosa=80|Paneer Butter Masala=240|Veg Thali=150'),
  ('G', 'SKILL', 'Full-stack web developer', 'Software developer', 'Full-stack web developer. Reliable, on time, fair rates. Message me to book.', 12.177, 75.907, 0, false, ''),
  ('G', 'BUSINESS', 'Paper & Pen Stationers', 'Stationery', 'School and office stationery, gift items and art supplies.', 12.171, 75.906, 4, false,
   'Colour Pencil Box=150|Fountain Pen=350|Highlighter Set=120|Scientific Calculator=900|Sketchbook A4=200'),
  ('G', 'SKILL', 'Maths and Science tutor (classes 8 to 12)', 'Tutor', 'Maths and Science tutor (classes 8 to 12). Reliable, on time, fair rates. Message me to book.', 12.177, 75.916, 0, false, ''),
  ('G', 'BUSINESS', 'Valley Fresh Vegetables', 'Vegetables', 'Farm-fresh vegetables and fruit, picked this morning.', 12.169, 75.915, 3, false,
   'Banana=50|Carrot=40|Cauliflower=35|Mango=120|Onion=30|Spinach=20|Tomato=25'),
  ('G', 'SKILL', 'Yoga trainer, home sessions', 'Yoga instructor', 'Yoga trainer, home sessions. Reliable, on time, fair rates. Message me to book.', 12.186, 75.925, 0, false, ''),
  ('W', 'BUSINESS', 'Oven Fresh Bakery', 'Bakery', 'Breads, cakes and snacks baked every morning. Custom birthday cakes on request.', 13.014, 77.738, 2, false,
   'Blueberry Muffin=60|Butter Croissant=80|Chocolate Truffle Cake=650|Plum Cake=300|Samosa=20|Whole Wheat Bread=45'),
  ('W', 'SKILL', 'Carpenter, furniture repair', 'Carpenter', 'Carpenter, furniture repair. Reliable, on time, fair rates. Message me to book.', 13.008, 77.749, 0, false, ''),
  ('W', 'BUSINESS', 'Urban Threads Fashion', 'Clothing', 'Everyday and festive wear for the family. Easy exchange within 7 days.', 12.997, 77.755, 3, false,
   'Canvas Sneakers=1200|Embroidered Kurta=1100|Silk Saree=4500'),
  ('W', 'SKILL', 'Logo and social media designer', 'Designer', 'Logo and social media designer. Reliable, on time, fair rates. Message me to book.', 13.008, 77.744, 0, false, ''),
  ('W', 'SKILL', 'Electrician for homes and shops', 'Electrician', 'Electrician for homes and shops. Reliable, on time, fair rates. Message me to book.', 13.003, 77.740, 0, false, ''),
  ('W', 'BUSINESS', 'Gadget Hub Electronics', 'Electronics', 'Phones, audio and accessories with a one-year warranty on every item.', 12.993, 77.748, 1, false,
   'Bluetooth Speaker=1500|Phone Case=299|USB-C Cable=199|Wireless Earbuds=1999'),
  ('W', 'BUSINESS', 'Fresh Basket Supermart', 'Grocery', 'Daily groceries, staples and Coorg coffee at fair prices. Home delivery within 5 km.', 12.992, 77.733, 2, false,
   'Basmati Rice=140|Coorg Coffee Powder=260|Cow Ghee=320|Pure Honey=250'),
  ('W', 'BUSINESS', 'MedPlus Care', 'Pharmacy', 'Medicines, health products and baby care. Prescription items need a valid prescription.', 13.007, 77.741, 3, false,
   'BP Monitor=1800|Digital Thermometer=250|Hand Sanitiser=90'),
  ('W', 'BUSINESS', 'Spice Route Kitchen', 'Restaurant', 'Home-style South Indian and Coorg meals, cooked fresh every day. Dine in or order a tiffin.', 13.018, 77.730, 2, false,
   'Chicken Biryani=220|Filter Coffee=35|Masala Chai=25|Masala Dosa=80|Veg Thali=150'),
  ('W', 'SKILL', 'Full-stack web developer', 'Software developer', 'Full-stack web developer. Reliable, on time, fair rates. Message me to book.', 12.999, 77.740, 0, false, ''),
  ('W', 'SKILL', 'Maths and Science tutor (classes 8 to 12)', 'Tutor', 'Maths and Science tutor (classes 8 to 12). Reliable, on time, fair rates. Message me to book.', 12.999, 77.744, 0, false, ''),
  ('W', 'SKILL', 'Yoga trainer, home sessions', 'Yoga instructor', 'Yoga trainer, home sessions. Reliable, on time, fair rates. Message me to book.', 13.012, 77.740, 0, false, ''),
  ('F', 'BUSINESS', 'Aspire More', 'Home decor', 'Handcrafted vases, sculptures and décor accents, shipped across India.', 18.546, 73.818, 0, true,
   'Abstract Cat Figurine — Medium=2400|Ivory Luxe Cake Display Stand — Regular=4250|Milky White Ceramic Vase=1800|Crimson Scabiosa Pod Botanical Bouquet=1700|Graphite Luxe Tea-Light Holder=1150|Heritage Table Clock=5850|Snowberry & Bunny Tail Bouquet=500|Amber Glow Molten Glass Vase=1500'),
  ('F', 'BUSINESS', 'Pixel Forge Software', 'IT services', 'Software agency building Android, web and AI products for startups.', 18.591, 73.739, 0, true,
   'Code audit=90000|Dedicated developer=150000|MVP build (8 weeks)=400000');

do $$
declare p record; v text; lid uuid;
begin
  for p in select * from gold_pages loop
    perform set_config('request.jwt.claims', json_build_object('sub', case p.place when 'G' then 'gold_g' when 'W' then 'gold_w' else 'gold_far' end,
                                                               'phone_number', case p.place when 'G' then '9000000611' when 'W' then '9000000612' else '9000000613' end)::text, false);
    insert into listings (kind, owner_id, title, category, description, area, location, details)
    values (p.kind, me(), p.title, p.category, p.description, case p.place when 'G' then 'Gonikoppal' when 'W' then 'Whitefield' else 'Pashan, Pune' end,
            geo(p.lat, p.lng), case when p.ships then '{"ships_india": true}'::jsonb else '{}'::jsonb end)
    returning id into lid;
    foreach v in array string_to_array(p.items, '|') loop
      continue when v = '';
      insert into items (listing_id, name, price, unit, in_stock) values (lid, split_part(v, '=', 1), split_part(v, '=', 2)::int, '', true);
    end loop;
  end loop;
end $$;
reset role;
update listings l set status = 'LIVE', trust_up = g.up from gold_pages g
  where l.title = g.title and l.owner_id = (select id from profiles where auth_uid = case g.place when 'G' then 'gold_g' when 'W' then 'gold_w' else 'gold_far' end);
set role authenticated;
select pg_temp.as_phone('gold_me', '9000000614');

\echo '== helpers'
select pg_temp.check('trust: no votes 0.35, one up 0.46, four up 0.64, 10 up 8 down below 2 of 2',
  round(search_trust(0, 0)::numeric, 2) = 0.35 and round(search_trust(1, 0)::numeric, 2) = 0.46 and round(search_trust(4, 0)::numeric, 2) = 0.64
  and search_trust(10, 8) < search_trust(2, 0));
select pg_temp.check('keys: plurals fold to one key', search_key('plumbers') = 'plumber' and search_key('batteries') = 'battery' and search_key('boxes') = 'box'
  and search_key('tomatoes') = 'tomato' and search_key('shoes') = 'shoe' and search_key('glass') = 'glass' and search_key('movies') = search_key('movie'));
select pg_temp.check('norm: punctuation splits, whole words padded', search_norm('Full-stack web developer, USB-C (Cable)') = ' full stack web developer usb c cable ');
select pg_temp.check('norm: nukta and old-style chillu fold', search_norm('सब्ज़ी') = search_norm('सब्जी') and search_norm('പാ' || chr(3378) || chr(3405) || chr(8205)) = search_norm('പാൽ'));
select pg_temp.check('parse: filler and modifiers', (select jsonb_path_query_array(search_parse('i need a cheap plumber near me'), '$.terms[*].key') = '["plumber"]'
  and search_parse('i need a cheap plumber near me')->'mods' = '["cheap"]'));
select pg_temp.check('parse: a price cap', (search_parse('rice under 200')->>'price_cap')::int = 200 and search_parse('200 tak ka chawal')->>'price_cap' = '200');
select pg_temp.check('parse: the longest phrase wins', jsonb_path_query_array(search_parse('home delivery grocery'), '$.terms[*].key') = '["grocery"]'
  and jsonb_path_query_array(search_parse('ac repair'), '$.terms[*].key') = '["ac repair"]');
select pg_temp.check('the lexicon is not readable directly', not has_table_privilege('authenticated', 'public.search_lexicon', 'select'));

-- ---------- the cases ----------
create temp table golden (id serial, place text, q text, want text[], forbid text[] default '{}', lang text default 'en', gap boolean default false) on commit preserve rows;
insert into golden (place, q, want, forbid, lang) values
  -- categories and page names
  ('G', 'bakery', '{Hill View Bakery}', '{}', 'en'), ('G', 'grocery', '{Kodagu Fresh Basket}', '{}', 'en'), ('G', 'pharmacy', '{CarePlus Pharmacy}', '{}', 'en'),
  ('G', 'restaurant', '{Coorg Spice Kitchen}', '{}', 'en'), ('G', 'electrician', '{Electrician for homes and shops}', '{}', 'en'),
  ('G', 'plumber', '{"Plumber, leaks and fittings"}', '{}', 'en'), ('G', 'photographer', '{Wedding and event photographer}', '{}', 'en'),
  ('G', 'tutor', '{"Maths and Science tutor (classes 8 to 12)"}', '{}', 'en'), ('G', 'yoga', '{"Yoga trainer, home sessions"}', '{}', 'en'),
  ('G', 'electronics', '{Gadget Hub Gonikoppal}', '{}', 'en'), ('G', 'clothing', '{Coorg Threads}', '{}', 'en'), ('G', 'stationery', '{Paper & Pen Stationers}', '{}', 'en'),
  ('G', 'vegetables', '{Valley Fresh Vegetables}', '{}', 'en'), ('G', 'meat', '{Coorg Chicken & Fish}', '{}', 'en'), ('G', 'fish', '{Coorg Chicken & Fish}', '{}', 'en'),
  ('G', 'home decor', '{Home Nest Decor}', '{}', 'en'), ('G', 'software developer', '{Full-stack web developer}', '{}', 'en'),
  ('W', 'carpenter', '{"Carpenter, furniture repair"}', '{}', 'en'), ('W', 'designer', '{Logo and social media designer}', '{}', 'en'),
  ('W', 'bakery', '{Oven Fresh Bakery}', '{}', 'en'), ('W', 'pharmacy', '{MedPlus Care}', '{}', 'en'), ('W', 'grocery', '{Fresh Basket Supermart}', '{}', 'en'),
  ('G', 'hill view bakery', '{Hill View Bakery}', '{}', 'en'), ('W', 'medplus', '{MedPlus Care}', '{}', 'en'),
  ('G', 'coorg spice kitchen', '{Coorg Spice Kitchen}', '{Coorg Threads}', 'en'),
  -- products
  ('G', 'basmati rice', '{Kodagu Fresh Basket}', '{}', 'en'), ('G', 'coffee powder', '{Kodagu Fresh Basket}', '{Coorg Spice Kitchen}', 'en'),
  ('G', 'filter coffee', '{Coorg Spice Kitchen}', '{Kodagu Fresh Basket}', 'en'), ('G', 'chicken biryani', '{Coorg Spice Kitchen}', '{Coorg Chicken & Fish}', 'en'),
  ('G', 'masala dosa', '{Coorg Spice Kitchen}', '{}', 'en'), ('G', 'idli', '{Coorg Spice Kitchen}', '{}', 'en'), ('G', 'samosa', '{Hill View Bakery}', '{}', 'en'),
  ('G', 'plum cake', '{Hill View Bakery}', '{}', 'en'), ('G', 'croissant', '{Hill View Bakery}', '{}', 'en'), ('G', 'bread', '{Hill View Bakery}', '{}', 'en'),
  ('G', 'ghee', '{Kodagu Fresh Basket}', '{}', 'en'), ('G', 'honey', '{Kodagu Fresh Basket}', '{}', 'en'), ('G', 'turmeric', '{Kodagu Fresh Basket}', '{}', 'en'),
  ('G', 'black pepper', '{Kodagu Fresh Basket}', '{}', 'en'), ('G', 'dal', '{Kodagu Fresh Basket}', '{}', 'en'), ('G', 'eggs', '{Coorg Chicken & Fish}', '{}', 'en'),
  ('G', 'prawns', '{Coorg Chicken & Fish}', '{}', 'en'), ('G', 'mutton', '{Coorg Chicken & Fish}', '{}', 'en'), ('G', 'kurta', '{Coorg Threads}', '{}', 'en'),
  ('G', 'saree', '{Coorg Threads}', '{}', 'en'), ('G', 'sneakers', '{Coorg Threads}', '{}', 'en'), ('G', 'earbuds', '{Gadget Hub Gonikoppal}', '{}', 'en'),
  ('G', 'headphones', '{Gadget Hub Gonikoppal}', '{}', 'en'), ('G', 'bluetooth speaker', '{Gadget Hub Gonikoppal}', '{}', 'en'),
  ('G', 'smart watch', '{Gadget Hub Gonikoppal}', '{}', 'en'), ('G', 'thermometer', '{CarePlus Pharmacy}', '{}', 'en'), ('G', 'sanitiser', '{CarePlus Pharmacy}', '{}', 'en'),
  ('G', 'first aid kit', '{CarePlus Pharmacy}', '{}', 'en'), ('G', 'fountain pen', '{Paper & Pen Stationers}', '{}', 'en'),
  ('G', 'calculator', '{Paper & Pen Stationers}', '{}', 'en'), ('G', 'table lamp', '{Home Nest Decor}', '{Aspire More}', 'en'), ('G', 'candles', '{Home Nest Decor}', '{}', 'en'),
  ('G', 'banana', '{Valley Fresh Vegetables}', '{}', 'en'), ('G', 'mango', '{Valley Fresh Vegetables}', '{}', 'en'), ('G', 'tomato', '{Valley Fresh Vegetables}', '{}', 'en'),
  ('G', 'onion', '{Valley Fresh Vegetables}', '{}', 'en'), ('G', 'paneer', '{Coorg Spice Kitchen}', '{}', 'en'), ('G', 'usb c cable', '{Gadget Hub Gonikoppal}', '{}', 'en'),
  ('W', 'chicken biryani', '{Spice Route Kitchen}', '{}', 'en'), ('W', 'basmati rice', '{Fresh Basket Supermart}', '{}', 'en'),
  -- plurals, Indian English spellings, typos, a half-typed word
  ('G', 'plumbers', '{"Plumber, leaks and fittings"}', '{}', 'en'), ('G', 'electricians', '{Electrician for homes and shops}', '{}', 'en'),
  ('G', 'bakeries', '{Hill View Bakery}', '{}', 'en'), ('G', 'tomatoes', '{Valley Fresh Vegetables}', '{}', 'en'), ('G', 'mangoes', '{Valley Fresh Vegetables}', '{}', 'en'),
  ('G', 'cookies', '{Hill View Bakery}', '{}', 'en'), ('G', 'plumbr', '{"Plumber, leaks and fittings"}', '{Hill View Bakery}', 'en'),
  ('G', 'electrecian', '{Electrician for homes and shops}', '{}', 'en'), ('G', 'tution', '{"Maths and Science tutor (classes 8 to 12)"}', '{}', 'en'),
  ('G', 'biriyani', '{Coorg Spice Kitchen}', '{}', 'en'), ('G', 'briyani', '{Coorg Spice Kitchen}', '{}', 'en'), ('G', 'panner', '{Coorg Spice Kitchen}', '{}', 'en'),
  ('G', 'vegitables', '{Valley Fresh Vegetables}', '{}', 'en'), ('G', 'stationary', '{Paper & Pen Stationers}', '{}', 'en'), ('G', 'resturant', '{Coorg Spice Kitchen}', '{}', 'en'),
  ('G', 'medcine', '{CarePlus Pharmacy}', '{}', 'en'), ('G', 'basmathi rice', '{Kodagu Fresh Basket}', '{}', 'en'), ('G', 'idly', '{Coorg Spice Kitchen}', '{}', 'en'),
  ('G', 'chiken', '{Coorg Chicken & Fish}', '{}', 'en'), ('G', 'pharm', '{CarePlus Pharmacy}', '{}', 'en'),
  ('G', 'electr', '{Electrician for homes and shops,Gadget Hub Gonikoppal}', '{}', 'en'),
  -- Hinglish, Kanglish, Tanglish and the other languages in Latin letters
  ('G', 'kirana', '{Kodagu Fresh Basket}', '{}', 'hi-Latn'), ('G', 'sabzi', '{Valley Fresh Vegetables}', '{}', 'hi-Latn'), ('G', 'dawai', '{CarePlus Pharmacy}', '{}', 'hi-Latn'),
  ('G', 'doodh', '{Kodagu Fresh Basket}', '{}', 'hi-Latn'), ('G', 'anda', '{Coorg Chicken & Fish}', '{}', 'hi-Latn'), ('G', 'murgi', '{Coorg Chicken & Fish}', '{}', 'hi-Latn'),
  ('G', 'machli', '{Coorg Chicken & Fish}', '{}', 'hi-Latn'), ('G', 'chai', '{Coorg Spice Kitchen}', '{}', 'hi-Latn'), ('G', 'mithai', '{Hill View Bakery}', '{}', 'hi-Latn'),
  ('G', 'bijli wala', '{Electrician for homes and shops}', '{}', 'hi-Latn'), ('G', 'nal wala', '{"Plumber, leaks and fittings"}', '{}', 'hi-Latn'),
  ('G', 'pyaz', '{Valley Fresh Vegetables}', '{}', 'hi-Latn'), ('G', 'kela', '{Valley Fresh Vegetables}', '{}', 'hi-Latn'), ('G', 'aam', '{Valley Fresh Vegetables}', '{}', 'hi-Latn'),
  ('G', 'chawal', '{Kodagu Fresh Basket}', '{}', 'hi-Latn'), ('G', 'dudh', '{Kodagu Fresh Basket}', '{}', 'hi-Latn'),
  ('G', 'kaapi', '{Coorg Spice Kitchen,Kodagu Fresh Basket}', '{}', 'kn-Latn'), ('G', 'haalu', '{Kodagu Fresh Basket}', '{}', 'kn-Latn'),
  ('G', 'meenu', '{Coorg Chicken & Fish}', '{}', 'kn-Latn'), ('G', 'koli', '{Coorg Chicken & Fish}', '{}', 'kn-Latn'), ('G', 'motte', '{Coorg Chicken & Fish}', '{}', 'kn-Latn'),
  ('G', 'akki', '{Kodagu Fresh Basket}', '{}', 'kn-Latn'), ('G', 'tarakari', '{Valley Fresh Vegetables}', '{}', 'kn-Latn'),
  ('G', 'paal', '{Kodagu Fresh Basket}', '{}', 'ta-Latn'), ('G', 'meen', '{Coorg Chicken & Fish}', '{}', 'ta-Latn'), ('G', 'kozhi', '{Coorg Chicken & Fish}', '{}', 'ta-Latn'),
  ('G', 'muttai', '{Coorg Chicken & Fish}', '{}', 'ta-Latn'), ('G', 'paalu', '{Kodagu Fresh Basket}', '{}', 'te-Latn'), ('G', 'chepa', '{Coorg Chicken & Fish}', '{}', 'te-Latn'),
  ('G', 'kombdi', '{Coorg Chicken & Fish}', '{}', 'mr-Latn'),
  -- native scripts: Kannada, Hindi, Tamil, Telugu, Malayalam, Marathi
  ('G', 'ಹಾಲು', '{Kodagu Fresh Basket}', '{}', 'kn'), ('G', 'ಕಾಫಿ', '{Coorg Spice Kitchen,Kodagu Fresh Basket}', '{}', 'kn'), ('G', 'ಮೀನು', '{Coorg Chicken & Fish}', '{}', 'kn'),
  ('G', 'ತರಕಾರಿ', '{Valley Fresh Vegetables}', '{}', 'kn'), ('G', 'ಔಷಧಿ', '{CarePlus Pharmacy}', '{}', 'kn'), ('G', 'ಬೇಕರಿ', '{Hill View Bakery}', '{}', 'kn'),
  ('G', 'ಮೊಟ್ಟೆ', '{Coorg Chicken & Fish}', '{}', 'kn'), ('G', 'ಅಕ್ಕಿ', '{Kodagu Fresh Basket}', '{}', 'kn'), ('G', 'ಪ್ಲಂಬರ್', '{"Plumber, leaks and fittings"}', '{}', 'kn'),
  ('G', 'ಹಾಲು ಬೇಕು', '{Kodagu Fresh Basket}', '{}', 'kn'),
  ('G', 'दूध', '{Kodagu Fresh Basket}', '{}', 'hi'), ('G', 'दवाई', '{CarePlus Pharmacy}', '{}', 'hi'), ('G', 'सब्ज़ी', '{Valley Fresh Vegetables}', '{}', 'hi'),
  ('G', 'मछली', '{Coorg Chicken & Fish}', '{}', 'hi'), ('G', 'चाय', '{Coorg Spice Kitchen}', '{}', 'hi'), ('G', 'बेकरी', '{Hill View Bakery}', '{}', 'hi'),
  ('G', 'अंडे', '{Coorg Chicken & Fish}', '{}', 'hi'), ('G', 'प्लंबर', '{"Plumber, leaks and fittings"}', '{}', 'hi'), ('G', 'दूध चाहिए', '{Kodagu Fresh Basket}', '{}', 'hi'),
  ('G', 'பால்', '{Kodagu Fresh Basket}', '{}', 'ta'), ('G', 'காபி', '{Coorg Spice Kitchen,Kodagu Fresh Basket}', '{}', 'ta'), ('G', 'மீன்', '{Coorg Chicken & Fish}', '{}', 'ta'),
  ('G', 'காய்கறி', '{Valley Fresh Vegetables}', '{}', 'ta'), ('G', 'மருந்து', '{CarePlus Pharmacy}', '{}', 'ta'), ('G', 'முட்டை', '{Coorg Chicken & Fish}', '{}', 'ta'),
  ('G', 'పాలు', '{Kodagu Fresh Basket}', '{}', 'te'), ('G', 'కాఫీ', '{Coorg Spice Kitchen,Kodagu Fresh Basket}', '{}', 'te'), ('G', 'చేప', '{Coorg Chicken & Fish}', '{}', 'te'),
  ('G', 'కూరగాయలు', '{Valley Fresh Vegetables}', '{}', 'te'), ('G', 'మందులు', '{CarePlus Pharmacy}', '{}', 'te'), ('G', 'గుడ్లు', '{Coorg Chicken & Fish}', '{}', 'te'),
  ('G', 'പാൽ', '{Kodagu Fresh Basket}', '{}', 'ml'), ('G', 'കാപ്പി', '{Coorg Spice Kitchen,Kodagu Fresh Basket}', '{}', 'ml'), ('G', 'മീൻ', '{Coorg Chicken & Fish}', '{}', 'ml'),
  ('G', 'പച്ചക്കറി', '{Valley Fresh Vegetables}', '{}', 'ml'), ('G', 'മരുന്ന്', '{CarePlus Pharmacy}', '{}', 'ml'), ('G', 'മുട്ട', '{Coorg Chicken & Fish}', '{}', 'ml'),
  ('G', 'പാ' || chr(3378) || chr(3405) || chr(8205), '{Kodagu Fresh Basket}', '{}', 'ml'),
  ('G', 'चहा', '{Coorg Spice Kitchen}', '{}', 'mr'), ('G', 'भाजीपाला', '{Valley Fresh Vegetables}', '{}', 'mr'), ('G', 'मासे', '{Coorg Chicken & Fish}', '{}', 'mr'),
  ('G', 'औषध', '{CarePlus Pharmacy}', '{}', 'mr'), ('G', 'अंडी', '{Coorg Chicken & Fish}', '{}', 'mr'), ('G', 'किराणा', '{Kodagu Fresh Basket}', '{}', 'mr'),
  -- sentences and modifiers
  ('G', 'i need a plumber near me', '{"Plumber, leaks and fittings"}', '{}', 'en'), ('G', 'where can i buy milk', '{Kodagu Fresh Basket}', '{}', 'en'),
  ('G', 'doodh chahiye', '{Kodagu Fresh Basket}', '{}', 'hi-Latn'), ('G', 'haalu beku', '{Kodagu Fresh Basket}', '{}', 'kn-Latn'),
  ('G', 'cheap grocery', '{Kodagu Fresh Basket}', '{}', 'en'), ('G', 'best bakery', '{Hill View Bakery}', '{}', 'en'), ('G', 'open now pharmacy', '{CarePlus Pharmacy}', '{}', 'en'),
  ('G', 'home delivery grocery', '{Kodagu Fresh Basket}', '{}', 'en'), ('G', 'plumber please', '{"Plumber, leaks and fittings"}', '{}', 'en'),
  ('G', 'show me bakeries nearby', '{Hill View Bakery}', '{}', 'en'), ('G', 'rice under 200', '{Kodagu Fresh Basket}', '{}', 'en'),
  ('G', 'fresh fish', '{Coorg Chicken & Fish}', '{Kodagu Fresh Basket,Valley Fresh Vegetables}', 'en'),
  ('G', 'coorg coffee', '{Kodagu Fresh Basket,Coorg Spice Kitchen}', '{Coorg Threads}', 'en'), ('G', 'kirana ki dukaan', '{Kodagu Fresh Basket}', '{}', 'hi-Latn'),
  ('G', 'grocery shop', '{Kodagu Fresh Basket}', '{}', 'en'), ('G', 'maths tutor', '{"Maths and Science tutor (classes 8 to 12)"}', '{}', 'en'),
  ('G', 'tutor for class 10', '{"Maths and Science tutor (classes 8 to 12)"}', '{}', 'en'), ('W', 'electrician for my shop', '{Electrician for homes and shops}', '{}', 'en'),
  -- the junk traps of the audit, and words that live inside other words
  ('W', 'taxi', '{}', '{Gadget Hub Electronics,Aspire More}', 'en'), ('G', 'cab', '{}', '{Gadget Hub Gonikoppal}', 'en'),
  ('W', 'milk', '{Fresh Basket Supermart}', '{Aspire More}', 'en'), ('W', 'medicine', '{MedPlus Care}', '{Aspire More}', 'en'),
  ('W', 'cake', '{Oven Fresh Bakery}', '{}', 'en'), ('W', 'ac repair', '{}', '{"Carpenter, furniture repair"}', 'en'),
  ('W', 'home stay', '{}', '{"Yoga trainer, home sessions"}', 'en'), ('G', 'tailor', '{}', '{Aspire More}', 'en'),
  ('W', 'fresh fish', '{}', '{Fresh Basket Supermart,Oven Fresh Bakery,Spice Route Kitchen}', 'en'),
  ('G', 'pen', '{Paper & Pen Stationers}', '{Kodagu Fresh Basket}', 'en'), ('G', 'mat', '{Home Nest Decor}', '{Valley Fresh Vegetables}', 'en'),
  ('G', 'ice', '{}', '{Kodagu Fresh Basket}', 'en'), ('G', 'tea', '{Coorg Spice Kitchen}', '{}', 'en'), ('G', 'oil', '{Kodagu Fresh Basket}', '{}', 'en'),
  ('G', 'cable', '{Gadget Hub Gonikoppal}', '{}', 'en'), ('W', 'website', '{Full-stack web developer}', '{}', 'en'), ('W', 'tution', '{"Maths and Science tutor (classes 8 to 12)"}', '{}', 'en'),
  ('W', 'mobile', '{Gadget Hub Electronics}', '{}', 'en'), ('W', 'laptop', '{Gadget Hub Electronics}', '{}', 'en'), ('W', 'kaapi', '{Fresh Basket Supermart,Spice Route Kitchen}', '{}', 'kn-Latn'),
  ('W', 'cheap grocery', '{Fresh Basket Supermart}', '{}', 'en'), ('W', 'ಹಾಲು', '{Fresh Basket Supermart}', '{}', 'kn'), ('W', 'दूध', '{Fresh Basket Supermart}', '{}', 'hi'),
  -- nothing to find: nothing must come back
  ('G', 'barber', '{}', '{}', 'en'), ('G', 'petrol', '{}', '{}', 'en'), ('G', 'car wash', '{}', '{}', 'en'), ('G', 'hospital', '{}', '{}', 'en'),
  ('G', 'laundry', '{}', '{}', 'en'), ('G', 'gym', '{}', '{}', 'en'), ('G', 'jobs', '{}', '{}', 'en'), ('G', 'zzqxv', '{}', '{}', 'en'), ('W', 'plumber', '{}', '{}', 'en'),
  ('W', 'tailor', '{}', '{}', 'en'), ('G', 'xerox', '{}', '{}', 'en'), ('G', 'ac repair', '{}', '{}', 'en'), ('G', 'auto', '{}', '{}', 'en'), ('G', 'aloo', '{}', '{}', 'hi-Latn'),
  ('G', 'darzi', '{}', '{Coorg Threads}', 'hi-Latn');

create temp table golden_run on commit preserve rows as
select g.*, r.titles, coalesce(r.n, 0) n
from golden g cross join lateral (
  select array_agg(s.title order by s.ord) titles, count(*) n
  from public.search_listings(g.q, case g.place when 'G' then 12.1817 else 12.9698 end, case g.place when 'G' then 75.9147 else 77.7500 end, 10000, null, 10)
       with ordinality s(id, kind, title, category, description, photo_url, area, online, trust_up, trust_down, details, distance_m, matched_item, min_price,
                         type_key, group_key, owner_id, owner_name, matched_price, ord)) r;

\echo '== the golden cases'
select case
         when passed and gap then 'ok golden ' || place || ' "' || q || '" (now passes: take the gap mark off)'
         when passed then 'ok golden ' || place || ' "' || q || '"'
         when gap then 'gap golden ' || place || ' "' || q || '" got: ' || coalesce(array_to_string(titles[1:3], ' | '), 'nothing')
         else 'FAIL golden ' || place || ' "' || q || '" (' || lang || ') want ' || coalesce(nullif(array_to_string(want, ' | '), ''), 'nothing')
              || case when cardinality(forbid) > 0 then ', never ' || array_to_string(forbid, ' | ') else '' end
              || ', got: ' || coalesce(array_to_string(titles[1:5], ' | '), 'nothing') end
from (select *, ((cardinality(want) = 0 and n = 0) or coalesce(titles[1:3] && want, false)) and not coalesce(titles[1:10] && forbid, false) passed
      from golden_run) x
order by id;

\echo '== the scorecard'
with m as (
  select count(*) filter (where cardinality(want) > 0) answerable,
         count(*) filter (where cardinality(want) > 0 and coalesce(titles[1:3] && want, false)) top3,
         coalesce(avg(case when cardinality(want) > 0 then coalesce((select 1.0 / min(t.o) from unnest(g.titles) with ordinality t(title, o) where t.title = any(g.want)), 0) end), 0) mrr,
         count(*) filter (where coalesce(titles[1:10] && forbid, false)) junk,
         count(*) filter (where cardinality(want) > 0 and n = 0) answerable_zero,
         count(*) filter (where cardinality(want) = 0) zero_cases,
         count(*) filter (where cardinality(want) = 0 and n = 0) zero_ok,
         count(*) cases, count(distinct lang) langs
  from golden_run g),
base as (select 0.95 success3, 0.90 mrr, 0 junk, 0.02 answerable_zero)   -- the committed baseline: raise it when the numbers rise, never lower it
select pg_temp.check(format('scorecard: %s cases in %s languages; success@3 %s (baseline %s); MRR %s (baseline %s); junk@10 %s; answerable zero rate %s; true zeros %s of %s',
                            m.cases, m.langs, round(m.top3::numeric / m.answerable, 3), b.success3, round(m.mrr, 3), b.mrr, m.junk,
                            round(m.answerable_zero::numeric / m.answerable, 3), m.zero_ok, m.zero_cases),
                     m.top3::numeric / m.answerable >= b.success3 and m.mrr >= b.mrr and m.junk <= b.junk
                     and m.answerable_zero::numeric / m.answerable <= b.answerable_zero and m.zero_ok = m.zero_cases)
from m cross join base b;

\echo '== the old search still answers the old call shapes'
select pg_temp.check('browse: the far shops come after every local page', (
  select max(o) filter (where title in ('Hill View Bakery', 'Coorg Threads', 'CarePlus Pharmacy')) < min(o) filter (where title in ('Aspire More', 'Pixel Forge Software'))
  from search_listings('', 12.1817, 75.9147, 10000, null, 40) with ordinality s(id, kind, title, category, description, photo_url, area, online, trust_up, trust_down, details,
       distance_m, matched_item, min_price, type_key, group_key, owner_id, owner_name, matched_price, o)));
select pg_temp.check('kinds filter: skills only', (select bool_and(kind = 'SKILL') from search_listings('', 12.1817, 75.9147, 10000, array['SKILL'])));
select pg_temp.check('a product match carries its own price', (select matched_item = 'Filter Coffee' and matched_price = 35 from search_listings('filter coffee', 12.1817, 75.9147) where title = 'Coorg Spice Kitchen'));
select pg_temp.check('under 200: the matched product is within the cap', (select matched_price <= 200 from search_listings('rice under 200', 12.1817, 75.9147) where title = 'Kodagu Fresh Basket'));
