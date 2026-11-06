-- Additive phone gateway. Existing tables and records are retained.
create schema if not exists eb_phone;
revoke all on schema eb_phone from public,anon,authenticated;
grant usage on schema eb_phone to authenticated;
alter table public.profiles add column if not exists phone_active boolean not null default true;
alter table public.profiles add column if not exists phone_must_change boolean not null default false;
create table eb_phone.control(id integer primary key check(id=1), revision bigint not null default 0, generation uuid not null default gen_random_uuid());
insert into eb_phone.control(id) values(1);
create table eb_phone.meta(kind text not null,id uuid not null,data jsonb not null default '{}',primary key(kind,id));
create table eb_phone.replays(actor uuid not null,key uuid not null,payload jsonb not null,result jsonb not null,primary key(actor,key));
create table eb_phone.cash(id uuid primary key,project uuid references public.projects(id),sender uuid not null references public.profiles(id),recipient uuid not null references public.profiles(id),amount bigint not null check(amount>0),status text not null check(status in ('pending','received','cancelled')),note text not null default '',time timestamptz not null default now(),received_at timestamptz);
create table eb_phone.reversals(id uuid primary key,kind text not null check(kind in ('bill','transfer')),reason text not null,actor uuid not null,time timestamptz not null default now());
create table eb_phone.handovers(id uuid primary key,data jsonb not null);
create table eb_phone.events(id uuid primary key default gen_random_uuid(),actor uuid not null,action text not null,target uuid,time timestamptz not null default now(),detail jsonb not null default '{}');
alter table eb_phone.control enable row level security;
alter table eb_phone.meta enable row level security;
alter table eb_phone.replays enable row level security;
alter table eb_phone.cash enable row level security;
alter table eb_phone.reversals enable row level security;
alter table eb_phone.handovers enable row level security;
alter table eb_phone.events enable row level security;
revoke all on all tables in schema eb_phone from public,anon,authenticated;

create function eb_phone.active() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.phone_active)
 and not exists(select 1 from eb_phone.meta m where m.kind='auth' and m.id=auth.uid() and (m.data->>'validAfter')::timestamptz>to_timestamp(coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'iat','0')::double precision))
$$;
-- Restrictive layer keeps existing row ownership policies and additionally rejects inactive/stale sessions.
do $$declare t text;begin
 foreach t in array array['profiles','projects','project_assignments','daily_updates','checkins','money_requests','transfers','expenses','inventory','equipment_requests','inventory_movements','notifications','financial_audit_events'] loop
 execute format('create policy phone_active_session on public.%I as restrictive for all to authenticated using (eb_phone.active()) with check (eb_phone.active())',t);
 end loop;
end $$;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select eb_phone.active() and exists(select 1 from public.profiles where id=auth.uid() and role::text='admin')
$$;
create or replace function public.confirm_transfer_receipt(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare r public.transfers%rowtype;
begin
 if not eb_phone.active() then raise exception 'Active current session required' using errcode='42501';end if;
 select * into r from public.transfers where id=p_id for update;
 if not found or r.supervisor_id<>auth.uid() or r.status<>'pending_receipt' then raise exception 'Transfer unavailable';end if;
 update public.transfers set status='received',received_at=now() where id=p_id;
end $$;

create function eb_phone.actor() returns public.profiles language plpgsql security definer set search_path='' as $$
declare u public.profiles;
begin
 select * into u from public.profiles where id=auth.uid() and phone_active;
 if found and exists(select 1 from eb_phone.meta where kind='auth' and id=u.id and (data->>'validAfter')::timestamptz>to_timestamp(coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'iat','0')::double precision)) then raise exception 'Sign in again after password reset' using errcode='42501';end if;
 if not found then raise exception 'Active account required' using errcode='42501';end if;
 return u;
end $$;
create function eb_phone.balance(s uuid) returns bigint language sql stable set search_path='' as $$
 select (coalesce((select sum(amount*100) from public.transfers t where supervisor_id=s and status='received' and not exists(select 1 from eb_phone.reversals r where r.id=t.id)),0)
 -coalesce((select sum(amount*100) from public.expenses e where supervisor_id=s and status='approved' and not exists(select 1 from eb_phone.reversals r where r.id=e.id)),0)
 +coalesce((select sum(case when recipient=s then amount else -amount end) from eb_phone.cash where status='received' and (sender=s or recipient=s) and not exists(select 1 from eb_phone.reversals r where r.id=cash.id)),0))::bigint
$$;
create function eb_phone.equipment(p uuid default null) returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',z.project_id::text||'_'||z.inventory_id::text,'project',z.project_id,'item',z.inventory_id,'quantity',z.q) order by z.project_id,z.inventory_id),'[]'::jsonb)
 from (select project_id,inventory_id,sum(case when action='issue' then quantity else -quantity end)::int q from public.inventory_movements where p is null or project_id=p group by project_id,inventory_id having sum(case when action='issue' then quantity else -quantity end)>0) z
$$;
create function eb_phone.effective(p uuid) returns uuid language sql stable security definer set search_path='' as $$
 select coalesce((select (data->>'to')::uuid from eb_phone.handovers where data->>'project'=p::text and data->>'status'='complete' and (data->>'temporary')::boolean and (data->>'start')::timestamptz<=now() and now()<(data->>'end')::timestamptz order by data->>'time' desc limit 1),(select supervisor_id from public.project_assignments where project_id=p order by supervisor_id limit 1))
