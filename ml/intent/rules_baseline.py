"""Score today's on-device rule engine (RuleIntentEngine in app/.../ai/Intent.kt, the only engine in Play builds) on the eval split.

A line-by-line Python port of RuleIntentEngine.parse; keep it in step with the Kotlin. Also defines the scorer the training
notebook uses, so the baseline and the model are measured the same way.
Usage: python3 -I rules_baseline.py [dataset.jsonl]
"""
import json
import re
import sys
from collections import Counter, defaultdict

PLACES = ["Koramangala, Bengaluru", "Nexus Mall, Koramangala", "Jayanagar 4th block", "MG Road", "Indiranagar 100 ft Rd",
          "Whitefield, ITPL", "Majestic bus stand", "Kempegowda airport"]  # Seed.PLACES


def place_in(l):
    for p in PLACES:
        if p.split(",")[0].lower().split(" ")[0] in l:
            return p
    return None


def rules(text):
    l = text.lower().strip()
    if not l:
        return None
    if re.search(r"^(yes|confirm|ok|okay|book it|go ahead|haan|sari|yes, ring them)\b", l): return ("confirm_pending", {})
    if re.search(r"^(no|cancel|stop|nahi|beda|never mind)\b", l): return ("cancel_pending", {})
    if "show the map" in l: return ("show_map", {})
    kind = ("BIKE" if re.search(r"\b(bike|scooter|scooty|two wheeler)\b", l) else "AUTO" if re.search(r"\b(auto|rickshaw)\b", l)
            else "CAB" if re.search(r"\b(cab|taxi|car)\b", l) else None)
    if kind or re.search(r"\b(ride|drop me|take me|pick me)\b", l):
        return ("request_ride", {"vehicle": kind or "AUTO", "destination": place_in(l) or ""})
    if re.search(r"\b(compare|cheapest|best|which is better)\b", l):
        return ("compare", {"query": re.sub(r"\b(compare|cheapest|best|which is better|for|the|near me|me)\b", "", l).strip()})
    if l.startswith("sort"):
        return ("sort_results", {"by": "PRICE" if re.search("price|cheap", l) else "NEAR" if re.search("near|close|distance", l) else "TRUST"})
    if re.search(r"\b(my orders|my rides|my requests|history|activity)\b", l): return ("show_activity", {})
    if l.startswith("post a request"): return ("post_request", {"what": re.sub(r"(?i)post a request for", "", text).strip()})
    if re.search(r"\b(go online|start duty|i'm online)\b", l): return ("go_online", {})
    if re.search(r"\b(become|provider|pro profile|add (my )?(vehicle|skill|business)|earn)\b", l): return ("become_provider", {})
    q = re.sub(r"\b(order|find|get|book|need|want|i|a|an|some|near|nearby|please|me|the|for)\b", "", l).strip()
    return ("search_marketplace", {"query": q}) if len(q) >= 3 else None


def norm_args(tool, args):
    """What has to match: place by its first word (the app looks places up that way), queries case-insensitively."""
    out = {}
    for k, v in (args or {}).items():
        v = str(v).strip().lower()
        if k == "destination":
            v = v.split(",")[0].split(" ")[0]
        out[k] = re.sub(r"^(a|an|the) ", "", v)
    return out


def score(target_tool, target_args, out_tool, out_args):
    return out_tool == target_tool, out_tool == target_tool and norm_args(target_tool, target_args) == norm_args(out_tool, out_args)


def main(path="dataset.jsonl"):
    tool_ok, full_ok, n = Counter(), Counter(), Counter()
    misses = defaultdict(list)
    for line in open(path, encoding="utf-8"):
        e = json.loads(line)
        if e["metadata"] != "eval":
            continue
        text = e["messages"][1]["content"]
        call = e["messages"][2]["tool_calls"][0]["function"]
        got = rules(text) or ("help", {})  # IntentRouter falls back to help
        t, f = score(call["name"], call["arguments"], *got)
        lang = e["lang"]
        n[lang] += 1; tool_ok[lang] += t; full_ok[lang] += f
        if not f and len(misses[lang]) < 3:
            misses[lang].append(f"{text!r} -> {got} (want {call['name']} {call['arguments']})")
    total = sum(n.values())
    print(f"Rule engine on {total} eval commands: right action {sum(tool_ok.values())/total:.0%}, right action and details {sum(full_ok.values())/total:.0%}")
    for lang in n:
        print(f"  {lang:8} n={n[lang]:3}  action {tool_ok[lang]/n[lang]:.0%}  full {full_ok[lang]/n[lang]:.0%}")
    for lang, m in misses.items():
        for s in m:
            print(f"  miss [{lang}] {s}")


if __name__ == "__main__":
    main(*sys.argv[1:])
