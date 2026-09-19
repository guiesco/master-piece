# Design: Wooden Bow + Arrow Projectile (replace staff)

**Date:** 2026-09-18  
**Status:** Approved (approach A)  
**Scope:** Demo Alvida Hold — second weapon is bow; ranged enemies use bow + LPC arrow VFX.

## Goal

Replace `staff` as the second equippable weapon with `wooden_bow`. Player and ranged enemies use LPC bow layers + `shoot` animation. Ranged combat VFX uses LPC arrow instead of the amber ball projectile.

## Non-goals

- Multiple bow types (great/recurve)
- Inventory migration for existing `staff` saves (demo; fresh characters OK)
- Authoritative projectile physics beyond current PendingHits delay
- Keeping staff as playable weapon

## Content model

| Old | New |
|---|---|
| item `staff` | item `wooden_bow` |
| `staff_thrust` / `staff_bash` | `bow_shot` / `bow_aimed` |
| layer `weapon_staff_wood` | layer `weapon_bow_wood` |
| goon_ranged anim `thrust` | anim `shoot` |
| loot `staff` | loot `wooden_bow` |

### Skills

Both bow skills:
- `anim`: `"shoot"`
- `is_ranged`: `true`
- `requires_weapon`: `"wooden_bow"`
- LMB `bow_shot`: lower CD / moderate damage
- RMB `bow_aimed`: slightly higher damage / longer CD / same range band (~5–6)

Server already supports ranged player skills via `is_ranged` + aim coords; PendingHits applies to enemy ranged — player ranged should also delay damage to impact if not already (verify during impl).

### Weapons.json

```json
{
  "id": "wooden_bow",
  "display_name": "Wooden Bow",
  "damage_bonus": 2,
  "skill_primary": "bow_shot",
  "skill_secondary": "bow_aimed",
  "lpc_layer": "weapon_bow_wood"
}
```

Remove `staff` entry entirely.

### Archetypes

- `goon_melee` loot: `staff` → `wooden_bow`
- `goon_ranged_weak`: `anim: "shoot"`, loot `wooden_bow`; description updated to archer

### LPC catalog

Add `weapon_bow_wood`; remove or leave unused `weapon_staff_wood` (prefer remove from catalog lists used by enemy_gen if staff was in weapon pool — ranged goons should prefer bow).

## Assets (vendor → godot/assets/lpc)

Sync via `tools/sync_lpc_assets.ps1`:

**Bow (normal / medium palette):**
- Walk FG/BG → `weapon_bow_wood.png` / `weapon_bow_wood_bg.png`
- Shoot FG/BG → `weapon_bow_wood_shoot.png` / `weapon_bow_wood_bg_shoot.png`

Vendor paths:
- `weapon/ranged/bow/normal/walk/foreground/medium.png`
- `weapon/ranged/bow/normal/walk/background/medium.png`
- `weapon/ranged/bow/normal/universal/foreground/shoot/medium.png`
- `weapon/ranged/bow/normal/universal/background/shoot/medium.png`

**Arrow (projectile texture):**
- `weapon/ranged/bow/arrow/shoot/arrow.png` → e.g. `godot/assets/fx/arrow.png` (or `lpc/weapon/weapon_arrow_shoot.png` + Projectile uses it)

**Body layers `shoot`:** body, head, hair, eyes, outfit (where vendor has the file) — same pattern as thrust/slash sync.

Remove staff gnarled copies from sync (or leave orphan PNGs; prefer stop syncing staff).

## Godot

### LPCAnimator
- Add `shoot` to anim set (load, play, meta, frame defaults — typically 13 frames / 64 or 128 like LPC shoot sheets)
- `play_anim("shoot")` / `play_shoot()`
- EquipmentVisual: `bow_shot`/`bow_aimed` → `"shoot"`

### EquipmentVisual / Composer
- Map `wooden_bow` → `weapon_bow_wood`
- Remove staff mappings (or alias only if needed — **no alias**; clean rename)

### Projectile
- Texture = LPC arrow crop/frame (first useful frame or full sheet region)
- Orient sprite along flight direction (not billboard-only ball; may keep billboard Y-up with rotation on XZ, or disable billboard and face velocity)
- Same speed 10 u/s; lifetime aligned to PendingHits

### Enemy gen / appearance
- Ranged archetypes get `weapon_layer: weapon_bow_wood` when generating appearance

### AlvidaHold
- Unchanged spawn path for `is_ranged`; Projectile visual change is enough
- Player ranged attacks must spawn arrow VFX (already if `is_ranged` on skill)

## Backend combat notes

- Enemy ranged: already launch + PendingHits
- Player skills with `is_ranged: true`: ensure HandleCombat does not apply instant melee AABB-only if range is long — validate range uses skill.range; delay hit like enemies **if currently instant** (check during impl; fix if player bow also hits instantly)

## Migration / save data

Demo: characters with `staff` in inventory will fail equip until cleared. Acceptable for local MVP. Optional one-line alias in EquipmentVisual only if cheap — **spec says no alias**; document that players should recreate or clear inventory.

## Success criteria

1. Equip `wooden_bow` → bow visible idle/walk; LMB/RMB play `shoot` with bow layers synced
2. Drop/loot shows wooden bow, never staff
3. `goon_ranged_weak` holds bow, shoots with `shoot` anim, flecha LPC flies, damage on impact
4. No amber ball projectile for ranged
5. Staff gone from weapons.json / skill maps

## Spec self-review

- [x] No placeholders TBD for core paths
- [x] Staff fully removed (not dual-supported)
- [x] shoot ≠ thrust called out
- [x] Player ranged delay flagged for verify
- [x] Scope limited to demo weapons + VFX
