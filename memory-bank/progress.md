# Progress — One Piece MMO

## Status Atual

**Build:** MVP Alvida Hold  
**Data:** 2026-09-19  
**Fase atual:** repo publicado em github.com/guiesco/master-piece (`origin/main`), incluindo `vendor/` LPC  
**Status global:** código + vendor no GitHub; playtest F5 manual do wooden_bow ainda pendente

---

## Fases do Projeto

| # | Nome | Status | Descrição |
|---|---|---|---|
| 0 | Bootstrap | ✅ Concluído | GDD, Memory Bank, docker-compose, README, design spec |
| 1 | Backend Go | ✅ Concluído | Plugin Go: match, movement, Storage profile |
| 2 | Godot Net | ✅ Concluído | NetworkManager, AlvidaHold HD-2D, Player base |
| 3 | LPC | ✅ Concluído | LPCComposer + catálogo + estrutura de assets |
| 4 | Combate | ✅ Concluído | Combate autoritativo + AI goons + punch |
| 5 | Progressão | ✅ Concluído | Loot, equip, skills, XP/atributos, HUD |
| 6 | Enemy Gen | ✅ Concluído | enemy_gen LPC automático por seed |
| 7 | DoD | ✅ Concluído | Auditoria + correções + Memory Bank atualizado |
| 7b | Boot local | ✅ Concluído | docker-compose corrigido; Nakama + plugin rodando |
| 7c | RPC shape fix | ✅ Concluído | Mismatches client↔backend corrigidos; CharacterSelect funcional |
| 7d | Combat anims | ✅ Concluído | LPC sync + dual skills + WeaponBehind + integração |
| 7e | Fix hit/death/busy/UI | ✅ Concluído (estático) | Hurt/thrust sync; hit=flash; busy lock; espada 0.023; HP 64 / dmg 96 |

---

## O Que Foi Implementado

### Fase 0 — Bootstrap
- ✅ GDD.md com visão completa e roadmap (facções por último)
- ✅ Memory Bank inicializado (todos os arquivos core)
- ✅ Design spec completo (4 seções aprovadas)
- ✅ `docker-compose.yml` com Postgres 15 + Nakama 3.21.1 + backend-builder
- ✅ `README.md` com instruções de setup

### Fase 1 — Backend Go (plugin Nakama)
- ✅ `backend/go.mod` + `go.sum` — módulo Go com nakama-common v1.31.0
- ✅ `backend/main.go` — InitModule registra match factory + 3 RPCs + after hook
  - `rpc_get_or_create_profile` — busca/cria perfil no Storage
  - `rpc_get_alvida_match_id` — retorna ID do match singleton (Fase 7: adicionado)
  - `rpc_save_appearance` — salva aparência LPC no Storage (Fase 7: adicionado)
- ✅ `match/handler.go` — tick loop 20 Hz, MatchInit/Join/Leave/Loop/Signal/Terminate
- ✅ `match/movement.go` — validação AABB, broadcast OpPlayerState
- ✅ `match/combat.go` — HandleCombat, TickAI (FSM: Wander→Chase→Attack)
- ✅ `match/progression.go` — HandleProgression, HandleAllocateStat, HandleEquip
- ✅ `match/enemy_gen.go` — SpawnAllEnemies, RespawnEnemy, GenerateEnemyAppearance
- ✅ `match/types.go` — OpCodes, PlayerState, EnemyState, MatchState, AppearanceDef
- ✅ `backend/profile/profile.go` — GetOrCreateProfile, SaveProfile, DefaultProfile + Appearance (Fase 7)
- ✅ `content/archetypes.json`, `skills.json`, `weapons.json`, `lpc_catalog.json`

### Fase 2 — Godot Net + Mundo HD-2D
- ✅ `godot/project.godot` — autoload NetworkManager, renderer Compatibility, resolução 1280×720
- ✅ `autoload/NetworkManager.gd` — Device ID auth, join match via RPC, send/recv
- ✅ `scenes/world/AlvidaHold.tscn` + `scripts/world/AlvidaHold.gd` — dispatcher de OpCodes completo
- ✅ `scenes/player/Player.tscn` — 4 Sprite3D billboard (Body/Hair/Outfit/Weapon)
- ✅ `scenes/enemy/Enemy.tscn` + `scripts/enemy/Enemy.gd`

### Fase 3 — LPC Composer + Catálogo
- ✅ `scripts/lpc/LPCComposer.gd` — camadas Body/Hair/Outfit/Weapon com modulate
- ✅ `scripts/lpc/EquipmentVisual.gd` — update_weapon_layer, get_skill_for_weapon
- ✅ `backend/content/lpc_catalog.json` — catálogo de partes e enemy_archetypes
- ✅ `godot/assets/lpc/` — subpastas com .gitkeep + README de download
- ⬜ Assets LPC reais (PNG) — baixar manualmente via Universal LPC Generator

