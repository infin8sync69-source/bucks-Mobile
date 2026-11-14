-- Bucks: in-app notifications for jobs. Safe to run more than once. Apply after jobs.sql and notifications.sql
-- (supabase/apply_all.sh runs it last).
--   A new application     -> everyone who runs the listing (owner and admins): "<name> applied for <job>"
--   Shortlisted / hired / declined -> the applicant: where their application stands
-- Withdrawals stay quiet: the count on the job page already drops.
set search_path = public, extensions;

create or replace function public.note_application() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare j jobs; shop text;
begin
  select * into j from jobs where id = new.job_id;
  if j.id is null then return null; end if;
  select coalesce(nullif(title, ''), 'The business') into shop from listings where id = j.listing_id;
  if tg_op = 'INSERT' then
    perform push_note_team(j.listing_id, 'JOB_APPLICATION', pname(new.applicant_id) || ' applied for ' || j.title, 'Open the job to see their application.', 'job/' || j.id);
  elsif new.status is distinct from old.status and new.status in ('SHORTLISTED', 'HIRED', 'REJECTED') then
    perform push_note(new.applicant_id, 'JOB_UPDATE',
      case new.status when 'SHORTLISTED' then 'You''re shortlisted for ' || j.title
                      when 'HIRED'       then 'You got the job: ' || j.title
                      else 'Your application for ' || j.title || ' was declined' end,
      case new.status when 'REJECTED' then shop || ' chose someone else this time.' else shop || ' may message you next. Tap to see the job.' end,
      'job/' || j.id);
  end if;
  return null;
end $$;
drop trigger if exists note_application on public.applications;
create trigger note_application after insert or update of status on public.applications for each row execute function public.note_application();

revoke execute on function public.note_application() from authenticated, anon, public;
