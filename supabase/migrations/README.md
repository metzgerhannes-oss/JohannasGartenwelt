# Supabase-Migrationen

Dieser Ordner spiegelt die in Supabase tatsächlich angewendeten Migrationen ab dem Infrastruktur-Audit vom 21.09.2026 wider.

Ältere Garten-Schemaänderungen sind weiterhin vollständig in `/supabase_setup.sql` dokumentiert. Neue produktive DDL-Änderungen sollen ab jetzt zusätzlich mit ihrer echten Supabase-Migrationsversion hier abgelegt werden.

Die Rate-Limit-Infrastruktur schützt sowohl die Garten-App (`jgw_*`) als auch den Vokabeltrainer (`vt_*`), weil beide derzeit dasselbe Supabase-Projekt verwenden.
