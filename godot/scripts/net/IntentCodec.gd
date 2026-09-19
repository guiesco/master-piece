class_name IntentCodec
## IntentCodec — Classe estática para serialização/deserialização de payloads JSON dos OpCodes.
##
## OpCodes de envio (Cliente → Servidor) — espelham types.go:
##   1  — move
##   10 — attack
##   21 — equip
##   32 — allocate_stat
##
## OpCodes de recepção (Servidor → Cliente) — espelham types.go:
##   2  — player_state
##   3  — player_joined
##   4  — player_left
##   11 — combat_event
##   20 — loot           (OpLoot = 20)
##   30 — xp_event       (OpXPEvent = 30)
##   31 — level_up       (OpLevelUp = 31)
##   40 — enemy_state    (OpEnemyState = 40)
##   41 — enemy_spawn    (OpEnemySpawn = 41)
##   42 — enemy_death    (OpEnemyDeath = 42)

# ─── Encoders (Cliente → Servidor) ──────────────────────────────────────────

## Serializa intenção de movimento.
## @param x  Posição X no mundo.
## @param y  Posição Y no mundo (profundidade, eixo Z na cena 3D).
## @param seq Número de sequência para reconciliação.
static func encode_move(x: float, y: float, seq: int) -> String:
	return JSON.stringify({"x": x, "y": y, "seq": seq})

## Serializa intenção de ataque.
## @param skill_id  ID da skill usada (ex: "punch", "sword_slash", "bow_shot").
## @param aim_x    Posição X do alvo no mundo.
## @param aim_y    Posição Y do alvo no mundo.
static func encode_attack(skill_id: String, aim_x: float, aim_y: float) -> String:
	return JSON.stringify({"skill_id": skill_id, "aim_x": aim_x, "aim_y": aim_y})

## Serializa intenção de equipar item.
## @param item_id  ID do item a equipar (ex: "sword_01").
static func encode_equip(item_id: String) -> String:
	return JSON.stringify({"item_id": item_id})

## Serializa intenção de alocar ponto de atributo.
## @param stat  Nome do atributo: "str", "agi" ou "int".
static func encode_allocate_stat(stat: String) -> String:
	return JSON.stringify({"stat": stat})

# ─── Decoders (Servidor → Cliente) ──────────────────────────────────────────

## OpCode 2 — Estado de um jogador (playerStateMsg do servidor: player_id, x, y, seq).
## Retorna: { id, x, y(=0), z(=server.y), hp, max_hp, state, dir, appearance, equipped }
## NOTA: servidor usa X e Y onde Y = profundidade (mapeado para Godot Z).
static func decode_player_state(json: Dictionary) -> Dictionary:
	return {
		"id": str(json.get("player_id", json.get("user_id", json.get("id", "")))),
		"x": float(json.get("x", 0.0)),
		"y": 0.0,                          # Godot Y = altura, sempre 0 no porão plano
		"z": float(json.get("y", 0.0)),    # Server Y = profundidade → Godot Z
		# hp/max_hp são -1 quando ausentes (ex.: playerStateMsg de movimento não tem hp).
		# Verificar >= 0 antes de aplicar HP em handlers.
		"hp": int(json.get("hp", -1)),
		"max_hp": int(json.get("max_hp", -1)),
		"state": str(json.get("state", "idle")),
		"dir": str(json.get("dir", "down")),
		"appearance": json.get("appearance", {}),
		"equipped": json.get("equipped", {}),
	}

## OpCode 3 — Jogador entrou no match (PlayerState do servidor: user_id, x, y, ...).
## Retorna: { id, x, y(=0), z(=server.y), appearance, username }
## NOTA: servidor envia PlayerState completo com user_id como chave de identificação.
static func decode_player_joined(json: Dictionary) -> Dictionary:
	return {
		"id": str(json.get("user_id", json.get("player_id", json.get("id", "")))),
		"x": float(json.get("x", 0.0)),
		"y": 0.0,                          # Godot Y = altura, sempre 0
		"z": float(json.get("y", 0.0)),    # Server Y = profundidade → Godot Z
		"appearance": json.get("appearance", {}),
		"username": str(json.get("username", "Anon")),
	}

## OpCode 4 — Jogador saiu do match (servidor envia {"player_id": "..."}).
## Retorna: { id }
static func decode_player_left(json: Dictionary) -> Dictionary:
	return {
		"id": str(json.get("player_id", json.get("id", ""))),
	}

## OpCode 11 — Evento de combate (dano aplicado a jogador ou inimigo).
## Servidor envia: { attacker_id, target_id, damage, target_hp, skill_id,
##   anim, is_ranged, from_x, from_y, to_x, to_y }
static func decode_combat_event(json: Dictionary) -> Dictionary:
	return {
		"attacker_id": str(json.get("attacker_id", "")),
		"target_id":   str(json.get("target_id", "")),
		"damage":      int(json.get("damage", json.get("amount", 0))),
		"target_hp":   int(json.get("target_hp", -1)),
		"skill_id":    str(json.get("skill_id", "")),
		"anim":        str(json.get("anim", "")),
		"is_ranged":   bool(json.get("is_ranged", false)),
		"from_x":      float(json.get("from_x", 0.0)),
		"from_y":      float(json.get("from_y", 0.0)),
		"to_x":        float(json.get("to_x", 0.0)),
		"to_y":        float(json.get("to_y", 0.0)),
	}

