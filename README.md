# One Piece MMO — MVP Alvida Hold

> Sandbox HD-2D cooperativo no universo de One Piece.  
> Stack: **Godot 4** + **Nakama 3.21.1** + **Go plugin** + **PostgreSQL 15** + **Docker Compose**  
> Assets: **LPC (CC-BY)** — sem sprites proprietários.

---

## Pré-requisitos

| Ferramenta | Versão mínima | Download |
|---|---|---|
| Docker Desktop | 4.x | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) |
| Godot Engine | 4.2+ | [godotengine.org](https://godotengine.org/download/) |
| Go (opcional) | 1.22+ | [go.dev/dl](https://go.dev/dl/) — só se quiser buildar fora do Docker |

> **Go** é opcional para desenvolvimento local. O `docker compose up --build` cuida do build do plugin automaticamente.

---

## Instalação do Plugin GDNakama (obrigatório antes de abrir o Godot)

O projeto requer o addon oficial Nakama para Godot 4:

```
1. Baixe/clone nakama-godot de: https://github.com/heroiclabs/nakama-godot

2. Do repositório, copie APENAS a pasta:
   nakama-godot/addons/com.heroiclabs.nakama/

3. Cole em:
   godot/addons/com.heroiclabs.nakama/

   Estrutura final esperada:
   godot/addons/com.heroiclabs.nakama/
     Nakama.gd
     Satori.gd
     api/
     client/
     socket/
     utils/

4. No project.godot, o autoload Nakama já está configurado:
   Nakama="*res://addons/com.heroiclabs.nakama/Nakama.gd"

NÃO copie o repositório inteiro para addons/nakama/nakama-godot/
(isso deixa o addon aninhado demais e o Godot não encontra as classes).
```

> **Sem esse addon, o autoload NetworkManager.gd gerará erros de classe não encontrada (NakamaClient, NakamaSocket, etc.).**

---

## Como Subir o Servidor

```powershell
# 1. Clone ou abra o projeto na pasta correta
cd "C:\Users\guies\Documents\One Piece MMO"

# 2. Suba todos os serviços (compila plugin Go + Postgres + Nakama)
docker compose up --build

# Dev com hot reload do plugin Go (observa backend/, rebuild + restart nakama):
docker compose --profile dev up --build

# Para rodar em background:
docker compose up --build -d
# (com hot reload:)
docker compose --profile dev up --build -d

# Para ver os logs do Nakama / do watcher:
docker compose logs -f nakama
docker compose --profile dev logs -f backend-watch

# Para derrubar tudo (preserva volumes):
docker compose --profile dev down

# Para derrubar E limpar banco de dados:
docker compose --profile dev down -v
```

> **Hot reload:** o Nakama só carrega o `.so` no boot. O profile `dev` sobe o serviço `backend-watch`, que faz polling em `backend/`, recompila o plugin e reinicia o Nakama (~2–5s). Clientes Godot desconectam nesse restart — rode F5 de novo.

Aguarde até ver no log:
```
nakama  | {"level":"info","msg":"Nakama started"}
```

**Endpoints disponíveis após subir:**
- **API / WebSocket:** `http://localhost:7350`
- **Console Admin:** `http://localhost:7351` (login: `admin` / senha: `password`)
- **PostgreSQL:** `localhost:5432` (user: `nakama`, password: `nakama`, db: `nakama`)

---

## Como Rodar o Godot (2 Instâncias para Teste)

1. Abra **Godot 4** e importe o projeto em `godot/project.godot`.
2. Pressione **F5** para rodar a primeira instância (ou clique em ▶ Run Project).
3. Para a segunda instância (segundo jogador na mesma máquina):
   - No Godot Editor, vá em **Debug → Run Second Instance** (ou pressione **Ctrl+F5**).
   - Alternativamente, abra um segundo Godot e importe o mesmo `project.godot`.

> Ambas as instâncias conectam ao Nakama em `localhost:7350` e entram no match `AlvidaHold_01` automaticamente.

---

## Estrutura de Pastas

```
One Piece MMO/
│
├── docker-compose.yml          # Infra: Postgres + Nakama + backend-builder (+ profile dev)
├── scripts/
│   └── backend-watch.sh        # Hot reload: poll backend/ → rebuild → restart nakama
├── GDD.md                      # Game Design Document (visão + corte vertical + roadmap)
├── README.md                   # Este arquivo
│
├── memory-bank/                # Memória do projeto para o agente de IA
│   ├── projectbrief.md         # Propósito, objetivos, escopo da build 1
│   ├── productContext.md       # Por que o jogo existe, experiência do usuário
│   ├── activeContext.md        # Foco atual, próximos passos
│   ├── systemPatterns.md       # Arquitetura, padrões, contrato de rede
│   ├── techContext.md          # Stack técnico, setup, restrições
│   └── progress.md             # O que funciona, o que falta, fases
│
├── docs/
│   └── superpowers/
│       └── specs/
│           └── 2026-09-17-alvida-hold-mvp-design.md   # Design spec completo (4 seções)
│
├── backend/                    # Plugin Go para Nakama
│   ├── go.mod                  # Módulo Go
│   ├── main.go                 # InitModule — registra match factory + RPCs
│   ├── match/
│   │   ├── handler.go          # Tick loop ~20 Hz, dispatcher de intents
│   │   ├── movement.go         # Validação de posição, movimento
│   │   ├── combat.go           # Dano, HP, cooldown, range AABB
│   │   ├── progression.go      # XP, level, alocação de atributos
│   │   └── enemy_gen.go        # Geração por seed, AI FSM, respawn
│   └── content/
│       ├── weapons.json        # Catálogo de armas
│       ├── skills.json         # Skills por arma
│       ├── archetypes.json     # Archetypes de inimigos (stats + loot table)
│       └── lpc_catalog.json    # Partes LPC disponíveis (body, hair, outfit)
│
└── godot/                      # Projeto Godot 4
    ├── project.godot
    ├── autoload/
    │   └── NetworkManager.gd   # Conexão Nakama, send intents, recv snapshots
    ├── scenes/
    │   ├── world/
    │   │   └── AlvidaHold.tscn # Mapa do porão (HD-2D: piso 3D + Sprite3D billboard)
    │   ├── player/
    │   │   └── Player.tscn     # Personagem local + remoto
    │   ├── enemy/
    │   │   └── Enemy.tscn      # Inimigo LPC
    │   └── ui/
    │       ├── CharacterCreator.tscn  # Compositor LPC inicial
    │       └── HUD.tscn               # HP, XP, botões de skill
    ├── scripts/
    │   ├── lpc/
    │   │   ├── LPCComposer.gd        # Compositor de camadas LPC (Sprite3D)
    │   │   └── EquipmentVisual.gd    # Atualiza camada weapon ao equipar
    │   └── net/
    │       └── IntentCodec.gd        # Serialização/desserialização de intents/snapshots
    └── assets/
        └── lpc/                # Spritesheets LPC (CC-BY)
            ├── body/
            ├── hair/
            ├── outfit/
            └── weapon/
```

---

## Fluxo de Desenvolvimento

```
[Editar backend/] → (profile dev) auto rebuild + restart nakama → F5 no Godot
[Editar backend/] → (sem profile) docker compose up --build → testa de novo
[Editar godot/]   → F5 no Godot → conecta ao Nakama local
[Commitar]        → git add . && git commit -m "feat: ..."
```

---

## Variáveis de Configuração

| Variável | Valor padrão | Onde mudar |
|---|---|---|
| Nakama host (Godot) | `localhost` | `godot/autoload/NetworkManager.gd` |
| Nakama port (Godot) | `7350` | `godot/autoload/NetworkManager.gd` |
| Server key (Godot) | `defaultkey` | `godot/autoload/NetworkManager.gd` |
| DB password | `nakama` | `docker-compose.yml` → `POSTGRES_PASSWORD` |
| Console password | `password` | `docker-compose.yml` → `NAKAMA_CONSOLE_PASSWORD` |
| Log level Nakama | `debug` | `docker-compose.yml` → `NAKAMA_LOG_LEVEL` |

> **Atenção:** As senhas padrão são apenas para desenvolvimento local. Nunca suba para produção sem trocá-las.

---

## Troubleshooting

### ❌ Erro: "Class 'NakamaClient' not found" no Godot
**Causa:** Addon GDNakama não instalado (ou aninhado errado).  
**Solução:** Copie `addons/com.heroiclabs.nakama` do repo nakama-godot para `godot/addons/com.heroiclabs.nakama/` (veja a seção de instalação acima).

### ❌ Erro: "rpc_get_alvida_match_id not found" no log do Nakama
**Causa:** Plugin Go não foi compilado ou não foi carregado.  
**Solução:** `docker compose down -v && docker compose up --build`. Verifique os logs do `backend-builder` para erros de compilação Go.

### ❌ Nakama não inicia: "database connection refused"
**Causa:** Postgres ainda está iniciando quando o Nakama tenta conectar.  
**Solução:** Aguarde mais 15–30 segundos. O healthcheck do `docker-compose.yml` garante a ordem, mas em máquinas lentas pode falhar. Rode `docker compose up` novamente.

### ❌ Dois jogadores não se veem no match
**Causa 1:** Um dos clientes está conectado a um match diferente.  
**Causa 2:** O RPC `rpc_get_alvida_match_id` retornou IDs diferentes nas duas instâncias.  
**Solução:** Verifique o console do Nakama em `http://localhost:7351` → Matches para confirmar que há apenas um match ativo.

### ❌ Plugin Go não compila: "wrong signature for method MatchInit"
**Causa:** Versão do nakama-common incompatível com o Nakama instalado.  
**Solução:** Confirme que `backend/go.mod` usa `github.com/heroiclabs/nakama-common v1.31.0` e que o Docker usa `heroiclabs/nakama:3.21.1`.

### ❌ Inimigos não aparecem ou não se movem
**Causa:** Assets LPC não baixados (só afeta visuais) ou problema no plugin Go.  
**Solução:** Inimigos aparecem como cubos coloridos sem os PNGs. Para visuais LPC reais, siga a nota de assets abaixo.

---

## Créditos e Licenças

### Assets Visuais — LPC (Liberated Pixel Cup)

> ✅ Subset já instalado em `godot/assets/lpc/` (walk sheets do Universal LPC).  
> Clone de referência: `vendor/Universal-LPC-Spritesheet-Character-Generator/` (gitignored, ~90k arquivos).  
> Detalhes: `godot/assets/lpc/README.md` + `CREDITS.txt` + `SOURCE_MAP.json`.  
> Skills/ferramentas úteis do repo oficial: `vendor/.../.agents/skills/` e `tools/`.

Este jogo usa assets do **Universal LPC Spritesheet Character Generator** e contribuições da comunidade LPC, licenciados sob **CC-BY 3.0** e/ou **CC-BY-SA 3.0**.

**Atribuição obrigatória:**
> "Character sprites from the Universal LPC Spritesheet (opengameart.org/content/universal-lpc-spritesheet-character-generator) by LPC contributors, licensed under CC-BY 3.0 / CC-BY-SA 3.0."

**Contribuidores notáveis do LPC:**
- Antifarea, Donator, ElizaWy, Eliza Wyatt, Johannes Sjölund (wulax), Matthew Krohn, Michael Whitlock, Pierre Vigier (pvigier), qubodup, Redshrike, Thane Brimhall e muitos outros.

Lista completa em: [opengameart.org/content/universal-lpc-spritesheet-character-generator](https://opengameart.org/content/universal-lpc-spritesheet-character-generator)

### Software

| Software | Licença |
|---|---|
| Godot Engine | MIT |
| Nakama (Heroic Labs) | Apache 2.0 |
| PostgreSQL | PostgreSQL License (similar a MIT) |
| Go | BSD-style |

### Temática

One Piece é propriedade intelectual de Eiichiro Oda / Shueisha / Toei Animation. Este projeto é um fan project sem fins lucrativos, não usa assets proprietários e não é afiliado a nenhuma dessas entidades.

---

## Roadmap Resumido

| Fase | Feature |
|---|---|
| ✅ MVP | Porão Alvida — PvE coop, LPC, progressão |
| 1 | Chat in-game + Party |
| 2 | Akuma no Mi (Paramecia) |
| 3 | Profissões (Espadachim, Sniper) |
| 4 | Haki (Observation + Armament) |
| 5 | Saída do porão → Loguetown |
| 6 | Barcos e Navegação |
| 7 | **Facções** (Piratas vs Marinha) — por último |

---

*Projeto iniciado em 2026-09-17. Consulte `GDD.md` para a visão completa e `memory-bank/` para contexto do desenvolvimento.*
