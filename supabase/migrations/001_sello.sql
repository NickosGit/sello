-- =============================================================================
-- Sello · 001_sello.sql
-- Paste into the Supabase SQL editor and run once.
--
-- Core rule: only Postgres decides a claim's status. The app, the API routes
-- and the AI can only *request* a change through the security-definer
-- functions below. Every status change writes an append-only event.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- Types
-- -----------------------------------------------------------------------------
create type public.claim_status as enum ('DECLARED', 'VOUCHED', 'VERIFIED');
create type public.decision_kind as enum ('advance', 'request_more', 'do_not_advance');

-- Fixed written criteria for independent review (the worker cannot weaken them).
create function public.review_criteria() returns text
language sql immutable set search_path = '' as $$
  select 'Criterios de revisión de Sello: '
      || '1) Revisa solo la evidencia y el enlace que la persona dio. '
      || '2) Verifica una frase solo si la evidencia muestra que la persona lo hizo. '
      || '3) Escribe el alcance: qué revisaste exactamente. '
      || '4) Escribe qué NO se puede concluir con esa evidencia. '
      || '5) Si la evidencia no alcanza, declina y explica por qué.'
$$;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  display_name      text check (display_name is null or char_length(display_name) <= 80),
  is_reviewer       boolean not null default false,
  reviewer_approved boolean not null default false,
  created_at        timestamptz not null default now()
);

create table public.proofs (
  id                      uuid primary key default gen_random_uuid(),
  owner_id                uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title                   text not null check (char_length(title) between 3 and 120),
  raw_evidence            text not null check (char_length(raw_evidence) between 20 and 4000),
  evidence_link           text check (evidence_link is null
                                      or (char_length(evidence_link) <= 500 and evidence_link ~* '^https?://')),
  intended_decision_maker text check (intended_decision_maker is null or char_length(intended_decision_maker) <= 120),
  intended_decision       text check (intended_decision is null or char_length(intended_decision) <= 200),
  is_demo                 boolean not null default true,
  created_at              timestamptz not null default now()
);
create index proofs_owner_idx on public.proofs (owner_id);

create table public.ai_drafts (
  id              uuid primary key default gen_random_uuid(),
  proof_id        uuid not null references public.proofs (id) on delete cascade,
  payload         jsonb not null check (pg_column_size(payload) <= 65536),
  overclaim_flags jsonb not null default '[]'::jsonb check (pg_column_size(overclaim_flags) <= 16384),
  simulated       boolean not null,
  created_at      timestamptz not null default now()
);
create index ai_drafts_proof_idx on public.ai_drafts (proof_id);

