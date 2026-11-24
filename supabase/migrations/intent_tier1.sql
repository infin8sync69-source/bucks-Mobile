-- The Android assistant's on-device intent model (app ai/IntentModel.kt, ml/intent/README.md "Shipping").
-- 0: phones never download it, and delete a downloaded copy (kill switch). 1: phones on Wi-Fi download it, check its SHA-256, use it.
-- Off by default; turn on only once the model file is hosted and it was tested on a real phone:
--   update public.settings set value = 1 where key = 'intent_tier1_enabled';
insert into public.settings (key, value) values ('intent_tier1_enabled', 0) on conflict (key) do nothing;
