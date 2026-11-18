import csv, re, sys, statistics, collections
src, out = sys.argv[1], sys.argv[2]
rows=[]; bad=0
for r in csv.DictReader(open(src, encoding='utf-8', errors='replace')):
    name=re.sub(r'\s+(B\.?O|S\.?O|H\.?O|G\.?P\.?O|BO|SO|HO|GPO|N\.?S\.?H|M\.?D\.?G|E\.?D\.?O)\.?$', '', r['OfficeName'].strip(), flags=re.I).strip()
    pin=r['Pincode'].strip()
    if not re.fullmatch(r'[1-9][0-9]{5}', pin) or not name: continue
    try: lat=float(r['Latitude']); lng=float(r['Longitude'])
    except: lat=lng=None
    if lat is not None and not (6<=lat<=38 and 68<=lng<=98): lat=lng=None
    if lat is None: bad+=1
    rows.append([name.title(), r['District'].strip().title(), r['StateName'].strip().title(), pin, lat, lng])
# Offices without a usable point take the median of their pincode's others; an office far (>40 km) from its pincode's median is treated as wrong.
by=collections.defaultdict(list)
for x in rows:
    if x[4] is not None: by[x[3]].append((x[4],x[5]))
med={p:(statistics.median(a for a,_ in v), statistics.median(b for _,b in v)) for p,v in by.items()}
fixed=dropped=moved=0; seen=set(); w=csv.writer(open(out,'w',newline=''))
for x in rows:
    m=med.get(x[3])
    if x[4] is None:
        if not m: dropped+=1; continue
        x[4],x[5]=m; fixed+=1
    elif m and (abs(x[4]-m[0])+abs(x[5]-m[1]))>0.4: x[4],x[5]=m; moved+=1
    k=(x[0].lower(),x[3])
    if k in seen: continue
    seen.add(k); w.writerow([x[0],x[1],x[2],x[3],round(x[4],5),round(x[5],5)])
print(f"rows={len(rows)} no_point={bad} filled={fixed} moved={moved} dropped={dropped} kept={len(seen)} pincodes={len(med)}")
