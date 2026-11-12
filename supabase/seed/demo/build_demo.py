"""Generates 10_data.sql: the staging tables (schema demo_seed) that 20_apply.sql turns into demo people, shops, products, gigs, jobs and posts.
Run: python3 build_demo.py. Photos come from chosen.json (Wikimedia Commons; see ../../../docs/DEMO_WORLD.md for credits)."""
import json
from catalog import SHOPS
CH = json.load(open("chosen.json"))
def q(v): return "null" if v is None else "'" + str(v).replace("'", "''") + "'"
CL = {"kodagu": ("Gonikoppal, Kodagu", 12.183, 75.915), "blr": ("Whitefield, Bengaluru", 13.003, 77.745), "kk": ("Kallukoottam, Kanyakumari", 8.248, 77.349)}
PEOPLE = {
 "kodagu": [("Ayyappa Ponnappa","Runs a few shops in Gonikoppal."),("Lakshmi Devaiah","Baker, decor lover, chai on tap."),("Ravi Machaiah","Fresh meat and gadgets, in that order."),("Priya Nanjappa","Pharmacist and boutique owner."),("Karthik Subbaiah","Developer and wedding photographer from Kodagu."),("Sneha Biddappa","Maths tutor and yoga teacher.")],
 "blr":    [("Arjun Mehta","Foodie and restaurant owner in Whitefield."),("Divya Rao","Baker. Cake orders open every day."),("Imran Sheikh","Gadgets and repairs."),("Neha Kapoor","Boutique and pharmacy in ITPL."),("Rohit Nair","Full-stack developer, weekend cyclist."),("Ananya Iyer","Designer and yoga trainer.")],
 "kk":     [("Selvam Raj","Provision store and fresh fish."),("Meena Kumari","Home bakery and meals."),("Joseph Antony","Medical shop and vegetables."),("Fathima Beevi","Cook, tailor and tuition teacher."),("Arun Pandian","Electrician and plumber."),("Deepa Mohan","Photographer and graphic designer.")]}
SHOPSET = {"kodagu": ["kitchen","bakery","grocery","veggies","meat","fashion","gadgets","stationers","pharmacy","decor"], "blr": ["kitchen","bakery","grocery","fashion","gadgets","pharmacy","decor"], "kk": ["kitchen","bakery","grocery","veggies","meat","pharmacy"]}
OWNER = {"kodagu": {"kitchen":0,"grocery":0,"veggies":0,"bakery":1,"decor":1,"stationers":1,"meat":2,"gadgets":2,"pharmacy":3,"fashion":3},
         "blr": {"kitchen":0,"grocery":0,"bakery":1,"decor":1,"gadgets":2,"fashion":3,"pharmacy":3}, "kk": {"grocery":0,"meat":0,"bakery":1,"kitchen":1,"pharmacy":2,"veggies":2}}
NAMES = {"kodagu": {"kitchen":"Coorg Spice Kitchen","bakery":"Hill View Bakery","grocery":"Kodagu Fresh Basket","veggies":"Valley Fresh Vegetables","meat":"Coorg Chicken & Fish","fashion":"Coorg Threads","gadgets":"Gadget Hub Gonikoppal","stationers":"Paper & Pen Stationers","pharmacy":"CarePlus Pharmacy","decor":"Home Nest Decor"},
         "blr": {"kitchen":"Spice Route Kitchen","bakery":"Oven Fresh Bakery","grocery":"Fresh Basket Supermart","fashion":"Urban Threads Fashion","gadgets":"Gadget Hub Electronics","pharmacy":"MedPlus Care","decor":"Home Nest Decor"},
         "kk": {"kitchen":"Nanjil Meals Kitchen","bakery":"Seaside Bakes","grocery":"Nanjil Provision Store","veggies":"Thovalai Veg Mart","meat":"Kanyakumari Fish & Chicken","pharmacy":"Lakshmi Medicals"}}
