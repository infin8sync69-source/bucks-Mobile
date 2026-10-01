-- Interaction notifications: comments, likes and Moment reactions show up in the Notifications tab (notifications.sql).
-- Comments already had a push (supabase/functions/notify); likes and reactions get one now. Every row opens the post.
set search_path = public, extensions;

-- A comment: the post's author hears about it, and so does anyone else already in the conversation.
create or replace function public.note_comment() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare p posts; who text; m uuid;
begin
  select * into p from posts where id = new.post_id;
  if not found or p.deleted_at is not null then return null; end if;
  who := pname(new.author_id);
  if p.author_id <> new.author_id then
    perform push_note(p.author_id, 'COMMENT', who || ' commented on your post', new.body, 'post/' || p.id);
  end if;
  for m in select distinct author_id from post_comments where post_id = new.post_id and author_id not in (new.author_id, p.author_id) loop
    perform push_note(m, 'COMMENT_THREAD', who || ' also commented on a post you commented on', new.body, 'post/' || p.id);
  end loop;
  return null;
end $$;
drop trigger if exists note_comment on public.post_comments;
create trigger note_comment after insert on public.post_comments for each row execute function public.note_comment();

-- A like (an up-vote). Taking a vote back and giving it again does not tell the author twice in a day.
create or replace function public.note_vote() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare p posts; t text;
begin
  if new.vote <> 1 or (tg_op = 'UPDATE' and old.vote = 1) then return null; end if;
  select * into p from posts where id = new.post_id;
  if not found or p.deleted_at is not null or p.author_id = new.profile_id then return null; end if;
  t := pname(new.profile_id) || ' recommended your post';
  if exists (select 1 from notifications where profile_id = p.author_id and kind = 'POST_LIKE' and route = 'post/' || p.id and title = t and created_at > now() - interval '1 day') then return null; end if;
  perform push_note(p.author_id, 'POST_LIKE', t, left(p.body, 120), 'post/' || p.id);
  return null;
end $$;
drop trigger if exists note_vote on public.post_votes;
create trigger note_vote after insert or update of vote on public.post_votes for each row execute function public.note_vote();

-- A reaction to a Moment (a plain view says nothing).
create or replace function public.note_reaction() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare a uuid;
begin
  if coalesce(new.reaction, '') = '' or (tg_op = 'UPDATE' and old.reaction is not distinct from new.reaction) then return null; end if;
  select author_id into a from moments where id = new.moment_id;
  if a is null or a = new.viewer_id then return null; end if;
  perform push_note(a, 'MOMENT_REACTION', pname(new.viewer_id) || ' reacted ' || new.reaction || ' to your moment', 'Your moment is up for 24 hours.', 'feed');
  return null;
end $$;
drop trigger if exists note_reaction on public.moment_views;
create trigger note_reaction after insert or update of reaction on public.moment_views for each row execute function public.note_reaction();

revoke execute on function public.note_comment(), public.note_vote(), public.note_reaction() from authenticated, anon, public;

-- Push for likes and reactions (comments already have theirs). push_notify (push.sql) reports every update of a table without a status column.
drop trigger if exists push_post_votes on public.post_votes;
create trigger push_post_votes after insert or update of vote on public.post_votes for each row execute function public.push_notify();
drop trigger if exists push_moment_views on public.moment_views;
create trigger push_moment_views after insert or update of reaction on public.moment_views for each row execute function public.push_notify();
