-- Contact details you attach to a person you are synced with: their number, email, organisation, address and a note.
--
-- Private to the person who attaches them: nobody else can read, edit or even see they exist (not the person they are about,
-- not Bucks staff through the app). It only needs the two people to be synced when it is created; it stays after an unsync
-- (it is your own address book) and goes away when either account is deleted.
set search_path = public, extensions;

-- A JSON array of at most max_n strings, each at most max_len characters.
create or replace function public.texts_ok(j jsonb, max_n int, max_len int) returns boolean language sql immutable set search_path = public, extensions as $$
  select jsonb_typeof(j) = 'array' and jsonb_array_length(j) <= max_n
     and not exists (select 1 from jsonb_array_elements(j) e where jsonb_typeof(e) <> 'string' or length(e #>> '{}') > max_len)
$$;

create table if not exists public.contact_links (
  owner_id    uuid not null references public.profiles on delete cascade,
  profile_id  uuid not null references public.profiles on delete cascade,
  phones      jsonb not null default '[]',
  emails      jsonb not null default '[]',
  org         text not null default '',
  title       text not null default '',
  address     text not null default '',
  note        text not null default '',
  updated_at  timestamptz not null default now(),
  primary key (owner_id, profile_id),
  check (owner_id <> profile_id),
  check (public.texts_ok(phones, 5, 40)),
  check (public.texts_ok(emails, 5, 120)),
  check (length(org) <= 120 and length(title) <= 120 and length(address) <= 300 and length(note) <= 500)
);
create index if not exists contact_links_profile_idx on public.contact_links (profile_id);
alter table public.contact_links enable row level security;
drop policy if exists contact_links_own on public.contact_links;
create policy contact_links_own on public.contact_links for all to authenticated
  using (owner_id = (select public.me())) with check (owner_id = (select public.me()));

-- Only for people you are synced with, checked when the link is made (an unsync later does not delete your own notes).
create or replace function public.contact_link_guard() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if tg_op = 'INSERT' and not synced(new.owner_id, new.profile_id) then
    raise exception 'you can add contact details only for people you are synced with';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists contact_link_guard on public.contact_links;
create trigger contact_link_guard before insert or update on public.contact_links for each row execute function public.contact_link_guard();

-- Who a link is about can't be changed by editing: delete it and make a new one.
revoke insert, update on public.contact_links from authenticated, anon;
grant select, delete on public.contact_links to authenticated;
grant insert (owner_id, profile_id, phones, emails, org, title, address, note) on public.contact_links to authenticated;
grant update (phones, emails, org, title, address, note) on public.contact_links to authenticated;
revoke execute on function public.contact_link_guard() from authenticated, anon, public;