SKILLS = [("Full-stack web developer","Software developer","₹900/hour","Mon to Sat, 10am to 8pm","Expert",["English","Hindi"]),("Maths and Science tutor (classes 8 to 12)","Tutor","₹500/hour","Evenings 4pm to 9pm","Expert",["English","Kannada"]),
          ("Electrician for homes and shops","Electrician","₹400/visit","Daily 8am to 7pm","Experienced",["Tamil","English"]),("Plumber, leaks and fittings","Plumber","₹350/visit","Daily 8am to 7pm","Experienced",["Tamil","Malayalam"]),
          ("Wedding and event photographer","Photographer","₹3,000/hour","Weekends and festivals","Expert",["English","Hindi"]),("Yoga trainer, home sessions","Yoga instructor","₹600/session","Mornings 5:30am to 9am","Expert",["English","Hindi"]),
          ("Logo and social media designer","Designer","₹700/hour","Mon to Fri, 11am to 7pm","Experienced",["English","Hindi"]),("Carpenter, furniture repair","Carpenter","₹800/day","Mon to Sat, 9am to 6pm","Experienced",["Tamil","English"])]
SKILL_PICK = {"kodagu": [(4,0),(5,1),(2,2),(0,3),(4,4),(5,5)], "blr": [(4,0),(5,5),(2,2),(1,6),(5,1),(0,7)], "kk": [(4,2),(4,3),(5,4),(3,1),(5,6),(3,7)]}
JOBS = [("Delivery partner","Deliver orders on your own bike in the area. Fuel allowance and weekly payout.","₹15,000 to ₹20,000 per month","FULL_TIME"),("Sales associate","Help customers, keep shelves tidy and handle billing.","₹14,000 to ₹18,000 per month","FULL_TIME"),
        ("Weekend helper","Saturday and Sunday shifts, 10am to 6pm.","₹600 per day","PART_TIME"),("Festival season packing","Two weeks of packing and wrapping for the festival rush.","₹700 per day","GIG")]
POSTS = [("Fresh batch just out of the oven. Come early, the first tray goes quickly!","PUBLIC",3),("Best filter coffee in {area}? I am asking for a friend.","PUBLIC",5),("Rain since morning, perfect weather for pakoras and chai.","LOCAL",8),("Anyone know a good plumber near {area}? Water pressure has dropped.","LOCAL",12),
         ("Weekend plan: long walk, big breakfast, no phone. Who is in?","SYNCED",20),("New stock arrived today. Do check it out and tell us what you think.","PUBLIC",26),("Small town, big hearts. Thank you for supporting local shops this season.","PUBLIC",30),
         ("Looking for a tutor for class 10 maths. Recommendations please.","LOCAL",40),("Photographers and designers: what do you use for quick edits on the phone?","PUBLIC",52),("Sunset from the terrace today. {area} is beautiful in this light.","PUBLIC",70)]
COMMENTS = ["Totally agree!","Count me in.","Thanks for sharing, will visit this week.","Great suggestion.","Same here, very good.","Looks wonderful.","Do you deliver nearby?","Recommended. Been there twice."]
import uuid
def uid(*p): return str(uuid.uuid5(uuid.NAMESPACE_URL, "bucks-demo/" + "/".join(p)))
out = ["-- Generated by build_demo.py. Staging data for the closed-test demo world (schema demo_seed). Dropped again by 20_apply.sql.",
       "drop schema if exists demo_seed cascade; create schema demo_seed;",
       "create table demo_seed.clusters(key text, label text, lat float8, lng float8);",
       "create table demo_seed.people(slug text, cluster text, name text, bio text);",
       "create table demo_seed.shops(id uuid, cluster text, shop_key text, title text, owner_slug text, dlat float8, dlng float8);",
       "create table demo_seed.shop_tpl(shop_key text, service text, category text, about text, hours text, radius_km int, free_delivery boolean);",
       "create table demo_seed.items(shop_key text, ord int, name text, price numeric, mrp numeric, unit text, grp text, photo text, credit text);",
       "create table demo_seed.skills(id uuid, cluster text, owner_slug text, title text, category text, rate text, hours text, level text, langs text);",
       "create table demo_seed.jobs(cluster text, shop_key text, title text, descr text, pay text, job_type text);",
       "create table demo_seed.posts(id uuid, cluster text, author_slug text, shop_key text, body text, vis text, hours_ago int);",
       "create table demo_seed.comments(post_id uuid, author_slug text, body text);"]
