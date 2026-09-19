# Tech Context — One Piece MMO

## Stack Tecnológico Completo

### Cliente — Godot 4.x (GDScript)

| Aspecto | Detalhe |
|---|---|
| Engine | Godot 4.x (recomendado 4.2+) |
| Linguagem | GDScript (tipado onde possível) |
| Render | Forward+ (para compatibilidade HD-2D com sombras) |
| Display | Sprites 2D billboard (`Sprite3D`) em cena 3D |
| SDK Nakama | `godot-nakama` (GDNative/GDExtension para Godot 4) |
| Autenticação | Device ID (anonymous) — sem password no MVP |

**Dependências Godot:**
- `nakama-godot` v3.x (compatível com Godot 4)
- Não há addons adicionais obrigatórios no MVP

**Convenções GDScript:**
- Autoloads na pasta `godot/autoload/`
- Scenes em `godot/scenes/` por categoria (world, player, enemy, ui)
- Scripts LPC em `godot/scripts/lpc/`
- Scripts de rede em `godot/scripts/net/`

---

### Servidor — Nakama 3.21.1

| Aspecto | Detalhe |
|---|---|
| Plataforma | Heroic Labs Nakama OSS |
| Versão | 3.21.1 (image: `heroiclabs/nakama:3.21.1`) |
| Customização | Go plugin (buildmode=plugin) |
| Porta HTTP/API | 7350 |
| Porta Console | 7351 |
| Porta WS | 7350 (mesmo endpoint) |

**APIs Nakama usadas:**
- `runtime.Match` (match handler interface)
- `runtime.NakamaModule` (Storage, Logger)
- Storage V2 (coleções e chaves por user ID)
- RPC (bootstrap_profile)
- Device ID Auth (anônima)

---

### Backend — Go 1.22 (Plugin)

| Aspecto | Detalhe |
|---|---|
| Versão Go | **1.21.6** (igual ao runtime interno do Nakama 3.21.1) |
| Builder | `heroiclabs/nakama-pluginbuilder:3.21.1` |
| Modo de build | `go build -trimpath -buildmode=plugin` |
| Output | volume Docker `plugin_build` → `/nakama/data/modules/plugin.so` |
| Módulo | `github.com/onepiece-mmo/backend` (ou path local) |
| Dependências | `github.com/heroiclabs/nakama-common v1.x` |

**Estrutura do módulo Go:**
```
backend/
├── go.mod
├── go.sum
├── main.go                  # InitModule — registra match factory + RPCs
├── match/
│   ├── handler.go           # MatchInit, MatchJoin, MatchLoop, MatchLeave
│   ├── movement.go
│   ├── combat.go
│   ├── progression.go
│   └── enemy_gen.go
└── content/
    ├── weapons.json
    ├── skills.json
    ├── archetypes.json
    └── lpc_catalog.json
```

**Notas críticas de compilação:**
- O plugin `.so` deve ser compilado com a mesma versão de Go usada pelo Nakama.
- `golang:1.22-alpine` combina com Nakama 3.21.1.
- O arquivo `.so` é montado no container Nakama via volume Docker.

---

### Banco de Dados — PostgreSQL 15

| Aspecto | Detalhe |
|---|---|
| Imagem | `postgres:15` |
| Usuário | `nakama` (default Nakama) |
| Senha | `nakama` (MVP local — não usar em prod) |
| Database | `nakama` |
| Volume | `pgdata` (named volume Docker) |
| Gerenciamento | Nakama gerencia o schema automaticamente |

---

### Infra Local — Docker Compose

**Serviços:**
1. `postgres` — banco de dados
2. `nakama-migrate` — `nakama migrate up` (schema)
3. `backend-builder` — `nakama-pluginbuilder:3.21.1` → `plugin.so`
4. `nakama` — servidor de jogo com plugin montado (`container_name: opm-nakama`)
5. `backend-watch` — (profile `dev`) polling em `backend/` → rebuild + restart nakama

**Project name Compose:** `onepiece-mmo` (estável; a pasta do repo tem espaços).

**Fluxo de boot:**
```
docker compose up -d
  1. postgres: healthy
  2. nakama-migrate: migrate up
  3. backend-builder: plugin.so via pluginbuilder
  4. nakama: carrega plugin.so, expõe :7350/:7351
```

---

### Assets — LPC (Liberated Pixel Cup)

| Aspecto | Detalhe |
|---|---|
| Licença | CC-BY 3.0 / CC-BY-SA 3.0 (verificar por asset) |
| Fonte | Universal LPC Spritesheet (opengameart.org) |
| Formato | PNG, spritesheets 64×64 por frame |
| Camadas | Body, Hair, Outfit, Weapon (transparência PNG) |
| Animações | Walk (4 dirs × 8 frames), Idle, Attack (4 dirs × 6 frames) |
| Pasta | `godot/assets/lpc/` |

**Créditos obrigatórios (em README e in-game):**
- "Universal LPC Spritesheet" por contributors do LPC (opengameart.org/content/universal-lpc-spritesheet-character-generator)
- Licença CC-BY — atribuição obrigatória em qualquer distribuição.

---

## Setup de Desenvolvimento

### Repositório
- Remote: `git@github.com:guiesco/master-piece.git` (`origin`, branch `main`)
- `vendor/` (Universal LPC) entra no git para permitir edição de assets
- `.superpowers/` fica fora do git

### Pré-requisitos
- Docker Desktop (Windows/Mac/Linux)
- Godot 4.x (baixar de godotengine.org)
- Go 1.22+ (opcional para desenvolvimento do plugin fora do Docker)
- Git

### Variáveis de Ambiente (desenvolvimento)
```env
NAKAMA_HOST=localhost
NAKAMA_PORT=7350
NAKAMA_SERVER_KEY=defaultkey
```

### Comandos Úteis
```powershell
# Subir tudo
docker compose up --build

# Dev com hot reload do plugin (backend-watch)
docker compose --profile dev up --build

# Ver logs do Nakama / watcher
docker compose logs -f nakama
docker compose --profile dev logs -f backend-watch

# Derrubar e limpar volumes
docker compose --profile dev down -v

# Rebuild só o plugin
docker compose run --rm backend-builder

# Console Nakama (admin)
# Abrir: http://localhost:7351
# User: admin / Password: password
```

**Hot reload (limitação):** Go plugin `.so` só carrega no boot do Nakama. O watcher faz rebuild + `restart nakama` (não é reload in-process). Script: `scripts/backend-watch.sh`.

## Restrições Técnicas Conhecidas

1. **Plugin Go = mesmo runtime:** Usar sempre `heroiclabs/nakama-pluginbuilder:3.21.1` (não `golang:*` genérico).
2. **Godot Nakama SDK:** A versão GDExtension para Godot 4 pode exigir recompilação manual em algumas plataformas. Testar no Windows primeiro.
3. **Sprite3D billboard:** Em Godot 4, `Sprite3D` com `billboard = BILLBOARD_ENABLED` funciona mas pode ter z-fighting em certas câmeras. Ajustar `render_priority` por camada LPC.
4. **Tamanho do snapshot JSON:** Com 2 players + 6 inimigos, o snapshot é pequeno (~1KB). Não há problema de bandwidth no MVP.
5. **Device ID no Windows:** Godot 4 gera Device ID estável no Windows Registry. Sem necessidade de login no MVP.
