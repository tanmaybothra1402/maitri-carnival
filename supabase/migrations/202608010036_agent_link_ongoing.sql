-- 202608010036_agent_link_ongoing.sql
--
-- Checkpoint 3.5b — make customers.agent → customer_crm.agent_id an ONGOING link.
-- Migration 032 was a ONE-TIME backfill; nothing keeps the link current, so at the
-- next exhibition a buyer who names an agent at registration gets free text and NO
-- agent_id, and the CRM shows blank for them — the same bug, recurring on day one.
-- Backfills nothing (all 406 existing links are already correct and verified).
--
-- CHOICE: a TRIGGER on public.customers, not a change to the registration RPC.
-- The writers of customers.agent are: (1) the auth.users→customers registration insert
-- (from user_metadata.agent), (2) the Google-Sheet mirror (data-sync writes agent
-- directly, service-role, bypassing every RPC), (3) crm_set_agent (the CRM edit path).
-- An RPC/Edge change would catch registration but MISS the Sheet mirror — a staff edit
-- in the Sheet would set agent text with no agent_id, i.e. the bug again. A row-level
-- trigger on customers catches ALL THREE writers plus any direct SQL, and ships as a
-- migration alone (no admin-api / customer-auth change — those are credential-blocked).
--
-- ONE resolve-or-create definition (C3): agent_resolve_or_create() is the single
-- canonical-key + blank-list resolver; both crm_set_agent and the trigger call it.

-- ── the single resolver (canonical key + 032's blank list) ───────────────────
-- Resolve a free-text agent to a canonical agents.id, creating the agent if the
-- canonical key is new. Empty, punctuation-only, and 032's junk list all return NULL
-- and create NOTHING. Canonical key = regexp_replace(upper(x),'[^A-Z0-9]','','g'),
-- identical to migrations 031/033 and the unique agents.name_key index.
create or replace function public.agent_resolve_or_create(p_name text, p_actor uuid default null)
returns uuid
language plpgsql security definer set search_path to 'public' as $$
declare v_name text := btrim(coalesce(p_name,'')); v_key text; v_id uuid;
begin
  if v_name = '' then return null; end if;
  v_key := regexp_replace(upper(v_name), '[^A-Z0-9]', '', 'g');
  if v_key = '' then return null; end if;  -- punctuation/whitespace only
  -- 032's blank list (migration 202608010032 line 73), canonicalised. Junk answers
  -- meaning "no agent" resolve to NULL and never create an agent row. The two entries
  -- ending in digits are the two phone numbers buyers typed into the agent field.
  if v_key in ('NA','NIL','NO','NOAGENT','XXX','NEW','NEWPARTY','AGENCY','9779827492058','0477190772') then
    return null;
  end if;
  select id into v_id from public.agents where name_key = v_key;
  if v_id is null then
    insert into public.agents(name, created_by) values (v_name, p_actor)
      on conflict (name_key) do nothing returning id into v_id;
    if v_id is null then select id into v_id from public.agents where name_key = v_key; end if;
  end if;
  return v_id;
end $$;
revoke all on function public.agent_resolve_or_create(text, uuid) from public, anon, authenticated;
grant execute on function public.agent_resolve_or_create(text, uuid) to service_role;

-- ── crm_set_agent restated to reuse the resolver (signature unchanged) ────────
-- Same (uuid, text, uuid) signature and {ok, agentId} return shape, so admin-api's
-- crmSetAgent handler is UNCHANGED. Behaviour is now: empty OR junk -> no agent (was:
-- junk would create a spurious agent row); a real name resolves-or-creates as before.
create or replace function public.crm_set_agent(p_customer_id uuid, p_agent_name text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_name text := btrim(coalesce(p_agent_name,'')); v_id uuid;
begin
  v_id := public.agent_resolve_or_create(v_name, p_actor);
  insert into public.customer_crm (customer_id, agent_id, crm_updated_at, crm_updated_by)
    values (p_customer_id, v_id, now(), p_actor)
    on conflict (customer_id) do update set agent_id=v_id, crm_updated_at=now(), crm_updated_by=p_actor;
  -- keep the buyer-visible free-text agent in sync with the canonical name (the
  -- dashboard/directory read it); '' when there is no resolved agent.
  update public.customers set agent=coalesce((select name from public.agents where id=v_id),''), updated_at=now()
    where id=p_customer_id;
  insert into public.customer_crm_log(customer_id, actor_id, field, new_value)
    values (p_customer_id, p_actor, 'agent', v_name);
  return jsonb_build_object('ok', true, 'agentId', v_id);
end $$;
revoke all on function public.crm_set_agent(uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.crm_set_agent(uuid,text,uuid) to service_role;

-- ── the trigger: resolve customers.agent -> customer_crm.agent_id on every write ─
-- Writes ONLY customer_crm (never customers), so no recursion. Skips creating an
-- empty customer_crm row when there is no agent (only clears an existing link).
create or replace function public.tg_sync_customer_agent() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid;
begin
  v_id := public.agent_resolve_or_create(NEW.agent, null);
  if v_id is not null then
    insert into public.customer_crm (customer_id, agent_id)
      values (NEW.id, v_id)
      on conflict (customer_id) do update set agent_id = excluded.agent_id;
  else
    update public.customer_crm set agent_id = null where customer_id = NEW.id and agent_id is not null;
  end if;
  return null;
end $$;

drop trigger if exists trg_sync_customer_agent on public.customers;
create trigger trg_sync_customer_agent
  after insert or update of agent on public.customers
  for each row execute function public.tg_sync_customer_agent();
