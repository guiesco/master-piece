# Game Design Document — One Piece MMO

> **Versão:** 0.1 — Bootstrap Fase 0  
> **Data:** 2026-09-17  
> **Autor:** Projeto MVP Alvida Hold

---

## 1. Visão Geral

**One Piece MMO** é um RPG online sandbox de mundo aberto ambientado no universo de One Piece, renderizado em estilo **HD-2D** (ambiente 3D de baixo polígono com sprites 2D em billboard) com personagens construídos por camadas do conjunto **LPC (Liberated Pixel Cup, CC-BY)**.

O objetivo de longo prazo é um mundo vivo onde jogadores navegam pelos Sete Mares, formam tripulações, conquistam ilhas, aprendem o Haki, dominam Akuma no Mi e escolhem profissões — espelhando o mundo-sandbox do mangá sem usar assets proprietários da Toei/Bandai.

### Stack Técnico

| Camada | Tecnologia |
|---|---|
| Cliente | Godot 4.x (GDScript) |
| Servidor de autoridade | Plugin Go (buildmode=plugin) |
| Plataforma de matchmaking | Nakama 3.21.1 |
| Banco de dados | PostgreSQL 15 |
| Infra local | Docker Compose |
| Assets visuais | LPC (CC-BY) — Universal LPC Spritesheet |
| Rede | WebSocket Nakama, mensagens binário JSON |

---

## 2. Norte — Visão Completa do Jogo (Pós-MVP)

O "norte" representa a visão completa descrita no documento fundador do projeto. Serve de bússola para todas as decisões de design.

### 2.1 Mundo e Navegação
- **Mapa aberto** com ilhas interligadas por rotas marítimas.
- **Barcos** navegáveis com física básica; tripulação compartilha embarcação.
- **Ilhas temáticas** com biomas, dungeons, NPCs e missões locais.

### 2.2 Facções e Política
- **Tripulações de piratas** formadas por jogadores (capitão elege rumo, divide loot).
- **Marinha** como facção oposta com ranking e missões de caça a piratas.
- **Guerra de territórios**: ilhas mudam de controle por PvP/siege.
- **Warlords/Yonko** como cargos de prestígio com buffs globais.

### 2.3 Sistema de Poderes
- **Haki**: Observation (detecção, esquiva), Armament (buff de dano/defesa), Conqueror (debuff AoE raro).
- **Akuma no Mi**: Paramecia, Logia (imunidade elementar), Zoan (forma animal com stats alterados). Uma fruta por servidor; rara, obtida por exploração.
- **Profissões de Combate**: Espadachim, Sniper, Artilheiro, Médico, Inventor — cada uma com árvore de skills exclusiva.

### 2.4 Progressão
- Atributos base: **STR** (dano físico), **AGI** (velocidade, esquiva), **INT** (Haki, curas).
- XP por combate, missões e crafting; level sem teto hard-cap mas com diminishing returns.
- Inventário e equipamento persistidos no servidor (Storage Nakama/Postgres).

### 2.5 Social
- **Chat** global, de tripulação e de ilha.
- **Party**: grupo até 4 jogadores com loot distribuído.
- **Bounty system**: piratas famosos ganham recompensa visível a todos.

---

## 3. Corte Vertical — Build 1: Porão da Alvida (MVP)

O corte vertical implementa o mínimo para provar a arquitetura e entregar diversão genuína para 2 jogadores cooperativos.

### 3.1 Premissa
Dois jogadores acordam presos no **porão do navio da Alvida**. Devem sobreviver e derrotar os capangas para avançar. Sem saída do porão nesta build — o mundo aberto fica para futuras fases.

### 3.2 O que está INCLUÍDO
- Compositor de personagem LPC (corpo, cabelo, roupa, cor).
- Combate PvE cooperativo autoritativo no servidor.
- Inimigos LPC auto-gerados por seed (4–6 spawn points, 1–2 archetypes).
- Loot de armas com unlock de skill de arma.
- Progressão: XP → level → alocação de STR/AGI/INT.
- Persistência: relogar mantém progresso, visual, inventário.
- HUD: HP, XP, 2 botões de skill.

### 3.3 O que está EXCLUÍDO desta build
- PvP, facções, Marinha.
- Akuma no Mi, Haki, profissões.
- Chat in-game, party formal.
- Mapa aberto, barcos, outras ilhas.
- Assets oficiais da Toei/Bandai.

---

## 4. Loop de Jogo — Build 1

```
SPAWN no porão (visual LPC do creator)
        │
        ▼
EXPLORAR o porão (movimento WASD, câmera HD-2D)
        │
        ▼
ENCONTRAR goon LPC (spawn auto-gerado por seed)
        │
        ▼
COMBATE PvE (intents → server → snapshots)
   ├─ Punch (skill base, sem equip)
   └─ Skill de arma (se arma equipada)
        │
        ▼
LOOT (item dropa no chão → coletar)
   ├─ Arma nova → unlock skill de arma
   └─ Consumíveis (HP)
        │
        ▼
EQUIP (inventário → slot de arma)
        │
        ▼
XP acumulada → LEVEL UP
        │
        ▼
ALOCAR ATRIBUTO (STR / AGI / INT)
        │
        ▼
Volta ao topo (mais goons, mais loot, level maior)
```

Goons respawnam após 30 s. O loop é infinito nesta build (roguelite de endurance coop).

---

## 5. Roadmap Pós-MVP (Ordem de Implementação)

| Fase | Feature | Observações |
|---|---|---|
| MVP | Porão Alvida PvE coop | Esta build |
| 1 | Chat in-game + Party (4 jogadores) | Base social mínima |
| 2 | Akuma no Mi (1–3 frutas, Paramecia) | Raridade + mecânica de poder |
| 3 | Profissões de Combate (Espadachim, Sniper) | Árvores de skill divergentes |
| 4 | Haki (Observation + Armament) | Desbloqueado por level alto |
| 5 | Saída do Porão → Loguetown | Primeiro mapa aberto |
| 6 | Barcos e Navegação | Rota entre ilhas |
| 7 | Facções (Piratas vs Marinha) | **Por último** — requer mundo aberto, PvP, reputação |

> **Nota:** Facções ficam por último porque dependem de mundo aberto estável, PvP balanceado e sistemas de reputação — todos complexos. Apressar facções sem base sólida cria desequilíbrio irrecuperável.

---

## 6. Identidade Visual

- **Estilo:** HD-2D — plano de chão 3D low-poly, sprites 2D billboard para personagens e inimigos.
- **Paleta:** tons quentes de madeira envelhecida, corda, metal enferrujado (porão de navio pirata).
- **Personagens:** LPC multi-camada (body → hair → outfit → weapon), animações 4 direções (walk, idle, attack).
- **Inimigos:** mesmo sistema LPC com seed de aparência — cada goon é visualmente único mas pertence a 1–2 archetypes de comportamento.

---

## 7. Autoridade de Rede

O servidor Nakama/Go é a **única fonte de verdade**:

- Clientes enviam **intents** (move, attack, equip, allocate_stat).
- O match handler Go valida, processa e publica **snapshots** de estado.
- Clientes interpolam posição e animam resultado — nunca aplicam dano ou XP localmente.
- Isso garante ausência de cheating desde o dia 1.

---

*Este GDD é um documento vivo. Atualize após cada fase concluída.*
