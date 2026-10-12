-- =============================================================================
-- Sello · attack suite (packet tests 1–12 plus extra bypass attempts)
--
-- Paste the whole file into the Supabase SQL editor and press Run.
-- It returns one row per test (PASS/FAIL + the actual error text) and a summary.
--
-- Nothing persists: every test runs inside one block that always ends with a
-- forced rollback (SQLSTATE SLRBK). The SQL editor only shows the result of the
-- last statement, so a plain `begin; … rollback;` script would hide the results.
--
-- Users are simulated exactly as in the prompt:
--   role := authenticated  +  request.jwt.claims := {"sub": <uuid>}
-- All test users and data are invented.
-- =============================================================================

create or replace function pg_temp.act(p_uid uuid) returns void
language plpgsql as $$
begin
  if p_uid is null then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('role', 'anon', true);
  else
    perform set_config('request.jwt.claims',
                       json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
  end if;
end $$;

create or replace function pg_temp.admin() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'none', true);
end $$;

create or replace function pg_temp.v(p_ok boolean, p_test text, p_detail text) returns jsonb
language sql as $$
  select jsonb_build_array(jsonb_build_object('ok', coalesce(p_ok, false), 'test', p_test, 'detail', coalesce(p_detail, '')))
$$;

create or replace function pg_temp.sello_attacks()
returns table (n integer, result text, test text, detail text)
language plpgsql as $fn$
declare
  out_log jsonb := '[]'::jsonb;

  -- invented users
  uA  uuid := 'a0000000-0000-4000-8000-0000000000a1';  -- worker (owner)
  uB  uuid := 'a0000000-0000-4000-8000-0000000000b2';  -- another worker
  uV  uuid := 'a0000000-0000-4000-8000-0000000000c3';  -- voucher
  uR1 uuid := 'a0000000-0000-4000-8000-0000000000d4';  -- approved, independent reviewer
  uR2 uuid := 'a0000000-0000-4000-8000-0000000000e5';  -- reviewer, NOT approved
  uR3 uuid := 'a0000000-0000-4000-8000-0000000000f6';  -- approved reviewer who also vouched
  uR4 uuid := 'a0000000-0000-4000-8000-000000000107';  -- approved reviewer who never claimed

  p1 uuid := 'b0000000-0000-4000-8000-000000000001';
  p2 uuid := 'b0000000-0000-4000-8000-000000000002';
  c1 uuid := 'c0000000-0000-4000-8000-000000000001';
  c2 uuid := 'c0000000-0000-4000-8000-000000000002';
  c3 uuid := 'c0000000-0000-4000-8000-000000000003';
  c4 uuid := 'c0000000-0000-4000-8000-000000000004';
  c5 uuid := 'c0000000-0000-4000-8000-000000000005';

  rr1 uuid; rr2 uuid;
  tok_v text; tok_r3 text; tok_r3b text;
  l1 uuid; l2 uuid; l3 uuid; tok_l1 text; tok_l2 text; tok_l3 text;

  evidence text := 'Durante tres años llevé los pedidos por WhatsApp y el inventario de la taquería familiar. '
                || 'Anoto cada pedido en una hoja de cálculo y cuadro el inventario los domingos. (Datos inventados)';
  j jsonb;
  k integer;
  k2 integer;
  s public.claim_status;
  t timestamptz;
