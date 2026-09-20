# Vendored browser libraries

Pinned local copies used to keep executable JavaScript and styles on the app's own origin.

- Leaflet 1.9.4 — source: cdnjs repository / Leaflet release — BSD-2-Clause
- Leaflet.draw 1.0.4 — source: cdnjs repository / Leaflet.draw release — MIT
- qrcode.js 1.0.0 — source: cdnjs repository / davidshimjs/qrcodejs — MIT

Leaflet/Leaflet.draw CSS image references intentionally point to their fixed-version cdnjs image assets. These are non-executable images and remain covered by the app's existing `img-src https:` policy.
