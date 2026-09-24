# Supabase Recovery – Johanna's Gartenwelt + Vokabeltrainer

Dieses Repository ist die kanonische Quelle für das gemeinsam genutzte Supabase-Backend beider Apps.

## Zwei unterschiedliche Quellen

- `supabase/migrations/` enthält die unveränderte, in Supabase gespeicherte Cloud-Migrationshistorie seit 2026-09-13.
- `supabase/bootstrap_current.sql` ist der verifizierte Current-State-Bootstrap für ein **neues, leeres Supabase-Projekt**.

Die historische Kette beginnt erst nach der ursprünglichen Gartenwelt-Einrichtung. Deshalb darf ein neues Projekt nicht ausschließlich durch Replay der historischen Migrationen aufgebaut werden.

## Wiederherstellung eines neuen Projekts

1. Neues Supabase-Projekt anlegen.
2. `supabase/bootstrap_current.sql` als Projekt-Admin/Postgres vollständig ausführen.
3. Prüfen:
   - private Tabellen: `jgw_gardens`, `jgw_rate_limits`, `vt_families`, `vt_devices`, `vt_documents`, `vt_invites`
   - RLS auf allen privaten Tabellen aktiv
   - keine direkten `anon`/`authenticated`-Tabellenrechte
   - `service_role` hat keine Garten-App-RPC-Rechte; privilegiert genutzt wird es nur serverseitig für Storage
   - Default-Privileges für neue `public`-Tabellen/Funktionen/Sequenzen sind geschlossen; benötigte Data-API-Rechte werden explizit pro Migration vergeben
   - `pgrst.db_pre_request = private.jgw_pre_request`
   - privater Storage-Bucket `jgw-photos`, 5 MB, nur JPEG/WebP/PNG
4. Die vier Edge Functions aus `supabase/functions/` deployen:
   - `jgw-photo`
   - `trefle-enrich`
   - `jgw-calendar`
   - `muell-moessingen`
5. Bei allen vier Funktionen den bestehenden öffentlichen Gateway-Modus `verify_jwt=false` beibehalten. Dieser Zustand ist zusätzlich in `supabase/config.toml` festgeschrieben und wird vom Recovery-CI geprüft. Die geschützten Funktionen authentisieren innerhalb der Function bzw. über nicht erratbare Tokens; `muell-moessingen` ist bewusst ein öffentlicher Read-only-Proxy.
6. Das externe Secret `TREFLE_TOKEN` im neuen Projekt setzen. Supabase-eigene Function-Umgebungswerte wie Projekt-URL und Service-Role werden nicht in GitHub gespeichert.
7. Danach Security- und Performance-Advisors prüfen sowie die App-/Sync-Smokes ausführen.

## Regeln

- Keine dauerhafte DDL-Änderung nur im Dashboard/SQL-Editor belassen: jede produktive Änderung muss als Migration im Repository landen.
- Jede Migration, die ein Data-API-Objekt anlegt, muss die minimal nötigen `GRANT`s im selben Skript explizit setzen. Keine Abhängigkeit von automatischen Default-Grants.
- Edge-Function-Produktionscode muss bytegleich zur jeweiligen Datei unter `supabase/functions/<name>/index.ts` sein.
- `service_role`, Trefle-Token oder andere Secrets dürfen nie in GitHub landen.
- `supabase_setup.sql` bleibt die lesbare Gartenwelt-/Shared-Baseline. Der vollständige Recovery-Einstiegspunkt ist ausschließlich `supabase/bootstrap_current.sql`.