### Fase 4 — Combate Autoritativo
- ✅ `match/combat.go` — range AABB, cooldown por skill, dano por stat
- ✅ Enemy AI: Wander → Chase (detectRange) → Attack (attackRange) → Wander
- ✅ Cooldown de ataque do inimigo: 1s
- ✅ OpCombatEvent broadcast para todos os clients
- ✅ OpPlayerDeath → respawn simples (HP restaurado, posição inicial)
- ✅ HP bars flutuantes via Label3D em Player e Enemy

### Fase 5 — Loot, Equip, Progressão, HUD
- ✅ Loot drop ao matar inimigo (por drop_chance da loot_table do archetype)
- ✅ Intent `equip` → unlock skill de arma no slot 2 do HUD
- ✅ XP → level → PendingStatPoints → `allocate_stat` (str/agi/int)
- ✅ Persistência de perfil no Storage a cada progressão
- ✅ `scenes/ui/HUD.tscn` + `scripts/ui/HUD.gd` — HP bar, XP bar, skill buttons, painel de atributos
- ✅ `scenes/ui/CharacterCreator.tscn` + `scripts/ui/CharacterCreator.gd`

### Fase 6 — Enemy Gen Automático
- ✅ 6 spawn points no porão (coordenadas 5–45 no mapa 50×50)
- ✅ Seed = fnv(matchID:spawnIndex:respawnCount) → aparência LPC determinística
- ✅ Dois archetypes: `goon_melee` e `goon_ranged_weak`
- ✅ Respawn em 100 ticks ≈ 5s a 20 Hz
- ✅ Nova aparência por seed a cada respawn

### Fase 7 — Auditoria DoD (correções aplicadas em 2026-09-17)
- ✅ `handler.go`: MatchInit return type corrigido: `[]runtime.Presence` → `[]runtime.PresenceChange`
- ✅ `main.go`: adicionados `rpc_get_alvida_match_id` e `rpc_save_appearance`
- ✅ `profile.go`: adicionado campo `Appearance AppearanceData` ao PlayerProfile
- ✅ `handler.go` MatchJoin: usa aparência salva do perfil em vez de hardcoded
- ✅ `IntentCodec.gd`: opcodes dos comentários corrigidos (22→20, 33→30, 34→31, 50→40, 51→41, 52→42)
- ✅ `IntentCodec.gd`: decode_player_state: `"id"` agora lê de `"player_id"`
- ✅ `IntentCodec.gd`: decode_player_joined: `"id"` agora lê de `"user_id"`
- ✅ `IntentCodec.gd`: decode_player_left: `"id"` agora lê de `"player_id"`
- ✅ `IntentCodec.gd`: decode_enemy_state: `"id"` agora lê de `"enemy_id"` (corrige bug crítico de state updates)
- ✅ `IntentCodec.gd`: decode_player_state/joined: mapeamento de coordenadas Y→Z corrigido
- ✅ `README.md`: instrução de instalação GDNakama, nota de assets LPC, seção Troubleshooting

---

## Checklist DoD — Resultado da Auditoria

| Item | Status | Observação |
|---|---|---|
| docker-compose.yml cobre Postgres + Nakama + plugin Go | ✅ | Postgres 15, Nakama 3.21.1, backend-builder com plugin_build volume |
| backend/main.go registra match, RPCs e hooks | ✅ | 3 RPCs + after hook authenticateDevice |
| match AlvidaHold_01 com 20Hz tick e movement broadcast | ✅ | MatchInit retorna tick=20; HandleMovement → OpPlayerState |
| Player profile criado no Storage no primeiro login | ✅ | after hook + rpc_get_or_create_profile |
| Creator mínimo (corpo/cabelo/roupa/cor) implementado | ✅ | CharacterCreator.tscn + rpc_save_appearance |
| Player.tscn com 4 Sprite3D LPC | ✅ | BodySprite, HairSprite, OutfitSprite, WeaponSprite |
| Combate PvE autoritativo (punch + 2 skills de arma) | ✅ | HandleCombat + skills.json (punch, sword_slash/backslash, bow_shot/aimed) |
| AI goons Wander/Chase/Attack | ✅ | TickAI FSM em combat.go |
| Loot drop com chance | ✅ | HandleProgression + loot_table em archetypes.json |
| Equip troca layer LPC + desbloqueia skill | ✅ | HandleEquip → OpEquip broadcast → EquipmentVisual.gd |
| XP/level/atributos (STR/AGI/INT) com persistência | ✅ | HandleProgression + HandleAllocateStat + SaveProfile |
| enemy_gen por seed LPC sem authoring manual | ✅ | GenerateEnemyAppearance via fnv hash |
| Respawn de inimigos em 5s (100 ticks @ 20Hz) | ✅ | RespawnQueue no MatchLoop |
| HUD completo (HP, XP, skills, atributos) | ✅ | HUD.gd com todos os elementos |
| Memory Bank atualizado | ✅ | progress.md + activeContext.md atualizados agora |