begin
  begin  -- ===== everything below is rolled back at the end =====

  -- ---------------------------------------------------------------- setup
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, jsonb_build_object('full_name', u.name), '{}'::jsonb, now(), now()
  from (values
    (uA,  'sello-test-a@example.invalid',  'Lupita R. (demo)'),
    (uB,  'sello-test-b@example.invalid',  'Otra Persona (demo)'),
    (uV,  'sello-test-v@example.invalid',  'Tía Carmen (demo)'),
    (uR1, 'sello-test-r1@example.invalid', 'Revisora Independiente (demo)'),
    (uR2, 'sello-test-r2@example.invalid', 'Revisor No Aprobado (demo)'),
    (uR3, 'sello-test-r3@example.invalid', 'Revisor Que Respaldó (demo)'),
    (uR4, 'sello-test-r4@example.invalid', 'Revisor Sin Asignar (demo)')
  ) as u(id, email, name);

  select count(*) into k from public.profiles where id in (uA, uB, uV, uR1, uR2, uR3, uR4);
  out_log := out_log || pg_temp.v(k = 7, 'T00 profile row auto-created on signup', k || ' of 7 profiles');

  update public.profiles set is_reviewer = true, reviewer_approved = true where id in (uR1, uR3, uR4);
  update public.profiles set is_reviewer = true where id = uR2;

  -- Worker A creates two proofs and claims.
  perform pg_temp.act(uA);
  insert into public.proofs (id, title, raw_evidence, intended_decision_maker, intended_decision)
  values (p1, 'Pedidos e inventario de la taquería', evidence, 'Roberto (demo)', 'Entrevista'),
         (p2, 'Segundo trabajo de prueba', evidence, null, null);

  -- ---------------------------------------------------------------- T01
  insert into public.claims (id, proof_id, text, status)
  values (c1, p1, 'Soy experta verificada en inventarios', 'VERIFIED');
  insert into public.claims (id, proof_id, text) values
    (c2, p1, 'Tomé unos 40 pedidos por WhatsApp en una semana'),
    (c3, p1, 'Cuadro el inventario cada domingo'),
    (c4, p2, 'Atendí clientes en mostrador'),
    (c5, p1, 'Uso hojas de cálculo para llevar pedidos');
  perform pg_temp.admin();

  select status into s from public.claims where id = c1;
  select count(*) into k from public.status_events
   where claim_id = c1 and from_status is null and to_status = 'DECLARED' and actor_role = 'worker' and actor_id = uA;
  out_log := out_log || pg_temp.v(s = 'DECLARED' and k = 1,
    'T01 insert with status=VERIFIED is stored as DECLARED + 1 event', 'status=' || s || ', events=' || k);

  select count(*) into k from public.status_events where claim_id in (c1, c2, c3, c4, c5);
  out_log := out_log || pg_temp.v(k = 5, 'T01b every new claim has exactly one event', k || ' events for 5 claims');

  -- ---------------------------------------------------------------- T02
  perform pg_temp.act(uA);
  begin
    update public.claims set status = 'VERIFIED' where id = c1;
    out_log := out_log || pg_temp.v(false, 'T02 worker direct UPDATE status=VERIFIED', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm like '%status can only change through transition functions%',
      'T02 worker direct UPDATE status=VERIFIED', sqlerrm);
  end;

  perform pg_temp.act(uA);
  begin
    perform set_config('sello.transition', 'on', true);
    update public.claims set status = 'VERIFIED' where id = c1;
    out_log := out_log || pg_temp.v(false, 'T02b worker sets sello.transition=on then UPDATE', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm like '%status can only change through transition functions%',
      'T02b worker sets sello.transition=on then UPDATE', sqlerrm);
  end;
  perform pg_temp.admin();
  perform set_config('sello.transition', '', true);

  select status into s from public.claims where id = c1;
  select count(*) into k from public.status_events where claim_id = c1;
  out_log := out_log || pg_temp.v(s = 'DECLARED' and k = 1,
    'T02c after the attempts: still DECLARED, no event logged', 'status=' || s || ', events=' || k);

  -- ---------------------------------------------------------------- T03
  perform pg_temp.act(uA);
  begin
    perform public.verify_claim(c1, 'Alcance suficiente aquí', 'No se puede inferir nada', 'Razón suficiente aquí');
    out_log := out_log || pg_temp.v(false, 'T03 worker calls verify_claim on own claim', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm like 'sello:%', 'T03 worker calls verify_claim on own claim', sqlerrm);
  end;

  perform pg_temp.act(uA);
  begin
    update public.profiles set reviewer_approved = true where id = uA;
    out_log := out_log || pg_temp.v(false, 'T03b worker approves themselves as reviewer', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm like '%reviewer_approval_is_manual%',
      'T03b worker approves themselves as reviewer', sqlerrm);
  end;

  perform pg_temp.act(uA);
  begin
    insert into public.status_events (claim_id, from_status, to_status, actor_id, actor_role, reason)
    values (c1, 'DECLARED', 'VERIFIED', uA, 'reviewer', 'fake');
    out_log := out_log || pg_temp.v(false, 'T03c direct INSERT into status_events', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(true, 'T03c direct INSERT into status_events', sqlerrm);
  end;

  perform pg_temp.act(uA);
  begin
    insert into public.vouches (claim_id, voucher_id, relationship, what_they_saw)
    values (c1, uA, 'yo misma', 'Me vi a mí misma hacer todo el trabajo.');
    out_log := out_log || pg_temp.v(false, 'T03d direct INSERT into vouches', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(true, 'T03d direct INSERT into vouches', sqlerrm);
  end;

  -- ---------------------------------------------------------------- vouch flow
  perform pg_temp.act(uA);
  insert into public.vouch_invites (proof_id, token, used, used_by)
  values (p1, repeat('0', 48), true, uV)          -- attacker-chosen token and pre-used: must be ignored
  returning token into tok_v;
  insert into public.vouch_invites (proof_id) values (p1) returning token into tok_r3;
  insert into public.vouch_invites (proof_id) values (p2) returning token into tok_r3b;
  perform pg_temp.admin();

  select count(*) into k from public.vouch_invites where token = tok_v and not used and used_by is null;
  out_log := out_log || pg_temp.v(tok_v <> repeat('0', 48) and k = 1,
    'T04 invite token is random and starts unused whatever was sent', 'token_len=' || length(tok_v));

  perform pg_temp.act(uA);
  begin
    perform public.accept_vouch_invite(tok_v);
    out_log := out_log || pg_temp.v(false, 'T04a owner opens their own vouch link', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:own_invite', 'T04a owner opens their own vouch link', sqlerrm);
  end;

  perform pg_temp.act(uV);
  begin
    perform public.accept_vouch_invite(tok_v);
    s := public.vouch_claim(c2, 'Su tía, dueña de la taquería', 'La vi tomar unos 40 pedidos por WhatsApp en una semana.');
    out_log := out_log || pg_temp.v(s = 'VOUCHED', 'T04b voucher with invite vouches DECLARED claim', 'returned ' || s);
  exception when others then
    out_log := out_log || pg_temp.v(false, 'T04b voucher with invite vouches DECLARED claim', sqlerrm);
  end;

  perform pg_temp.act(uV);
  begin
    perform public.vouch_claim(c3, 'Su tía', 'muy corto');
    out_log := out_log || pg_temp.v(false, 'T04c what_they_saw under 20 chars', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:what_they_saw_length', 'T04c what_they_saw under 20 chars', sqlerrm);
  end;

  perform pg_temp.act(uV);
  begin
    perform public.vouch_claim(c2, 'Su tía', 'La vi tomar pedidos otra vez, segunda vez.');
    out_log := out_log || pg_temp.v(false, 'T04d vouch an already VOUCHED claim', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:only_declared_can_be_vouched', 'T04d vouch an already VOUCHED claim', sqlerrm);
  end;

  perform pg_temp.act(uB);
  begin
    perform public.vouch_claim(c3, 'Vecino', 'La vi cuadrar el inventario un domingo.');
    out_log := out_log || pg_temp.v(false, 'T04e user without invite vouches', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:no_invite', 'T04e user without invite vouches', sqlerrm);
  end;

  -- R3 vouches on both proofs (sets up the conflict-of-interest tests)
  perform pg_temp.act(uR3);
  perform public.accept_vouch_invite(tok_r3);
  perform public.vouch_claim(c3, 'Cliente frecuente', 'La vi cuadrar el inventario un domingo en la tarde.');
  perform public.accept_vouch_invite(tok_r3b);
  perform public.vouch_claim(c4, 'Cliente frecuente', 'La vi atender clientes en el mostrador varias veces.');
  perform pg_temp.admin();

  select status into s from public.claims where id = c2;
  select count(*) into k from public.status_events where claim_id = c2 and to_status = 'VOUCHED' and actor_role = 'voucher';
  out_log := out_log || pg_temp.v(s = 'VOUCHED' and k = 1, 'T04f vouch wrote status + one voucher event', 'status=' || s || ', events=' || k);

  -- ---------------------------------------------------------------- review requests
  perform pg_temp.act(uA);
  insert into public.review_requests (proof_id, reviewer_id, status, no_prior_relationship, criteria)
  values (p1, uR1, 'claimed', true, 'nada')       -- attacker-chosen fields: must be ignored
  returning id into rr1;
  insert into public.review_requests (proof_id) values (p2) returning id into rr2;
  perform pg_temp.admin();

  out_log := out_log || pg_temp.v((select status = 'open' and reviewer_id is null and not no_prior_relationship
                                          and criteria = public.review_criteria()
                                   from public.review_requests where id = rr1),
    'T05 new review request is open, unassigned, fixed criteria', '');

  perform pg_temp.act(uR3);
  begin
    update public.review_requests set reviewer_id = uR3, status = 'claimed', no_prior_relationship = true where id = rr1;
    get diagnostics k = row_count;
    out_log := out_log || pg_temp.v(false, 'T05a reviewer who vouched claims the request', 'rows=' || k);
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:reviewer_conflict_of_interest', 'T05a reviewer who vouched claims the request', sqlerrm);
  end;

  perform pg_temp.act(uR2);
  begin
    update public.review_requests set reviewer_id = uR2, status = 'claimed', no_prior_relationship = true where id = rr1;
    get diagnostics k = row_count;
    out_log := out_log || pg_temp.v(k = 0, 'T05b unapproved reviewer claims the request', 'rows updated=' || k);
  exception when others then
    out_log := out_log || pg_temp.v(true, 'T05b unapproved reviewer claims the request', sqlerrm);
  end;

  perform pg_temp.act(uR1);
  begin
    update public.review_requests set reviewer_id = uR1, status = 'claimed', no_prior_relationship = false where id = rr1;
    get diagnostics k = row_count;
    out_log := out_log || pg_temp.v(false, 'T05c claim without ticking "no prior relationship"', 'rows=' || k);
  exception when others then
    out_log := out_log || pg_temp.v(true, 'T05c claim without ticking "no prior relationship"', sqlerrm);
  end;

  perform pg_temp.act(uR1);
  begin
    update public.review_requests set reviewer_id = uR1, status = 'claimed', no_prior_relationship = true where id = rr1;
    get diagnostics k = row_count;
    out_log := out_log || pg_temp.v(k = 1, 'T05d independent approved reviewer claims the request', 'rows=' || k);
  exception when others then
    out_log := out_log || pg_temp.v(false, 'T05d independent approved reviewer claims the request', sqlerrm);
  end;

  perform pg_temp.act(uR4);
  begin
    perform public.verify_claim(c1, 'Revisé la hoja de pedidos', 'Desempeño con punto de venta', 'La evidencia lo muestra');
    out_log := out_log || pg_temp.v(false, 'T05e approved reviewer WITHOUT claiming verifies', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:review_not_claimed', 'T05e approved reviewer WITHOUT claiming verifies', sqlerrm);
  end;

  perform pg_temp.act(uR2);
  begin
    perform public.verify_claim(c1, 'Revisé la hoja de pedidos', 'Desempeño con punto de venta', 'La evidencia lo muestra');
    out_log := out_log || pg_temp.v(false, 'T05f unapproved reviewer verifies (packet 5)', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:reviewer_not_approved', 'T05f unapproved reviewer verifies (packet 5)', sqlerrm);
  end;

  perform pg_temp.act(uR3);
  begin
    perform public.verify_claim(c1, 'Revisé la hoja de pedidos', 'Desempeño con punto de venta', 'La evidencia lo muestra');
    out_log := out_log || pg_temp.v(false, 'T05g approved reviewer who vouched verifies (packet 4)', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:reviewer_conflict_of_interest', 'T05g approved reviewer who vouched verifies (packet 4)', sqlerrm);
  end;

  -- Race: R3 got assigned to p2's request anyway (forced as admin). Verify must still refuse.
  perform pg_temp.admin();
  alter table public.review_requests disable trigger review_requests_guard_update;
  update public.review_requests set reviewer_id = uR3, status = 'claimed', no_prior_relationship = true where id = rr2;
  alter table public.review_requests enable trigger review_requests_guard_update;
  perform pg_temp.act(uR3);
  begin
    perform public.verify_claim(c4, 'Revisé el mostrador', 'Desempeño con punto de venta', 'La evidencia lo muestra');
    out_log := out_log || pg_temp.v(false, 'T05h assigned reviewer who vouched verifies', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:reviewer_conflict_of_interest', 'T05h assigned reviewer who vouched verifies', sqlerrm);
  end;

  -- ---------------------------------------------------------------- T06
  perform pg_temp.act(uR1);
  begin
    perform public.verify_claim(c1, '', 'Desempeño con punto de venta', 'La evidencia lo muestra');
    out_log := out_log || pg_temp.v(false, 'T06 verify with empty scope (packet 6)', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:scope_required', 'T06 verify with empty scope (packet 6)', sqlerrm);
  end;

  perform pg_temp.act(uR1);
  begin
    perform public.verify_claim(c1, 'Revisé la hoja de pedidos', 'x', 'La evidencia lo muestra');
    out_log := out_log || pg_temp.v(false, 'T06b verify with too-short cannot_infer', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:cannot_infer_required', 'T06b verify with too-short cannot_infer', sqlerrm);
  end;

  perform pg_temp.act(uR1);
  begin
    perform public.verify_claim(c1, 'Revisé la hoja de pedidos', 'Desempeño con punto de venta', null);
    out_log := out_log || pg_temp.v(false, 'T06c verify with no reason', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:reason_required', 'T06c verify with no reason', sqlerrm);
  end;

  -- ---------------------------------------------------------------- T07
  perform pg_temp.act(uR1);
  begin
    s := public.verify_claim(c1,
      'Revisé la hoja de 40 pedidos de una semana y el inventario del domingo',
      'Desempeño con un sistema de punto de venta o en equipo',
      'La hoja de pedidos coincide con lo que dice la frase');
    out_log := out_log || pg_temp.v(s = 'VERIFIED', 'T07 valid verification (packet 7)', 'returned ' || s);
  exception when others then
    out_log := out_log || pg_temp.v(false, 'T07 valid verification (packet 7)', sqlerrm);
  end;
  perform pg_temp.admin();

  select status into s from public.claims where id = c1;
  select count(*) into k from public.status_events where claim_id = c1;
  select count(*) into k2 from public.status_events
   where claim_id = c1 and from_status = 'DECLARED' and to_status = 'VERIFIED' and actor_role = 'reviewer'
     and actor_id = uR1 and reason like 'La hoja de pedidos%';
  out_log := out_log || pg_temp.v(s = 'VERIFIED' and k = 2 and k2 = 1,
    'T07b VERIFIED with exactly one new reviewer event', 'status=' || s || ', total events=' || k || ', matching=' || k2);

  out_log := out_log || pg_temp.v((select scope like 'Revisé la hoja%' and cannot_infer like 'Desempeño%' from public.claims where id = c1),
    'T07c scope and cannot_infer stored on the claim', '');

  perform pg_temp.act(uR1);
  begin
    perform public.verify_claim(c1, 'Revisé la hoja de pedidos', 'Desempeño con punto de venta', 'La evidencia lo muestra');
    out_log := out_log || pg_temp.v(false, 'T07d verify an already VERIFIED claim', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:already_verified', 'T07d verify an already VERIFIED claim', sqlerrm);
  end;

  -- The transition flag must not leak into later statements of the same transaction.
  perform pg_temp.act(uA);
  begin
    update public.claims set status = 'VERIFIED' where id = c5;
    out_log := out_log || pg_temp.v(false, 'T07e direct UPDATE right after a valid verify (flag leak)', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm like '%status can only change%', 'T07e direct UPDATE right after a valid verify (flag leak)', sqlerrm);
  end;

  -- ---------------------------------------------------------------- T08 locks
  perform pg_temp.act(uA);
  begin
    update public.claims set text = 'Soy la mejor del mundo en inventarios' where id = c1;
    out_log := out_log || pg_temp.v(false, 'T08 worker edits text of VERIFIED claim', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:claim_locked', 'T08 worker edits text of VERIFIED claim', sqlerrm);
  end;

  perform pg_temp.act(uA);
  begin
    update public.claims set scope = 'Todo, garantizado' where id = c1;
    out_log := out_log || pg_temp.v(false, 'T08b worker edits the reviewer scope', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:claim_locked', 'T08b worker edits the reviewer scope', sqlerrm);
  end;

  perform pg_temp.act(uA);
  begin
    update public.proofs set raw_evidence = evidence || ' Evidencia cambiada después de la revisión.' where id = p1;
    out_log := out_log || pg_temp.v(false, 'T08c worker swaps evidence after verification', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:proof_locked', 'T08c worker swaps evidence after verification', sqlerrm);
  end;

  perform pg_temp.act(uA);
  begin
    update public.claims set text = 'Uso hojas de cálculo para llevar pedidos diarios' where id = c5;
    get diagnostics k = row_count;
    out_log := out_log || pg_temp.v(k = 1, 'T08d worker CAN edit text of a DECLARED claim', 'rows=' || k);
  exception when others then
    out_log := out_log || pg_temp.v(false, 'T08d worker CAN edit text of a DECLARED claim', sqlerrm);
  end;

  perform pg_temp.act(uA);
  begin
    update public.status_events set reason = 'reescrito' where claim_id = c1;
    get diagnostics k = row_count;
    out_log := out_log || pg_temp.v(k = 0, 'T08e worker rewrites status_events', 'rows=' || k);
  exception when others then
    out_log := out_log || pg_temp.v(true, 'T08e worker rewrites status_events', sqlerrm);
  end;

  perform pg_temp.act(uA);
  begin
    delete from public.status_events where claim_id = c1;
    get diagnostics k = row_count;
    out_log := out_log || pg_temp.v(k = 0, 'T08f worker deletes status_events', 'rows=' || k);
  exception when others then
    out_log := out_log || pg_temp.v(true, 'T08f worker deletes status_events', sqlerrm);
  end;

  perform pg_temp.act(uR1);
  begin
    s := public.decline_claim(c5, 'La evidencia no muestra hojas de cálculo');
    out_log := out_log || pg_temp.v(s = 'DECLARED', 'T08g decline keeps status', 'returned ' || s);
  exception when others then
    out_log := out_log || pg_temp.v(false, 'T08g decline keeps status', sqlerrm);
  end;
  perform pg_temp.admin();
  select count(*) into k from public.status_events
   where claim_id = c5 and from_status = 'DECLARED' and to_status = 'DECLARED' and actor_role = 'reviewer';
  out_log := out_log || pg_temp.v(k = 1, 'T08h decline logged an event with from = to', 'events=' || k);

  -- ---------------------------------------------------------------- T09 share links
  perform pg_temp.act(uA);
  insert into public.share_links (proof_id, token, decision_maker_label, intended_decision, opened_at, decision, decided_at)
  values (p1, repeat('a', 48), 'Roberto, operaciones (demo)', 'Entrevista para auxiliar de operaciones', now(), 'advance', now())
  returning id, token into l1, tok_l1;
  insert into public.share_links (proof_id, decision_maker_label, intended_decision)
  values (p1, 'Otra empresa (demo)', 'Entrevista') returning id, token into l2, tok_l2;
  insert into public.share_links (proof_id, decision_maker_label, intended_decision)
  values (p1, 'Nadie la abre (demo)', 'Entrevista') returning id, token into l3, tok_l3;
  perform pg_temp.admin();

  out_log := out_log || pg_temp.v(
    tok_l1 <> repeat('a', 48)
      and (select opened_at is null and decision is null and decided_at is null from public.share_links where id = l1),
    'T09 new link: random token, no open, no decision, whatever was sent', '');

  perform pg_temp.act(uA);
  begin
    update public.share_links set opened_at = now(), decision = 'advance', decided_at = now() where id = l2;
    get diagnostics k = row_count;
    out_log := out_log || pg_temp.v(k = 0, 'T09a owner fakes opened/decided directly', 'rows=' || k);
  exception when others then
    out_log := out_log || pg_temp.v(true, 'T09a owner fakes opened/decided directly', sqlerrm);
  end;

  perform pg_temp.act(uA);
  j := public.open_share_link(tok_l1);
  perform pg_temp.admin();
  out_log := out_log || pg_temp.v(j is not null and (select opened_at is null from public.share_links where id = l1),
    'T09b owner previewing own link does not count as opened', 'is_owner=' || coalesce(j ->> 'is_owner', 'null'));

  perform pg_temp.act(null);
  begin
    perform public.record_decision(tok_l1, 'advance', null);
    out_log := out_log || pg_temp.v(false, 'T09c record_decision before open', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:not_opened', 'T09c record_decision before open', sqlerrm);
  end;

  perform pg_temp.act(null);
  j := public.open_share_link(tok_l1);
  perform pg_temp.admin();
  out_log := out_log || pg_temp.v(
    j ->> 'title' = 'Pedidos e inventario de la taquería'
      and jsonb_array_length(j -> 'claims') = 4
      and (select opened_at is not null from public.share_links where id = l1),
    'T09d anon opens link: data returned, opened_at set (packet 8)',
    'claims=' || coalesce(jsonb_array_length(j -> 'claims')::text, 'null'));

  -- now() is constant inside one transaction, so pin a known value and reopen.
  update public.share_links set opened_at = '2026-01-01 12:00:00+00' where id = l1;
  perform pg_temp.act(null);
  perform public.open_share_link(tok_l1);
  perform pg_temp.admin();
  select opened_at into t from public.share_links where id = l1;
  out_log := out_log || pg_temp.v(t = '2026-01-01 12:00:00+00', 'T09e reopening does not move opened_at (packet 8)', t::text);

  perform pg_temp.act(null);
  begin
    j := public.record_decision(tok_l1, 'advance', 'Se ve claro qué se revisó. (demo)');
    out_log := out_log || pg_temp.v(j ->> 'decision' = 'advance', 'T09f anon records a decision (packet 9)', j::text);
  exception when others then
    out_log := out_log || pg_temp.v(false, 'T09f anon records a decision (packet 9)', sqlerrm);
  end;

  perform pg_temp.act(null);
  begin
    perform public.record_decision(tok_l1, 'do_not_advance', null);
    out_log := out_log || pg_temp.v(false, 'T09g second decision', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:already_decided', 'T09g second decision', sqlerrm);
  end;

  perform pg_temp.act(null);
  perform public.open_share_link(tok_l2);
  perform pg_temp.act(uA);
  begin
    perform public.record_decision(tok_l2, 'advance', null);
    out_log := out_log || pg_temp.v(false, 'T09h owner records a decision on own link', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:own_link', 'T09h owner records a decision on own link', sqlerrm);
  end;

  perform pg_temp.act(null);
  begin
    perform public.record_decision(tok_l2, 'advance', repeat('x', 501));
    out_log := out_log || pg_temp.v(false, 'T09i decision note over 500 chars', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm = 'sello:note_too_long', 'T09i decision note over 500 chars', sqlerrm);
  end;

  -- ---------------------------------------------------------------- T10 tokens and anon
  perform pg_temp.act(null);
  out_log := out_log || pg_temp.v(public.open_share_link('nope') is null
                                  and public.open_share_link(repeat('f', 48)) is null
                                  and public.open_share_link(left(tok_l1, 47) || 'x') is null,
    'T10 tampered / unknown token returns null (packet 10)', '');

  perform pg_temp.act(null);
  begin
    select count(*) into k from public.share_links;
    out_log := out_log || pg_temp.v(k = 0, 'T10b anon selects share_links', 'rows=' || k);
  exception when others then
    out_log := out_log || pg_temp.v(true, 'T10b anon selects share_links', sqlerrm);
  end;

  perform pg_temp.act(null);
  begin
    select count(*) into k from public.proofs;
    out_log := out_log || pg_temp.v(k = 0, 'T10c anon selects proofs', 'rows=' || k);
  exception when others then
    out_log := out_log || pg_temp.v(true, 'T10c anon selects proofs', sqlerrm);
  end;

  perform pg_temp.act(null);
  begin
    perform public.verify_claim(c2, 'Revisé la hoja de pedidos', 'Desempeño con punto de venta', 'La evidencia lo muestra');
    out_log := out_log || pg_temp.v(false, 'T10d anon calls verify_claim', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm like 'permission denied%', 'T10d anon calls verify_claim', sqlerrm);
  end;

  perform pg_temp.act(null);
  begin
    perform public.accept_vouch_invite(tok_r3);
    out_log := out_log || pg_temp.v(false, 'T10e anon calls accept_vouch_invite', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm like 'permission denied%', 'T10e anon calls accept_vouch_invite', sqlerrm);
  end;

  perform pg_temp.act(uA);
  begin
    perform public._assert_independent_reviewer(p1);
    out_log := out_log || pg_temp.v(false, 'T10f signed-in user calls the internal reviewer check', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm like 'permission denied%', 'T10f signed-in user calls the internal reviewer check', sqlerrm);
  end;

  -- ---------------------------------------------------------------- T11 automation
  perform pg_temp.admin();
  update public.share_links set created_at = now() - interval '8 days' where id = l3;       -- never opened
  update public.share_links set opened_at  = now() - interval '8 days' where id = l2;       -- opened, no decision
  perform pg_temp.act(null);
  perform public.flag_stale_links();
  perform pg_temp.admin();
  out_log := out_log || pg_temp.v(
    (select flag from public.share_links where id = l3) = 'no_inspection'
      and (select flag from public.share_links where id = l2) = 'no_action'
      and (select flag is null from public.share_links where id = l1),
    'T11 cron flags no_inspection / no_action, leaves decided link alone (packet 11)',
    'l3=' || coalesce((select flag from public.share_links where id = l3), 'null')
      || ', l2=' || coalesce((select flag from public.share_links where id = l2), 'null')
      || ', l1=' || coalesce((select flag from public.share_links where id = l1), 'null'));

  -- ---------------------------------------------------------------- T12 sizes (DB layer)
  perform pg_temp.act(uA);
  begin
    insert into public.proofs (title, raw_evidence) values ('Demasiado largo', repeat('a', 4001));
    out_log := out_log || pg_temp.v(false, 'T12 raw_evidence of 4,001 chars', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm like '%check constraint%', 'T12 raw_evidence of 4,001 chars', sqlerrm);
  end;

  perform pg_temp.act(uA);
  begin
    insert into public.claims (proof_id, text) values (p1, repeat('a', 401));
    out_log := out_log || pg_temp.v(false, 'T12b claim text of 401 chars', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(sqlerrm like '%check constraint%', 'T12b claim text of 401 chars', sqlerrm);
  end;

  -- ---------------------------------------------------------------- T13 isolation
  perform pg_temp.act(uB);
  select count(*) into k from public.proofs where owner_id = uA;
  out_log := out_log || pg_temp.v(k = 0, 'T13 user B selects user A''s proofs', 'rows=' || k);

  perform pg_temp.act(uB);
  select (select count(*) from public.claims where proof_id = p1)
       + (select count(*) from public.status_events)
       + (select count(*) from public.share_links)
       + (select count(*) from public.vouch_invites)
       + (select count(*) from public.ai_drafts)
    into k;
  out_log := out_log || pg_temp.v(k = 0, 'T13b user B sees none of A''s claims, events, links, invites, drafts', 'rows=' || k);

  perform pg_temp.act(uB);
  begin
    update public.claims set text = 'Hackeado por B' where id = c5;
    get diagnostics k = row_count;
    out_log := out_log || pg_temp.v(k = 0, 'T13c user B edits A''s claim', 'rows=' || k);
  exception when others then
    out_log := out_log || pg_temp.v(true, 'T13c user B edits A''s claim', sqlerrm);
  end;

  perform pg_temp.act(uB);
  begin
    insert into public.claims (proof_id, text) values (p1, 'Claim plantado por B');
    out_log := out_log || pg_temp.v(false, 'T13d user B inserts a claim into A''s proof', 'no error');
  exception when others then
    out_log := out_log || pg_temp.v(true, 'T13d user B inserts a claim into A''s proof', sqlerrm);
  end;

  perform pg_temp.act(uR1);
  select count(*) into k from public.claims where proof_id = p1;
  out_log := out_log || pg_temp.v(k = 4, 'T13e assigned reviewer CAN read the claims', 'rows=' || k);

  perform pg_temp.act(uR4);
  select count(*) into k from public.proofs where id = p1;
  out_log := out_log || pg_temp.v(k = 0, 'T13f unassigned reviewer cannot read the proof', 'rows=' || k);

  -- ---------------------------------------------------------------- T14 retract
  perform pg_temp.act(uR1);
  begin
    s := public.retract_verification(c1, 'Encontré que la hoja era de otra persona');
    out_log := out_log || pg_temp.v(s = 'DECLARED', 'T14 reviewer retracts verification', 'returned ' || s);
  exception when others then
    out_log := out_log || pg_temp.v(false, 'T14 reviewer retracts verification', sqlerrm);
  end;
  perform pg_temp.admin();
  select count(*) into k from public.status_events
   where claim_id = c1 and from_status = 'VERIFIED' and to_status = 'DECLARED' and actor_role = 'reviewer';
  out_log := out_log || pg_temp.v(k = 1 and (select status from public.claims where id = c1) = 'DECLARED',
    'T14b retract logged VERIFIED → DECLARED', 'events=' || k);

  -- ===== undo everything =====
  raise exception using errcode = 'SLRBK', message = 'sello attack suite: rollback';
  exception when sqlstate 'SLRBK' then
    null;
  end;

  perform pg_temp.admin();

  return query
    select e.ord::int,
           case when (e.val ->> 'ok')::boolean then 'PASS' else 'FAIL' end,
           e.val ->> 'test',
           e.val ->> 'detail'
    from jsonb_array_elements(out_log) with ordinality as e(val, ord);

  return query
    select 999, 'SUMMARY',
           (select count(*) from jsonb_array_elements(out_log) as v(val) where (v.val ->> 'ok')::boolean)::text
             || ' of ' || jsonb_array_length(out_log)::text || ' PASS',
           'All test data was rolled back.';
end $fn$;

select * from pg_temp.sello_attacks();