-- Claims cannot be deleted (no policy) and block proof deletion (restrict):
-- once a claim exists it is part of the record.
create table public.claims (
  id            uuid primary key default gen_random_uuid(),
  proof_id      uuid not null references public.proofs (id) on delete restrict,
  text          text not null check (char_length(text) between 3 and 400),
  scope         text check (scope is null or char_length(scope) <= 800),
  conditions    text check (conditions is null or char_length(conditions) <= 800),
  ai_assistance text check (ai_assistance is null or char_length(ai_assistance) <= 800),
  revisions     text check (revisions is null or char_length(revisions) <= 800),
  missing_info  text check (missing_info is null or char_length(missing_info) <= 800),
  cannot_infer  text check (cannot_infer is null or char_length(cannot_infer) <= 800),
  status        public.claim_status not null default 'DECLARED',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index claims_proof_idx on public.claims (proof_id);

create table public.review_requests (
  id                    uuid primary key default gen_random_uuid(),
  proof_id              uuid not null references public.proofs (id) on delete cascade,
  reviewer_id           uuid references auth.users (id),
  no_prior_relationship boolean not null default false,
  criteria              text not null default public.review_criteria()
                        check (char_length(criteria) between 10 and 2000),
  status                text not null default 'open' check (status in ('open', 'claimed', 'done')),
  claimed_at            timestamptz,
  created_at            timestamptz not null default now()
);
create unique index review_requests_one_active_per_proof
  on public.review_requests (proof_id) where status <> 'done';
create index review_requests_reviewer_idx on public.review_requests (reviewer_id);

create table public.vouch_invites (
  id         uuid primary key default gen_random_uuid(),
  proof_id   uuid not null references public.proofs (id) on delete cascade,
  token      text not null unique default encode(extensions.gen_random_bytes(24), 'hex'),
  used       boolean not null default false,
  used_by    uuid references auth.users (id),
  used_at    timestamptz,
  created_at timestamptz not null default now()
);
create index vouch_invites_proof_idx on public.vouch_invites (proof_id);

create table public.vouches (
  id            uuid primary key default gen_random_uuid(),
  claim_id      uuid not null references public.claims (id) on delete restrict,
  voucher_id    uuid not null references auth.users (id),
  relationship  text not null check (char_length(relationship) between 2 and 120),
  what_they_saw text not null check (char_length(what_they_saw) between 20 and 800),
  created_at    timestamptz not null default now(),
  unique (claim_id, voucher_id)
);

-- Append-only provenance log. Only the definer functions/triggers write here.
create table public.status_events (
  id          uuid primary key default gen_random_uuid(),
  claim_id    uuid not null references public.claims (id) on delete restrict,
  from_status public.claim_status,
  to_status   public.claim_status not null,
  actor_id    uuid,
  actor_role  text not null check (actor_role in ('worker', 'voucher', 'reviewer', 'system')),
  reason      text check (reason is null or char_length(reason) <= 1000),
  created_at  timestamptz not null default now()
);
create index status_events_claim_idx on public.status_events (claim_id, created_at);

create table public.share_links (
  id                   uuid primary key default gen_random_uuid(),
  proof_id             uuid not null references public.proofs (id) on delete cascade,
  token                text not null unique default encode(extensions.gen_random_bytes(24), 'hex'),
  decision_maker_label text not null check (char_length(decision_maker_label) between 2 and 120),
  intended_decision    text not null check (char_length(intended_decision) between 3 and 200),
  opened_at            timestamptz,
  decision             public.decision_kind,
  decision_note        text check (decision_note is null or char_length(decision_note) <= 500),
  decided_at           timestamptz,
  flag                 text check (flag in ('no_inspection', 'no_action')),
  created_at           timestamptz not null default now()
);
create index share_links_proof_idx on public.share_links (proof_id);

-- -----------------------------------------------------------------------------
-- Helpers used by RLS policies (security definer avoids policy recursion).
-- Each one only answers a yes/no question about the *caller*.
-- -----------------------------------------------------------------------------
create function public.is_proof_owner(p_proof_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from proofs where id = p_proof_id and owner_id = auth.uid())
$$;

create function public.is_assigned_reviewer(p_proof_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from review_requests
    where proof_id = p_proof_id and reviewer_id = auth.uid() and status in ('claimed', 'done')
  )
$$;

create function public.has_vouch_access(p_proof_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from vouch_invites where proof_id = p_proof_id and used and used_by = auth.uid()
  )
$$;

create function public.is_approved_reviewer() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and reviewer_approved)
$$;

-- True when the current statement runs as a signed-in or anonymous API user
-- (as opposed to inside a definer function, which runs as the table owner).
create function public.is_api_role() returns boolean
language sql stable set search_path = '' as $$
  select current_user in ('authenticated', 'anon')
$$;

-- -----------------------------------------------------------------------------
-- Profiles: auto-create on signup; users cannot approve themselves.
-- -----------------------------------------------------------------------------
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)), 80)
  )
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.profiles_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.id is distinct from old.id or new.created_at is distinct from old.created_at then
    raise exception using message = 'sello:profile_immutable_field';
  end if;
  if public.is_api_role() and new.reviewer_approved is distinct from old.reviewer_approved then
    raise exception using message = 'sello:reviewer_approval_is_manual';
  end if;
  return new;
end $$;

create trigger profiles_guard before update on public.profiles
  for each row execute function public.profiles_guard();

