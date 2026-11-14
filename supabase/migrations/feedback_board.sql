-- Feedback board: anyone signed in can suggest an idea or report a bug, upvote others' posts, and see what the team is doing about them.
-- Staff set a status (OPEN, PLANNED, IN_PROGRESS, DONE, DECLINED) and an optional public note. Everything is written through the
-- functions below; the tables have no write grants. Minors are shown as "Bucks member", never by name.
set search_path = public, extensions;

create table if not exists public.feedback_posts (
  id          uuid primary key default public.uuid_v7(),
  author_id   uuid not null references public.profiles on delete cascade,
  category    text not null default 'IDEA' check (category in ('IDEA', 'BUG', 'OTHER')),
  title       text not null check (length(btrim(title)) between 4 and 100),
  body        text not null default '' check (length(body) <= 1000),
  status      text not null default 'OPEN' check (status in ('OPEN', 'PLANNED', 'IN_PROGRESS', 'DONE', 'DECLINED')),
  staff_note  text not null default '' check (length(staff_note) <= 500),
  votes       int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists feedback_posts_top_idx on public.feedback_posts (votes desc, created_at desc);
create index if not exists feedback_posts_new_idx on public.feedback_posts (created_at desc);
create table if not exists public.feedback_votes (
  post_id    uuid not null references public.feedback_posts on delete cascade,
  profile_id uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, profile_id)
);
alter table public.feedback_posts enable row level security;
alter table public.feedback_votes enable row level security;
drop policy if exists feedback_posts_read on public.feedback_posts;
create policy feedback_posts_read on public.feedback_posts for select to authenticated using (true);
drop policy if exists feedback_votes_own on public.feedback_votes;
create policy feedback_votes_own on public.feedback_votes for select to authenticated using (profile_id = (select public.me()));
revoke all on public.feedback_posts, public.feedback_votes from anon, authenticated;
grant select on public.feedback_posts, public.feedback_votes to authenticated;

-- The board. sort: TOP (most votes) or NEW. status: null for everything except DECLINED, or one status. mine: only my own posts.
create or replace function public.feedback_list(sort text default 'TOP', p_status text default null, mine boolean default false, lim int default 50, off int default 0)
returns table (id uuid, category text, title text, body text, status text, staff_note text, votes int, voted boolean, is_mine boolean, author_name text, created_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select f.id, f.category, f.title, f.body, f.status, f.staff_note, f.votes,
         exists (select 1 from feedback_votes v where v.post_id = f.id and v.profile_id = me()),
         f.author_id = me(),
         case when is_minor(f.author_id) or a.status <> 'ACTIVE' then 'Bucks member' else a.name end,
         f.created_at
  from feedback_posts f join profiles a on a.id = f.author_id
  where me() is not null
    and (case when p_status is null then f.status <> 'DECLINED' else f.status = upper(p_status) end)
    and (not coalesce(mine, false) or f.author_id = me())
    and not blocked_between(me(), f.author_id)
  order by case when upper(coalesce(sort, 'TOP')) = 'NEW' then 0 else f.votes end desc, f.created_at desc
  limit greatest(1, least(coalesce(lim, 50), 100)) offset greatest(coalesce(off, 0), 0)
$$;

-- Post an idea or bug; the author's own vote comes with it. At most 5 posts a day per person (keeps the board readable).
create or replace function public.feedback_post(p_title text, p_body text default '', p_category text default 'IDEA') returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); fid uuid;
begin
  if my is null then raise exception 'not signed in'; end if;
  if (select count(*) from feedback_posts where author_id = my and created_at > now() - interval '1 day') >= 5 then
    raise exception 'you can post 5 ideas a day; try again tomorrow';
  end if;
  insert into feedback_posts (author_id, title, body, category) values (my, btrim(p_title), btrim(coalesce(p_body, '')), upper(coalesce(p_category, 'IDEA')))
  returning id into fid;
  insert into feedback_votes (post_id, profile_id) values (fid, my);
  update feedback_posts set votes = 1 where id = fid;
  return fid;
end $$;

-- Vote or unvote; returns the new count.
create or replace function public.feedback_vote(p_post uuid, p_on boolean) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); n int;
begin
  if my is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from feedback_posts where id = p_post) then raise exception 'that post was removed'; end if;
  if p_on then insert into feedback_votes (post_id, profile_id) values (p_post, my) on conflict do nothing;
  else delete from feedback_votes where post_id = p_post and profile_id = my; end if;
  update feedback_posts set votes = (select count(*) from feedback_votes where post_id = p_post) where id = p_post returning votes into n;
  return n;
end $$;

-- Delete my own post (staff can delete any).
create or replace function public.feedback_delete(p_post uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from feedback_posts where id = p_post and (author_id = me() or is_staff());
  if not found then raise exception 'you can only delete your own posts'; end if;
end $$;

-- Staff: set where a post stands, with an optional note everyone sees.
create or replace function public.feedback_set_status(p_post uuid, p_status text, p_note text default null) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_staff() then raise exception 'staff only'; end if;
  update feedback_posts set status = upper(p_status), staff_note = coalesce(left(btrim(p_note), 500), staff_note), updated_at = now() where id = p_post;
  if not found then raise exception 'no such post'; end if;
end $$;

revoke execute on function public.feedback_list(text, text, boolean, int, int), public.feedback_post(text, text, text), public.feedback_vote(uuid, boolean),
                           public.feedback_delete(uuid), public.feedback_set_status(uuid, text, text) from public, anon;
grant execute on function public.feedback_list(text, text, boolean, int, int), public.feedback_post(text, text, text), public.feedback_vote(uuid, boolean),
                          public.feedback_delete(uuid), public.feedback_set_status(uuid, text, text) to authenticated;
