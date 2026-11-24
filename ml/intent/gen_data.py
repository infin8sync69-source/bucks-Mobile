"""Generate training and eval data for the on-device intent model (FunctionGemma 270M).

Writes dataset.jsonl in the format of Google's Mobile Actions dataset (google/mobile-actions): one JSON object per line with
"metadata" ("train" or "eval"), "lang", "tools" (tools.json) and "messages" (developer, user, assistant with tool_calls).
Phrasings and vocabulary live in phrases.py; templates starting with "!" are eval-only. review.csv lists every distinct
phrasing for native speakers.

Usage: python3 -I gen_data.py [--train-per-template N] [--seed S]
"""
import argparse
import csv
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find phrases.py even under python -I
from phrases import (COMPARE, CONTENT, CONTENT_ANY, FIXED, ITEMS, NAMES, PEOPLE, PLACE_TO, PLACES, POST, POSTS_BY, RIDE, RIDE_NO_PLACE,
                     RIDE_NO_VEHICLE, SEARCH, SORTS, TOPICS, VEHICLES)

HERE = Path(__file__).parent
DEVELOPER = "You are a model that can do function calling with the following functions"
LANGS = ["en", "hi", "hi-Latn", "kn", "kn-Latn", "ta", "te", "ml", "ml-Latn"]
FIXED_REPEAT = 6  # short fixed phrasings are repeated in training so ~thousands of ride/search examples don't swamp them


def split(template):
    return ("eval", template[1:]) if template.startswith("!") else ("train", template)


def example(lang, text, tool, args, split_name, tools):
    return {"metadata": split_name, "lang": lang, "tools": tools, "messages": [
        {"role": "developer", "content": DEVELOPER},
        {"role": "user", "content": text},
        {"role": "assistant", "tool_calls": [{"function": {"name": tool, "arguments": args}}]},
    ]}


def generate(per_template, rng, tools):
    out = []

    def fill(templates, lang, tool, make):
        for t in templates.get(lang, []):
            sp, t = split(t)
            for _ in range(per_template if sp == "train" else max(3, per_template // 4)):
                kw, args = make()
                out.append(example(lang, t.format(**kw), tool, args, sp, tools))

    for lang in LANGS:
        def place_kw(p):
            return {"p": rng.choice(PLACES[p][lang]), "pt": rng.choice(PLACE_TO[p].get(lang, PLACES[p][lang]))}

        def ride():
            v = rng.choice(list(VEHICLES)); p = rng.choice(list(PLACES))
            return {"v": rng.choice(VEHICLES[v][lang]), **place_kw(p)}, {"vehicle": v, "destination": p}

        def ride_nv():
            p = rng.choice(list(PLACES))
            return place_kw(p), {"vehicle": "AUTO", "destination": p}

        def ride_np():
            v = rng.choice(list(VEHICLES))
            return {"v": rng.choice(VEHICLES[v][lang])}, {"vehicle": v, "destination": ""}

        def item(key):
            def f():
                i = rng.choice(list(ITEMS))
                return {"i": rng.choice(ITEMS[i][lang])}, {key: i}
            return f

        fill(RIDE, lang, "request_ride", ride)
        fill(RIDE_NO_VEHICLE, lang, "request_ride", ride_nv)
        fill(RIDE_NO_PLACE, lang, "request_ride", ride_np)
        fill(SEARCH, lang, "search_marketplace", item("query"))
        fill(COMPARE, lang, "compare", item("query"))
        fill(POST, lang, "post_request", item("what"))
        for kind, forms in CONTENT.items():
            def topic(kind=kind):
                t = rng.choice(TOPICS[lang])
                return {"t": t}, {"kind": kind, "query": t}
            fill(forms, lang, "find_content", topic)
        for kind, forms in CONTENT_ANY.items():
            for t in forms.get(lang, []):
                sp, t = split(t)
                out.append(example(lang, t, "find_content", {"kind": kind, "query": ""}, sp, tools))

        def person(kind):
            def f():
                n = rng.choice(NAMES[lang])
                return {"n": n}, {"kind": kind, "query": n}
            return f
        fill(PEOPLE, lang, "find_content", person("PEOPLE"))
        fill(POSTS_BY, lang, "find_content", person("ALL"))
        for by, forms in SORTS.items():
            for t in forms[lang]:
                sp, t = split(t)
                out.append(example(lang, t, "sort_results", {"by": by}, sp, tools))
        for tool, forms in FIXED.items():
            for t in forms.get(lang, []):
                sp, t = split(t)
                out.append(example(lang, t, tool, {}, sp, tools))

    seen, uniq = set(), []
    for e in out:  # one copy of each (text, split)
        k = (e["messages"][1]["content"], e["metadata"])
        if k not in seen:
            seen.add(k); uniq.append(e)
    train_texts = {e["messages"][1]["content"] for e in uniq if e["metadata"] == "train"}
    uniq = [e for e in uniq if e["metadata"] == "train" or e["messages"][1]["content"] not in train_texts]  # no eval text in train
    fixed = set(FIXED) | {"sort_results"}
    # find_content phrasings without a topic are fixed too, so they get the same repeat as other short commands
    fixed_texts = {e["messages"][1]["content"] for e in uniq if e["messages"][2]["tool_calls"][0]["function"]["name"] == "find_content"
                   and e["messages"][2]["tool_calls"][0]["function"]["arguments"]["query"] == ""}
    uniq += [e for e in list(uniq) if e["metadata"] == "train" and (e["messages"][2]["tool_calls"][0]["function"]["name"] in fixed or e["messages"][1]["content"] in fixed_texts)] * (FIXED_REPEAT - 1)
    rng.shuffle(uniq)
    return uniq


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train-per-template", type=int, default=40)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--eval-set", default="eval_set_v3.jsonl",
                    help="frozen held-out set (run 2's); generated eval rows are replaced by it so scores stay comparable. '' = generate")
    a = ap.parse_args()
    tools = json.loads((HERE / "tools.json").read_text(encoding="utf-8"))
    data = generate(a.train_per_template, random.Random(a.seed), tools)
    if a.eval_set and (HERE / a.eval_set).exists():
        frozen = [json.loads(l) for l in (HERE / a.eval_set).open(encoding="utf-8")]
        frozen_texts = {e["text"] for e in frozen}
        data = [e for e in data if e["metadata"] == "train" and e["messages"][1]["content"] not in frozen_texts]
        data += [example(e["lang"], e["text"], e["call"]["name"], e["call"]["arguments"], "eval", tools) for e in frozen]
        random.Random(a.seed).shuffle(data)
    with (HERE / "dataset.jsonl").open("w", encoding="utf-8") as f:
        for e in data:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    with (HERE / "review.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f); w.writerow(["lang", "split", "text", "tool", "arguments", "reviewer_ok", "correction"])
        for e in sorted({(e["lang"], e["metadata"], e["messages"][1]["content"], e["messages"][2]["tool_calls"][0]["function"]["name"],
                          json.dumps(e["messages"][2]["tool_calls"][0]["function"]["arguments"], ensure_ascii=False)) for e in data}):
            w.writerow(list(e) + ["", ""])
    by = {}
    for e in data:
        by[(e["metadata"], e["lang"])] = by.get((e["metadata"], e["lang"]), 0) + 1
    for sp in ("train", "eval"):
        print(sp, sum(v for (s, _), v in by.items() if s == sp), {l: by.get((sp, l), 0) for l in LANGS})


if __name__ == "__main__":
    main()