-- -----------------------------------------------------------------------------
-- Proofs: evidence is frozen once any claim is VOUCHED or VERIFIED
-- (otherwise a worker could swap the evidence after it was inspected).
-- -----------------------------------------------------------------------------
create function public.proofs_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.owner_id is distinct from old.owner_id or new.created_at is distinct from old.created_at then
    raise exception using message = 'sello:proof_immutable_field';
  end if;
  if (new.title, new.raw_evidence, new.evidence_link)
       is distinct from (old.title, old.raw_evidence, old.evidence_link)
     and exists (select 1 from claims where proof_id = old.id and status <> 'DECLARED') then
    raise exception using message = 'sello:proof_locked';
  end if;
  return new;
end $$;

create trigger proofs_guard before update on public.proofs
  for each row execute function public.proofs_guard();

-- -----------------------------------------------------------------------------
-- Claims: status enforcement (the core of the slice)
-- -----------------------------------------------------------------------------
create function public.claims_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.status := 'DECLARED';           -- whatever was sent
  new.created_at := now();
  new.updated_at := now();
  return new;
end $$;

create function public.claims_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into status_events (claim_id, from_status, to_status, actor_id, actor_role, reason)
  values (new.id, null, 'DECLARED', auth.uid(), 'worker', 'Aprobado por quien hizo el trabajo');
  return null;
end $$;

create trigger claims_before_insert before insert on public.claims
  for each row execute function public.claims_before_insert();
create trigger claims_after_insert after insert on public.claims
  for each row execute function public.claims_after_insert();

create function public.claims_guard_update() returns trigger
language plpgsql set search_path = public as $$
declare
  -- The flag alone is not enough: an API user could set it themselves.
  -- A real transition runs inside a definer function, i.e. not as an API role.
  in_transition boolean :=
    coalesce(current_setting('sello.transition', true), '') = 'on' and not public.is_api_role();
begin
  if new.id is distinct from old.id
     or new.proof_id is distinct from old.proof_id
     or new.created_at is distinct from old.created_at then
    raise exception using message = 'sello:claim_immutable_field';
  end if;

  if new.status is distinct from old.status and not in_transition then
    raise exception 'status can only change through transition functions';
  end if;

  if not in_transition
     and old.status <> 'DECLARED'
     and (new.text, new.scope, new.conditions, new.ai_assistance, new.revisions, new.missing_info, new.cannot_infer)
         is distinct from
         (old.text, old.scope, old.conditions, old.ai_assistance, old.revisions, old.missing_info, old.cannot_infer) then
    raise exception using message = 'sello:claim_locked';
  end if;

  new.updated_at := now();
  return new;
end $$;

create trigger claims_guard_update before update on public.claims
  for each row execute function public.claims_guard_update();

-- status_events: append-only, and only writable from definer context.
create function public.status_events_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception using message = 'sello:status_events_append_only';
  end if;
  if public.is_api_role() then
    raise exception using message = 'sello:status_events_definer_only';
  end if;
  return new;
end $$;

create trigger status_events_guard before insert or update or delete on public.status_events
  for each row execute function public.status_events_guard();

-- -----------------------------------------------------------------------------
-- Insert guards: tokens are always random; metrics start empty.
-- -----------------------------------------------------------------------------
create function public.share_links_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.token := encode(extensions.gen_random_bytes(24), 'hex');
  new.opened_at := null;
  new.decision := null;
  new.decision_note := null;
  new.decided_at := null;
  new.flag := null;
  new.created_at := now();
  return new;
end $$;

create trigger share_links_before_insert before insert on public.share_links
  for each row execute function public.share_links_before_insert();

create function public.vouch_invites_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.token := encode(extensions.gen_random_bytes(24), 'hex');
  new.used := false;
  new.used_by := null;
  new.used_at := null;
  new.created_at := now();
  return new;
end $$;

create trigger vouch_invites_before_insert before insert on public.vouch_invites
  for each row execute function public.vouch_invites_before_insert();

