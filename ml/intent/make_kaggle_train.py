import base64, hashlib, io, json, sys, tarfile
out = sys.argv[1]
_buf = io.BytesIO()
with tarfile.open(fileobj=_buf, mode="w:xz", preset=9) as _t:
    for _f in ["phrases.py", "gen_data.py", "tools.json", "convert_litertlm.py", "eval_set_v3.jsonl"]:
        _t.add(_f)
_raw = _buf.getvalue()
PACKED_CELL = ("# 2. Unpack phrases.py, gen_data.py, tools.json, convert_litertlm.py (no upload needed) and generate the data\n"
               "import base64, io, tarfile, hashlib\nB64 = \"" + base64.b64encode(_raw).decode() + "\"\nraw = base64.b64decode(B64)\n"
               "assert hashlib.sha256(raw).hexdigest().startswith(\"" + hashlib.sha256(_raw).hexdigest()[:16] + "\"), \"files damaged\"\n"
               "tarfile.open(fileobj=io.BytesIO(raw), mode=\"r:xz\").extractall(\".\")\n!python -I gen_data.py")
md = lambda s: {"cell_type": "markdown", "metadata": {}, "source": s}
code = lambda s: {"cell_type": "code", "metadata": {}, "source": s, "outputs": [], "execution_count": None}
cells = [
md("""# Bucks intent model, run 4: train, test and convert (free Kaggle GPU)

Settings (right panel): **Accelerator: GPU T4 x2** (or P100), **Internet: on**. Add-ons → Secrets: `HF_TOKEN` = your Hugging Face read token,
attached to this notebook (Gemma licence accepted on `google/functiongemma-270m-it`). Then **Save Version → Save & Run All (Commit)**:
it runs on Kaggle's servers even if your browser or internet goes away (about 2–3 hours).
When it finishes, open the version's **Output** tab and download `bucks-intent-run4.zip` and `litertlm/bucks-intent_q8_ekv1024.litertlm`."""),
code("""# 1. GPU check and training libraries (one GPU is enough; use the first)
import os; os.environ["CUDA_VISIBLE_DEVICES"] = "0"
import subprocess, sys, torch
assert torch.cuda.is_available(), "No GPU: Settings > Accelerator > GPU T4 x2, then run again"
print(torch.__version__, torch.cuda.get_device_name(0))
!pip install -q transformers==4.57.1 trl==0.25.1 datasets==4.4.1 accelerate"""),
code(PACKED_CELL),
code("""# 3. Hugging Face login from the Kaggle secret HF_TOKEN (Add-ons > Secrets, attached to this notebook)
from kaggle_secrets import UserSecretsClient
from huggingface_hub import login, whoami
login(token=UserSecretsClient().get_secret("HF_TOKEN"))
print("Logged in as", whoami()["name"])"""),
code("""# 4. Data in FunctionGemma's chat format; held-out split into validation (picks the checkpoint) and test (the reported score)
import json, re
import pandas as pd
from datasets import load_dataset
from transformers import AutoTokenizer, AutoModelForCausalLM, pipeline
gemma_model = "google/functiongemma-270m-it"
tokenizer = AutoTokenizer.from_pretrained(gemma_model)
dataset = load_dataset("text", data_files="dataset.jsonl", encoding="utf-8")["train"].shuffle(seed=7)
def apply_format(sample):
    row = json.loads(sample["text"])
    full = tokenizer.apply_chat_template(row["messages"], tools=row["tools"], tokenize=False, add_generation_prompt=False)
    prompt = tokenizer.apply_chat_template(row["messages"][:-1], tools=row["tools"], tokenize=False, add_generation_prompt=True)
    return {"prompt": prompt, "completion": full[len(prompt):], "split": row["metadata"], "lang": row["lang"]}
processed = dataset.map(apply_format)
train_dataset = processed.filter(lambda e: e["split"] == "train")
held_out = processed.filter(lambda e: e["split"] == "eval")
import hashlib   # split by each command's text, so every run is tested on exactly the same commands
_test = lambda e: int(hashlib.sha256(json.loads(e["text"])["messages"][1]["content"].encode()).hexdigest(), 16) % 2 == 1
val_dataset = held_out.filter(lambda e: not _test(e))
test_dataset = held_out.filter(_test)
max_token_count = max(len(tokenizer.tokenize(e["prompt"] + e["completion"])) for e in processed) + 50
print(len(train_dataset), "train,", len(val_dataset), "validation,", len(test_dataset), "test, max_length", max_token_count)"""),
code("""# 5. Scoring: same rules as rules_baseline.py
def extract_function_call(text):
    out = []
    for raw in re.findall(r"<start_function_call>(.*?)<end_function_call>", text, re.DOTALL):
        if not raw.strip().startswith("call:") or "{" not in raw: continue
        pre, rest = raw.split("{", 1); rest = rest.strip()
        if rest.endswith("}"): rest = rest[:-1]
        args = {m.group("k").strip(): m.group("v") for m in re.finditer(r"(?P<k>[^:,]*?):<escape>(?P<v>.*?)<escape>", rest, re.DOTALL)}
        out.append({"name": pre.replace("call:", "").strip(), "arguments": args})
    return out
def norm_args(args):
    out = {}
    for k, v in (args or {}).items():
        v = str(v).strip().lower()
        if k == "destination": v = v.split(",")[0].split(" ")[0]
        out[k] = re.sub(r"^(a|an|the) ", "", v)
    return out
def evaluate(pipe, ds, show_misses=0):
    rows = []
    for e in ds:
        row = json.loads(e["text"]); want = row["messages"][2]["tool_calls"][0]["function"]
        gen = pipe(e["prompt"], max_new_tokens=64, do_sample=False, skip_special_tokens=False)[0]["generated_text"][len(e["prompt"]):]
        calls = extract_function_call(gen); got = calls[0] if calls else {"name": "help", "arguments": {}}
        action = got["name"] == want["name"]
        rows.append({"lang": e["lang"], "user": row["messages"][1]["content"], "want": want, "got": got, "action": action,
                     "full": action and norm_args(got["arguments"]) == norm_args(want["arguments"])})
    df = pd.DataFrame(rows)
    print(f"right action {df.action.mean():.0%}, right action and details {df.full.mean():.0%}")
    print(df.groupby("lang")[["action", "full"]].mean().round(2))
    print(df.assign(tool=df.want.map(lambda w: w["name"])).groupby("tool")[["action", "full"]].mean().round(2))
    for _, r in df[~df.full].head(show_misses).iterrows(): print(f"  [{r.lang}] {r.user!r} -> {r.got} (want {r.want})")
    return df"""),
code("""# 6. Fine-tune. A T4 has no bf16 and Gemma overflows in fp16, so this trains in fp32 (270M parameters fit easily in 15 GB).
from trl import SFTConfig, SFTTrainer
output_dir = "bucks-intent-run4"
args = SFTConfig(
    output_dir=output_dir, num_train_epochs=1,            # runs 1-2 were best at 0.7-1.4 epochs
    per_device_train_batch_size=1, gradient_accumulation_steps=16, per_device_eval_batch_size=1,   # 262k-word vocab: batch 4 runs out of T4 memory
    logging_strategy="steps", logging_steps=25, eval_strategy="steps", eval_steps=100,
    save_strategy="steps", save_steps=100, save_total_limit=2,
    load_best_model_at_end=True, metric_for_best_model="eval_loss", greater_is_better=False,
    learning_rate=1e-5, lr_scheduler_type="cosine", max_length=max_token_count,
    gradient_checkpointing=True, packing=False, optim="adamw_torch_fused",
    bf16=False, fp16=False, completion_only_loss=True, report_to="none")
model = AutoModelForCausalLM.from_pretrained(gemma_model, device_map="auto", dtype=torch.float32, attn_implementation="eager")
model.config.pad_token_id = tokenizer.pad_token_id
trainer = SFTTrainer(model=model, args=args, train_dataset=train_dataset, eval_dataset=val_dataset)
trainer.train()
trainer.save_model(output_dir); tokenizer.save_pretrained(output_dir)
print("best checkpoint:", trainer.state.best_model_checkpoint, "eval_loss", trainer.state.best_metric)"""),
code("""# 7. Score the trained model on the test commands (never used for training or choosing)
tuned = AutoModelForCausalLM.from_pretrained(output_dir, device_map="auto", dtype=torch.float32)
tuned_pipe = pipeline("text-generation", model=tuned, tokenizer=AutoTokenizer.from_pretrained(output_dir))
scored = evaluate(tuned_pipe, test_dataset, show_misses=40)
scored.to_json("eval_run4.json", orient="records", force_ascii=False)"""),
code("""# 8. Download the checkpoint and test results
import zipfile, os
with zipfile.ZipFile("bucks-intent-run4.zip", "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(os.listdir(output_dir)):
        p = os.path.join(output_dir, f)
        if os.path.isfile(p): z.write(p, f)
    z.write("eval_run4.json")
print(round(os.path.getsize("bucks-intent-run4.zip") / 1e6, 1), "MB  (Output tab of this version)")
!rm -rf bucks-intent-run4/checkpoint-*   # keep the Output small: the final model is already saved at the top level"""),
code("""# 9. Convert to .litertlm in a separate environment (the converter needs torch < 2.15 and jax 0.12.0.1)
!pip install -q uv
!uv venv -q /kaggle/working/conv_env
!uv pip install -q --python /kaggle/working/conv_env/bin/python "torch<2.15" --index-url https://download.pytorch.org/whl/cpu
!uv pip install -q --python /kaggle/working/conv_env/bin/python "litert-torch==0.10.0" tensorflow-cpu "jax==0.12.0.1" "jaxlib==0.12.0.1" "litert-lm-builder==0.18.1"
!mkdir -p litertlm
!for s in export quantize pack; do /kaggle/working/conv_env/bin/python convert_litertlm.py $s bucks-intent-run4 litertlm 2>&1 | grep -E "exported|quantized|packed|Error|error" || true; done
!ls -la litertlm"""),
code("""# 10. Tidy the Output: keep the zip, the test results and the phone model
!rm -rf /kaggle/working/conv_env conv litertlm/*.tflite
!ls -la litertlm *.zip *.json"""),
]
nb = {"nbformat": 4, "nbformat_minor": 5, "cells": cells,
      "metadata": {"kernelspec": {"name": "python3", "display_name": "Python 3"}, "kaggle": {"accelerator": "nvidiaTeslaT4", "isInternetEnabled": True, "isGpuEnabled": True}}}
json.dump(nb, open(out, "w"), indent=1)