for k, (label, la, ln) in CL.items(): out.append(f"insert into demo_seed.clusters values ({q(k)},{q(label)},{la},{ln});")
for c, ps in PEOPLE.items():
    for i, (n, b) in enumerate(ps): out.append(f"insert into demo_seed.people values ({q(c+str(i))},{q(c)},{q(n)},{q(b + ' (demo profile)')});")
import random; R = random.Random(7)
for c, keys in SHOPSET.items():
    for k in keys:
        out.append(f"insert into demo_seed.shops values ({q(uid(c,k))},{q(c)},{q(k)},{q(NAMES[c][k])},{q(c+str(OWNER[c][k]))},{round(R.uniform(-0.016,0.016),5)},{round(R.uniform(-0.016,0.016),5)});")
for s in SHOPS:
    out.append(f"insert into demo_seed.shop_tpl values ({q(s['key'])},{q(s['service'])},{q(s['category'])},{q(s['about'])},{q(s['hours'])},{8 if s['key']!='kitchen' else 6},{'true' if s['key'] in ('grocery','veggies') else 'false'});")
    for o, it in enumerate(s["items"]):
        p = CH.get(s["key"] + "|" + it[0]); au = (p['author'] if p and len(p['author']) <= 28 and p['author'].isascii() else 'Wikimedia contributor') if p else ''; cr = f"{au}, {p['lic']}" if p else None
        out.append(f"insert into demo_seed.items values ({q(s['key'])},{o},{q(it[0])},{it[1]},{it[2] if it[2] else 'null'},{q(it[3])},{q(it[4])},{q(p['url'].replace('https://thumb.wikimedia.org/wikipedia/commons/thumb/', '') if p else None)},{q(cr)});")
for c, picks in SKILL_PICK.items():
    for owner, sk in picks:
        t = SKILLS[sk]; out.append(f"insert into demo_seed.skills values ({q(uid(c,'skill',str(sk)))},{q(c)},{q(c+str(owner))},{q(t[0])},{q(t[1])},{q(t[2])},{q(t[3])},{q(t[4])},{q(', '.join(t[5]))});")
for c, keys in SHOPSET.items():
    for j, k in enumerate(keys[:4]):
        t = JOBS[j % 4]; out.append(f"insert into demo_seed.jobs values ({q(c)},{q(k)},{q(t[0])},{q(t[1])},{q(t[2])},{q(t[3])});")
    pid = []
for c, keys in SHOPSET.items():
    for n, (body, vis, h) in enumerate(POSTS):
        a = n % 6; shop = None
        if n in (0, 5): # page posts: by the owner as the shop
            shop = keys[n % len(keys)]; a = OWNER[c][shop]
        pidn = uid(c, "post", str(n)); out.append(f"insert into demo_seed.posts values ({q(pidn)},{q(c)},{q(c+str(a))},{q(shop)},{q(body)},{q(vis)},{h});")
        for m in range(2): out.append(f"insert into demo_seed.comments values ({q(pidn)},{q(c+str((a+m+1)%6))},{q(COMMENTS[(n+m*3)%len(COMMENTS)])});")
open("10_data.sql", "w").write("\n".join(out) + "\n"); print(len(out), "statements,", len("\n".join(out)) // 1024, "KB")