create function public.review_requests_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.status := 'open';
  new.reviewer_id := null;
  new.no_prior_relationship := false;
  new.claimed_at := null;
  new.criteria := public.review_criteria();
  new.created_at := now();
  return new;
end $$;

create trigger review_requests_before_insert before insert on public.review_requests
  for each row execute function public.review_requests_before_insert();

-- Reviewers claim a request with a plain UPDATE (RLS); this guards the transition.
create function public.review_requests_guard_update() returns trigger
language plpgsql set search_path = public as $$
begin
  if not public.is_api_role() then
    return new;
  end if;

  if new.proof_id is distinct from old.proof_id
     or new.criteria is distinct from old.criteria
     or new.created_at is distinct from old.created_at then
    raise exception using message = 'sello:review_request_immutable_field';
  end if;

  if old.status = 'open' and new.status = 'claimed' then
    if new.reviewer_id is distinct from auth.uid() or not new.no_prior_relationship then
      raise exception using message = 'sello:claim_requires_no_prior_relationship';
    end if;
    if public.is_proof_owner(new.proof_id) then
      raise exception using message = 'sello:reviewer_is_owner';
    end if;
    if public.has_vouch_access(new.proof_id)
       or exists (select 1 from vouches v join claims c on c.id = v.claim_id
                  where c.proof_id = new.proof_id and v.voucher_id = auth.uid()) then
      raise exception using message = 'sello:reviewer_conflict_of_interest';
    end if;
    new.claimed_at := now();
    return new;
  end if;

  if old.status = 'claimed' and new.status = 'done'
     and old.reviewer_id = auth.uid()
     and new.reviewer_id = old.reviewer_id
     and new.no_prior_relationship = old.no_prior_relationship then
    return new;
  end if;

  raise exception using message = 'sello:review_request_transition';
end $$;

create trigger review_requests_guard_update before update on public.review_requests
  for each row execute function public.review_requests_guard_update();

-- -----------------------------------------------------------------------------
-- Transition functions
-- -----------------------------------------------------------------------------

