
create schema if not exists private;

create table if not exists private.vt_families (
  family_id text primary key,
  secret_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vt_family_id_format check (family_id ~ '^[a-z0-9_-]{6,80}$')
);
alter table private.vt_families enable row level security;

create table if not exists private.vt_devices (
  family_id text not null references private.vt_families(family_id) on delete cascade,
  device_id text not null,
  device_secret_hash text not null,
  role text not null check (role in ('parent','child')),
  profile_id text,
  label text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (family_id, device_id),
  constraint vt_device_id_format check (device_id ~ '^[A-Za-z0-9_-]{8,120}$'),
  constraint vt_child_profile_required check ((role='parent' and profile_id is null) or (role='child' and profile_id is not null))
);
alter table private.vt_devices enable row level security;

create table if not exists private.vt_documents (
  family_id text not null references private.vt_families(family_id) on delete cascade,
  doc_key text not null,
  revision bigint not null default 1 check (revision > 0),
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (family_id, doc_key),
  constraint vt_doc_key_format check (
    doc_key='shared'
    or doc_key ~ '^profile/[A-Za-z0-9_-]{3,120}/(setup|progress)$'
  )
);
alter table private.vt_documents enable row level security;

create table if not exists private.vt_invites (
  token_hash text primary key,
  family_id text not null references private.vt_families(family_id) on delete cascade,
  profile_id text not null,
  created_by_device_id text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  constraint vt_invite_token_hash_format check (token_hash ~ '^[0-9a-f]{64}$')
);
alter table private.vt_invites enable row level security;

revoke all on private.vt_families, private.vt_devices, private.vt_documents, private.vt_invites from public, anon, authenticated;

