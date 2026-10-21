# Verbindliche Supabase Data API Sicherheitsrichtlinie

Beschluss: 21.10.2026. Verbindlich fuer neue Tabellen, Migrationen, RPCs, CI und Wiederherstellung.

1. Neue Tabellen sind standardmaessig nicht ueber Data API erreichbar. Fuer den Ersteller postgres werden automatische Berechtigungen neuer public-Tabellen, Funktionen und Sequenzen gegenueber anon, authenticated und service_role widerrufen. Neue GRANTs nur ausdruecklich in derselben Migration.
2. Fuer jede neue API-Tabelle muessen CREATE TABLE, ENABLE ROW LEVEL SECURITY, passgenaue RLS-Policies und explizite minimale GRANT-Rechte zusammen in derselben Migration stehen. Nur erforderliche SELECT/INSERT/UPDATE/DELETE-, Sequenz- und RPC-Rechte vergeben.
3. authenticated allein genuegt nicht: Policies muessen an Nutzer-/Eigentuemer-/Einladungsumfang gebunden sein. service_role niemals in Client oder oeffentlichen Quellcode.
4. Interne Daten gehoeren in nicht API-exponierte Schemas. Neue interne public-Tabellen nur mit RLS, ausdruecklich dokumentierter Ausnahme (data-api: internal-only <table>) und REVOKE ALL.
5. Keine pauschalen GRANT ALL ON ALL TABLES oder ALTER DEFAULT PRIVILEGES ... GRANT auf API-Rollen. SECURITY DEFINER/RPC nur nach pruefbarer Kontrolle von Zugriffen, Eingaben, search_path, Ausgabe und Rate-Limits.
6. Jede Migration mit tatsaechlich registrierter Versionsnummer im supabase/migrations Verzeichnis nachfuehren. Ein separates database/*.sql-Verzeichnis ersetzt keine reproduzierbare Migrationskette. Neue Projekte/Branches/db reset isoliert pruefen.
7. CI-/Unit-Tests nur mit synthetischen Daten und niemals produktiven Supabase-Aufrufen. SQL-Guard unter scripts/check_data_api_migrations.py und GitHub Actions workflow data-api-permissions.yml ist verbindlich, zusaetzlich Supabase Security Advisors und Rollen-/RLS-Matrix pruefen.
8. Bestehende Grants und RPCs nicht blind aendern; Einladung, Profil, Live-Daten, Importe und private Familien-/Kinderdaten muessen unveraendert funktionieren.

Beispiel: CREATE TABLE public.example_items(id uuid primary key, owner_id uuid not null); ALTER TABLE public.example_items ENABLE ROW LEVEL SECURITY; CREATE POLICY owner_read ON public.example_items FOR SELECT TO authenticated USING ((select auth.uid())=owner_id); GRANT SELECT ON public.example_items TO authenticated;

Offizielle Referenz: https://supabase.com/docs/guides/api/securing-your-api

Projekt: JohannasGartenwelt
Supabase ilfblkqxbldkzmqczbgo. Live-Haertung 20261021043026_data_api_opt_in_strict_defaults_20261021. Vorherige Haertung 20260924070028.
