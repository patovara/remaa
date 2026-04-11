-- Enforce non-empty project names at database level.
update public.projects
set name = trim(name)
where name is not null;

do $$
begin
  if exists (
    select 1
    from public.projects
    where coalesce(length(trim(name)), 0) = 0
  ) then
    raise exception 'projects.name contains blank values; fix data before applying projects_name_not_blank_check';
  end if;
end;
$$;

alter table public.projects
  drop constraint if exists projects_name_not_blank_check;

alter table public.projects
  add constraint projects_name_not_blank_check
  check (length(trim(name)) > 0);
