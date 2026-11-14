-- Supabase advisor 0011 (function_search_path_mutable): pin search_path on the helpers added without one, so a caller's search_path
-- can never redirect the names they use.
do $$
declare f text;
begin
  foreach f in array array['public.cancel_reason_label(text)', 'public.cancel_reason_ok(text,text)', 'public.item_product_key(jsonb,uuid)', 'public.showcase_check_fields(text,text,text)'] loop
    if to_regprocedure(f) is not null then execute format('alter function %s set search_path = public, extensions', f); end if;
  end loop;
end $$;
