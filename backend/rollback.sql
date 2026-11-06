-- First publish the previous frontend. Keep all new records; do not drop the schema.
BEGIN;
CREATE OR REPLACE FUNCTION public.assigned_to(p uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(select 1 from public.project_assignments where project_id = p and supervisor_id = (select auth.uid()));
$function$
;
REVOKE EXECUTE ON FUNCTION public.phone_state(),public.phone_action(jsonb) FROM public,anon,authenticated;
DO $$ DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['profiles','projects','project_assignments','daily_updates','checkins','money_requests','transfers','expenses','inventory','equipment_requests','inventory_movements','notifications','financial_audit_events'] LOOP
 EXECUTE format('DROP POLICY IF EXISTS phone_active_session ON public.%I',t);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.confirm_transfer_receipt(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.transfers%rowtype;
begin
 select * into r from public.transfers where id=p_id for update;
 if not found or r.supervisor_id <> (select auth.uid()) or r.status <> 'pending_receipt'
 then raise exception 'Transfer unavailable'; end if;
 update public.transfers set status='received',received_at=now() where id=p_id;
end $function$;
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(select 1 from public.profiles where id = (select auth.uid()) and role = 'admin');
$function$;
COMMIT;
-- Columns and eb_phone records are retained for recovery. Permanent handovers already confirmed
-- must be reviewed individually; never bulk-delete financial history.