---

## Playtest UX Pass — Correções RPC Shape (2026-09-17)

### CharacterSelect 3 slots
- ✅ `list_characters()` extrai `{"slots":[...]}` corretamente (corrigido pelo agente backend)
- ✅ Slot ocupado → "⚔ Jogar" → `select_character` → carrega perfil → AlvidaHold
- ✅ Slot vazio → "+ Criar" → CharacterCreator → `create_character` → `select_character` → AlvidaHold

### Camera HD-2D / Colisões / Animações
- ✅ CameraFollow: lerp suave, offset (0,9,20), pitch 24°, target = jogador local
- ✅ `move_and_slide()` com `MOTION_MODE_FLOATING` — sem gravidade
- ✅ LPCAnimator walk/idle/slash wired, fallback para walk sheet se slash ausente
- ✅ Projectile spawn em combate ranged wired

### Inventário / HUD / Skills
- ✅ Inventário `I` para abrir/fechar painel, botão Equipar por item
- ✅ Slots de skill no HUD: aim usa posição do mouse no plano Y=0
- ✅ HP bar atualiza via OpXPEvent (inclui hp/max_hp) e OpCombatEvent

### HP/max_hp
- ✅ `rpc_select_character` sem hp/max_hp: `max_hp = 100 + strength*5` calculado no cliente
- ✅ `OpXPEvent` com hp e max_hp: Player.receive_xp_event() sincroniza e chama hud.update_hp()
- ✅ `AlvidaHold._spawn_local_player`: usa `has("max_hp")` antes de aplicar fallback

### Correção crítica CharacterCreator
- ✅ Fallback de `select_character` não propaga `{"ok":true}` como `last_profile` (era bug que corromperia spawn)

## Boot Local — Correções (2026-09-17)

- ✅ `docker-compose.yml`: `nakama-pluginbuilder:3.21.1`, `nakama-migrate`, flags corretas no Nakama
- ✅ `backend/go.mod`: `go 1.21` (alinhado ao runtime Nakama go1.21.6)
- ✅ `match/handler.go`: MatchInit → `(interface{}, int, string)` com label `AlvidaHold_01`
- ✅ Validado: `Startup done`, plugin carregado, RPCs registrados, healthcheck 200

## fix_combat_animations (2026-09-17) — Concluído + integração

### Assets
- ✅ `tools/sync_lpc_assets.ps1` + 57 PNGs em `godot/assets/lpc/`
- ✅ Espada: arming **brass** FG/BG walk + slash + backslash (`weapon_sword_wood*`)
- ✅ Arco: bow FG/BG walk + shoot (`weapon_bow_wood*`); flecha `godot/assets/fx/arrow.png`
- ✅ SOURCE_MAP com `anim` / `frame_w` / `frames` / `rows`

### Backend
- ✅ `weapons.json`: `skill_primary` + `skill_secondary` + `damage_bonus`
- ✅ `skills.json`: punch, sword_slash, sword_backslash, bow_shot, bow_aimed (`anim` shoot, `is_ranged`, `requires_weapon` wooden_bow)
- ✅ HandleCombat: dano = skill + weapon bonus; valida arma; OpCombatEvent enriquecido
- ✅ HandleEquip: broadcast `skill_primary` / `skill_secondary`

### Godot
- ✅ LPCComposer WeaponBehind FG+BG; LPCAnimator multi-anim + fallback backslash→slash
- ✅ Player LMB/RMB + gate (busy OR CD); Enemy LPCAnimator + velocity lerp
- ✅ AlvidaHold: OpCombatEvent `is_ranged` → Projectile; OpEquip dual skills
- ✅ IntentCodec: decode combat VFX fields + equip dual skills
- ✅ EquipmentVisual: maps alinhados a skills/weapons.json (sem `precise_cut`)

### Fixes de integração (pós-workstreams)
- ✅ Cooldowns client = `skills.json` (backslash 1100, thrust 900)
- ✅ Removido leftover `precise_cut` de EquipmentVisual / comentário IntentCodec
- ✅ `apply_equipped_weapon` grava `weapon_layer` em `_last_appearance` + snapshot walk
- ✅ LPCAnimator: rect **por layer** (64/128/192 coexistindo); meta sem forçar 128px