$$;
create or replace function public.assigned_to(p uuid) returns boolean language sql stable security definer set search_path='' as $$
 select eb_phone.active() and eb_phone.effective(p)=auth.uid()
$$;
create function eb_phone.project_access(p uuid,u public.profiles,writing boolean default true) returns void language plpgsql set search_path='' as $$
begin
 if not exists(select 1 from public.projects where id=p) then raise exception 'Project unavailable';end if;
 if u.role::text<>'admin' and eb_phone.effective(p) is distinct from u.id then raise exception 'Project access denied' using errcode='42501';end if;
 if writing and not exists(select 1 from public.projects where id=p and status='ongoing') then raise exception 'Project is not active';end if;
end $$;
create function eb_phone.money(a jsonb,k text default 'amount',allow_zero boolean default false) returns bigint language plpgsql set search_path='' as $$
declare n numeric;
begin
 n=(a->>k)::numeric;
 if n is null or n::text in ('NaN','Infinity','-Infinity') or n<0 or (not allow_zero and n=0) or n>1000000000 or n*100<>trunc(n*100) then raise exception 'Invalid amount';end if;
 return (n*100)::bigint;
end $$;
create function eb_phone.intval(a jsonb,k text,lo integer,hi integer) returns integer language plpgsql set search_path='' as $$
declare n numeric;
begin n=(a->>k)::numeric;if n is null or n::text in ('NaN','Infinity','-Infinity') or n<>trunc(n) or n<lo or n>hi then raise exception 'Invalid %',k;end if;return n::integer;end $$;

create function eb_phone.state() returns jsonb language plpgsql security definer set search_path='' as $$
declare u public.profiles;isad boolean;ad uuid;d jsonb;ps uuid[];us jsonb;
begin
 u=eb_phone.actor();isad=u.role::text='admin';select id into ad from public.profiles where role::text='admin';
 select coalesce(array_agg(id),'{}') into ps from public.projects where isad or eb_phone.effective(projects.id)=u.id;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',display_name,'username',case when isad or id=u.id then (select au.email from auth.users au where au.id=profiles.id) else '' end,'role',role,'active',phone_active,'mustChange',phone_must_change)),'[]') into us from public.profiles where isad or id=u.id or id=ad;
 d=jsonb_build_object('version',3,'revision',(select revision from eb_phone.control where id=1),'queueGeneration',(select generation from eb_phone.control where id=1),'users',us,
 'projects',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'location',p.location,'start',p.start_date,'end',p.end_date,'budget',(p.budget*100)::bigint,'progress',p.progress_pct,'status',p.status,'lat',p.site_lat,'lng',p.site_lng,'radius',coalesce((m.data->>'radius')::int,1000),'supervisor',eb_phone.effective(p.id)) order by p.created_at),'[]') from public.projects p left join eb_phone.meta m on m.kind='project' and m.id=p.id where p.id=any(ps)),
 'requests',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'user',r.supervisor_id,'project',r.project_id,'amount',(r.amount*100)::bigint,'status',r.status,'time',r.created_at,'note',coalesce(m.data->>'note',''),'reason',coalesce(m.data->>'reason','')) order by r.created_at),'[]') from public.money_requests r left join eb_phone.meta m on m.kind='request' and m.id=r.id where isad or r.supervisor_id=u.id),
 'transfers',(select coalesce(jsonb_agg(x order by x->>'time'),'[]') from (
 select jsonb_build_object('id',t.id,'from',ad,'to',t.supervisor_id,'project',t.project_id,'amount',(t.amount*100)::bigint,'status',case when rv.id is not null then 'reversed' when t.status='pending_receipt' then 'pending' else t.status end,'time',t.created_at,'request',t.request_id,'note',coalesce(m.data->>'note',''),'reason',rv.reason) x from public.transfers t left join eb_phone.reversals rv on rv.id=t.id left join eb_phone.meta m on m.kind='transfer' and m.id=t.id where isad or t.supervisor_id=u.id
 union all select jsonb_build_object('id',c.id,'from',c.sender,'to',c.recipient,'project',c.project,'amount',c.amount,'status',case when rv.id is not null then 'reversed' else c.status end,'time',c.time,'note',c.note,'reason',rv.reason) from eb_phone.cash c left join eb_phone.reversals rv on rv.id=c.id where isad or u.id in (c.sender,c.recipient)) ts),
 'bills',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'user',e.supervisor_id,'project',e.project_id,'amount',(e.amount*100)::bigint,'category',e.category,'note',e.description,'date',coalesce(m.data->>'date',to_char(e.created_at at time zone 'Asia/Colombo','YYYY-MM-DD')),'time',e.created_at,'photo',e.bill_path,'reason',coalesce(rv.reason,m.data->>'reason',''),'status',case when rv.id is not null then 'reversed' else e.status end) order by e.created_at),'[]') from public.expenses e left join eb_phone.meta m on m.kind='bill' and m.id=e.id left join eb_phone.reversals rv on rv.id=e.id where isad or e.supervisor_id=u.id),
 'items',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'code',i.code,'kind',i.category,'stock',i.quantity,'missing',i.missing_count,'damaged',coalesce((m.data->>'damaged')::int,0),'total',i.quantity+i.missing_count+coalesce((m.data->>'damaged')::int,0)+coalesce((select sum(case when action='issue' then quantity else -quantity end) from public.inventory_movements where inventory_id=i.id),0)) order by i.code),'[]') from public.inventory i left join eb_phone.meta m on m.kind='item' and m.id=i.id),
 'equipment',(select coalesce(jsonb_agg(e||jsonb_build_object('holder',eb_phone.effective((e->>'project')::uuid))),'[]') from jsonb_array_elements(eb_phone.equipment()) e where isad or (e->>'project')::uuid=any(ps)),
 'stockRequests',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'user',r.supervisor_id,'project',r.project_id,'item',r.inventory_id,'quantity',r.quantity,'kind',r.action,'condition',coalesce(m.data->>'condition','good'),'status',case when r.status='accepted' then 'approved' else r.status end,'time',r.created_at,'reason',coalesce(m.data->>'reason','')) order by r.created_at),'[]') from public.equipment_requests r left join eb_phone.meta m on m.kind='stock' and m.id=r.id where isad or r.supervisor_id=u.id),
 'days',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'user',r.supervisor_id,'project',r.project_id,'workers',r.worker_count,'stage',r.work_stage,'note',r.notes,'time',r.created_at,'photo',r.photo_paths[1],'progress',(m.data->>'progress')::int,'previousProgress',(m.data->>'previousProgress')::int) order by r.created_at),'[]') from public.daily_updates r left join eb_phone.meta m on m.kind='day' and m.id=r.id where isad or r.supervisor_id=u.id),
 'attendance',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'user',r.supervisor_id,'project',r.project_id,'in',r.recorded_at,'out',case when r.next_type='out' then r.next_time else null end,'minutes',case when r.next_type='out' then extract(epoch from r.next_time-r.recorded_at)/60 else 0 end,'offline',r.offline_record,'verification',r.verification_status) order by r.recorded_at),'[]') from (select c.*,lead(recorded_at) over(partition by supervisor_id,project_id order by recorded_at,id) next_time,lead(event_type) over(partition by supervisor_id,project_id order by recorded_at,id) next_type from public.checkins c where isad or c.supervisor_id=u.id) r where r.event_type='in'),
 'handovers',(select coalesce(jsonb_agg(data order by data->>'time'),'[]') from eb_phone.handovers where isad or u.id::text in (data->>'from',data->>'to')),
 'balances',(select coalesce(jsonb_object_agg(id,eb_phone.balance(id)),'{}') from public.profiles where role::text='supervisor' and (isad or id=u.id)),
 'adjustments','[]'::jsonb,'audit',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'user',actor,'action',action,'time',time,'detail',detail) order by time),'[]') from eb_phone.events where isad));
 return jsonb_build_object('user',(select value from jsonb_array_elements(us) where value->>'id'=u.id::text),'data',d,'serverTime',clock_timestamp());