create or replace function private.vt_device_context(
  p_family_id text,
  p_device_id text,
  p_device_secret text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family text := lower(trim(coalesce(p_family_id,'')));
  v_device private.vt_devices%rowtype;
begin
  select * into v_device
  from private.vt_devices
  where family_id=v_family
    and device_id=trim(coalesce(p_device_id,''))
    and active=true
    and device_secret_hash=extensions.crypt(coalesce(p_device_secret,''),device_secret_hash);

  if not found then
    return jsonb_build_object('ok',false,'error','unauthorized');
  end if;

  update private.vt_devices
     set last_seen_at=now()
   where family_id=v_family and device_id=v_device.device_id;

  return jsonb_build_object(
    'ok',true,
    'family_id',v_family,
    'device_id',v_device.device_id,
    'role',v_device.role,
    'profile_id',v_device.profile_id
  );
end;
$$;

create or replace function private.vt_create_family_impl(
  p_family_id text,
  p_family_secret_hash text,
  p_device_id text,
  p_device_secret text,
  p_label text,
  p_documents jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family text := lower(trim(coalesce(p_family_id,'')));
  v_key text;
  v_payload jsonb;
begin
  if v_family !~ '^[a-z0-9_-]{6,80}$' then
    return jsonb_build_object('ok',false,'error','invalid_family_id');
  end if;
  if length(coalesce(p_family_secret_hash,''))<>64 or p_family_secret_hash !~ '^[0-9a-fA-F]{64}$' then
    return jsonb_build_object('ok',false,'error','invalid_family_secret');
  end if;
  if trim(coalesce(p_device_id,'')) !~ '^[A-Za-z0-9_-]{8,120}$' then
    return jsonb_build_object('ok',false,'error','invalid_device_id');
  end if;
  if length(coalesce(p_device_secret,''))<32 or length(p_device_secret)>256 then
    return jsonb_build_object('ok',false,'error','invalid_device_secret');
  end if;
  if jsonb_typeof(coalesce(p_documents,'{}'::jsonb))<>'object' then
    return jsonb_build_object('ok',false,'error','invalid_documents');
  end if;
  if pg_column_size(coalesce(p_documents,'{}'::jsonb))>33554432 then
    return jsonb_build_object('ok',false,'error','payload_too_large');
  end if;

  insert into private.vt_families(family_id,secret_hash)
  values(v_family,extensions.crypt(lower(p_family_secret_hash),extensions.gen_salt('bf',12)));

  insert into private.vt_devices(family_id,device_id,device_secret_hash,role,label)
  values(v_family,trim(p_device_id),extensions.crypt(p_device_secret,extensions.gen_salt('bf',12)),'parent',left(coalesce(p_label,''),120));

  for v_key,v_payload in select key,value from jsonb_each(coalesce(p_documents,'{}'::jsonb))
  loop
    if not (v_key='shared' or v_key ~ '^profile/[A-Za-z0-9_-]{3,120}/(setup|progress)$') then
      raise exception 'invalid_doc_key';
    end if;
    if pg_column_size(v_payload)>16777216 then
      raise exception 'document_too_large';
    end if;
    insert into private.vt_documents(family_id,doc_key,payload)
    values(v_family,v_key,coalesce(v_payload,'{}'::jsonb));
  end loop;

  return jsonb_build_object('ok',true,'family_id',v_family,'role','parent');
exception
  when unique_violation then return jsonb_build_object('ok',false,'error','exists');
  when others then
    if sqlerrm in ('invalid_doc_key','document_too_large') then
      return jsonb_build_object('ok',false,'error',sqlerrm);
    end if;
    raise;
end;
$$;

create or replace function private.vt_join_parent_impl(
  p_family_id text,
  p_family_secret_hash text,
  p_device_id text,
  p_device_secret text,
  p_label text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family text := lower(trim(coalesce(p_family_id,'')));
begin
  if trim(coalesce(p_device_id,'')) !~ '^[A-Za-z0-9_-]{8,120}$'
     or length(coalesce(p_device_secret,''))<32 or length(p_device_secret)>256 then
    return jsonb_build_object('ok',false,'error','invalid_device');
  end if;

  perform 1 from private.vt_families
   where family_id=v_family
     and secret_hash=extensions.crypt(lower(coalesce(p_family_secret_hash,'')),secret_hash);
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;

  if exists(select 1 from private.vt_devices where family_id=v_family and device_id=trim(p_device_id)) then
    return jsonb_build_object('ok',false,'error','device_exists');
  end if;

  insert into private.vt_devices(family_id,device_id,device_secret_hash,role,label)
  values(v_family,trim(p_device_id),extensions.crypt(p_device_secret,extensions.gen_salt('bf',12)),'parent',left(coalesce(p_label,''),120));

  return jsonb_build_object('ok',true,'family_id',v_family,'role','parent');
end;
$$;

create or replace function private.vt_create_child_invite_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text,
  p_profile_id text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_profile text := trim(coalesce(p_profile_id,''));
  v_token text;
  v_hash text;
  v_expires timestamptz := now()+interval '15 minutes';
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true or v_ctx->>'role'<>'parent' then
    return jsonb_build_object('ok',false,'error','unauthorized');
  end if;
  if v_profile !~ '^[A-Za-z0-9_-]{3,120}$' then
    return jsonb_build_object('ok',false,'error','invalid_profile_id');
  end if;
  if not exists(
    select 1 from private.vt_documents
    where family_id=v_ctx->>'family_id' and doc_key='profile/'||v_profile||'/setup'
  ) then
    return jsonb_build_object('ok',false,'error','profile_not_found');
  end if;

  delete from private.vt_invites where expires_at<now() or used_at is not null;
  v_token:=encode(extensions.gen_random_bytes(24),'hex');
  v_hash:=encode(extensions.digest(v_token,'sha256'),'hex');
  insert into private.vt_invites(token_hash,family_id,profile_id,created_by_device_id,expires_at)
  values(v_hash,v_ctx->>'family_id',v_profile,trim(p_device_id),v_expires);

  return jsonb_build_object('ok',true,'token',v_token,'profile_id',v_profile,'expires_at',v_expires);
end;
$$;

create or replace function private.vt_claim_child_invite_impl(
  p_invite_token text,
  p_device_id text,
  p_device_secret text,
  p_label text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := encode(extensions.digest(coalesce(p_invite_token,''),'sha256'),'hex');
  v_inv private.vt_invites%rowtype;
  v_docs jsonb;
begin
  if trim(coalesce(p_device_id,'')) !~ '^[A-Za-z0-9_-]{8,120}$'
     or length(coalesce(p_device_secret,''))<32 or length(p_device_secret)>256 then
    return jsonb_build_object('ok',false,'error','invalid_device');
  end if;

  select * into v_inv from private.vt_invites
   where token_hash=v_hash and used_at is null and expires_at>now()
   for update;
  if not found then return jsonb_build_object('ok',false,'error','invite_invalid'); end if;

  if exists(select 1 from private.vt_devices where family_id=v_inv.family_id and device_id=trim(p_device_id)) then
    return jsonb_build_object('ok',false,'error','device_exists');
  end if;

  insert into private.vt_devices(family_id,device_id,device_secret_hash,role,profile_id,label)
  values(v_inv.family_id,trim(p_device_id),extensions.crypt(p_device_secret,extensions.gen_salt('bf',12)),'child',v_inv.profile_id,left(coalesce(p_label,''),120));

  update private.vt_invites set used_at=now() where token_hash=v_hash;

  select coalesce(jsonb_agg(jsonb_build_object('key',doc_key,'revision',revision,'payload',payload,'updated_at',updated_at) order by doc_key),'[]'::jsonb)
    into v_docs
    from private.vt_documents
   where family_id=v_inv.family_id
     and doc_key in ('shared','profile/'||v_inv.profile_id||'/setup','profile/'||v_inv.profile_id||'/progress');

  return jsonb_build_object('ok',true,'family_id',v_inv.family_id,'role','child','profile_id',v_inv.profile_id,'documents',v_docs);
end;
$$;

create or replace function private.vt_pull_documents_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_docs jsonb;
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true then return v_ctx; end if;

  select coalesce(jsonb_agg(jsonb_build_object('key',doc_key,'revision',revision,'payload',payload,'updated_at',updated_at) order by doc_key),'[]'::jsonb)
    into v_docs
    from private.vt_documents
   where family_id=v_ctx->>'family_id'
     and (
       v_ctx->>'role'='parent'
       or doc_key='shared'
       or doc_key='profile/'||(v_ctx->>'profile_id')||'/setup'
       or doc_key='profile/'||(v_ctx->>'profile_id')||'/progress'
     );

  return jsonb_build_object('ok',true,'family_id',v_ctx->>'family_id','role',v_ctx->>'role','profile_id',v_ctx->>'profile_id','documents',v_docs);
end;
$$;

create or replace function private.vt_status_documents_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_docs jsonb;
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true then return v_ctx; end if;

  select coalesce(jsonb_agg(jsonb_build_object('key',doc_key,'revision',revision,'updated_at',updated_at) order by doc_key),'[]'::jsonb)
    into v_docs
    from private.vt_documents
   where family_id=v_ctx->>'family_id'
     and (
       v_ctx->>'role'='parent'
       or doc_key='shared'
       or doc_key='profile/'||(v_ctx->>'profile_id')||'/setup'
       or doc_key='profile/'||(v_ctx->>'profile_id')||'/progress'
     );

  return jsonb_build_object('ok',true,'family_id',v_ctx->>'family_id','role',v_ctx->>'role','profile_id',v_ctx->>'profile_id','documents',v_docs);
end;
$$;

create or replace function private.vt_push_document_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text,
  p_doc_key text,
  p_payload jsonb,
  p_base_revision bigint
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_key text := trim(coalesce(p_doc_key,''));
  v_revision bigint;
  v_updated timestamptz;
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true then return v_ctx; end if;
  if not (v_key='shared' or v_key ~ '^profile/[A-Za-z0-9_-]{3,120}/(setup|progress)$') then
    return jsonb_build_object('ok',false,'error','invalid_doc_key');
  end if;
  if pg_column_size(coalesce(p_payload,'{}'::jsonb))>16777216 then
    return jsonb_build_object('ok',false,'error','payload_too_large');
  end if;

  if v_ctx->>'role'='child' then
    if v_key <> 'profile/'||(v_ctx->>'profile_id')||'/progress' then
      return jsonb_build_object('ok',false,'error','forbidden');
    end if;
  end if;

  if coalesce(p_base_revision,0)=0 then
    begin
      insert into private.vt_documents(family_id,doc_key,revision,payload,updated_at)
      values(v_ctx->>'family_id',v_key,1,coalesce(p_payload,'{}'::jsonb),now())
      returning revision,updated_at into v_revision,v_updated;
      return jsonb_build_object('ok',true,'revision',v_revision,'updated_at',v_updated);
    exception when unique_violation then
      select revision into v_revision from private.vt_documents where family_id=v_ctx->>'family_id' and doc_key=v_key;
      return jsonb_build_object('ok',false,'conflict',true,'revision',v_revision);
    end;
  end if;

  update private.vt_documents
     set payload=coalesce(p_payload,'{}'::jsonb),revision=revision+1,updated_at=now()
   where family_id=v_ctx->>'family_id' and doc_key=v_key and revision=p_base_revision
   returning revision,updated_at into v_revision,v_updated;

  if found then return jsonb_build_object('ok',true,'revision',v_revision,'updated_at',v_updated); end if;

  select revision into v_revision from private.vt_documents where family_id=v_ctx->>'family_id' and doc_key=v_key;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  return jsonb_build_object('ok',false,'conflict',true,'revision',v_revision);
end;
$$;

create or replace function private.vt_list_devices_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_devices jsonb;
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true or v_ctx->>'role'<>'parent' then
    return jsonb_build_object('ok',false,'error','unauthorized');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('device_id',device_id,'role',role,'profile_id',profile_id,'label',label,'active',active,'last_seen_at',last_seen_at,'created_at',created_at) order by created_at),'[]'::jsonb)
    into v_devices
    from private.vt_devices where family_id=v_ctx->>'family_id';
  return jsonb_build_object('ok',true,'devices',v_devices);
end;
$$;

create or replace function private.vt_revoke_device_impl(
  p_family_id text,
  p_device_id text,
  p_device_secret text,
  p_target_device_id text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true or v_ctx->>'role'<>'parent' then
    return jsonb_build_object('ok',false,'error','unauthorized');
  end if;
  if trim(coalesce(p_target_device_id,''))=trim(coalesce(p_device_id,'')) then
    return jsonb_build_object('ok',false,'error','cannot_revoke_self');
  end if;
  update private.vt_devices set active=false
   where family_id=v_ctx->>'family_id' and device_id=trim(coalesce(p_target_device_id,''));
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.vt_create_family(p_family_id text,p_family_secret_hash text,p_device_id text,p_device_secret text,p_label text,p_documents jsonb)
returns jsonb language sql set search_path='' as $$ select private.vt_create_family_impl(p_family_id,p_family_secret_hash,p_device_id,p_device_secret,p_label,p_documents); $$;
create or replace function public.vt_join_parent(p_family_id text,p_family_secret_hash text,p_device_id text,p_device_secret text,p_label text)
returns jsonb language sql set search_path='' as $$ select private.vt_join_parent_impl(p_family_id,p_family_secret_hash,p_device_id,p_device_secret,p_label); $$;
create or replace function public.vt_create_child_invite(p_family_id text,p_device_id text,p_device_secret text,p_profile_id text)
returns jsonb language sql set search_path='' as $$ select private.vt_create_child_invite_impl(p_family_id,p_device_id,p_device_secret,p_profile_id); $$;
create or replace function public.vt_claim_child_invite(p_invite_token text,p_device_id text,p_device_secret text,p_label text)
returns jsonb language sql set search_path='' as $$ select private.vt_claim_child_invite_impl(p_invite_token,p_device_id,p_device_secret,p_label); $$;
create or replace function public.vt_pull_documents(p_family_id text,p_device_id text,p_device_secret text)
returns jsonb language sql set search_path='' as $$ select private.vt_pull_documents_impl(p_family_id,p_device_id,p_device_secret); $$;
create or replace function public.vt_status_documents(p_family_id text,p_device_id text,p_device_secret text)
returns jsonb language sql set search_path='' as $$ select private.vt_status_documents_impl(p_family_id,p_device_id,p_device_secret); $$;
create or replace function public.vt_push_document(p_family_id text,p_device_id text,p_device_secret text,p_doc_key text,p_payload jsonb,p_base_revision bigint)
returns jsonb language sql set search_path='' as $$ select private.vt_push_document_impl(p_family_id,p_device_id,p_device_secret,p_doc_key,p_payload,p_base_revision); $$;
create or replace function public.vt_list_devices(p_family_id text,p_device_id text,p_device_secret text)
returns jsonb language sql set search_path='' as $$ select private.vt_list_devices_impl(p_family_id,p_device_id,p_device_secret); $$;
create or replace function public.vt_revoke_device(p_family_id text,p_device_id text,p_device_secret text,p_target_device_id text)
returns jsonb language sql set search_path='' as $$ select private.vt_revoke_device_impl(p_family_id,p_device_id,p_device_secret,p_target_device_id); $$;

revoke execute on all functions in schema private from public, authenticated;
grant usage on schema private to anon;
grant execute on function private.vt_device_context(text,text,text) to anon;
grant execute on function private.vt_create_family_impl(text,text,text,text,text,jsonb) to anon;
grant execute on function private.vt_join_parent_impl(text,text,text,text,text) to anon;
grant execute on function private.vt_create_child_invite_impl(text,text,text,text) to anon;
grant execute on function private.vt_claim_child_invite_impl(text,text,text,text) to anon;
grant execute on function private.vt_pull_documents_impl(text,text,text) to anon;
grant execute on function private.vt_status_documents_impl(text,text,text) to anon;
grant execute on function private.vt_push_document_impl(text,text,text,text,jsonb,bigint) to anon;
grant execute on function private.vt_list_devices_impl(text,text,text) to anon;
grant execute on function private.vt_revoke_device_impl(text,text,text,text) to anon;

revoke execute on function public.vt_create_family(text,text,text,text,text,jsonb) from public, authenticated;
revoke execute on function public.vt_join_parent(text,text,text,text,text) from public, authenticated;
revoke execute on function public.vt_create_child_invite(text,text,text,text) from public, authenticated;
revoke execute on function public.vt_claim_child_invite(text,text,text,text) from public, authenticated;
revoke execute on function public.vt_pull_documents(text,text,text) from public, authenticated;
revoke execute on function public.vt_status_documents(text,text,text) from public, authenticated;
revoke execute on function public.vt_push_document(text,text,text,text,jsonb,bigint) from public, authenticated;
revoke execute on function public.vt_list_devices(text,text,text) from public, authenticated;
revoke execute on function public.vt_revoke_device(text,text,text,text) from public, authenticated;

grant execute on function public.vt_create_family(text,text,text,text,text,jsonb) to anon;
grant execute on function public.vt_join_parent(text,text,text,text,text) to anon;
grant execute on function public.vt_create_child_invite(text,text,text,text) to anon;
grant execute on function public.vt_claim_child_invite(text,text,text,text) to anon;
grant execute on function public.vt_pull_documents(text,text,text) to anon;
grant execute on function public.vt_status_documents(text,text,text) to anon;
grant execute on function public.vt_push_document(text,text,text,text,jsonb,bigint) to anon;
grant execute on function public.vt_list_devices(text,text,text) to anon;
grant execute on function public.vt_revoke_device(text,text,text,text) to anon;
