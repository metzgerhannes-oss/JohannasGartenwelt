-- Vokabeltrainer family sync v3: tighten internal RPC helper boundary.
-- Public RPC wrappers continue to call the private SECURITY DEFINER implementations.
-- The device-context helper itself is never a browser RPC entrypoint.
revoke execute on function private.vt_device_context(text,text,text) from anon, authenticated, public;
