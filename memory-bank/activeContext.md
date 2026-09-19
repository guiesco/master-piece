# Active Context — One Piece MMO

## Foco Atual

**wooden_bow + arrow VFX (2026-09-18)** — staff removido; arco LPC, anim `shoot`, projétil flecha, dano ranged com delay (player + inimigo).

## Última entrega (Tasks 1–6)

| Área | Entrega |
|---|---|
| Content | `wooden_bow`, skills `bow_shot` / `bow_aimed`, loot goons, layer `weapon_bow_wood` |
| Assets | `sync_lpc_assets.ps1`: bow + shoot + `arrow.png`; staff PNGs fora do sync |
| Client LPC | `LPCAnimator` shoot; `EquipmentVisual` maps bow; sem alias `staff` |
| VFX | `Projectile` flecha LPC; sem amber ball |
| Server | `PendingHits` player + alvo inimigo; `goon_ranged_weak` anim `shoot` + bow layer |

Polish anterior (espada Z, facing mouse, busy) permanece válido.

## Gaps restantes

- Outfit pirate/guard: sem `_backslash` no vendor → layer usa walk durante backslash (cabelo/corpo OK).
- Inventário legado com item `staff` não migra (MVP demo — recriar personagem ou limpar storage).

## Próximo

Playtest F5 manual (checklist em `progress.md` — wooden_bow + arrow).
