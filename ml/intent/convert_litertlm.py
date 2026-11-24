"""Convert the fine-tuned checkpoint to a .litertlm for LiteRT-LM on the phone. CPU only, no GPU needed.

Runs in three separate processes (export, quantize, pack) so the peak memory of each step stays under ~4 GB.
Needs a venv with: torch<2.15 (CPU build), litert-torch==0.10.0, tensorflow-cpu (imported but not declared), jax==0.12.0.1
and jaxlib==0.12.0.1 (0.12.1 breaks the export), litert-lm-builder==0.18.1 (0.19 dropped TfLiteModelType).
Usage: python -I convert_litertlm.py {export|quantize|pack} CHECKPOINT_DIR OUT_DIR
Output: OUT_DIR/bucks-intent_q8_ekv1024.litertlm (dynamic int8, 1024-token context; the 12-tool prompt is ~613 tokens).
"""
import glob
import sys

step, ck, out = sys.argv[1], sys.argv[2], sys.argv[3]
Q8 = f"{out}/bucks-intent_q8_ekv1024.tflite"
if step == "export":
    from litert_torch.generative.examples.gemma3 import gemma3
    from litert_torch.generative.layers import kv_cache
    from litert_torch.generative.utilities import converter
    from litert_torch.generative.utilities.export_config import ExportConfig
    cfg = ExportConfig(); cfg.kvcache_layout = kv_cache.KV_LAYOUT_TRANSPOSED; cfg.mask_as_input = True
    print("exported", converter.convert_to_tflite(gemma3.build_model_270m(ck), out, "bucks-intent", 256, 1024,
                                                  quantize="none", export_config=cfg))
elif step == "quantize":
    from litert_torch.generative.examples.gemma3 import decoder
    from litert_torch.generative.quantize import quant_recipes
    from litert_torch.quantize import translate_recipe
    src = glob.glob(f"{out}/bucks-intent_*f32*.tflite")[0]
    recipe = translate_recipe.translate_to_ai_edge_recipe(quant_recipes.full_dynamic_recipe(mcfg=decoder.get_decoder_config_270m()).generative_recipe)
    q = translate_recipe.quantize_model(open(src, "rb").read(), recipe)
    open(Q8, "wb").write(q); print("quantized", len(q))
elif step == "pack":
    import tempfile
    from litert_torch.generative.utilities import litertlm_builder
    with tempfile.TemporaryDirectory() as wd:
        litertlm_builder.build_litertlm(
            tflite_model_path=Q8, workdir=wd, output_path=out, context_length=1024,
            hf_tokenizer_model_path=f"{ck}/tokenizer.json", llm_model_type="generic",
            start_token="<bos>", stop_tokens=["<end_of_turn>", "<start_function_response>", "<eos>"],
            user_prompt_prefix="<start_of_turn>user\n", user_prompt_suffix="<end_of_turn>\n",
            model_prompt_prefix="<start_of_turn>model\n", model_prompt_suffix="<end_of_turn>\n",
            jinja_prompt_template=open(f"{ck}/chat_template.jinja").read())
    print("packed")
