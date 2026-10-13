# InsurgencySandstormStyleReloadForNQR

A Payday 2 mod that treats magazines as actual things. You no longer have "120 rounds in reserve", you have a handful of magazines that are all filled differently. It's built on top of NQR and won't run without it.

I made this for myself because it annoyed me that a half-empty magazine just vanishes when you reload. Here it goes back into your supply.

## How it plays

When you reload, the fullest magazine goes in first. The old one goes back into your supply with whatever rounds are still in it, and gets used again later. The round in the chamber stays where it is.

Ammo you pick up doesn't go into magazines, it ends up as loose rounds. Up to the cap you set in the options (default 100% of starting ammo).

You have to stuff those loose rounds into magazines yourself:

- **Tap R** to reload as usual.
- **Hold R** (longer than NQR's retention time, otherwise 0.2 s) to bring up the HUD. If you have loose rounds and a magazine that isn't full, the weapon gets holstered and refills round by round until you let go or everything is full. This doesn't happen in the middle of a reload, since that would cancel it.

The ammo bag fills the magazines directly. Whatever doesn't fit stays loose. With the "unblock bag" option you can use the bag even when your total ammo is full but some magazines still have room. Otherwise the game just says "full".

If NQR makes you drop a magazine during a reload, it lies on the ground. Look at it, hold the interact key for one second, and it's yours again. Your weapon is holstered briefly while you do it. You can only pick it up while there's room in your supply.

Every level start (new day) resets the magazine supply.

## HUD

A row of boxes shows up at the bottom right. The first one is the magazine in the weapon, with a white line above it. After that come the magazines in your supply, fullest first. If there's no magazine in the weapon right now, the first box is dashed with an X. If they don't all fit in the row, there's a "+3" or similar at the end.

Above it (if you turn it on) are the magazine count and the loose rounds, below it the next magazine and the caliber. The number next to the weapon icon in the normal HUD shows magazines instead of reserve rounds for affected weapons.

By default the panel is only there while you hold R. "Overlay always on" keeps it up permanently.

## Settings

All under the mod options, entry InsurgencySandstormStyleReloadForNQR.

Magazines:

| Option | What it does |
|---|---|
| Enabled | Turns the whole mod on/off |
| Extra magazines | 0 to 2 empty magazines on top of the normal amount |
| Max ammo | Cap for loot, 100 to 200% of starting amount |
| Overlay always on | HUD always visible |
| Show magazine count | Header and footer with numbers |
| Show loose rounds | Counter for loose ammo |
| Show caliber | Caliber in the footer |
| Max boxes | How many boxes in one row, 2 to 24 |
| Show "+X" | Shows how many magazines no longer fit in the row |
| Font size | 10 to 28 |
| Padding right / bottom | Position of the panel |

Refill:

| Option | What it does |
|---|---|
| Enabled | Refilling by holding R on/off |
| Speed | Seconds per round, 0.02 to 1 |
| Sound | Sound when a magazine is full |
| Unblock bag | See above |

The button at the very bottom resets everything.

Settings are saved to `issr_settings.txt` and `issr_reload_settings.txt` in BLT's save folder. If something goes wrong you can just delete them.

## What isn't affected

The mod leaves a weapon alone if it

- is a shotgun with single-shell reloading,
- is flagged as "special",
- is an underbarrel secondary,
- has no detectable magazine part.

Those use the normal game behavior.

## Installation

Put the folder in `mods/`. You need SuperBLT and NQR. In the `mod.txt` the files have to be hooked up like this:

- `menu.lua` on the menu manager (it also loads `state.lua`)
- `main.lua` on `PlayerStandard`
- `day_reset.lua` on `GameSetup`

Texts live in `loc/<language>.txt`, English is the fallback. Missing HUD texts fall back to the built-in strings. If you want to translate them, you need these keys:

```
issr_hud_mags
issr_hud_loose
issr_hud_next
issr_hud_no_mag
issr_pickup
```

## Files

```
lua/
  main.lua          loads the parts, reports load errors in the BLT log
  menu.lua          menu, built from the schema
  state.lua         settings (schema), magazine logic, hook helpers
  hud.lua           the panel
  hooks_weapon.lua  reloading, loot, ammo bag
  hooks_player.lua  R tap/hold, pickup, per-frame stuff
  day_reset.lua     reset on a new day
```

New setting? Add one line to the schema in `state.lua`, plus `<id>_title` and `<id>_desc` in the loc files. The menu builds itself.

## If something doesn't work

Look for `[issr]` in the BLT log. If a part fails to load, it says which one and why. If another mod messes with the same reload functions, things can get rough. This mod only wraps its hooks once, but I can't promise anything.
