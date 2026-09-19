# Wooden Bow + Arrow Projectile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace staff with `wooden_bow` (LPC bow + shoot), and use LPC arrow VFX for all ranged hits (player and `goon_ranged_weak`).

**Architecture:** Content JSON renames staff→bow; sync adds bow/arrow/`shoot` sheets; LPCAnimator gains `shoot`; Projectile uses arrow texture + flight facing; server delays player ranged damage via existing `PendingHits` (same as enemy).

**Tech Stack:** Godot 4 GDScript, Nakama Go plugin, PowerShell LPC sync, Docker rebuild for `.so`.

## Global Constraints

- Item id: `wooden_bow` (no `staff` alias)
- LPC anim for bow attack: `shoot` (never `thrust`)
- Bow palette: `medium` normal bow FG/BG
- Arrow VFX: LPC `weapon/ranged/bow/arrow/shoot/arrow.png`
- No commits unless user asks

---

### Task 1: Content JSON — weapons, skills, archetypes, catalog

**Files:**
- Modify: `backend/content/weapons.json`
- Modify: `backend/content/skills.json`
- Modify: `backend/content/archetypes.json`
- Modify: `backend/content/lpc_catalog.json`

**Interfaces:**
- Produces: item `wooden_bow`, skills `bow_shot`/`bow_aimed`, layer id `weapon_bow_wood`

- [ ] **Step 1: Replace weapons.json staff entry**

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

Keep `wooden_sword` unchanged. Remove `staff` entirely.

- [ ] **Step 2: Replace staff skills with bow skills in skills.json**

Remove `staff_thrust` and `staff_bash`. Add:

```json
{
  "id": "bow_shot",
  "display_name": "Bow Shot",
  "description": "A quick arrow shot.",
  "damage": 8,
  "range": 6.0,
  "cooldown_ms": 900,
  "requires_weapon": "wooden_bow",
  "anim": "shoot",
  "is_ranged": true
},
{
  "id": "bow_aimed",
  "display_name": "Aimed Shot",
  "description": "A heavier aimed arrow.",
  "damage": 11,
  "range": 7.0,
  "cooldown_ms": 1200,
  "requires_weapon": "wooden_bow",
  "anim": "shoot",
  "is_ranged": true
}
```

- [ ] **Step 3: Update archetypes.json**

- `goon_melee` loot: `"staff"` → `"wooden_bow"`
- `goon_ranged_weak`: `"anim": "shoot"`, loot `"wooden_bow"`, update description to archer with bow

- [ ] **Step 4: Update lpc_catalog.json weapons list**

Replace `"weapon_staff_wood"` with `"weapon_bow_wood"`.

- [ ] **Step 5: Verify JSON parses**

Run: `Get-Content backend/content/*.json | ForEach-Object { $_ | ConvertFrom-Json | Out-Null }; Write-Host OK`  
Expected: `OK` (no parse errors)

---

### Task 2: Sync LPC bow, arrow, and shoot body layers

**Files:**
- Modify: `tools/sync_lpc_assets.ps1`
- Output: `godot/assets/lpc/weapon/weapon_bow_wood*.png`, `godot/assets/fx/arrow.png`, `*_shoot.png` for body/head/hair/eyes/outfit
- Regenerates: `godot/assets/lpc/SOURCE_MAP.json`

**Interfaces:**
- Produces: files loadable as `res://assets/lpc/weapon/weapon_bow_wood.png` (+ `_bg`, `_shoot`, `_bg_shoot`) and `res://assets/fx/arrow.png`

- [ ] **Step 1: Remove StaffCopies block; add BowCopies + Arrow copy**

In `sync_lpc_assets.ps1`, replace staff section with:

```powershell
$BowCopies = @(
    @{ id = "weapon_bow_wood";          anim = "walk";  source = "weapon\ranged\bow\normal\walk\foreground\medium.png"; role = "fg" }
    @{ id = "weapon_bow_wood_bg";       anim = "walk";  source = "weapon\ranged\bow\normal\walk\background\medium.png"; role = "bg" }
    @{ id = "weapon_bow_wood_shoot";    anim = "shoot"; source = "weapon\ranged\bow\normal\universal\foreground\shoot\medium.png"; role = "fg" }
    @{ id = "weapon_bow_wood_bg_shoot"; anim = "shoot"; source = "weapon\ranged\bow\normal\universal\background\shoot\medium.png"; role = "bg" }
)
```

Copy arrow to fx (not only lpc/weapon):

