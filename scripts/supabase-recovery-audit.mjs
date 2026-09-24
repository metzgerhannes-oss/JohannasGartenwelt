import fs from "node:fs";
import path from "node:path";

const expectedMigrations = [
  "20260913130210_create_jgw_photo_storage_bucket.sql",
  "20260913130836_secure_rls_auto_enable_function.sql",
  "20260913143037_grant_photo_edge_service_role_rpc.sql",
  "20260913143059_grant_photo_edge_service_role_private_rpc.sql",
  "20260919162352_add_automatic_garden_calendar_feed.sql",
  "20260919165100_harden_jgw_gardens_rls_and_rpc_boundary.sql",
  "20260919165143_fix_calendar_token_rotation_search_path.sql",
  "20260919165259_refine_jgw_rls_rpc_boundary.sql",
  "20260919191636_harden_jgw_master_secret_bcrypt_v2.sql",
  "20260920090414_jgw_rpc_rate_limit_hardening.sql",
  "20260920090450_fix_jgw_rpc_rate_limit_coalesce.sql",
  "20260921092507_create_vokabeltrainer_family_sync_v1.sql",
  "20260921092520_index_vokabeltrainer_invites_family.sql",
  "20260921094351_enable_rls_jgw_rate_limits.sql",
  "20260921100151_harden_vt_rate_limits.sql",
  "20260921134427_global_rate_limit_cleanup.sql",
  "20260924070028_harden_data_api_default_privileges.sql"
];

const actualMigrations = fs.readdirSync("supabase/migrations")
  .filter(name => name.endsWith(".sql"))
  .sort();
const expectedSorted = [...expectedMigrations].sort();

function fail(message) {
  console.error("SUPABASE RECOVERY AUDIT FAILED:", message);
  process.exitCode = 1;
}

if (JSON.stringify(actualMigrations) !== JSON.stringify(expectedSorted)) {
  fail("Migrationsinventar weicht von der verifizierten Cloud-Historie ab.\nExpected: " +
    expectedSorted.join(", ") + "\nActual: " + actualMigrations.join(", "));
}

for (const name of expectedMigrations) {
  const content = fs.readFileSync(path.join("supabase/migrations", name), "utf8");
  if (!content.trim()) fail("Leere Migration: " + name);
}

const bootstrap = fs.readFileSync("supabase/bootstrap_current.sql", "utf8");
const gardenBaseline = fs.readFileSync("supabase_setup.sql", "utf8").trim();
const vtBaseline = fs.readFileSync(
  "supabase/migrations/20260921092507_create_vokabeltrainer_family_sync_v1.sql",
  "utf8"
).trim();

if (!bootstrap.includes(gardenBaseline)) fail("Gartenwelt-Baseline fehlt im Bootstrap");
if (!bootstrap.includes(vtBaseline)) fail("VT-Family-Sync-Baseline fehlt im Bootstrap");

const requiredBootstrapMarkers = [
  "create extension if not exists pgcrypto with schema extensions",
  "alter default privileges for role postgres in schema public",
  "revoke select, insert, update, delete on tables from anon, authenticated, service_role",
  "revoke execute on functions from public",
  "CREATE OR REPLACE FUNCTION public.rls_auto_enable()",
  "create event trigger ensure_rls",
  "private.jgw_gardens",
  "private.jgw_rate_limits",
  "private.vt_families",
  "private.vt_devices",
  "private.vt_documents",
  "private.vt_invites",
  "jgw_rate_limits_requested_at_idx",
  "where requested_at < pg_catalog.now() - interval '24 hours'",
  "'jgw-photos'",
  "5242880",
  "image/jpeg",
  "image/webp",
  "image/png",
  "alter role authenticator set pgrst.db_pre_request = 'private.jgw_pre_request'",
  "grant execute on function public.jgw_status_garden(text,text) to service_role"
];
for (const marker of requiredBootstrapMarkers) {
  if (!bootstrap.includes(marker)) fail("Bootstrap-Marker fehlt: " + marker);
}

const edgeFunctions = ["jgw-photo", "trefle-enrich", "jgw-calendar", "muell-moessingen"];
for (const name of edgeFunctions) {
  const file = path.join("supabase/functions", name, "index.ts");
  if (!fs.existsSync(file) || !fs.readFileSync(file, "utf8").trim()) {
    fail("Edge Function Source fehlt: " + file);
  }
}

const forbiddenSecretPatterns = [
  /SUPABASE_SERVICE_ROLE_KEY\s*=\s*["'][^"']+["']/i,
  /sb_secret_[A-Za-z0-9_-]+/,
  /BEGIN PRIVATE KEY/,
  /TREFLE_TOKEN\s*=\s*["'][^"']+["']/i
];
const sourceFiles = [
  "supabase/bootstrap_current.sql",
  "supabase_setup.sql",
  ...edgeFunctions.map(name => path.join("supabase/functions", name, "index.ts"))
];
for (const file of sourceFiles) {
  const content = fs.readFileSync(file, "utf8");
  for (const pattern of forbiddenSecretPatterns) {
    if (pattern.test(content)) fail("Mögliches Secret in " + file + ": " + pattern);
  }
}

if (!process.exitCode) {
  console.log("SUPABASE_RECOVERY_AUDIT_OK migrations=" + expectedMigrations.length +
    " functions=" + edgeFunctions.length);
}
