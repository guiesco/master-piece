# Product Context — One Piece MMO

## Por Que Este Jogo Existe

One Piece tem uma das maiores e mais apaixonadas bases de fãs do mundo, mas carece de um MMO sandbox que capture a essência do mangá: a liberdade de velejar pelos Sete Mares, formar tripulações genuínas, encontrar frutas do Diabo e crescer de pirata desconhecido a lenda. Os jogos oficiais existentes são majoritariamente de luta ou RPG linear — nenhum oferece o sandbox social que o universo pede.

Este projeto preenche essa lacuna usando tecnologia moderna e assets 100% legais (LPC CC-BY), tornando-o distribuível sem riscos legais.

## Problemas que Resolve

### Para o Jogador
| Problema | Solução |
|---|---|
| MMOs de One Piece oficiais são lineares / pay-to-win | Progressão baseada em habilidade e cooperação, sem microtransações |
| Falta de MMO sandbox 2D com universo One Piece | Mundo aberto navegável com ilhas e tripulações |
| Multiplayer de One Piece é local ou PvP puro | Coop PvE como modo primário, facções opcionais depois |
| Servidores cheateáveis em jogos indie | Arquitetura autoritativa desde o dia 1 |

### Para o Desenvolvedor
| Problema | Solução |
|---|---|
| Assets proprietários bloqueiam desenvolvimento indie | LPC CC-BY: criação de personagens rica e legal |
| Backends de MMO complexos de escalar | Nakama + Go plugin: plataforma battle-tested com matchmaking, Storage, Auth |
| Sincronização de estado é difícil de acertar depois | Modelo intents→server→snapshots desde o primeiro commit |

## Como o Jogo Deve Funcionar

### Experiência Ideal — Sessão de 30 Minutos (Build 1)
1. Jogador abre Godot, escolhe visual do personagem no compositor LPC (30 s).
2. Conecta ao Nakama, entra no match "Alvida Hold" com um amigo (20 s).
3. Ambos aparecem no porão escuro — veem-se imediatamente, com nomes flutuando.
4. Avançam pelo corredor, encontram um goon LPC visualmente único.
5. Coordenam: um soca, outro coleta o loot enquanto o goon cai.
6. Arma dropada → equipada → nova skill desbloqueada no HUD.
7. Matam mais goons, sobem de nível, alocam atributos.
8. Um dos dois sai; ao reconectar, o progresso está intacto.

### Sentimento Alvo
- **Coop descontraído:** "Olha esse cara que apareceu, bora matar juntos!"
- **Progressão satisfatória:** cada level e nova arma tem impacto visual e mecânico.
- **Mundo Vivo (futuro):** ilhas com história, NPCs reativos, facções em guerra.

## Metas de Experiência do Usuário

- **Onboarding < 1 minuto:** criação de personagem rápida, join automático.
- **Feedback imediato:** HP bars, números de dano, animações de hit.
- **Persistência invisível:** o jogo salva automaticamente; o jogador nunca perde progresso por desconexão.
- **Fairness:** sem advantage de pagamento; quem joga mais fica mais forte, mas newcomers sempre conseguem alcançar.

## Roadmap de Experiência (Pós-MVP)

1. **Social (chat/party):** Jogar com amigos de forma organizada.
2. **Akuma no Mi:** A "magia" do universo — transformações raras e poderosas.
3. **Profissões:** Identidade de combate: cada jogador tem um papel único.
4. **Haki:** Sistema de maestria — recompensa dedicação long-term.
5. **Mundo Aberto (Loguetown):** A primeira ilha real com mapa, NPCs e quests.
6. **Navegação e Barcos:** Velejar em grupo — core fantasy do One Piece.
7. **Facções (por último):** O endgame social — piratas vs Marinha com consequências reais.
