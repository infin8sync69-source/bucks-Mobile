\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
set search_path = public, extensions;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when coalesce(cond, false) then 'ok ' || label else 'FAIL ' || label end $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.post(b text) returns uuid language sql security definer as $$ select id from public.posts where body = b $$;

set role authenticated;
-- me (lm) is synced with two friends (lf1, lf2); ls is a stranger.
select pg_temp.as_user('lm');  select (public.ensure_profile('Me Mala', '9000000901')).id is not null;
select pg_temp.as_user('lf1'); select (public.ensure_profile('Friend One', '9000000902')).id is not null;
select pg_temp.as_user('lf2'); select (public.ensure_profile('Friend Two', '9000000903')).id is not null;
select pg_temp.as_user('ls');  select (public.ensure_profile('Stranger Sam', '9000000904')).id is not null;
select pg_temp.as_user('lm'); select request_sync(pg_temp.pid('lf1')); select request_sync(pg_temp.pid('lf2'));
select pg_temp.as_user('lf1'); update syncs set status = 'ACCEPTED' where addressee_id = me();
select pg_temp.as_user('lf2'); update syncs set status = 'ACCEPTED' where addressee_id = me();

select pg_temp.as_user('lf1'); insert into posts (author_id, body, visibility) values (me(), 'Friend post', 'SYNCED');
select pg_temp.as_user('ls');  insert into posts (author_id, body, visibility, location) values (me(), 'Stranger public post', 'PUBLIC', geo(12.9, 77.6));
select pg_temp.as_user('lm');  insert into posts (author_id, body, visibility) values (me(), 'My own post', 'PUBLIC');

\echo '== Feed: synced people and me only'
select pg_temp.as_user('lm');
select pg_temp.check('a friend''s post is there', exists (select 1 from feed_synced() where body = 'Friend post'));
select pg_temp.check('my own post is there', exists (select 1 from feed_synced() where body = 'My own post'));
select pg_temp.check('a stranger''s public post is not', not exists (select 1 from feed_synced() where body = 'Stranger public post'));
select pg_temp.check('the old feed still shows it (older apps)', exists (select 1 from feed(12.9, 77.6) where body = 'Stranger public post'));

\echo '== For you: only what synced people recommend, counts only'
select pg_temp.as_user('lf1'); insert into post_votes (post_id, profile_id, vote) values (pg_temp.post('Stranger public post'), me(), 1);
select pg_temp.as_user('lm');
select pg_temp.check('one friend''s vote is not enough to show a post', not exists (select 1 from for_you() where kind = 'POST'));
select pg_temp.as_user('lf2'); insert into post_votes (post_id, profile_id, vote) values (pg_temp.post('Stranger public post'), me(), 1);
select pg_temp.as_user('lm');
select pg_temp.check('two friends voting it up: it shows, recommended by 2', (select recommenders = 2 from for_you() where kind = 'POST' and subtitle = 'Stranger public post'));
select pg_temp.as_user('ls'); insert into post_votes (post_id, profile_id, vote) values (pg_temp.post('My own post'), me(), 1);
select pg_temp.as_user('lm');
select pg_temp.check('a stranger''s vote never counts, and my own posts never show', not exists (select 1 from for_you() where subtitle = 'My own post'));

select pg_temp.as_user('ls');
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Sam Sweets', 'Sweets', 'Hindupur', geo(13.83, 77.49));
insert into items (listing_id, name, price, unit) values ((select id from listings where title = 'Sam Sweets'), 'Mysore Pak', 200, '250 g');
reset role; update listings set status = 'LIVE' where title = 'Sam Sweets';
insert into recommendations (listing_id, recommender_id, at_location) values ((select id from listings where title = 'Sam Sweets'), pg_temp.pid('lf1'), geo(13.83, 77.49));
insert into product_ratings (listing_id, product_key, profile_id, vote)
  select l.id, item_product_key(i.details, i.id), pg_temp.pid('lf2'), 1 from listings l join items i on i.listing_id = l.id where l.title = 'Sam Sweets';
set role authenticated;
select pg_temp.as_user('lm');
select pg_temp.check('a shop a friend recommended', exists (select 1 from for_you() where kind = 'LISTING' and title = 'Sam Sweets' and recommenders = 1));
select pg_temp.check('a product a friend rated up, with its shop', exists (select 1 from for_you() where kind = 'PRODUCT' and title = 'Mysore Pak' and subtitle = 'Sam Sweets'));
select pg_temp.as_user('ls');
select pg_temp.check('the stranger, synced with nobody, gets nothing', not exists (select 1 from for_you()));
