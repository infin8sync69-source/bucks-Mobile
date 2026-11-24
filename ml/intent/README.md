# On-device intent model

A fine-tuned **FunctionGemma 270M** that turns a typed or spoken command into one of the assistant's 13 actions on the phone,
offline and free. It is Tier 1 of the Android `IntentRouter` (rules → this model → classic search) and replaced `GeminiIntentEngine`,
whose key could not ship (launch blocker #12). Status: run 4 is wired into the Android app (`ai/FunctionGemmaIntentEngine.kt`), off
until the file is hosted and the `intent_tier1_enabled` setting is 1 (see "Shipping" at the end). iOS stays on the rules.

| File | What it is |
|---|---|
| `tools.json` | The 13 actions the model was trained on; the app passes a byte copy (`app/src/main/assets/intent_tools.json`) |
| `gen_data.py` | Writes `dataset.jsonl` (train and held-out eval) and `review.csv`, in English, Hindi, Hinglish, Kannada (both scripts), Tamil, Telugu |
| `review.csv` | Every phrasing, for native speakers to mark `reviewer_ok` / `correction` before a real run |
| `rules_baseline.py` | A Python port of today's `RuleIntentEngine` and the shared scorer |
| `train_intent.ipynb` | Fine-tune, evaluate and export to `.litertlm` (adapted from Google's Apache-2.0 Mobile Actions notebook) |

## Today's baseline

`python3 -I gen_data.py && python3 -I rules_baseline.py` on the 278 held-out commands (2026-11-16):

| | Right action | Right action and details |
|---|---|---|
| All | 53% | 24% |
| English | 71% | 47% |
| Hinglish | 42% | 24% |
| Kannada / Tamil / Telugu / Hindi script | 27–47% | 0% |

The trained model is worth shipping only if it clearly beats this, in every language, at a size and speed that suit
mid-range phones.

## First training run (2026-11-16)

Brev, 1× L4, 6 epochs on the 1,868 training commands (30 min of training). Same 278 held-out commands as the baseline:

| | Right action | Right action and details |
|---|---|---|
| Rules today | 53% | 24% |
| **Fine-tuned FunctionGemma** | **85%** | **78%** |
| by language (full) | en 88% · hi 100% · hi-Latn 55% · kn 62% · kn-Latn 73% · ta 89% · te 93% | |

- Checkpoint: `out/bucks-intent-checkpoint.zip` (430 MB, git-ignored; also in `~/Downloads`). It has no `tokenizer.model`;
  take that file from `google/functiongemma-270m-it` (same tokenizer) when converting.
- Not yet converted to `.litertlm`: the `ai-edge-torch` nightly failed against torch 2.15 on the instance. Conversion needs
  no GPU; do it in a separate venv with the torch version `ai-edge-torch` pins.
- Validation loss was lowest around epoch 1.4 (step 160) and crept up after: train 2–3 epochs or keep the best checkpoint.
- Almost every miss is a phrasing pattern the model never saw ("X jaana hai", "sabse accha X kaunsa hai", "best X near me",
  "X ಹೋಲಿಸಿ"): it memorised templates. More varied phrasings is the main lever, not more epochs.

## Second training run (2026-11-20, Kaggle)

Data round 3: 13 tools (new `find_content{kind: ALL|VIDEO|IMAGE|FILE|PEOPLE, query}` for posts, videos, photos, files and
people, backed by `explore()` / `search_people`), 9 language forms (Malayalam `ml` and Manglish `ml-Latn` added), 7,108
training and 1,156 held-out commands (578 validation, 578 test). Trained on a free Kaggle T4 (`train_kaggle.ipynb`, built by
`make_kaggle_train.py`): fp32, batch 1 × grad-accum 16, 2 epochs, best checkpoint at step 300 (eval loss 0.107). Converted on
Kaggle CPU (`convert_kaggle.ipynb`). Free Colab failed here because the laptop's phone hotspot kept dropping.

| Test set (578 commands, harder than run 1's) | Right action | Right action and details |
|---|---|---|
| Rules today | 26% | 8% |
| **Fine-tuned FunctionGemma, run 2** | **78%** | **72%** |
| by language (full) | en 93 · hi 84 · ml 80 · kn 77 · ml-Latn 66 · te 64 · hi-Latn 63 · ta 63 · kn-Latn 52 | |
| by action (full) | show_activity 100 · ride 87 · find_content 81 · confirm 80 · map 80 · search 77 · go_online 71 · compare 64 · sort 36 · help 29 · post_request 19 | |

- Phone model: `out/bucks-intent-run2_q8_ekv1024.litertlm` (285 MB, dynamic int8, 1,024-token context; sha256 9399e920b58c589f…);
  per-command results in `out/eval_run2.json`. Both git-ignored. Not yet run on a phone.
- Main confusions: compare → search (22), post_request → search/help (31). Best checkpoint came at 0.7 epochs again: more varied
  phrasings, not more epochs, is the lever.
- The model sometimes invents a destination (a Telugu Hebbal ride came back "Hamarang"; "jaldi cab chahiye" got "Jayanagar").
  The app must accept a place only if it matches its own place list (fuzzy), and otherwise ask; the confirm sheet stays.
- Conversion pins that matter: torch < 2.15, litert-torch 0.10.0, jax/jaxlib 0.12.0.1, litert-lm-builder 0.18.1, and
  `full_dynamic_recipe(...).generative_recipe` for quantization.

## Fourth training run (2026-11-20, Kaggle) — the model to ship

Round 5 data: 43 more search phrasings in every language pairing the "show"/"is there" verbs with shop items (run 3 read
"X दिखाओ" / "X காட்டு" as a posts or people search, because training only used those verbs for photos, profiles, map and sort).
10,466 training commands, 1 epoch, best checkpoint step 500 (validation loss 0.073, run 3 0.082). From this run the test set
is fixed by a text hash: 555 commands from the frozen pool.

| | Right action | Right action and details |
|---|---|---|
| Rules today | 26% | 8% |
| Run 3 | 84% | 79% |
| **Run 4** | **86%** | **82%** |
| by language (full) | hi 94 · ml-Latn 89 · en 89 · kn 87 · ml 84 · te 84 · ta 82 · kn-Latn 67 · hi-Latn 65 | |

- Search 60% → 96% (77/80). On commands both runs saw: run 3 77% → run 4 83% (26 fixed, 10 newly wrong); vs run 2 74% → 83%.
- No invented destinations (0). Remaining weak spots: compare 70% (Hinglish "sabse badhiya X", "kaunsa X accha hai" read as
  search), post_request 74% ("padosiyon se X pucho" style), and the Latin-script Hindi and Kannada sets (65–67%).
- Phone model: `out/bucks-intent-run4_q8_ekv1024.litertlm` (285 MB, sha256 430cf43106da07c0…); results `out/eval_run4.json`.
  Use this one for the app.

## Third training run (2026-11-20, Kaggle)

Round 4 data (9,514 training commands, same frozen held-out pool as run 2), 1 epoch, best checkpoint step 400
(validation loss 0.082 vs run 2's 0.107). Converted in the same run.

| | Right action | Right action and details |
|---|---|---|
| Rules today | 26% | 8% |
| Run 2 | 78% | 72% |
| **Run 3** | **84%** | **79%** |
| by language (full) | en 91 · ml-Latn 85 · hi 83 · te 79 · kn 78 · ta 77 · ml 76 · hi-Latn 70 · kn-Latn 70 | |

- Each run is scored on a random half (578) of the same 1,156 frozen commands; on the 308 commands both runs were tested on,
  run 2 got 73% and run 3 80% (48 fixed, 29 newly wrong). The notebooks now split by a hash of the text, so from run 4 every
  run is tested on exactly the same 555 commands.
- Invented destinations are gone: on rides with no place, run 2 made one up 8 times in 25, run 3 0 times in 20.
- post_request 19% → 92%, compare 64% → 80%, go_online and become_provider up. New weak spot: search_marketplace 77% → 60%
  (plain "show X" / "is there X nearby" now sometimes read as compare, post or a person lookup). Confirm/map/activity have
  under 10 test commands each, so their swings are noise.
- Phone model: `out/bucks-intent-run3_q8_ekv1024.litertlm` (285 MB, sha256 bb50a0b8ac6da56d…); results `out/eval_run3.json`.
  Superseded by run 4.

## Data round 4 (2026-11-20, for run 3)

230 new training phrasings aimed at run 2's misses: post_request (289 → 1,017 training commands), compare (665 → 1,498), sort,
small talk, confirm/cancel, become_provider, go_online, people lookups, urgent rides with no place (to stop invented
destinations), and Kannada in Latin letters. Training: 9,514 commands. The held-out set is frozen: `eval_set_v3.jsonl` is run 2's
exact 1,156 commands and `gen_data.py` reuses it (no overlap with training), so run 3's score compares directly with run 2's 72%.
Notebook: `train_kaggle_run3.ipynb` (1 epoch, about 2 hours on a Kaggle T4).

## How to train (≈ 1 hour of GPU, about $1–3)

1. Hugging Face: open `google/functiongemma-270m-it`, accept the Gemma licence, create a read token.
2. Native speakers check `review.csv`; fold corrections back into `gen_data.py` and rerun it.
3. Brev (brev.nvidia.com): create an instance with **1× L4 (24 GB)** and Jupyter (from $0.85/hour).
4. Upload `train_intent.ipynb` and `dataset.jsonl`, run all cells, paste the token when asked.
5. Download `litertlm/bucks-intent_q8_ekv1024.litertlm` and `eval_finetuned.json`. **Stop the instance.**

## In the app (Android)

- `app/src/main/java/com/bucks/app/ai/FunctionGemmaIntentEngine.kt`: LiteRT-LM `com.google.ai.edge.litertlm:litertlm-android:0.19.1`,
  CPU backend, started lazily off the main thread on the first command and closed after 2 idle minutes. The prompt is the training
  one: the developer line, the 13 declarations from `app/src/main/assets/intent_tools.json` (a byte copy of `tools.json`;
  `scripts/hygiene.sh` fails if they differ), the user's words. `automaticToolCalling = false`, greedy (top-k 1, temperature 0), 64
  output tokens. The developer line and declarations (~750 tokens) are prefilled once (`prefillPrefaceOnInit`) and each command runs
  on a `clone()` of that conversation. The generic model type returns the call as text, which `parseCall` reads.
- `ai/Intent.kt` `IntentRouter`: rules accepted at ≥ 0.9; otherwise the model, accepted only if the call parses, names one of the 13
  tools with its required arguments (enum values checked), isn't `help`, and the rules didn't say something else at ≥ 0.6 (the
  rules' leftover-words search is 0.5, so it never vetoes); otherwise classic search. `KnownPlaces` accepts a ride destination only
  if it matches a known place (exact, prefix or one or two typos); anything else gets "where to?". A "yes" from the model never
  confirms: the person still taps Confirm (and biometrics where needed).
- `find_content` opens Explore with the filter and words filled in, or Discover for `PEOPLE`.
- `AgentGate`: English command words, any non-Latin script, or 3+ words go to the assistant; short searches ("rice") stay plain.
- `ai/IntentModel.kt`: delivery (below). Never in the APK.

### On the phone runtime

`litert-lm-api==0.19.1` (the same runtime, Linux CPU) run on the 555 test commands with the app's exact prompt and parser:
right action 86.8%, right action and details **82.7%** (training-side evaluation: 82%); 93% of answers identical to the
training-side ones (int8 vs fp32). By language (full): en 93 · hi 96 · kn 90 · ml-Latn 89 · te 84 · ml 83 · ta 80 · hi-Latn 67 ·
kn-Latn 63. On a laptop CPU: median 2.1 s per command, p90 2.6 s, engine start ~2–3 s. Phones will be slower; measure there.
Of 164 rides the model proposed, two named a place that doesn't exist ("Akame no Shibori", "AC repair"): `KnownPlaces` rejects both.

## Shipping

1. **Host the file** (`out/bucks-intent-run4_q8_ekv1024.litertlm`, 285,002,368 bytes, SHA-256
   `430cf43106da07c0da1855f22eba555bb6903fc37605512c2294d2ce7f53d236`). The app downloads `INTENT_MODEL_URL` (build field; default a
   public Supabase Storage URL `…/storage/v1/object/public/models/bucks-intent-run4_q8_ekv1024.litertlm`; override with
   `INTENT_MODEL_URL` / `INTENT_MODEL_SHA256` in `local.properties` or CI). Options:
   - Supabase Storage, public bucket `models`: same project, simple. The free plan caps uploads at 50 MB per file (Pro raises it) and
     includes 5 GB egress a month, about 17 downloads; Pro includes 250 GB.
   - A GitHub Release asset on this public repository (for example tag `intent-model-run4`): free, up to 2 GB per file, already how
     tester APKs are delivered; the in-app updater ignores tags that aren't `build-N`.
   - Play for On-device AI (AI packs, beta): delivered by Play with the app, Play builds only, needs the AAB packaging work. The
     long-term option for the store build.
2. **Test on a real mid-range phone** with a debug build and the file in place: first-command latency (engine start), later
   commands, peak memory (RSS), battery, and a few commands in each language.
3. **Turn it on**: apply `supabase/migrations/intent_tier1.sql` (adds the row at 0), then
   `update settings set value = 1 where key = 'intent_tier1_enabled'` (back to 0 is the kill switch: phones stop using it and delete
   the file). Phones download it on Wi-Fi (or mobile data if allowed in Settings > Voice), check the hash, then use it.