## OpCode 21 — Broadcast de equip (servidor → clientes).
## Campos: player_id, item_id, skill_id (legado), skill_primary, skill_secondary
static func decode_equip(json: Dictionary) -> Dictionary:
	var primary := str(json.get("skill_primary", ""))
	var secondary := str(json.get("skill_secondary", json.get("skill_id", "")))
	return {
		"player_id":       str(json.get("player_id", "")),
		"item_id":         str(json.get("item_id", "")),
		"skill_id":        str(json.get("skill_id", secondary)),
		"skill_primary":   primary,
		"skill_secondary": secondary,
	}

## OpCode 20 — Loot dropado para o jogador (lootMsg: player_id, item_id).
## Retorna: { item_id, item_name, x, y, z, loot_id }
static func decode_loot(json: Dictionary) -> Dictionary:
	return {
		"item_id": str(json.get("item_id", "")),
		"item_name": str(json.get("item_name", "")),
		"x": float(json.get("x", 0.0)),
		"y": float(json.get("y", 0.0)),
		"z": float(json.get("z", 0.0)),
		"loot_id": str(json.get("loot_id", "")),
	}

## OpCode 30 — Ganho de XP (xpEventMsg: player_id, xp_gained, total_xp, level,
##   pending_points, xp_to_next, strength, agility, intelligence, hp, max_hp).
## hp e max_hp incluídos desde que o backend adicionou o campo (contrato atual).
## AlvidaHold passa o raw dict direto ao Player; este decoder é documentação/compat.
static func decode_xp_event(json: Dictionary) -> Dictionary:
	return {
		"player_id":     str(json.get("player_id", "")),
		"xp_gained":     int(json.get("xp_gained", 0)),
		"total_xp":      int(json.get("total_xp", 0)),
		"level":         int(json.get("level", 1)),
		"pending_points":int(json.get("pending_points", 0)),
		"xp_to_next":    int(json.get("xp_to_next", 100)),
		"strength":      int(json.get("strength", 1)),
		"agility":       int(json.get("agility", 1)),
		"intelligence":  int(json.get("intelligence", 1)),
		"hp":            int(json.get("hp", -1)),
		"max_hp":        int(json.get("max_hp", -1)),
	}

## OpCode 31 — Level up (levelUpMsg: player_id, new_level, pending_points).
## Retorna: { player_id, new_level, stat_points, stats }
static func decode_level_up(json: Dictionary) -> Dictionary:
	return {
		"player_id": str(json.get("player_id", "")),
		"new_level": int(json.get("new_level", 1)),
		"stat_points": int(json.get("stat_points", 0)),
		"stats": json.get("stats", {}),
	}

## OpCode 40 — Estado de um inimigo (enemyStateSnapshotMsg: enemy_id, x, y, ai_state, hp).
## Retorna: { id, archetype, x, y(server), hp, max_hp, state, appearance }
## NOTA: servidor usa "enemy_id"; aplica o Y do servidor como Godot Z via apply_server_state().
static func decode_enemy_state(json: Dictionary) -> Dictionary:
	return {
		"id": str(json.get("enemy_id", json.get("id", ""))),
		"archetype": str(json.get("archetype", "")),
		"x": float(json.get("x", 0.0)),
		"y": float(json.get("y", 0.0)),    # Server Y = profundidade (Enemy.gd usa como Godot Z)
		"hp": int(json.get("hp", 0)),
		"max_hp": int(json.get("max_hp", 60)),
		"state": str(json.get("ai_state", json.get("state", "idle"))),
		"appearance": json.get("appearance", {}),
	}

## OpCode 41 — Inimigo spawnado no match (enemySpawnMsg: enemy_id, archetype, x, y, hp, max_hp, appearance).
## Retorna: { id, archetype, x, y(server), hp, max_hp, appearance }
## NOTA: AlvidaHold.gd lê "enemy_id" diretamente do raw, mas este decoder normaliza para "id".
static func decode_enemy_spawn(json: Dictionary) -> Dictionary:
	return {
		"id": str(json.get("enemy_id", json.get("id", ""))),
		"archetype": str(json.get("archetype", "")),
		"x": float(json.get("x", 0.0)),
		"y": float(json.get("y", 0.0)),    # Server Y = profundidade (mapeado para Godot Z pelo setup())
		"hp": int(json.get("hp", 60)),
		"max_hp": int(json.get("max_hp", 60)),
		"appearance": json.get("appearance", {}),
	}