```powershell
# After bow copies — destination godot/assets/fx/arrow.png
Copy-Item (Join-Path $VendorSheets "weapon\ranged\bow\arrow\shoot\arrow.png") `
  (Join-Path $RepoRoot "godot\assets\fx\arrow.png") -Force
```

Also add a SOURCE_MAP-friendly copy under weapon if desired: `weapon_arrow_shoot` id optional.

- [ ] **Step 2: Add shoot to body/head/hair/eyes anim lists**

- `$BodyHeadAnimNames`: add `"shoot"` (keep slash, backslash, hurt, thrust)
- `$HairAnimNames`: add `"shoot"`
- `$EyesAnimCopies`: add shoot source `eyes\human\adult\default\shoot.png`
- Outfit loop: add `"shoot"` alongside slash/hurt/backslash/thrust

- [ ] **Step 3: Run sync**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "tools/sync_lpc_assets.ps1"
```

Expected: exit 0; `weapon_bow_wood*.png` present; `godot/assets/fx/arrow.png` exists; no staff required sources.

- [ ] **Step 4: Delete orphan staff PNGs under godot/assets/lpc/weapon/** (optional cleanup)

```powershell
Remove-Item "godot/assets/lpc/weapon/weapon_staff_wood*.png" -ErrorAction SilentlyContinue
```

---

### Task 3: LPCAnimator + EquipmentVisual — shoot + bow maps

**Files:**
- Modify: `godot/scripts/lpc/LPCAnimator.gd`
- Modify: `godot/scripts/lpc/EquipmentVisual.gd`

**Interfaces:**
- Produces: `play_shoot()`, `play_anim("shoot")`, maps for `wooden_bow` / `bow_shot` / `bow_aimed`

- [ ] **Step 1: LPCAnimator — add shoot**

- Add `const SHOOT_FRAMES := 13` (or detect from texture; default 13)
- Include `"shoot"` in `setup_layers` / `load_anim_textures` anim loops (with slash, backslash, hurt, thrust)
- `play_shoot()` → `_start_action("shoot")`
- In `play_anim`: match `"shoot": play_shoot()`
- `_default_frame_count`: `"shoot": return SHOOT_FRAMES`

- [ ] **Step 2: EquipmentVisual — replace staff maps**

```gdscript
# primary
"wooden_bow": "bow_shot",
"weapon_bow_wood": "bow_shot",
# secondary
"wooden_bow": "bow_aimed",
"weapon_bow_wood": "bow_aimed",
# layer
"wooden_bow": "weapon_bow_wood",
"weapon_bow_wood": "weapon_bow_wood",
# anim
"bow_shot": "shoot",
"bow_aimed": "shoot",
# cooldown_ms match skills.json
"bow_shot": 900,
"bow_aimed": 1200,
# is_ranged
"bow_shot": true,
"bow_aimed": true,
```

Remove all `staff` / `staff_thrust` / `staff_bash` / `weapon_staff_wood` keys.

- [ ] **Step 3: Static grep**

```powershell
Select-String -Path "godot/scripts/lpc/*.gd" -Pattern "staff" 
```

Expected: no matches (or only comments if any — prefer zero).

---

### Task 4: Projectile arrow visual + orientation

**Files:**
- Modify: `godot/scenes/fx/Projectile.tscn`
- Modify: `godot/scripts/fx/Projectile.gd`
- Uses: `godot/assets/fx/arrow.png`

**Interfaces:**
- Consumes: `launch(from, aim, speed)` unchanged signature
- Produces: arrow-looking projectile facing velocity on XZ

- [ ] **Step 1: Point tscn texture to arrow.png; remove amber modulate (use Color.WHITE)**

```
texture = ExtResource(... arrow.png)
modulate = Color(1, 1, 1, 1)
billboard = 0   # or keep 1 if rotation alone looks wrong — prefer face flight
```

- [ ] **Step 2: In Projectile.gd launch(), after setting `_velocity` for ranged**

Orient sprite on XZ toward aim (Godot Y-up):

```gdscript
if speed > 0.001 and is_instance_valid(sprite):
    var flat := Vector3(_velocity.x, 0.0, _velocity.z)
    if flat.length_squared() > 0.001:
        # Arrow art points +X in sheet; rotate Y so +X aligns with flat dir
        sprite.rotation.y = atan2(-flat.z, flat.x)
        sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
```

If arrow sheet is multi-frame, enable `region_enabled` and pick a single mid flight frame (e.g. one 64×64 cell) after measuring PNG size in sync notes.

- [ ] **Step 3: Confirm AlvidaHold still calls `_spawn_projectile(..., 10.0)` on `is_ranged`** — no signature change required.

---

### Task 5: Server — player ranged uses PendingHits; enemy_gen bow for ranged

**Files:**
- Modify: `backend/match/combat.go` (`HandleCombat`)
- Modify: `backend/match/enemy_gen.go` (force bow on ranged archetypes)
- Modify: `backend/match/types.go` only if PendingHit needs extra fields (reuse existing)

**Interfaces:**
- Consumes: `skill.IsRanged`, `PendingHit`, `ProcessPendingHits`
- Produces: delayed enemy HP reduction for player bow shots; launch event with `damage:0` + impact event

- [ ] **Step 1: In HandleCombat, when skill.IsRanged and enemy in range/cone**

Instead of immediate `enemy.HP -= dmg`:

1. Broadcast launch `OpCombatEvent` with `Damage: 0`, `TargetHP: enemy.HP`, `IsRanged: true`, anim/skill/from/to set
2. Append `PendingHit` with `ApplyAtTick = tick + delayTicks`, damage=`dmg`, target=`enemy.ID`, attacker=`userID`
3. Do **not** mark death on launch

Delay formula (same as enemy ranged):

```go
const projectileSpeed = 10.0
flightSec := dist / projectileSpeed
// clamp 0.15..0.55
delayTicks := int64(math.Ceil(flightSec * 20.0))
```

- [ ] **Step 2: Extend ProcessPendingHits / apply path for enemy targets**

Today `applyPlayerHit` only damages players. Add `applyEnemyHit` (or branch in ProcessPendingHits):

- Look up `state.Enemies[hit.TargetID]`
- Apply damage, broadcast impact event (`IsRanged: false`, `Anim: ""`, `Damage: dmg`)
- On death: `OpEnemyDeath` + `KillerOf` as in HandleCombat

PendingHit.TargetID already string — works for both player and enemy ids.

- [ ] **Step 3: enemy_gen — if archetype is ranged, force WeaponLayer**

In `SpawnAllEnemies` / `RespawnEnemy` / `GenerateEnemyAppearance` call sites: after generating appearance, if `arch.IsRanged` (or id contains `ranged`):

```go
appearance.WeaponLayer = "weapon_bow_wood"
```

- [ ] **Step 4: Compile match package**

```powershell
cd backend; go test ./match/ -count=1
```

Expected: ok (or `no test files` with exit 0)

- [ ] **Step 5: Rebuild plugin + restart Nakama**

```powershell
docker compose --profile dev up --force-recreate backend-builder
# wait exit 0
docker compose restart nakama
```

Expected: `Startup done` in nakama logs; new `plugin.so` timestamp.

---

### Task 6: Client polish + memory bank

**Files:**
- Modify: `godot/scripts/enemy/Enemy.gd` — ranged archetype uses shoot (already via event anim)
- Modify: `godot/scripts/net/IntentCodec.gd` comment if it cites staff
- Modify: `memory-bank/activeContext.md`, `memory-bank/progress.md`

- [ ] **Step 1: Grep repo (non-vendor) for staff / staff_thrust / weapon_staff**

```powershell
Select-String -Path backend,godot,tools -Pattern "staff_thrust|staff_bash|weapon_staff|\"staff\"" -Recurse
```

Fix remaining references in game code (ignore vendor/).

- [ ] **Step 2: Update memory bank** — focus wooden_bow + arrow; note staff removed.

- [ ] **Step 3: Playtest checklist (manual F5)**

1. Loot/equip wooden_bow → bow visible
2. LMB/RMB → shoot anim, arrow flies, damage on impact
3. goon_ranged holds bow, shoot + arrow, damage delayed
4. No amber ball
5. Sword still works

---

## Plan self-review

| Spec requirement | Task |
|---|---|
| wooden_bow content rename | T1 |
| shoot skills is_ranged | T1 |
| sync bow/arrow/shoot | T2 |
| LPCAnimator shoot | T3 |
| EquipmentVisual maps | T3 |
| Arrow projectile VFX | T4 |
| Player ranged delay | T5 |
| Ranged enemy bow layer | T5 |
| Staff removed | T1–T3, T6 grep |
| Success criteria playtest | T6 |

No TBD placeholders. PendingHits extended for enemy targets explicitly in T5.
