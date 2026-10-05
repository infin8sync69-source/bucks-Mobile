-- Two-device test settings, so a couple of phones can exercise every flow: one recommendation takes a listing live (new
-- accounts may recommend), and one checked provider unlocks each service. Documents are still required.
-- Applied to bucks-app for the device tests. RUN THE REVERT BLOCK BEFORE INVITING REAL PILOT USERS.

-- ---------- apply ----------
update settings set value = '1' where key = 'min_recommendations';
update settings set value = '0' where key = 'recommender_min_account_days';
update service_rules set min_supply = 1, updated_at = now() where mode = 'AUTO';

-- ---------- revert to the launch values (docs/SERVICES_UNLOCK.md) ----------
-- update settings set value = '7'  where key = 'min_recommendations';
-- update settings set value = '14' where key = 'recommender_min_account_days';
-- update service_rules set min_supply = v.n, updated_at = now() from (values
--   ('TAXI', 3), ('AUTO', 3), ('PARCEL', 4), ('FOOD', 10), ('GROCERY', 5), ('VEGETABLES', 3), ('MEAT', 2),
--   ('SHOPPING', 5), ('GIGS', 8), ('JOBS', 5), ('PROPERTIES', 10)) v(k, n) where key = v.k;