## fix_animacoes_combate (2026-09-17) — Concluído (verificação estática)

### Assets
- ✅ `tools/sync_lpc_assets.ps1` expandido: hair/eyes hurt+thrust; body/head/outfit thrust
- ✅ 19 PNGs novos confirmados (amostras hair_*_hurt/thrust, body_*_thrust, outfit_*_thrust)
- ✅ `SOURCE_MAP.json` regenerado; ~76 PNGs totais em `godot/assets/lpc/`

### Godot — hit / death / busy
- ✅ Player/Enemy: dano → flash só (`_flash_red` / `play_hit_flash`); sem `play_hurt` no hit
- ✅ Player `receive_death`: `play_hurt` + await busy antes do respawn
- ✅ Enemy `play_death`: mantém `play_hurt`
- ✅ Player `_handle_local_movement`: `is_busy()` zera velocity e não envia move intent

### Godot — espada + UI
- ✅ LPCComposer FG+BG + `visible=true` pós-equip; LPCAnimator `_apply_rect` força weapon FG/BG no idle/walk
- ✅ WeaponSprite / WeaponBehindSprite `pixel_size = 0.023` (Player + Enemy)
- ✅ HPLabel `font_size = 64`; AlvidaHold damage numbers `font_size = 96`

### Verificação
- ✅ Code review estático alinhado ao checklist do plano
- ⬜ Playtest F5 visual no editor (não executável headless nesta sessão)

## wooden_bow + arrow (2026-09-18) — Tasks 1–6

### Content + server
- ✅ `weapons.json` / `skills.json` / `archetypes.json` / `lpc_catalog.json`: staff → `wooden_bow`, anim ranged `shoot`
- ✅ `PendingHits`: dano player ranged e hits em inimigos no tick de impacto
- ✅ Enemy gen: `goon_ranged_weak` com layer bow + skill ranged

### Godot
- ✅ `sync_lpc_assets.ps1` + SOURCE_MAP bow/shoot/arrow
- ✅ `LPCAnimator` + `EquipmentVisual` bow maps; `IntentCodec` comentário atualizado
- ✅ `Projectile` flecha; `Enemy.play_attack_anim` fallback ranged → `shoot`
- ✅ Task 6 grep: zero `staff_*` em `backend/`, `godot/scripts/`, `tools/` (cache `.godot` ignorado)

### Playtest F5 (manual — pendente)
- ⬜ Loot/equip `wooden_bow` → bow visível
- ⬜ LMB/RMB → anim shoot, flecha voa, dano no impacto
- ⬜ `goon_ranged_weak` segura arco, shoot + flecha, dano atrasado
- ⬜ Sem amber ball
- ⬜ Espada (`wooden_sword`) ainda funciona

---

## Problemas Conhecidos / Limitações do MVP

- **Outfit pirate/guard:** sem `_backslash.png` no vendor → durante backslash a layer de roupa usa walk (cabelo/corpo/arma syncados).
- **Espada visual brass ≠ id `weapon_sword_wood`:** naming legado; metal real é brass (arming).
- **Inventário legado `staff`:** sem migração; equip falha até limpar perfil/storage.
- **Sem PvP, facções, Haki, Akuma** — conforme escopo definido no GDD.

---

## Decisões Registradas

| Data | Decisão | Motivo |
|---|---|---|
| 2026-09-17 | Facções por último no roadmap | Dependem de mundo aberto + PvP maduros |
| 2026-09-17 | PostgreSQL (não CockroachDB) | Simplicidade no ambiente local |
| 2026-09-17 | Device ID Auth (anônima) | Onboarding zero-friction no MVP |
| 2026-09-17 | JSON para snapshots (não binário) | Debug mais fácil na fase inicial |
| 2026-09-17 | HD-2D com Sprite3D billboard | Estilo visual único sem arte 3D de personagem |
| 2026-09-17 | MatchInit retorna `(state, tickRate, label)` | Assinatura real do nakama-common v1.31.0 |
| 2026-09-17 | Aparência salva no PlayerProfile | Evita storage extra; simplifica GetOrCreateProfile |
| 2026-09-17 | Build via `nakama-pluginbuilder:3.21.1` | Go plugins exigem toolchain idêntica ao Nakama |
| 2026-09-17 | Dual skill LMB/RMB por arma | skill_primary + skill_secondary no equip |
| 2026-09-17 | Espada LPC = arming brass | longsword wood walk incompleto no vendor |
| 2026-09-17 | Hit = flash; morte = hurt LPC | Sheet hurt é knockdown; evita queda em todo dano |
| 2026-09-17 | Busy trava movimento local | Evita andar no windup/ataque/hurt |
| 2026-09-17 | HP mundo 64 / dano 96 | Legibilidade Label3D |
