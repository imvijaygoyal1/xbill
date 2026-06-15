-- App Store reviewer demo account seed.
-- Idempotent: safe to run multiple times against the linked production project.

do $$
declare
  reviewer_id uuid;
  auth_instance_id constant uuid := '00000000-0000-0000-0000-000000000000';
  alice_id constant uuid := 'aaaaaaaa-0001-0001-0001-000000000001';
  bob_id constant uuid := 'aaaaaaaa-0002-0002-0002-000000000002';
  review_group_id constant uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
begin
  select id
  into reviewer_id
  from auth.users
  where email = 'appreviewer@xbill.vijaygoyal.org';

  if reviewer_id is null then
    reviewer_id := gen_random_uuid();

    insert into auth.users (
      id,
      instance_id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      confirmation_token,
      recovery_token,
      email_change_token_new,
      email_change,
      email_change_token_current,
      reauthentication_token,
      is_sso_user,
      is_anonymous
    )
    values (
      reviewer_id,
      auth_instance_id,
      'authenticated',
      'authenticated',
      'appreviewer@xbill.vijaygoyal.org',
      null,
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"display_name":"App Reviewer"}'::jsonb,
      now(),
      now(),
      '',
      '',
      '',
      '',
      '',
      '',
      false,
      false
    );
  else
    update auth.users
    set instance_id = auth_instance_id,
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        aud = 'authenticated',
        role = 'authenticated',
        raw_app_meta_data = '{"provider":"email","providers":["email"]}'::jsonb,
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || '{"display_name":"App Reviewer"}'::jsonb,
        confirmation_token = '',
        recovery_token = '',
        email_change_token_new = '',
        email_change = '',
        email_change_token_current = '',
        reauthentication_token = '',
        updated_at = now(),
        deleted_at = null,
        banned_until = null
    where id = reviewer_id;
  end if;

  insert into auth.identities (
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    reviewer_id::text,
    reviewer_id,
    jsonb_build_object(
      'sub', reviewer_id::text,
      'email', 'appreviewer@xbill.vijaygoyal.org',
      'email_verified', true,
      'phone_verified', false
    ),
    'email',
    now(),
    now(),
    now()
  )
  on conflict (provider_id, provider) do update
  set identity_data = excluded.identity_data,
      user_id = excluded.user_id,
      updated_at = now();

  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    email_change_token_current,
    reauthentication_token,
    is_sso_user,
    is_anonymous
  )
  values
    (
      alice_id,
      auth_instance_id,
      'authenticated',
      'authenticated',
      'alice.seed@xbill.vijaygoyal.org',
      null,
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"display_name":"Alice Chen"}'::jsonb,
      now(),
      now(),
      '',
      '',
      '',
      '',
      '',
      '',
      false,
      false
    ),
    (
      bob_id,
      auth_instance_id,
      'authenticated',
      'authenticated',
      'bob.seed@xbill.vijaygoyal.org',
      null,
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"display_name":"Bob Patel"}'::jsonb,
      now(),
      now(),
      '',
      '',
      '',
      '',
      '',
      '',
      false,
      false
    )
  on conflict (id) do update
  set instance_id = auth_instance_id,
      email_confirmed_at = coalesce(auth.users.email_confirmed_at, now()),
      aud = 'authenticated',
      role = 'authenticated',
      raw_app_meta_data = excluded.raw_app_meta_data,
      raw_user_meta_data = excluded.raw_user_meta_data,
      confirmation_token = '',
      recovery_token = '',
      email_change_token_new = '',
      email_change = '',
      email_change_token_current = '',
      reauthentication_token = '',
      updated_at = now(),
      deleted_at = null,
      banned_until = null;

  insert into auth.identities (
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values
    (
      alice_id::text,
      alice_id,
      jsonb_build_object('sub', alice_id::text, 'email', 'alice.seed@xbill.vijaygoyal.org', 'email_verified', true, 'phone_verified', false),
      'email',
      now(),
      now(),
      now()
    ),
    (
      bob_id::text,
      bob_id,
      jsonb_build_object('sub', bob_id::text, 'email', 'bob.seed@xbill.vijaygoyal.org', 'email_verified', true, 'phone_verified', false),
      'email',
      now(),
      now(),
      now()
    )
  on conflict (provider_id, provider) do update
  set identity_data = excluded.identity_data,
      user_id = excluded.user_id,
      updated_at = now();

  insert into public.profiles (id, display_name, avatar_url, venmo_handle, paypal_email, paypal_handle, email)
  values
    (reviewer_id, 'App Reviewer', null, 'appreviewer', 'appreviewer@xbill.vijaygoyal.org', 'appreviewer', 'appreviewer@xbill.vijaygoyal.org'),
    (alice_id, 'Alice Chen', null, 'alicechen', null, null, 'alice.seed@xbill.vijaygoyal.org'),
    (bob_id, 'Bob Patel', null, 'bobpatel', null, null, 'bob.seed@xbill.vijaygoyal.org')
  on conflict (id) do update
  set display_name = excluded.display_name,
      avatar_url = excluded.avatar_url,
      venmo_handle = excluded.venmo_handle,
      paypal_email = excluded.paypal_email,
      paypal_handle = excluded.paypal_handle,
      email = excluded.email;

  insert into public.groups (id, name, emoji, currency, created_by, is_archived)
  values (review_group_id, 'Tokyo Trip', '🗼', 'USD', reviewer_id, false)
  on conflict (id) do update
  set name = excluded.name,
      emoji = excluded.emoji,
      currency = excluded.currency,
      created_by = excluded.created_by,
      is_archived = false;

  insert into public.group_members (group_id, user_id, is_active, removed_at)
  values
    (review_group_id, reviewer_id, true, null),
    (review_group_id, alice_id, true, null),
    (review_group_id, bob_id, true, null)
  on conflict (group_id, user_id) do update
  set is_active = true,
      removed_at = null;

  update public.friends
  set status = 'accepted'
  where least(requester_id, addressee_id) = least(reviewer_id, alice_id)
    and greatest(requester_id, addressee_id) = greatest(reviewer_id, alice_id);

  insert into public.friends (id, requester_id, addressee_id, status)
  select 'dddddddd-0001-0001-0001-000000000001', reviewer_id, alice_id, 'accepted'
  where not exists (
    select 1
    from public.friends
    where least(requester_id, addressee_id) = least(reviewer_id, alice_id)
      and greatest(requester_id, addressee_id) = greatest(reviewer_id, alice_id)
  );

  update public.friends
  set status = 'accepted'
  where least(requester_id, addressee_id) = least(reviewer_id, bob_id)
    and greatest(requester_id, addressee_id) = greatest(reviewer_id, bob_id);

  insert into public.friends (id, requester_id, addressee_id, status)
  select 'dddddddd-0002-0002-0002-000000000002', reviewer_id, bob_id, 'accepted'
  where not exists (
    select 1
    from public.friends
    where least(requester_id, addressee_id) = least(reviewer_id, bob_id)
      and greatest(requester_id, addressee_id) = greatest(reviewer_id, bob_id)
  );

  insert into public.expenses (id, group_id, paid_by, amount, title, category, currency, notes, receipt_url, recurrence, created_at)
  values
    ('eeeeeeee-0001-0001-0001-000000000001', review_group_id, reviewer_id, 180.00, 'Flights to Tokyo', 'transport', 'USD', 'Reviewer paid; equal split.', null, 'none', now() - interval '5 days'),
    ('eeeeeeee-0002-0002-0002-000000000002', review_group_id, alice_id, 90.00, 'Hotel - Night 1', 'accommodation', 'USD', 'Alice paid; reviewer owes a share.', null, 'none', now() - interval '4 days'),
    ('eeeeeeee-0003-0003-0003-000000000003', review_group_id, reviewer_id, 120.00, 'Sushi dinner', 'food', 'USD', 'Reviewer paid; custom split.', null, 'none', now() - interval '3 days'),
    ('eeeeeeee-0004-0004-0004-000000000004', review_group_id, bob_id, 60.00, 'Day trip to Nikko', 'transport', 'USD', 'Bob paid; reviewer owes a share.', null, 'none', now() - interval '2 days'),
    ('eeeeeeee-0005-0005-0005-000000000005', review_group_id, reviewer_id, 45.00, 'Convenience store run', 'shopping', 'USD', 'Recent activity sample.', null, 'none', now() - interval '1 day')
  on conflict (id) do update
  set group_id = excluded.group_id,
      paid_by = excluded.paid_by,
      amount = excluded.amount,
      title = excluded.title,
      category = excluded.category,
      currency = excluded.currency,
      notes = excluded.notes,
      receipt_url = excluded.receipt_url,
      recurrence = excluded.recurrence,
      created_at = excluded.created_at;

  insert into public.splits (expense_id, user_id, amount, is_settled, settled_at)
  values
    ('eeeeeeee-0001-0001-0001-000000000001', reviewer_id, 60.00, true, now() - interval '5 days'),
    ('eeeeeeee-0001-0001-0001-000000000001', alice_id, 60.00, false, null),
    ('eeeeeeee-0001-0001-0001-000000000001', bob_id, 60.00, false, null),
    ('eeeeeeee-0002-0002-0002-000000000002', reviewer_id, 30.00, false, null),
    ('eeeeeeee-0002-0002-0002-000000000002', alice_id, 30.00, true, now() - interval '4 days'),
    ('eeeeeeee-0002-0002-0002-000000000002', bob_id, 30.00, false, null),
    ('eeeeeeee-0003-0003-0003-000000000003', reviewer_id, 50.00, true, now() - interval '3 days'),
    ('eeeeeeee-0003-0003-0003-000000000003', alice_id, 40.00, false, null),
    ('eeeeeeee-0003-0003-0003-000000000003', bob_id, 30.00, false, null),
    ('eeeeeeee-0004-0004-0004-000000000004', reviewer_id, 20.00, false, null),
    ('eeeeeeee-0004-0004-0004-000000000004', alice_id, 20.00, false, null),
    ('eeeeeeee-0004-0004-0004-000000000004', bob_id, 20.00, true, now() - interval '2 days'),
    ('eeeeeeee-0005-0005-0005-000000000005', reviewer_id, 15.00, true, now() - interval '1 day'),
    ('eeeeeeee-0005-0005-0005-000000000005', alice_id, 15.00, false, null),
    ('eeeeeeee-0005-0005-0005-000000000005', bob_id, 15.00, false, null)
  on conflict (expense_id, user_id) do update
  set amount = excluded.amount,
      is_settled = excluded.is_settled,
      settled_at = excluded.settled_at;

  insert into public.ious (id, created_by, lender_id, borrower_id, amount, currency, description, is_settled)
  values ('ffffffff-ffff-ffff-ffff-ffffffffffff', reviewer_id, reviewer_id, alice_id, 25.00, 'USD', 'Concert tickets', false)
  on conflict (id) do update
  set created_by = excluded.created_by,
      lender_id = excluded.lender_id,
      borrower_id = excluded.borrower_id,
      amount = excluded.amount,
      currency = excluded.currency,
      description = excluded.description,
      is_settled = excluded.is_settled;

  insert into public.comments (id, expense_id, user_id, text, created_at)
  values
    ('99999999-0001-0001-0001-000000000001', 'eeeeeeee-0003-0003-0003-000000000003', reviewer_id, 'Great dinner spot.', now() - interval '3 days'),
    ('99999999-0002-0002-0002-000000000002', 'eeeeeeee-0005-0005-0005-000000000005', alice_id, 'Thanks for grabbing snacks.', now() - interval '1 day')
  on conflict (id) do update
  set expense_id = excluded.expense_id,
      user_id = excluded.user_id,
      text = excluded.text,
      created_at = excluded.created_at;
end $$;
