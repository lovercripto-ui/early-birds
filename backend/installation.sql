-- One installation per database. No shared-customer access is introduced.
create table eb_phone.installation (
 id integer primary key check (id=1), company_name text not null default '',
 claim uuid, claimed_at timestamptz, completed_at timestamptz
);
alter table eb_phone.installation enable row level security;
revoke all on eb_phone.installation from public,anon,authenticated;
grant select,insert,update on eb_phone.installation to service_role;
grant insert(id,display_name,role,phone_active,phone_must_change) on public.profiles to service_role;
insert into eb_phone.installation(id,completed_at)
values(1,case when exists(select 1 from public.profiles) then now() else null end);

create function public.phone_install_status() returns jsonb language sql security invoker set search_path='' as $$
 select jsonb_build_object('initialized',i.completed_at is not null or exists(select 1 from public.profiles),'company',i.company_name) from eb_phone.installation i where i.id=1
$$;
create function public.phone_install_claim() returns uuid language plpgsql security invoker set search_path='' as $$
declare i eb_phone.installation; c uuid;
begin
 select * into strict i from eb_phone.installation where id=1 for update;
 if i.completed_at is not null or exists(select 1 from public.profiles) then raise exception 'Workspace already initialized';end if;
 if i.claim is not null and i.claimed_at>now()-interval '10 minutes' then raise exception 'Setup in progress; retry later';end if;
 c=gen_random_uuid();update eb_phone.installation set claim=c,claimed_at=now() where id=1;return c;
end $$;
create function public.phone_install_finish(p_claim uuid,p_user uuid,p_name text,p_company text) returns void language plpgsql security invoker set search_path='' as $$
declare i eb_phone.installation;
begin
 select * into strict i from eb_phone.installation where id=1 for update;
 if p_claim is null or i.claim is distinct from p_claim or i.completed_at is not null or exists(select 1 from public.profiles) then raise exception 'Setup unavailable';end if;
 if p_name is null or p_company is null or length(btrim(p_name)) not between 2 and 120 or length(btrim(p_company)) not between 2 and 160 then raise exception 'Invalid company or Admin name';end if;
 insert into public.profiles(id,display_name,role,phone_active,phone_must_change) values(p_user,btrim(p_name),'admin',true,false);
 update eb_phone.installation set company_name=btrim(p_company),completed_at=now(),claim=null where id=1;
end $$;
create function public.phone_install_release(p_claim uuid) returns void language sql security invoker set search_path='' as $$
 update eb_phone.installation set claim=null,claimed_at=null where id=1 and claim=p_claim and completed_at is null
$$;
create function public.phone_company_set(p_company text) returns void language plpgsql security invoker set search_path='' as $$
begin
 if p_company is null or length(btrim(p_company)) not between 2 and 160 then raise exception 'Company name must have 2–160 characters';end if;
 update eb_phone.installation set company_name=btrim(p_company) where id=1;
end $$;
revoke all on function public.phone_install_status(),public.phone_install_claim(),public.phone_install_finish(uuid,uuid,text,text),public.phone_install_release(uuid),public.phone_company_set(text) from public,anon,authenticated;
grant execute on function public.phone_install_status(),public.phone_install_claim(),public.phone_install_finish(uuid,uuid,text,text),public.phone_install_release(uuid),public.phone_company_set(text) to service_role;
-- Close the old signup-to-workspace shortcut; provisioning now requires an installation token.
revoke execute on function public.register_company_workspace(text,text,text,text) from public,anon,authenticated;