end $$;

create function eb_phone.action(a jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u public.profiles;isad boolean;op text;a_clean jsonb;v_key uuid;cached eb_phone.replays;target uuid;pi uuid;sid uuid;it uuid;q int;amt bigint;rv bigint;ad uuid;p public.projects;r record;b record;h jsonb;before jsonb;eq jsonb;start_at timestamptz;end_at timestamptz;v_condition text;oldq int;result jsonb;v_lat double precision;v_lng double precision;v_acc double precision;v_dist double precision;v_time timestamptz;v_in timestamptz;v_out timestamptz;
begin
 u=eb_phone.actor();isad=u.role::text='admin';op=a->>'op';v_key=(a->>'requestId')::uuid;target=nullif(a->>'id','')::uuid;pi=nullif(a->>'project','')::uuid;
 if v_key is null then raise exception 'Request ID required';end if;
 if u.phone_must_change then raise exception 'Change temporary password first' using errcode='42501';end if;
 perform 1 from eb_phone.control where id=1 for update;
 if a ? 'queuedAt' and a->>'generation' is distinct from (select generation::text from eb_phone.control where id=1) then raise exception 'Old offline queue: review before re-entry';end if;
 a_clean=a-array['requestId','revision','owner','queuedAt','offline','lastError','lastAttempt','generation','password','password2','current'];
 select * into cached from eb_phone.replays where actor=u.id and replays.key=v_key;
 if found then if cached.payload<>a_clean then raise exception 'Request ID reused with different data';end if;return cached.result;end if;
 select id into ad from public.profiles where role::text='admin';
 if op=any(array['project.save','money.send','request.decide','bill.decide','bill.reverse','money.reverse','item.add','item.adjust','stock.decide','handover.create','handover.cancel','attendance.correct','user.active']) and not isad then raise exception 'Admin only' using errcode='42501';end if;
 if op=any(array['money.request','money.return','bill.add','bill.resubmit','stock.request','stock.return','day.add','day.edit','attendance']) and isad then raise exception 'Supervisor account required';end if;
 if op='project.save' then
  if (a->>'revision')::bigint is distinct from (select revision from eb_phone.control where id=1) then raise exception 'Stale data: refresh';end if;
  if length(btrim(coalesce(a->>'name','')))=0 or (a->>'end')::date<(a->>'start')::date then raise exception 'Invalid project name/dates';end if;
  sid=(a->>'supervisor')::uuid;if not exists(select 1 from public.profiles where id=sid and role::text='supervisor' and phone_active) then raise exception 'Active supervisor required';end if;
  if target is not null then
   if exists(select 1 from eb_phone.handovers where data->>'project'=target::text and (data->>'status'='pending' or data->>'status'='complete' and (data->>'temporary')::boolean and (data->>'end')::timestamptz>now())) then raise exception 'Finish handover before editing project';end if;
   if exists(select 1 from public.project_assignments where project_id=target) and (select array_agg(supervisor_id order by supervisor_id) from public.project_assignments where project_id=target) is distinct from array[sid] then raise exception 'Use Handover to replace supervisor';end if;
   select to_jsonb(x) into before from public.projects x where id=target for update;if before is null then raise exception 'Project unavailable';end if;
  else target=gen_random_uuid();end if;
  if a->>'status' not in ('ongoing','hold','done','archived') then raise exception 'Invalid project status';end if;
  perform eb_phone.intval(a,'radius',50,5000);perform eb_phone.intval(a,'progress',0,100);amt=eb_phone.money(a,'budget',true);
  insert into public.projects(id,name,location,start_date,end_date,budget,status,progress_pct,site_lat,site_lng) values(target,btrim(a->>'name'),a->>'location',(a->>'start')::date,(a->>'end')::date,amt/100.0,a->>'status',(a->>'progress')::int,nullif(a->>'lat','')::double precision,nullif(a->>'lng','')::double precision)
  on conflict(id) do update set name=excluded.name,location=excluded.location,start_date=excluded.start_date,end_date=excluded.end_date,budget=excluded.budget,status=excluded.status,progress_pct=excluded.progress_pct,site_lat=excluded.site_lat,site_lng=excluded.site_lng;
  if ((a->>'lat'='') is distinct from (a->>'lng'='')) then raise exception 'Both GPS coordinates required';end if;
  insert into public.project_assignments values(target,sid) on conflict do nothing;
  insert into eb_phone.meta values('project',target,jsonb_build_object('radius',(a->>'radius')::int)) on conflict(kind,id) do update set data=excluded.data;
 elsif op='money.request' then
  perform eb_phone.project_access(pi,u);amt=eb_phone.money(a);target=v_key;insert into public.money_requests(id,project_id,supervisor_id,amount) values(target,pi,u.id,amt/100.0);insert into eb_phone.meta values('request',target,jsonb_build_object('note',left(a->>'note',300)));
 elsif op='request.decide' then
  select to_jsonb(x) into before from public.money_requests x where id=target;
  perform public.admin_decide_money_request(target,(a->>'approve')::boolean is true);
  insert into eb_phone.meta values('request',target,jsonb_build_object('reason',a->>'reason')) on conflict(kind,id) do update set data=eb_phone.meta.data||excluded.data;
 elsif op='money.send' then
  amt=eb_phone.money(a);sid=(a->>'to')::uuid;if pi is not null then perform eb_phone.project_access(pi,u);end if;
  if coalesce(a->>'request','')<>'' then raise exception 'Approved requests already create a pending transfer. Confirm its receipt; do not send twice.';end if;
  if not exists(select 1 from public.profiles where id=sid and phone_active) then raise exception 'Account inactive';end if;
  target=v_key;
  if pi is null then insert into eb_phone.cash(id,sender,recipient,amount,status,note) values(target,u.id,sid,amt,'pending',coalesce(a->>'note',''));
  else if eb_phone.effective(pi) is distinct from sid then raise exception 'Supervisor not assigned';end if;insert into public.transfers(id,project_id,supervisor_id,amount) values(target,pi,sid,amt/100.0);end if;
  insert into eb_phone.meta values('transfer',target,jsonb_build_object('note',a->>'note'));
 elsif op='money.return' then
  if pi is not null then perform eb_phone.project_access(pi,u,false);end if;
  amt=eb_phone.money(a);
  select coalesce(sum(amount),0) into rv from eb_phone.cash where sender=u.id and status='pending';
  rv=rv+coalesce((select sum((data->>'amount')::bigint) from eb_phone.handovers where data->>'from'=u.id::text and data->>'status'='pending'),0);
  if amt>eb_phone.balance(u.id)-rv then raise exception 'Insufficient available balance';end if;
  target=v_key;insert into eb_phone.cash(id,project,sender,recipient,amount,status,note) values(target,pi,u.id,ad,amt,'pending',coalesce(a->>'note',''));
 elsif op='money.receive' then
  select * into r from public.transfers where id=target for update;
  if found then perform public.confirm_transfer_receipt(target);
  else
   select * into r from eb_phone.cash where id=target for update;
   if not found or r.recipient<>u.id or r.status<>'pending' then raise exception 'Transfer unavailable';end if;
   update eb_phone.cash set status='received',received_at=now() where id=target;
  end if;
 elsif op='money.cancel' then
  if length(btrim(coalesce(a->>'reason','')))=0 then raise exception 'Reason required';end if;
  if not isad and not exists(select 1 from eb_phone.cash where id=target and sender=u.id and status='pending') then raise exception 'Own pending cash return required';end if;
  update public.transfers set status='cancelled' where id=target and status='pending_receipt';
  if not found then update eb_phone.cash set status='cancelled' where id=target and status='pending';if not found then raise exception 'Pending transfer unavailable';end if;end if;
 elsif op in ('money.reverse','bill.reverse') then
  if length(btrim(coalesce(a->>'reason','')))=0 then raise exception 'Reason required';end if;
  if op='bill.reverse' and not exists(select 1 from public.expenses where id=target and status='approved') then raise exception 'Approved bill unavailable';end if;
  if op='money.reverse' and not exists(select 1 from public.transfers where id=target and status='received') and not exists(select 1 from eb_phone.cash where id=target and status='received') then raise exception 'Received transfer unavailable';end if;
  insert into eb_phone.reversals(id,kind,actor,reason) values(target,case when op='bill.reverse' then 'bill' else 'transfer' end,u.id,a->>'reason');
 elsif op='bill.add' then
  perform eb_phone.project_access(pi,u);amt=eb_phone.money(a);target=v_key;
  if (a->>'date')::date>(now() at time zone 'Asia/Colombo')::date or length(btrim(coalesce(a->>'note','')))=0 or a->>'category' not in ('labour','materials','equipment','other') then raise exception 'Invalid expense';end if;
  if not coalesce((a->>'confirmDuplicate')::boolean,false) and exists(select 1 from public.expenses e where project_id=pi and supervisor_id=u.id and amount=amt/100.0 and description=a->>'note' and status in ('pending','approved') and not exists(select 1 from eb_phone.reversals where id=e.id)) then raise exception 'Possible duplicate bill: review and confirm';end if;
  if coalesce(a->>'photo','')<>'' and a->>'photo' not like pi::text||'/'||u.id::text||'/bills/%' then raise exception 'Photo owner/path mismatch';end if;
  insert into public.expenses(id,project_id,supervisor_id,amount,category,description,bill_path) values(target,pi,u.id,amt/100.0,a->>'category',a->>'note',nullif(a->>'photo',''));
  insert into eb_phone.meta values('bill',target,jsonb_build_object('date',a->>'date'));
 elsif op='bill.decide' then
  select to_jsonb(x) into before from public.expenses x where id=target;
  perform public.admin_decide_expense(target,(a->>'approve')::boolean is true);
  insert into eb_phone.meta values('bill',target,jsonb_build_object('reason',a->>'reason')) on conflict(kind,id) do update set data=eb_phone.meta.data||excluded.data;
 elsif op='bill.resubmit' then
  select * into r from public.expenses where id=target and supervisor_id=u.id and status='rejected' for update;if not found then raise exception 'Rejected own bill required';end if;
  perform eb_phone.project_access(r.project_id,u);amt=eb_phone.money(a);before=to_jsonb(r);
  if length(btrim(coalesce(a->>'note','')))=0 then raise exception 'Description required';end if;
  update public.expenses set amount=amt/100.0,description=a->>'note',status='pending' where id=target;
 elsif op='item.add' then
  target=v_key;q=eb_phone.intval(a,'quantity',0,1000000);
  if length(btrim(coalesce(a->>'name','')))=0 or length(btrim(coalesce(a->>'code','')))=0 then raise exception 'Item name/code required';end if;
  insert into public.inventory(id,code,name,category,quantity,condition,missing_count) values(target,upper(btrim(a->>'code')),btrim(a->>'name'),a->>'kind',q,'good',0);
 elsif op='item.adjust' then
  q=eb_phone.intval(a,'quantity',1,1000000);v_condition=a->>'kind';if length(btrim(coalesce(a->>'reason','')))=0 then raise exception 'Reason required';end if;
  select * into r from public.inventory where id=target for update;if not found then raise exception 'Item unavailable';end if;before=to_jsonb(r);
  select coalesce((data->>'damaged')::int,0) into oldq from eb_phone.meta where kind='item' and id=target;oldq=coalesce(oldq,0);
  if v_condition='receive' then update public.inventory set quantity=quantity+q where id=target;
  elsif v_condition in ('missing','damaged') then
   if r.quantity<q then raise exception 'Insufficient stock';end if;
   update public.inventory set quantity=quantity-q,missing_count=missing_count+case when v_condition='missing' then q else 0 end where id=target;
   if v_condition='damaged' then oldq=oldq+q;end if;
  elsif v_condition='recover' then
   if r.missing_count<q then raise exception 'Excess recovery';end if;update public.inventory set quantity=quantity+q,missing_count=missing_count-q where id=target;
  elsif v_condition='repair' then
   if oldq<q then raise exception 'Excess repair';end if;oldq=oldq-q;update public.inventory set quantity=quantity+q where id=target;
  else raise exception 'Invalid stock adjustment';end if;
  insert into eb_phone.meta values('item',target,jsonb_build_object('damaged',oldq)) on conflict(kind,id) do update set data=excluded.data;
 elsif op in ('stock.request','stock.return') then
  q=eb_phone.intval(a,'quantity',1,1000000);
  if op='stock.return' then pi=split_part(a->>'equipment','_',1)::uuid;it=split_part(a->>'equipment','_',2)::uuid;else it=(a->>'item')::uuid;end if;
  perform eb_phone.project_access(pi,u,op='stock.request');
  if op='stock.request' then
   if not exists(select 1 from public.inventory where id=it and quantity>=q) then raise exception 'Insufficient stock';end if;
  else
   select coalesce(sum(case when action='issue' then quantity else -quantity end),0) into oldq from public.inventory_movements where project_id=pi and inventory_id=it;
   select coalesce(sum(quantity),0) into rv from public.equipment_requests where project_id=pi and inventory_id=it and action='return' and status='pending';
   if q+rv>oldq then raise exception 'Return exceeds issued quantity';end if;
  end if;
  target=v_key;v_condition=coalesce(a->>'condition','good');if v_condition not in ('good','missing','damaged') then raise exception 'Invalid condition';end if;
  insert into public.equipment_requests(id,project_id,supervisor_id,inventory_id,quantity,action) values(target,pi,u.id,it,q,case when op='stock.request' then 'issue' else 'return' end);
  insert into eb_phone.meta values('stock',target,jsonb_build_object('condition',v_condition));
 elsif op='stock.decide' then
  select * into r from public.equipment_requests where id=target for update;if not found then raise exception 'Request unavailable';end if;
  before=to_jsonb(r);
  if (a->>'approve')::boolean is true and r.action='issue' and eb_phone.effective(r.project_id) is distinct from r.supervisor_id then raise exception 'Supervisor changed: reject request';end if;
  perform public.admin_decide_equipment(target,(a->>'approve')::boolean is true);
  select data->>'condition' into v_condition from eb_phone.meta where kind='stock' and id=target;
  if (a->>'approve')::boolean is true and r.action='return' and v_condition in ('damaged','missing') then
   update public.inventory set quantity=quantity-r.quantity,missing_count=missing_count+case when v_condition='missing' then r.quantity else 0 end where id=r.inventory_id;
   if v_condition='damaged' then insert into eb_phone.meta values('item',r.inventory_id,jsonb_build_object('damaged',r.quantity)) on conflict(kind,id) do update set data=jsonb_set(eb_phone.meta.data,'{damaged}',to_jsonb(coalesce((eb_phone.meta.data->>'damaged')::int,0)+r.quantity));end if;
  end if;
  insert into eb_phone.meta values('stock',target,jsonb_build_object('reason',a->>'reason')) on conflict(kind,id) do update set data=eb_phone.meta.data||excluded.data;
 elsif op in ('day.add','day.edit') then
  if op='day.edit' and (a->>'revision')::bigint is distinct from (select revision from eb_phone.control where id=1) then raise exception 'Stale daily update: refresh';end if;
  if op='day.edit' then select * into r from public.daily_updates where id=target and supervisor_id=u.id for update;if not found then raise exception 'Own update required';end if;pi=r.project_id;before=to_jsonb(r);else target=v_key;end if;
  perform eb_phone.project_access(pi,u);q=eb_phone.intval(a,'workers',0,100000);oldq=eb_phone.intval(a,'progress',0,100);
  if length(btrim(coalesce(a->>'stage','')))=0 then raise exception 'Stage required';end if;
  if op='day.edit' and target is distinct from (select id from public.daily_updates where project_id=pi order by created_at desc,id desc limit 1) then raise exception 'Only latest update can be edited';end if;
  if coalesce(a->>'photo','')<>'' and a->>'photo' not like pi::text||'/'||u.id::text||'/updates/%' then raise exception 'Photo path mismatch';end if;
  select progress_pct into rv from public.projects where id=pi;
  insert into public.daily_updates(id,project_id,supervisor_id,worker_count,work_stage,notes,photo_paths) values(target,pi,u.id,q,a->>'stage',a->>'note',case when coalesce(a->>'photo','')='' then '{}'::text[] else array[a->>'photo'] end)
   on conflict(id) do update set worker_count=excluded.worker_count,work_stage=excluded.work_stage,notes=excluded.notes;
  update public.projects set progress_pct=oldq where id=pi;
  insert into eb_phone.meta values('day',target,jsonb_build_object('progress',oldq,'previousProgress',rv)) on conflict(kind,id) do update set data=excluded.data;
 elsif op='attendance' then
  perform eb_phone.project_access(pi,u,a->>'kind'='in');select * into p from public.projects where id=pi;
  v_lat=(a->>'lat')::double precision;v_lng=(a->>'lng')::double precision;v_acc=(a->>'accuracy')::double precision;
  if a->>'kind' not in ('in','out') or v_lat is null or v_lng is null or v_lat not between -90 and 90 or v_lng not between -180 and 180 or v_acc is null or v_acc not between 0 and 100 or p.site_lat is null or p.site_lng is null then raise exception 'Invalid GPS/event or accuracy > 100m';end if;
  v_time=(a->>'deviceTime')::timestamptz;if v_time is null or v_time>now()+interval '5 minutes' or v_time<now()-interval '7 days' then raise exception 'Timestamp outside sync window';end if;
  select coalesce((data->>'radius')::int,1000) into oldq from eb_phone.meta where kind='project' and id=pi;oldq=coalesce(oldq,1000);
  v_dist=6371000*2*asin(sqrt(least(1.0,greatest(0.0,power(sin(radians(v_lat-p.site_lat)/2),2)+cos(radians(p.site_lat))*cos(radians(v_lat))*power(sin(radians(v_lng-p.site_lng)/2),2)))));
  if v_dist>oldq then raise exception 'Outside site radius';end if;
  select * into r from public.checkins where supervisor_id=u.id order by recorded_at desc,received_at desc,id desc limit 1;
  if found and r.recorded_at>v_time then raise exception 'Attendance events must be synchronized in time order';end if;
  if a->>'kind'='in' and found and r.event_type='in' then raise exception 'Active check-in already exists';end if;
  if a->>'kind'='out' and (not found or r.event_type<>'in' or r.project_id<>pi) then raise exception 'Matching active check-in required';end if;
  target=v_key;insert into public.checkins(id,project_id,supervisor_id,event_type,recorded_at,lat,lng,accuracy_m,offline_record,verification_status,client_event_id) values(target,pi,u.id,a->>'kind',v_time,v_lat,v_lng,v_acc,coalesce((a->>'offline')::boolean,false),case when coalesce((a->>'offline')::boolean,false) then 'offline_unverified' else 'location_checked' end,target);
 elsif op='attendance.correct' then
  select * into r from public.checkins where id=target and event_type='in' for update;if not found then raise exception 'Check-in required';end if;before=to_jsonb(r);
  v_in=(a->>'in')::timestamptz;v_out=(a->>'out')::timestamptz;
  if coalesce(a->>'in','') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' or coalesce(a->>'out','') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' or v_in is null or v_out is null or v_out<v_in or v_out>clock_timestamp() or length(btrim(coalesce(a->>'reason','')))=0 then raise exception 'Valid correction times and reason required';end if;
  select * into b from public.checkins where supervisor_id=r.supervisor_id and project_id=r.project_id and recorded_at>=r.recorded_at and id<>r.id order by recorded_at,received_at,id limit 1 for update;
  if found and b.event_type='out' then update public.checkins set recorded_at=v_out,verification_status='admin_corrected' where id=b.id;
  else insert into public.checkins(project_id,supervisor_id,event_type,recorded_at,lat,lng,accuracy_m,offline_record,verification_status,client_event_id) values(r.project_id,r.supervisor_id,'out',v_out,r.lat,r.lng,r.accuracy_m,false,'admin_corrected',v_key);end if;
  update public.checkins set recorded_at=v_in,verification_status='admin_corrected' where id=target;
 elsif op='handover.create' then
  perform eb_phone.project_access(pi,u);
  start_at=now();end_at=null;
  if coalesce((a->>'temporary')::boolean,false) then
   start_at=(a->>'start')::timestamptz;end_at=(a->>'end')::timestamptz;
   if start_at is null or end_at is null or end_at<=start_at or end_at<=now() then raise exception 'Invalid temporary dates';end if;
  end if;
  if (a->>'revision')::bigint is distinct from (select revision from eb_phone.control where id=1) then raise exception 'Refresh before handover';end if;
  select * into p from public.projects where id=pi for update;
  if (select count(*) from public.project_assignments where project_id=pi)<>1 then raise exception 'Exactly one current Supervisor is required';end if;
  select supervisor_id into sid from public.project_assignments where project_id=pi;
  if sid=(a->>'to')::uuid or not exists(select 1 from public.profiles where id=(a->>'to')::uuid and role::text='supervisor' and phone_active) then raise exception 'Choose another active Supervisor';end if;
  if exists(select 1 from (select distinct on(supervisor_id) event_type,project_id from public.checkins order by supervisor_id,recorded_at desc,received_at desc,id desc) z where z.project_id=pi and z.event_type='in') then raise exception 'Close active attendance before handover';end if;
  if exists(select 1 from eb_phone.handovers where data->>'project'=pi::text and (data->>'status'='pending' or data->>'status'='complete' and (data->>'temporary')::boolean and (data->>'end')::timestamptz>now())) or exists(select 1 from public.equipment_requests where project_id=pi and status='pending') then raise exception 'Resolve pending equipment/handover first';end if;
  amt=eb_phone.money(a,'amount',true);if end_at is not null and amt<>0 then raise exception 'Temporary assignment cash must be zero';end if;
  select coalesce(sum(amount),0) into rv from eb_phone.cash where sender=sid and status='pending';rv=rv+coalesce((select sum((data->>'amount')::bigint) from eb_phone.handovers where data->>'from'=sid::text and data->>'status'='pending'),0);
  if amt>0 and amt>eb_phone.balance(sid)-rv then raise exception 'Insufficient available handover cash';end if;
  if length(btrim(coalesce(a->>'reason','')))=0 then raise exception 'Reason required';end if;
  target=v_key;h=jsonb_build_object('id',target,'project',pi,'from',sid,'to',(a->>'to')::uuid,'amount',amt,'equipment',eb_phone.equipment(pi),'reason',a->>'reason','temporary',end_at is not null,'start',start_at,'end',coalesce(end_at::text,''),'status','pending','time',clock_timestamp());insert into eb_phone.handovers values(target,h);
 elsif op='handover.accept' then
  select data into h from eb_phone.handovers where id=target for update;
  if h is null or h->>'status'<>'pending' or h->>'to'<>u.id::text then raise exception 'Handover unavailable';end if;
  pi=(h->>'project')::uuid;sid=(h->>'from')::uuid;amt=(h->>'amount')::bigint;
  if not exists(select 1 from public.project_assignments where project_id=pi and supervisor_id=sid) or (select count(*) from public.project_assignments where project_id=pi)<>1 then raise exception 'Assignment changed';end if;
  if exists(select 1 from (select distinct on(supervisor_id) event_type,project_id from public.checkins order by supervisor_id,recorded_at desc,received_at desc,id desc) z where z.project_id=pi and z.event_type='in') then raise exception 'Close active attendance before handover';end if;
  if exists(select 1 from public.equipment_requests where project_id=pi and status='pending') or h->'equipment'<>eb_phone.equipment(pi) then raise exception 'Equipment changed: recreate handover';end if;
  select coalesce(sum(amount),0) into rv from eb_phone.cash where sender=sid and status='pending';rv=rv+coalesce((select sum((data->>'amount')::bigint) from eb_phone.handovers where id<>target and data->>'from'=sid::text and data->>'status'='pending'),0);
  if amt>0 and amt>eb_phone.balance(sid)-rv then raise exception 'Insufficient handover cash';end if;
  if (h->>'temporary')::boolean then
   if (h->>'end')::timestamptz<=now() then raise exception 'Temporary assignment expired';end if;
  else
   delete from public.project_assignments where project_id=pi;insert into public.project_assignments values(pi,u.id);
  end if;
  if amt>0 then insert into eb_phone.cash(id,project,sender,recipient,amount,status,note,received_at) values(target,pi,sid,u.id,amt,'received','Handover',now());end if;
  update eb_phone.handovers set data=data||jsonb_build_object('status','complete','acceptedAt',now(),'acceptedBy',u.id) where id=target;
 elsif op='handover.cancel' then
  if length(btrim(coalesce(a->>'reason','')))=0 then raise exception 'Reason required';end if;
  update eb_phone.handovers set data=data||jsonb_build_object('status','cancelled','cancelReason',a->>'reason') where id=target and (data->>'status'='pending' or data->>'status'='complete' and (data->>'temporary')::boolean);if not found then raise exception 'Pending/temporary handover required';end if;
 elsif op='user.active' then
  select * into r from public.profiles where id=target and role::text='supervisor' for update;if not found then raise exception 'Supervisor required';end if;
  if not (a ? 'active') then raise exception 'Desired account state required';end if;
  if not (a->>'active')::boolean then
   if exists(select 1 from public.project_assignments where supervisor_id=target) or eb_phone.balance(target)<>0 or exists(select 1 from public.transfers where supervisor_id=target and status='pending_receipt') or exists(select 1 from public.money_requests where supervisor_id=target and status='pending') or exists(select 1 from public.expenses where supervisor_id=target and status='pending') or exists(select 1 from eb_phone.handovers where (data->>'status'='pending' or data->>'status'='complete' and (data->>'temporary')::boolean and (data->>'end')::timestamptz>now()) and target::text in (data->>'from',data->>'to')) then raise exception 'Settle assignments, cash and pending records first';end if;
  end if;
  before=to_jsonb(r);update public.profiles set phone_active=(a->>'active')::boolean where id=target;
 else raise exception 'Unsupported operation: %',op;
 end if;
 insert into eb_phone.events(actor,action,target,detail) values(u.id,op,target,jsonb_build_object('input',a_clean,'before',before));
 update eb_phone.control set revision=revision+1 where id=1 returning revision into rv;
 result=jsonb_build_object('ok',true,'id',target,'revision',rv);insert into eb_phone.replays values(u.id,v_key,a_clean,result);return result;
end $$;

-- Service-only credential invalidation marker. Called only after Auth Admin verifies/changes credentials.
grant usage on schema eb_phone to service_role;
grant select(id,role,phone_active,phone_must_change),update(phone_must_change) on public.profiles to service_role;
grant select,insert,update on eb_phone.meta to service_role;
create function public.phone_auth_stamp(p_target uuid,p_clear_temp boolean) returns void language plpgsql security invoker set search_path='' as $$
begin
 insert into eb_phone.meta(kind,id,data) values('auth',p_target,jsonb_build_object('validAfter',to_timestamp(floor(extract(epoch from clock_timestamp()))+1))) on conflict(kind,id) do update set data=excluded.data;
 if p_clear_temp then update public.profiles set phone_must_change=false where id=p_target;end if;
end $$;
revoke all on function public.phone_auth_stamp(uuid,boolean) from public,anon,authenticated;
grant execute on function public.phone_auth_stamp(uuid,boolean) to service_role;

create function public.phone_state() returns jsonb language sql security invoker set search_path='' as $$ select eb_phone.state() $$;
create function public.phone_action(a jsonb) returns jsonb language sql security invoker set search_path='' as $$ select eb_phone.action(a) $$;
revoke all on all functions in schema eb_phone from public,anon,authenticated;
grant execute on function eb_phone.state(),eb_phone.action(jsonb),eb_phone.active() to authenticated;
revoke all on function public.phone_state(),public.phone_action(jsonb) from public,anon;
grant execute on function public.phone_state(),public.phone_action(jsonb) to authenticated;
