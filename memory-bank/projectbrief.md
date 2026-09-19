# Project Brief — One Piece MMO

## Propósito

Construir um MMO-RPG sandbox 2D/HD-2D ambientado no universo de One Piece usando exclusivamente assets open-source (LPC CC-BY) e tecnologia de servidor autoritativo (Nakama + Go plugin), entregando uma experiência cooperativa genuína sem violar propriedade intelectual da Toei/Bandai.

## Objetivos do Projeto

### Objetivo Imediato (Build 1 — MVP Alvida Hold)
Provar a arquitetura completa client-server autoritativa com dois jogadores cooperativos num ambiente confinado (porão da Alvida), incluindo:
- Criação de personagem visual LPC
- Combate PvE autoritativo no servidor
- Progressão persistida (XP, level, atributos, inventário)
- Inimigos visualmente únicos (geração procedural por seed LPC)

### Objetivo de Médio Prazo
Expandir para Loguetown e outras ilhas, adicionar Akuma no Mi, profissões e Haki — construindo o loop completo de progressão de piratas.

### Objetivo de Longo Prazo
MMO sandbox completo com facções (piratas vs Marinha), mundo aberto navegável, guerra de territórios e sistema político dinâmico.

## Escopo da Build 1 (MVP)

### Incluído
- **Ambiente:** Porão do navio da Alvida (mapa único, sem saída)
- **Jogadores:** 2 players em coop (Nakama matchmaking)
- **Visual:** Compositor LPC (corpo, cabelo, roupa, cor) com animações 4 direções
- **Combate:** Punch base + skill de arma (unlock por equip), PvE apenas
- **Inimigos:** Goons LPC auto-gerados por seed (4–6 spawns, 1–2 archetypes)
- **Progressão:** XP → level → STR/AGI/INT → reloga com progresso
- **Loot:** Armas e consumíveis droppados por inimigos
- **Persistência:** Storage Nakama → Postgres, relogin mantém tudo

### Excluído (explicitamente)
- PvP, friendly fire
- Facções (piratas, Marinha)
- Akuma no Mi, Haki, profissões
- Chat in-game, party formal
- Mundo aberto, barcos, outras ilhas
- Assets proprietários (sprites Toei/Bandai)

## Restrições Inegociáveis

1. **Rede autoritativa:** servidor valida 100% das ações; cliente só envia intents.
2. **Assets legais:** apenas LPC (CC-BY) + criações próprias; zero assets de copyright.
3. **Stack fixo:** Godot 4 + Nakama 3.21.1 + Go plugin + Postgres + Docker Compose.
4. **Facções por último:** não implementar até mundo aberto e PvP estarem maduros.
5. **Banco de dados:** PostgreSQL (não CockroachDB) no ambiente local MVP.
