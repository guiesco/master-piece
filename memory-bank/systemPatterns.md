# System Patterns — One Piece MMO

## Arquitetura Geral

```
┌─────────────────────────────────────────────────────────┐
│                    CLIENTE (Godot 4)                    │
│                                                         │
│  ┌──────────────┐   intents    ┌──────────────────────┐ │
│  │ Player Input │─────────────▶│  NetworkManager.gd   │ │
│  └──────────────┘              │  (Autoload)          │ │
│                                │  - Device ID Auth    │ │
│  ┌──────────────┐  snapshots   │  - Join Match        │ │
│  │ World State  │◀─────────────│  - Send/Recv JSON    │ │
│  │ (interpolado)│              └──────────────────────┘ │
│  └──────────────┘                         │             │
│         │                                 │ WebSocket   │
│  ┌──────┴───────┐                         │             │
│  │ LPCComposer  │                         │             │
│  │ (visual)     │                         │             │
│  └──────────────┘                         │             │
└───────────────────────────────────────────┼─────────────┘
                                            │
                                            ▼
┌─────────────────────────────────────────────────────────┐
│               NAKAMA 3.21.1 (servidor)                  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Match Handler Go Plugin             │   │
│  │                                                  │   │
│  │  MatchInit  → estado inicial                     │   │
│  │  MatchJoin  → adiciona player ao estado          │   │
│  │  MatchLoop  → tick ~20 Hz                        │   │
│  │    ├── dispatch(intent) → módulo correto         │   │
│  │    ├── movement.go  (move, validate, broadcast)  │   │
│  │    ├── combat.go    (attack, HP, range, cooldown)│   │
│  │    ├── progression.go (XP, level, alloc_stat)    │   │
│  │    └── enemy_gen.go (seed → spawn, AI, respawn)  │   │
│  │  MatchLeave → limpa estado do player             │   │
│  └──────────────────────────────────────────────────┘   │
│                          │                              │
│              ┌───────────┴───────────┐                  │
│              │   Storage API         │                  │
│              │   (appearance, stats, │                  │
│              │    xp, inventory,     │                  │
│              │    equipped)          │                  │
│              └───────────────────────┘                  │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │   PostgreSQL 15       │
              │   (Nakama Storage)    │
              └───────────────────────┘
```

## Padrão Central: Intents → Server → Snapshots

### Intent (Cliente → Servidor)
```json
{
  "type": "move",
  "data": { "dx": 1, "dy": 0 }
}
```
```json
{
  "type": "attack",
  "data": { "target_id": "enemy_3" }
}
```
```json
{
  "type": "equip",
  "data": { "item_id": "sword_01", "slot": "weapon" }
}
```
```json
{
  "type": "allocate_stat",
  "data": { "stat": "str" }
}
```

### Snapshot (Servidor → Todos os Clientes)
```json
{
  "tick": 1423,
  "players": [
    {
      "id": "p1",
      "x": 3.5, "y": 0, "z": 2.1,
      "hp": 85, "max_hp": 100,
      "state": "walk",
      "dir": "right",
      "appearance": { "body": "male_light", "hair": "long_black", "outfit": "pirate_a" }
    }
  ],
  "enemies": [
    {
      "id": "e_0_1",
      "archetype": "goon_a",
      "x": 5.0, "y": 0, "z": 2.1,
      "hp": 40, "max_hp": 60,
      "state": "chase",
      "appearance": { "body": "male_dark", "hair": "short_brown", "outfit": "guard_b" }
    }
  ],
  "events": [
    { "type": "damage", "target": "e_0_1", "amount": 15, "attacker": "p1" },
    { "type": "loot_drop", "item_id": "sword_01", "x": 5.0, "z": 2.1 }
  ]
}
```

## Módulos Go do Match Handler

| Módulo | Responsabilidade |
|---|---|
| `match/handler.go` | Tick loop, dispatcher de intents, montagem do snapshot |
| `match/movement.go` | Valida `move` intent, atualiza posição, detecta colisão simples |
| `match/combat.go` | Valida `attack`, range AABB, cooldown, dano, HP, morte |
| `match/progression.go` | XP/level, `allocate_stat`, persistência via Storage API |
| `match/enemy_gen.go` | Geração de inimigos por seed, AI (Wander→Chase→Attack), respawn |
| `content/` | JSON estáticos: `weapons.json`, `skills.json`, `archetypes.json`, `lpc_catalog.json` |

## Padrões de Design Adotados

### 1. Separação Intent/State (Command Pattern)
Cada intent é um comando imutável. O handler processa e muta o estado do match. Facilita debug e replay.

### 2. State Snapshot (Observer)
O servidor sempre publica o estado completo relevante a cada tick. Clientes não mantêm estado canônico — só display state interpolado.

### 3. Modularidade Go por Domínio
Cada submódulo (movement, combat, etc.) expõe uma função `Process(state, intent) error`. O handler.go orquestra; módulos não se conhecem.

### 4. Geração Procedural por Seed
`enemy_gen.go` usa `seed = hash(match_id + spawn_slot)` para gerar aparência LPC determinística. Dois clientes que recebem o mesmo snapshot reconstroem o mesmo visual sem transmitir os dados de aparência a cada tick — apenas na primeira vez (join event).

### 5. HD-2D (Godot)
- Câmera perspectiva leve (~15° de inclinação).
- Piso e paredes: `MeshInstance3D` low-poly com textura tileable.
- Personagens e inimigos: `Sprite3D` (billboard) com `LPCComposer.gd` gerenciando camadas.
- Sombras projetadas pelo 3D criam profundidade sem arte 3D de personagem.

## Contrato de Rede

| Campo | Valor |
|---|---|
| Protocolo | WebSocket (Nakama SDK) |
| Serialização | JSON (UTF-8) |
| Tick rate servidor | ~20 Hz (50 ms/tick) |
| Tick de snapshot | Todo tick (estado completo relevante) |
| Autenticação | Device ID (anonymous, sem senha no MVP) |
| Match ID | `AlvidaHold_01` (fixo, MVP) |

## Estrutura de Storage (Nakama)

```
Collection: "player_data"
  Key: "appearance"   → { body, hair, outfit, colors }
  Key: "stats"        → { hp, max_hp, str, agi, int, stat_points }
  Key: "progression"  → { xp, level }
  Key: "inventory"    → [ { item_id, quantity } ]
  Key: "equipped"     → { weapon: item_id | null }
```
