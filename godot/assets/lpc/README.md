# Liberated Pixel Cup / Universal LPC — assets e referência

## Estrutura no projeto

```
godot/assets/lpc/
  body/     body_*.png      ← torso/membros (SEM cabeça no ULPC)
  head/     head_male.png, head_female.png
  eyes/     eyes_default.png
  hair/     hair_*.png
  outfit/   outfit_*.png
  weapon/   weapon_*.png
```

O Universal LPC separa corpo e cabeça. Sem a camada `head`, o rosto fica
buraco preto no preview e no mundo.

## Como os IDs funcionam

Os nomes dos PNG batem com `backend/content/lpc_catalog.json`.
O `LPCComposer` carrega `res://assets/lpc/{layer}/{id}.png` e mostra
1 frame do walk sheet (64×64, direção "baixo").

Tons de pele/cabelo usam `body_tint` / `hair_tint` (modulate), porque as
bases de corpo/cabelo do Universal LPC são sheets recoloríveis.

## Atualizar / expandir assets

1. Edite o mapeamento e rode um copy a partir de `vendor/.../spritesheets/`.
2. Ou use o gerador web / skills do repo (`.agents/skills/`).
3. Atualize `SOURCE_MAP.json` e `CREDITS.txt`.

## Não commitar o vendor inteiro

O clone tem ~90k arquivos. Preferir:

- versionar só `godot/assets/lpc/*.png` + CREDITS/SOURCE_MAP
- manter `vendor/` local (já no `.gitignore` da raiz)
