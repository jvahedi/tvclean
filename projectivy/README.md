# Projectivy layout scripts

Rebuild the home layout after a Projectivy reset/reinstall or on another TV. They drive the
UI over adb (keyevents + `uiautomator dump`), so keep the TV untouched while they run.

1. `./hide-row.sh`  — hides every TV Apps tile except `KEEP` (hidden apps stay in *All apps*).
   Only ever taps a menu item labelled exactly "Hide" (Uninstall is in the same menu).
2. `./order-row.sh` — moves the kept tiles into `ORDER`. Run it again until it reports no moves.
3. Rows (TV Apps → Watch Next → Inputs → Settings) were reordered by hand: header ⟵ Reorder.

Edit `KEEP` / `ORDER` at the top of each script. Timing notes: Projectivy's reorder mode drops
keypresses sent faster than ~0.25s, and the first press after tapping a menu item needs ~0.6s.
`tap.sh "Label"` taps an on-screen item by its exact text.

A settings export also exists on the TV itself (Projectivy settings → Manage settings →
Export → Save locally, 2026-10-30); it lives in Projectivy's private storage.
