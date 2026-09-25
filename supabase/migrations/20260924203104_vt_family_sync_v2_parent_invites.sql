-- Vokabeltrainer family/device sync v2: one-time parent invites
-- Enables secure QR/link pairing of an additional parent device without exposing the reusable family PIN.

create table if not exists private.vt_parent_invites (
  token_hash text primary key,
  family_id text not null references private.vt_families(family_id) on delete cascade,
  created_by_device_id text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  constraint vt_parent_invite_token_hash_format check (token_hash ~ '^[0-9a-f]{64}$')
);
alter table private.vt_parent_invites enable row level security;
create index if not exists vt_parent_invites_family_idx on private.vt_parent_invites(family_id);
revoke all on private.vt_parent_invites from public, anon, authenticated;

create or replace function private.vt_create_parent_invite_impl(p_family_id text,p_device_id text,p_device_secret text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_ctx jsonb;
  v_token text;
  v_hash text;
  v_expires timestamptz := now()+interval '15 minutes';
begin
  v_ctx:=private.vt_device_context(p_family_id,p_device_id,p_device_secret);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true or v_ctx->>'role'<>'parent'
    then return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  delete from private.vt_parent_invites where expires_at<now() or used_at is not null;
  v_token:=encode(extensions.gen_random_bytes(24),'hex');
  v_hash:=encode(extensions.digest(v_token,'sha256'),'hex');
  insert into private.vt_parent_invites(token_hash,family_id,created_by_device_id,expires_at)
  values(v_hash,v_ctx->>'family_id',trim(p_device_id),v_expires);
  return jsonb_build_object('ok',true,'token',v_token,'expires_at',v_expires);
end;
$$;

create or replace function private.vt_claim_parent_invite_impl(p_invite_token text,p_device_id text,p_device_secret text,p_label text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_hash text := encode(extensions.digest(coalesce(p_invite_token,''),'sha256'),'hex');
  v_inv private.vt_parent_invites%rowtype;
  v_docs jsonb;
begin
  if trim(coalesce(p_device_id,'')) !~ '^[A-Za-z0-9_-]{8,120}$' or length(coalesce(p_device_secret,''))<32 or length(p_device_secret)>256
    then return jsonb_build_object('ok',false,'error','invalid_device'); end if;
  select * into v_inv from private.vt_parent_invites where token_hash=v_hash and used_at is null and expires_at>now() for update;
  if not found then return jsonb_build_object('ok',false,'error','invite_invalid'); end if;
  if exists(select 1 from private.vt_devices where family_id=v_inv.family_id and device_id=trim(p_device_id))
    then return jsonb_build_object('ok',false,'error','device_exists'); end if;
  insert into private.vt_devices(family_id,device_id,device_secret_hash,role,label)
  values(v_inv.family_id,trim(p_device_id),extensions.crypt(p_device_secret,extensions.gen_salt('bf',12)),'parent',left(coalesce(p_label,''),120));
  update private.vt_parent_invites set used_at=now() where token_hash=v_hash;
  select coalesce(jsonb_agg(jsonb_build_object('key',doc_key,'revision',revision,'payload',payload,'updated_at',updated_at) order by doc_key),'[]'::jsonb)
    into v_docs from private.vt_documents where family_id=v_inv.family_id;
  return jsonb_build_object('ok',true,'family_id',v_inv.family_id,'role','parent','documents',v_docs);
end;
$$;

create or replace function public.vt_create_parent_invite(p_family_id text,p_device_id text,p_device_secret text)
returns jsonb language sql set search_path='' as $$
  select private.vt_create_parent_invite_impl(p_family_id,p_device_id,p_device_secret);
$$;

create or replace function public.vt_claim_parent_invite(p_invite_token text,p_device_id text,p_device_secret text,p_label text)
returns jsonb language sql set search_path='' as $$
  select private.vt_claim_parent_invite_impl(p_invite_token,p_device_id,p_device_secret,p_label);
$$;

revoke execute on function private.vt_create_parent_invite_impl(text,text,text) from public, authenticated;
revoke execute on function private.vt_claim_parent_invite_impl(text,text,text,text) from public, authenticated;
grant execute on function private.vt_create_parent_invite_impl(text,text,text) to anon;
grant execute on function private.vt_claim_parent_invite_impl(text,text,text,text) to anon;

revoke execute on function public.vt_create_parent_invite(text,text,text) from public, authenticated;
revoke execute on function public.vt_claim_parent_invite(text,text,text,text) from public, authenticated;
grant execute on function public.vt_create_parent_invite(text,text,text) to anon;
grant execute on function public.vt_claim_parent_invite(text,text,text,text) to anon;
