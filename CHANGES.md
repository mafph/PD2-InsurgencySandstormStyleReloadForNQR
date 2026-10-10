# nqr_mags — Überarbeitung (Dez 2026)

Vergleich: **Vorher** = alter Stand (dieses Repo, `8639308` + Zwischenstände) vs. **Jetzt** = überarbeitete Version im Install-Ordner.

## Warum vorher nichts funktionierte

1. **Input war nie definiert (Hauptursache).**
   `update_pickup(self, t, input)` wurde in `_get_input` aufgerufen, *bevor*
   `orig_get_input(...)` lief. `input` existierte in dem Scope nirgends →
   Global-Lookup → `nil`. Der Check `if not input or not input.btn_interact_state`
   hat deshalb **jeden Frame vorzeitig returniert**: Taste wurde nie registriert,
   Balken nie gestartet, Pickup nie ausgelöst.

2. **Balken füllte sich nicht.**
   Vorher wurde `show_interaction_bar(progress, total)` *jeden Frame neu* aufgerufen.
   `show` baut die Anzeige jedes Mal neu auf (Reset/Animation) → sichtbar keine Füllung.
   Vanilla-Muster ist: **einmal** `show_interaction_bar(0, total)`, dann pro Frame
   `set_interaction_bar_width(current, total)`.

3. **Timer/Prompt instabil.**
   `pickup_t` wurde beim Zielwechsel gesetzt und beim Loslassen nicht sauber
   zurückgesetzt; `clear_pickup` tötete Prompt + Timer together → Flackern,
   und nach erneutem Drücken war die Zeit schon abgelaufen.

4. **Konflikt mit laufenden Waffen-Aktionen.**
   Der Pickup lief sofort, während die Waffe noch in der Hand war (Nachladen,
   vanilla Interact auf F, Magazin-Animationen überlagerten den Zustand).

## Was die Überarbeitung ändert

### hooks_player.lua
- **Input-Fix:** `local input = orig_get_input(self, t, dt, paused)` läuft *zuerst*,
  `update_pickup(self, t, input)` bekommt den echten Per-Frame-Input,
  Rückgabe ist `input`. Zusätzlich nutzt `update_pickup` wie Vanilla
  `state._controller:get_input_bool("interact")`.
- **Holster-System (neu):** `holster_start/holster_release/holstered` +
  Hook auf `PlayerStandard._update_equip_weapon_timers` (hält den
  Unequip-Timer an). Vor Pickup **und** Refill wird die Waffe weggesteckt;
  der Balken startet erst, wenn sie ganz unten ist.
- **Bar-Pattern:** einmal `show_interaction_bar(0, PICKUP_HOLD)` beim Start,
  dann pro Frame `set_interaction_bar_width(progress * PICKUP_HOLD, PICKUP_HOLD)`.
- **Loslassen:** `bar_stop(false)` setzt `pickup_t` *und* `pickup_tag` zurück →
  Prompt/Balken erscheinen sauber neu, Timer startet frisch.
- **Refill-Logik:** läuft nur bei weggesteckter Waffe, nur wenn `needs_fill(wep)`.
- **Ammo-Deckel:** pro Frame `base:set_ammo_max(api.max_total(base))`
  (Faktor `cfg.total_factor`, Standard 1.5).

### hooks_weapon.lua
- **Stale-Magazin-Fix:** `old_mag.rounds` wird vor der Rückgabe in die Queue mit
  `clip - chamber` synchronisiert (`.rounds` war nach Schüssen veraltet → falsche
  Queue-Buchung). Mit Debug-Logs (`reload: stale mag rounds …`).
- **Loot-Deckel:** `add_ammo` gedeckelt auf `get_ammo_max() - get_ammo_total()`,
  bei 0 → `sync_total` + `false`.
- **Bag:** `sync_total` vor dem Original-Aufruf.

### state.lua
- **`fill_one_round` statt `fill_one_mag`:** füllt pro Tick **eine Patrone**
  (`rcfg.round_interval`, Standard 0.1 s) statt ein ganzes Magazin auf einmal.
  Sound nur, wenn ein Magazin voll geworden ist.
- **`max_total(wep)` (neu):** `ammo_max` = `total_factor × (Volles Magazin +
  Kammer + Magazinanzahl × Magazingröße)`.
- **`needs_fill(wep)` (neu):** prüft ob ein Queue-Magazin unvoll ist.
- Aufräumen: ungenutzte Exports entfernt (`capacity_of`, `full_of`).

### menu.lua
- Refill-Slider: „Sekunden pro Magazin" → **„Sekunden pro Patrone"**
  (`round_interval`, 0.02–1.0), Hinweis „Nur bei weggesteckter Waffe".
- Sound-Beschreibung: „wenn ein Magazin voll ist".

### main.lua / save.lua
- **`save.lua` komplett entfernt** — Datei gelöscht und aus dem Ladepfad
  (`PARTS`) genommen. Die Savegame-Sicherung der Magazin-Queue gibt es nicht mehr.

## Repo / Arbeitsweise
- **Git lebt jetzt im Install-Ordner** (`mods\nqr_mags\.git`). History migriert
  (Commits `421a3b5` v1, `9de867b` v1.1, Präfix `nqr_mags/` gestrippt).
- Dev-Kopie (`Default Project\nqr_mags`) ist nur noch ein Spiegel — Änderungen
  immer direkt an install, dann Dev ← install spiegeln.
- `lua/day_reset.lua` wird pro Level über den `gamesetup`-Hook in mod.txt geladen
  (Magazin-Lager + liegende Magazine zurücksetzen).

## Offene Punkte / Aufräumen
- Dev-Kopie enthält noch ungetrackte Duplikate auf `nqr_mags/`-Root
  (`hooks_player.lua` etc.) — nicht vorhanden an install, löschwürdig.