-- Voucher opens an invite link: marks it used by them (single use).
create function public.accept_vouch_invite(p_token text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  inv vouch_invites;
  v_owner uuid;
begin
  if auth.uid() is null then
    raise exception using message = 'sello:not_signed_in';
  end if;
  if p_token is null or p_token !~ '^[0-9a-f]{48}$' then
    raise exception using message = 'sello:invite_not_found';
  end if;

  select * into inv from vouch_invites where token = p_token for update;
  if not found then
    raise exception using message = 'sello:invite_not_found';
  end if;

  select owner_id into v_owner from proofs where id = inv.proof_id;
  if v_owner = auth.uid() then
    raise exception using message = 'sello:own_invite';
  end if;
  if exists (select 1 from review_requests where proof_id = inv.proof_id and reviewer_id = auth.uid()) then
    raise exception using message = 'sello:reviewer_conflict_of_interest';
  end if;

  if inv.used then
    if inv.used_by = auth.uid() then
      return inv.proof_id;
    end if;
    raise exception using message = 'sello:invite_used';
  end if;

  update vouch_invites set used = true, used_by = auth.uid(), used_at = now() where id = inv.id;
  return inv.proof_id;
end $$;

create function public.vouch_claim(p_claim_id uuid, p_relationship text, p_what_they_saw text)
returns public.claim_status
language plpgsql security definer set search_path = public as $$
declare
  c claims;
  v_owner uuid;
  v_rel text := btrim(coalesce(p_relationship, ''));
  v_saw text := btrim(coalesce(p_what_they_saw, ''));
begin
  if auth.uid() is null then
    raise exception using message = 'sello:not_signed_in';
  end if;

  select * into c from claims where id = p_claim_id for update;
  if not found then
    raise exception using message = 'sello:claim_not_found';
  end if;

  select owner_id into v_owner from proofs where id = c.proof_id;
  if v_owner = auth.uid() then
    raise exception using message = 'sello:cannot_vouch_own_claim';
  end if;
  if not exists (select 1 from vouch_invites
                 where proof_id = c.proof_id and used and used_by = auth.uid()) then
    raise exception using message = 'sello:no_invite';
  end if;
  if exists (select 1 from review_requests where proof_id = c.proof_id and reviewer_id = auth.uid()) then
    raise exception using message = 'sello:reviewer_conflict_of_interest';
  end if;
  if char_length(v_rel) not between 2 and 120 then
    raise exception using message = 'sello:relationship_length';
  end if;
  if char_length(v_saw) not between 20 and 800 then
    raise exception using message = 'sello:what_they_saw_length';
  end if;
  if c.status <> 'DECLARED' then
    raise exception using message = 'sello:only_declared_can_be_vouched';
  end if;

  perform set_config('sello.transition', 'on', true);
  update claims set status = 'VOUCHED' where id = c.id;
  insert into vouches (claim_id, voucher_id, relationship, what_they_saw)
  values (c.id, auth.uid(), v_rel, v_saw);
  insert into status_events (claim_id, from_status, to_status, actor_id, actor_role, reason)
  values (c.id, 'DECLARED', 'VOUCHED', auth.uid(), 'voucher', v_rel || ': ' || v_saw);
  perform set_config('sello.transition', 'off', true);

  return 'VOUCHED';
end $$;

-- Shared reviewer checks. Internal: not granted to any API role.
create function public._assert_independent_reviewer(p_proof_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
begin
  if auth.uid() is null then
    raise exception using message = 'sello:not_signed_in';
  end if;
  if not exists (select 1 from profiles where id = auth.uid() and reviewer_approved) then
    raise exception using message = 'sello:reviewer_not_approved';
  end if;

  select owner_id into v_owner from proofs where id = p_proof_id;
  if v_owner = auth.uid() then
    raise exception using message = 'sello:reviewer_is_owner';
  end if;

  if exists (select 1 from vouches v join claims c on c.id = v.claim_id
             where c.proof_id = p_proof_id and v.voucher_id = auth.uid())
     or exists (select 1 from vouch_invites
                where proof_id = p_proof_id and used_by = auth.uid()) then
    raise exception using message = 'sello:reviewer_conflict_of_interest';
  end if;

  if not exists (select 1 from review_requests
                 where proof_id = p_proof_id
                   and reviewer_id = auth.uid()
                   and no_prior_relationship
                   and status = 'claimed') then
    raise exception using message = 'sello:review_not_claimed';
  end if;
end $$;

create function public.verify_claim(p_claim_id uuid, p_scope text, p_cannot_infer text, p_reason text)
returns public.claim_status
language plpgsql security definer set search_path = public as $$
declare
  c claims;
  v_scope text := btrim(coalesce(p_scope, ''));
  v_cannot text := btrim(coalesce(p_cannot_infer, ''));
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  select * into c from claims where id = p_claim_id for update;
  if not found then
    raise exception using message = 'sello:claim_not_found';
  end if;

  perform _assert_independent_reviewer(c.proof_id);

  if char_length(v_scope) not between 10 and 800 then
    raise exception using message = 'sello:scope_required';
  end if;
  if char_length(v_cannot) not between 10 and 800 then
    raise exception using message = 'sello:cannot_infer_required';
  end if;
  if char_length(v_reason) not between 10 and 800 then
    raise exception using message = 'sello:reason_required';
  end if;
  if c.status not in ('DECLARED', 'VOUCHED') then
    raise exception using message = 'sello:already_verified';
  end if;

  perform set_config('sello.transition', 'on', true);
  update claims set status = 'VERIFIED', scope = v_scope, cannot_infer = v_cannot where id = c.id;
  insert into status_events (claim_id, from_status, to_status, actor_id, actor_role, reason)
  values (c.id, c.status, 'VERIFIED', auth.uid(), 'reviewer', v_reason);
  perform set_config('sello.transition', 'off', true);

  return 'VERIFIED';
end $$;

create function public.decline_claim(p_claim_id uuid, p_reason text)
returns public.claim_status
language plpgsql security definer set search_path = public as $$
declare
  c claims;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  select * into c from claims where id = p_claim_id for update;
  if not found then
    raise exception using message = 'sello:claim_not_found';
  end if;

  perform _assert_independent_reviewer(c.proof_id);

  if char_length(v_reason) not between 10 and 800 then
    raise exception using message = 'sello:reason_required';
  end if;
  if c.status not in ('DECLARED', 'VOUCHED') then
    raise exception using message = 'sello:already_verified';
  end if;

  insert into status_events (claim_id, from_status, to_status, actor_id, actor_role, reason)
  values (c.id, c.status, c.status, auth.uid(), 'reviewer', v_reason);

  return c.status;
end $$;

create function public.retract_verification(p_claim_id uuid, p_reason text)
returns public.claim_status
language plpgsql security definer set search_path = public as $$
declare
  c claims;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  select * into c from claims where id = p_claim_id for update;
  if not found then
    raise exception using message = 'sello:claim_not_found';
  end if;

  perform _assert_independent_reviewer(c.proof_id);

  if char_length(v_reason) not between 10 and 800 then
    raise exception using message = 'sello:reason_required';
  end if;
  if c.status <> 'VERIFIED' then
    raise exception using message = 'sello:not_verified';
  end if;

  perform set_config('sello.transition', 'on', true);
  update claims set status = 'DECLARED' where id = c.id;
  insert into status_events (claim_id, from_status, to_status, actor_id, actor_role, reason)
  values (c.id, 'VERIFIED', 'DECLARED', auth.uid(), 'reviewer', v_reason);
  perform set_config('sello.transition', 'off', true);

  return 'DECLARED';
end $$;

-- Open review requests with the minimum a reviewer needs to decide whether they
-- know the worker. Empty for anyone who is not an approved reviewer.
create function public.list_open_review_requests()
returns table (id uuid, created_at timestamptz, criteria text, proof_title text, worker_name text, n_claims integer)
language sql stable security definer set search_path = public as $$
  select rr.id, rr.created_at, rr.criteria, p.title, pr.display_name,
         (select count(*)::int from claims c where c.proof_id = p.id)
  from review_requests rr
  join proofs p on p.id = rr.proof_id
  left join profiles pr on pr.id = p.owner_id
  where rr.status = 'open'
    and public.is_approved_reviewer()
    and p.owner_id <> auth.uid()
  order by rr.created_at
$$;

-- -----------------------------------------------------------------------------
-- Share links (granted to anon)
-- -----------------------------------------------------------------------------
create function public.open_share_link(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  l share_links;
  p proofs;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{48}$' then
    return null;
  end if;

  select * into l from share_links where token = p_token for update;
  if not found then
    return null;
  end if;
  select * into p from proofs where id = l.proof_id;

  -- Set once. The owner previewing their own link does not count as "opened".
  if l.opened_at is null and auth.uid() is distinct from p.owner_id then
    update share_links set opened_at = now() where id = l.id returning * into l;
  end if;

  return jsonb_build_object(
    'title', p.title,
    'is_demo', p.is_demo,
    'worker_name', (select display_name from profiles where id = p.owner_id),
    'decision_maker_label', l.decision_maker_label,
    'intended_decision', l.intended_decision,
    'opened_at', l.opened_at,
    'decision', l.decision,
    'decided_at', l.decided_at,
    'ai_organized', exists (select 1 from ai_drafts where proof_id = p.id),
    'is_owner', auth.uid() is not distinct from p.owner_id,
    'claims', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'text', c.text,
               'status', c.status,
               'scope', c.scope,
               'conditions', c.conditions,
               'ai_assistance', c.ai_assistance,
               'missing_info', c.missing_info,
               'cannot_infer', c.cannot_infer,
               'events', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'from', e.from_status, 'to', e.to_status,
                          'actor_role', e.actor_role, 'reason', e.reason, 'at', e.created_at)
                        order by e.created_at)
                 from status_events e where e.claim_id = c.id), '[]'::jsonb))
             order by c.created_at)
      from claims c where c.proof_id = p.id), '[]'::jsonb)
  );
end $$;

create function public.record_decision(p_token text, p_decision text, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  l share_links;
  v_owner uuid;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if p_token is null or p_token !~ '^[0-9a-f]{48}$' then
    raise exception using message = 'sello:link_not_found';
  end if;

  select * into l from share_links where token = p_token for update;
  if not found then
    raise exception using message = 'sello:link_not_found';
  end if;

  select owner_id into v_owner from proofs where id = l.proof_id;
  if v_owner is not distinct from auth.uid() then
    raise exception using message = 'sello:own_link';
  end if;
  if l.opened_at is null then
    raise exception using message = 'sello:not_opened';
  end if;
  if l.decided_at is not null then
    raise exception using message = 'sello:already_decided';
  end if;
  if p_decision is null or p_decision not in ('advance', 'request_more', 'do_not_advance') then
    raise exception using message = 'sello:bad_decision';
  end if;
  if v_note is not null and char_length(v_note) > 500 then
    raise exception using message = 'sello:note_too_long';
  end if;

  update share_links
  set decision = p_decision::decision_kind, decision_note = v_note, decided_at = now()
  where id = l.id
  returning * into l;

  return jsonb_build_object('decision', l.decision, 'decided_at', l.decided_at);
end $$;

-- Daily automation. Idempotent; only records facts that are already true.
create function public.flag_stale_links() returns integer
language plpgsql security definer set search_path = public as $$
declare
  n1 integer;
  n2 integer;
begin
  update share_links set flag = 'no_inspection'
  where opened_at is null
    and created_at < now() - interval '7 days'
    and flag is distinct from 'no_inspection';
  get diagnostics n1 = row_count;

  update share_links set flag = 'no_action'
  where opened_at < now() - interval '7 days'
    and decided_at is null
    and flag is distinct from 'no_action';
  get diagnostics n2 = row_count;

  return n1 + n2;
end $$;

-- -----------------------------------------------------------------------------
-- Row Level Security: on for every table
-- -----------------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.proofs          enable row level security;
alter table public.ai_drafts       enable row level security;
alter table public.claims          enable row level security;
alter table public.review_requests enable row level security;
alter table public.vouch_invites   enable row level security;
alter table public.vouches         enable row level security;
alter table public.status_events   enable row level security;
alter table public.share_links     enable row level security;

-- profiles
create policy profiles_select_own on public.profiles for select to authenticated
  using (id = auth.uid());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- proofs
create policy proofs_select on public.proofs for select to authenticated
  using (owner_id = auth.uid() or public.is_assigned_reviewer(id) or public.has_vouch_access(id));
create policy proofs_insert_own on public.proofs for insert to authenticated
  with check (owner_id = auth.uid());
create policy proofs_update_own on public.proofs for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy proofs_delete_own on public.proofs for delete to authenticated
  using (owner_id = auth.uid());

-- ai_drafts (owner only; the AI route runs as the signed-in owner)
create policy ai_drafts_owner on public.ai_drafts for all to authenticated
  using (public.is_proof_owner(proof_id)) with check (public.is_proof_owner(proof_id));

-- claims (no delete policy)
create policy claims_select on public.claims for select to authenticated
  using (public.is_proof_owner(proof_id) or public.is_assigned_reviewer(proof_id) or public.has_vouch_access(proof_id));
create policy claims_insert_own on public.claims for insert to authenticated
  with check (public.is_proof_owner(proof_id));
create policy claims_update_own on public.claims for update to authenticated
  using (public.is_proof_owner(proof_id)) with check (public.is_proof_owner(proof_id));

-- review_requests
create policy rr_owner_select on public.review_requests for select to authenticated
  using (public.is_proof_owner(proof_id));
create policy rr_owner_insert on public.review_requests for insert to authenticated
  with check (public.is_proof_owner(proof_id));
create policy rr_reviewer_select on public.review_requests for select to authenticated
  using (public.is_approved_reviewer() and (status = 'open' or reviewer_id = auth.uid()));
create policy rr_reviewer_claim on public.review_requests for update to authenticated
  using (public.is_approved_reviewer() and status = 'open' and reviewer_id is null
         and not public.is_proof_owner(proof_id))
  with check (reviewer_id = auth.uid() and status = 'claimed' and no_prior_relationship);
create policy rr_reviewer_done on public.review_requests for update to authenticated
  using (reviewer_id = auth.uid() and status = 'claimed')
  with check (reviewer_id = auth.uid());

-- vouch_invites (owner reads/creates; accepting goes through accept_vouch_invite)
create policy vouch_invites_owner_select on public.vouch_invites for select to authenticated
  using (public.is_proof_owner(proof_id));
create policy vouch_invites_owner_insert on public.vouch_invites for insert to authenticated
  with check (public.is_proof_owner(proof_id));

-- vouches (read only; written by vouch_claim)
create policy vouches_select on public.vouches for select to authenticated
  using (voucher_id = auth.uid()
         or exists (select 1 from public.claims c where c.id = claim_id and public.is_proof_owner(c.proof_id)));

-- status_events: select only. No insert/update/delete policies.
create policy status_events_select on public.status_events for select to authenticated
  using (exists (select 1 from public.claims c
                 where c.id = claim_id
                   and (public.is_proof_owner(c.proof_id) or public.is_assigned_reviewer(c.proof_id))));

-- share_links: owner reads/creates. No update policy: the owner cannot fake opens or decisions.
create policy share_links_owner_select on public.share_links for select to authenticated
  using (public.is_proof_owner(proof_id));
create policy share_links_owner_insert on public.share_links for insert to authenticated
  with check (public.is_proof_owner(proof_id));

-- -----------------------------------------------------------------------------
-- Grants: least privilege, on top of RLS
-- -----------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;

grant select, update                 on public.profiles        to authenticated;
grant select, insert, update, delete on public.proofs          to authenticated;
grant select, insert, update, delete on public.ai_drafts       to authenticated;
grant select, insert, update         on public.claims          to authenticated;
grant select, insert, update         on public.review_requests to authenticated;
grant select, insert                 on public.vouch_invites   to authenticated;
grant select                         on public.vouches         to authenticated;
grant select                         on public.status_events   to authenticated;
grant select, insert                 on public.share_links     to authenticated;

-- Functions: Postgres grants EXECUTE to PUBLIC by default, so revoke from PUBLIC too.
revoke all on all functions in schema public from public, anon, authenticated;

grant execute on function public.is_proof_owner(uuid)        to authenticated;
grant execute on function public.is_assigned_reviewer(uuid)  to authenticated;
grant execute on function public.has_vouch_access(uuid)      to authenticated;
grant execute on function public.is_approved_reviewer()      to authenticated;
grant execute on function public.is_api_role()               to authenticated, anon;
grant execute on function public.review_criteria()           to authenticated;
grant execute on function public.accept_vouch_invite(text)   to authenticated;
grant execute on function public.vouch_claim(uuid, text, text)            to authenticated;
grant execute on function public.verify_claim(uuid, text, text, text)     to authenticated;
grant execute on function public.decline_claim(uuid, text)                to authenticated;
grant execute on function public.retract_verification(uuid, text)         to authenticated;
grant execute on function public.list_open_review_requests()              to authenticated;

-- The only functions anon may call:
grant execute on function public.open_share_link(text)               to anon, authenticated;
grant execute on function public.record_decision(text, text, text)   to anon, authenticated;

-- The cron route has no service-role key, so it calls this as anon too.
-- Safe: it is idempotent and only flags links that are already stale.
-- The route itself still demands CRON_SECRET (see DECISIONS.md).
grant execute on function public.flag_stale_links() to anon;

-- Functions created later in this schema are not callable by the API roles by
-- default. (PUBLIC's built-in EXECUTE cannot be revoked per schema, so every
-- later migration must still `revoke ... from public` explicitly.)
alter default privileges in schema public revoke execute on functions from anon, authenticated;
