extends Node3D
## AlvidaHold — Cena principal do mundo (porão do navio da Alvida).
## Conecta signals do NetworkManager, instancia jogadores e inimigos,
## e despacha eventos por OpCode.
##
## Fase 4: handlers de OpCombatEvent, OpEnemyDeath e OpPlayerDeath corrigidos
## para chamar os métodos visuais nas entidades corretas.

## OpCodes — devem espelhar types.go exatamente.
const OP_PLAYER_STATE  := 2
const OP_PLAYER_JOINED := 3
const OP_PLAYER_LEFT   := 4
const OP_PLAYER_DEATH  := 5   # Fase 4: respawn simples
const OP_COMBAT_EVENT  := 11
const OP_LOOT          := 20  # Fase 5: item dropado
const OP_EQUIP         := 21  # Fase 5: broadcast de equip (servidor → clientes)
const OP_XP_EVENT      := 30  # Fase 5: ganho de XP / alocação de stat
const OP_LEVEL_UP      := 31  # Fase 5: subiu de nível
const OP_ENEMY_STATE   := 40
const OP_ENEMY_SPAWN   := 41
const OP_ENEMY_DEATH   := 42  # types.go: OpEnemyDeath = 42

const PLAYER_SCENE     := preload("res://scenes/player/Player.tscn")
const ENEMY_SCENE      := preload("res://scenes/enemy/Enemy.tscn")
const PROJECTILE_SCENE := preload("res://scenes/fx/Projectile.tscn")

@onready var players_container: Node = $Players
@onready var enemies_container: Node = $Enemies
@onready var hud: HUD = $HUD
@onready var camera_follow: Node3D = $CameraFollow   # CameraFollow extends Camera3D

## Dicionário: user_id → Player node (apenas jogadores remotos)
var _remote_players: Dictionary = {}

## Dicionário: enemy_id → Enemy node
var _enemies: Dictionary = {}

var _local_player: Node3D = null
var _match_id: String = ""

# ─── Lifecycle ──────────────────────────────────────────────────────────────

func _ready() -> void:
	_connect_network_signals()
	_connect_hud_signals()
	# Catch-up de perfil (já carregado no CharacterCreator).
	if not NetworkManager.last_profile.is_empty():
		_on_profile_loaded(NetworkManager.last_profile)
	elif not NetworkManager.appearance_data.is_empty():
		_on_profile_loaded({"appearance": NetworkManager.appearance_data})
	# Join atrasado: spawns de inimigos chegam com a cena já ouvindo.
	await NetworkManager.join_match_if_needed()
	if NetworkManager.is_in_match():
		_on_match_joined(NetworkManager.get_match_id())

func _connect_network_signals() -> void:
	NetworkManager.match_joined.connect(_on_match_joined)
	NetworkManager.match_state_received.connect(_on_match_state_received)
	NetworkManager.profile_loaded.connect(_on_profile_loaded)

func _connect_hud_signals() -> void:
	if is_instance_valid(hud):
		hud.skill_pressed.connect(_on_skill_pressed)
		hud.allocate_stat_pressed.connect(_on_allocate_stat_pressed)
		hud.equip_item_pressed.connect(_on_equip_item_pressed)

# ─── NetworkManager handlers ────────────────────────────────────────────────

func _on_match_joined(match_id: String) -> void:
	_match_id = match_id

func _on_profile_loaded(profile_data: Dictionary) -> void:
	if _local_player == null:
		_spawn_local_player(profile_data)

func _spawn_local_player(profile_data: Dictionary) -> void:
	_local_player = PLAYER_SCENE.instantiate()
	# Centro do mapa servidor 50×50 — definir antes do add_child para o _ready gravar spawn.
	_local_player.position  = Vector3(25.0, 0.0, 25.0)
	players_container.add_child(_local_player)
	_local_player.is_local  = true
	_local_player.player_id = NetworkManager.local_user_id
	_local_player.hud       = hud

	# Aponta a câmera para o jogador local
	if is_instance_valid(camera_follow):
		camera_follow.target = _local_player

	var appearance: Dictionary = NetworkManager.appearance_data
	if appearance.is_empty():
		appearance = profile_data.get("appearance", {})
	_local_player.apply_appearance(appearance)

	# Inicializa vars de progressão no Player a partir do perfil.
	var stats: Dictionary = profile_data.get("stats", {})
	_local_player.xp             = int(profile_data.get("xp", 0))
	_local_player.level          = int(profile_data.get("level", 1))
	_local_player.pending_points = int(profile_data.get("pending_stat_points", 0))
	_local_player.stats_str      = int(stats.get("strength", 1))
	_local_player.stats_agi      = int(stats.get("agility", 1))
	_local_player.stats_int      = int(stats.get("intelligence", 1))

	# Inventário e arma equipada.
	var inv = profile_data.get("inventory", [])
	if inv is Array:
		_local_player.inventory = inv
	var eq: String = str(profile_data.get("equipped", ""))
	if eq != "":
		_local_player.equipped_weapon = eq
		_local_player.apply_equipped_weapon(eq)
	else:
		_local_player.skill_slots = ["punch", "punch"]

	if is_instance_valid(hud):
		# rpc_select_character pode não incluir hp/max_hp — calcular se ausentes.
		var cur_max_hp: int
		if profile_data.has("max_hp") and int(profile_data.get("max_hp", 0)) > 0:
			cur_max_hp = int(profile_data["max_hp"])
		else:
			cur_max_hp = 100 + _local_player.stats_str * 5
		var cur_hp: int = int(profile_data.get("hp", cur_max_hp))
		_local_player.hp     = cur_hp
		_local_player.max_hp = cur_max_hp
		var xp_to_next: int = _local_player.level * 100
		hud.update_hp(cur_hp, cur_max_hp)
		hud.update_xp(_local_player.xp, xp_to_next)
		hud.update_level(_local_player.level)
		hud.update_stats(
			_local_player.stats_str,
			_local_player.stats_agi,
			_local_player.stats_int,
			_local_player.pending_points
		)
		hud.refresh_inventory(_local_player.inventory, _local_player.equipped_weapon)
		hud.update_skills(str(_local_player.skill_slots[0]), str(_local_player.skill_slots[1]))

func _on_match_state_received(op_code: int, data: Variant, _presence: Variant) -> void:
	match op_code:
		OP_PLAYER_STATE:
			_handle_player_state(data)
		OP_PLAYER_JOINED:
			_handle_player_joined(data)
		OP_PLAYER_LEFT:
			_handle_player_left(data)
		OP_PLAYER_DEATH:
			_handle_player_death(data)
		OP_COMBAT_EVENT:
			_handle_combat_event(data)
		OP_LOOT:
			_handle_loot(data)
		OP_EQUIP:
			_handle_equip(data)
		OP_XP_EVENT:
			_handle_xp_event(data)
		OP_LEVEL_UP:
			_handle_level_up(data)
		OP_ENEMY_STATE:
			_handle_enemy_state(data)
		OP_ENEMY_SPAWN:
			_handle_enemy_spawn(data)
		OP_ENEMY_DEATH:
			_handle_enemy_death(data)

# ─── OpCode handlers ────────────────────────────────────────────────────────

func _handle_player_state(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var state := IntentCodec.decode_player_state(raw)
	var pid: String = state["id"]

	if pid == NetworkManager.local_user_id:
		# hp == -1 indica que este snapshot é só de movimento (playerStateMsg) — sem HP.
		# Evita zerar o HP local com cada pacote de movimento.
		if state["hp"] >= 0:
			var max_hp_val: int = state["max_hp"] if state["max_hp"] >= 0 else \
				(_local_player.max_hp if is_instance_valid(_local_player) else 100)
			if is_instance_valid(hud):
				hud.update_hp(state["hp"], max_hp_val)
			if is_instance_valid(_local_player):
				_local_player.update_hp(state["hp"], max_hp_val)
		return

	if _remote_players.has(pid):
		var player: Node3D = _remote_players[pid]
		if is_instance_valid(player):
			player.apply_server_state(state)

func _handle_player_joined(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var joined := IntentCodec.decode_player_joined(raw)
	var pid: String = joined["id"]

	if pid == NetworkManager.local_user_id:
		return
	if _remote_players.has(pid):
		return

	var player: Node3D = PLAYER_SCENE.instantiate()
	players_container.add_child(player)
	player.is_local   = false
	player.player_id  = pid
	player.position   = Vector3(joined["x"], joined["y"], joined["z"])
	player.apply_appearance(joined.get("appearance", {}))
	_remote_players[pid] = player

func _handle_player_left(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var left := IntentCodec.decode_player_left(raw)
	var pid: String = left["id"]

	if _remote_players.has(pid):
		var player: Node3D = _remote_players[pid]
		if is_instance_valid(player):
			player.queue_free()
		_remote_players.erase(pid)

## Fase 4 — OpCombatEvent (opcode 11).
## Projétil is_ranged spawna ANTES de qualquer early return (todos os hits).
## Roteia dano/hurt para o alvo e anim de ataque para o atacante.
func _handle_combat_event(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var evt := IntentCodec.decode_combat_event(raw)
	var target_id: String = evt["target_id"]
	var damage:    int    = evt["damage"]
	var target_hp: int    = evt["target_hp"]
	var attacker_id: String = evt["attacker_id"]

	# ── VFX ranged (TODOS os hits, antes de returns) ─────────────────────────
	if bool(evt.get("is_ranged", false)):
		var from_pos := Vector3(float(evt.get("from_x", 0.0)), 0.0, float(evt.get("from_y", 0.0)))
		var to_aim := Vector2(float(evt.get("to_x", 0.0)), float(evt.get("to_y", 0.0)))
		# Fallback: posições dos nós se coords do servidor vierem zeradas
		if from_pos.length_squared() < 0.0001:
			var atk_node: Node3D = _resolve_entity_node(attacker_id)
			if is_instance_valid(atk_node):
				from_pos = atk_node.global_position
		if to_aim.length_squared() < 0.0001:
			var tgt_node: Node3D = _resolve_entity_node(target_id)
			if is_instance_valid(tgt_node):
				to_aim = Vector2(tgt_node.global_position.x, tgt_node.global_position.z)
		_spawn_projectile(from_pos, to_aim, 10.0)

	# ── Anim de ataque no atacante ───────────────────────────────────────────
	_play_attacker_anim(attacker_id, evt)

	# ── Inimigo ──────────────────────────────────────────────────────────────
	if _enemies.has(target_id):
		var enemy = _enemies[target_id]
		if is_instance_valid(enemy):
			enemy.receive_combat_event(evt)
		if damage > 0:
			_show_damage_number(target_id, damage)
		return

	# ── Jogador local ─────────────────────────────────────────────────────────
	if target_id == NetworkManager.local_user_id:
		if is_instance_valid(_local_player):
			_local_player.receive_combat_event(evt)
		if is_instance_valid(hud) and damage > 0:
			var cur_max_hp: int = _local_player.max_hp if is_instance_valid(_local_player) else 100
			hud.update_hp(target_hp, cur_max_hp)
		if damage > 0:
			_show_damage_number(target_id, damage)
		return

	# ── Jogador remoto ────────────────────────────────────────────────────────
	if _remote_players.has(target_id):
		var player: Node3D = _remote_players[target_id]
		if is_instance_valid(player):
			player.receive_combat_event(evt)
		if damage > 0:
			_show_damage_number(target_id, damage)

func _resolve_entity_node(entity_id: String) -> Node3D:
	if entity_id == NetworkManager.local_user_id:
		return _local_player
	if _remote_players.has(entity_id):
		return _remote_players[entity_id]
	if _enemies.has(entity_id):
		return _enemies[entity_id]
	return null

func _play_attacker_anim(attacker_id: String, evt: Dictionary) -> void:
	var anim_name := str(evt.get("anim", ""))
	# Hit de impacto (dano delayed): sem anim — evita re-tocar o golpe.
	if anim_name == "" and not bool(evt.get("is_ranged", false)):
		return
	var from_x := float(evt.get("from_x", 0.0))
	var from_y := float(evt.get("from_y", 0.0))
	var to_x := float(evt.get("to_x", from_x))
	var to_y := float(evt.get("to_y", from_y))
	var face_dx := to_x - from_x
	var face_dz := to_y - from_y
	if _enemies.has(attacker_id):
		var enemy = _enemies[attacker_id]
		if is_instance_valid(enemy) and enemy.has_method("play_attack_anim"):
			enemy.play_attack_anim(anim_name, face_dx, face_dz)
		return
	# Remoto: anima ataque; local já animou no input
	if attacker_id != NetworkManager.local_user_id and _remote_players.has(attacker_id):
		var player: Node3D = _remote_players[attacker_id]
		if is_instance_valid(player) and player.has_method("play_attack_from_event"):
			player.play_attack_from_event(evt)

## Fase 4 — OpPlayerDeath (opcode 5).
## Chama receive_death() no jogador local se o player_id bater.
func _handle_player_death(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var pid: String = str(raw.get("player_id", ""))
	if pid != NetworkManager.local_user_id:
		return
	if is_instance_valid(_local_player):
		_local_player.receive_death()
	if is_instance_valid(hud):
		var max_hp: int = _local_player.max_hp if is_instance_valid(_local_player) else 100
		hud.update_hp(max_hp, max_hp)

## Fase 5 — OpLoot (opcode 20).
## Se o player_id bater com o local, delega ao Player para adicionar ao inventário.
func _handle_loot(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var pid: String = str(raw.get("player_id", ""))
	if pid == NetworkManager.local_user_id and is_instance_valid(_local_player):
		_local_player.receive_loot(raw)

## Fase 5 — OpEquip (opcode 21, servidor → clientes).
## dual skills: skill_primary (LMB) + skill_secondary (RMB).
func _handle_equip(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var eq := IntentCodec.decode_equip(raw)
	var pid: String = eq["player_id"]
	var item_id: String = eq["item_id"]
	var skill_primary: String = eq["skill_primary"]
	var skill_secondary: String = eq["skill_secondary"]

	if pid == NetworkManager.local_user_id:
		if is_instance_valid(_local_player):
			_local_player.equipped_weapon = item_id
			_local_player.apply_equipped_weapon(item_id, skill_primary, skill_secondary)
			if is_instance_valid(hud):
				hud.update_skills(
					str(_local_player.skill_slots[0]),
					str(_local_player.skill_slots[1])
				)
	else:
		if _remote_players.has(pid):
			var player: Node3D = _remote_players[pid]
			if is_instance_valid(player):
				player.apply_equipped_weapon(item_id, skill_primary, skill_secondary)

## Fase 5 — OpXPEvent (opcode 30).
## Delega ao Player local que atualiza vars e chama HUD internamente.
func _handle_xp_event(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var pid: String = str(raw.get("player_id", ""))
	if pid == NetworkManager.local_user_id and is_instance_valid(_local_player):
		_local_player.receive_xp_event(raw)

## Fase 5 — OpLevelUp (opcode 31).
## Delega ao Player local que exibe efeito visual e chama HUD.
func _handle_level_up(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var pid: String = str(raw.get("player_id", ""))
	if pid == NetworkManager.local_user_id and is_instance_valid(_local_player):
		_local_player.receive_level_up(raw)

func _handle_enemy_state(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var state := IntentCodec.decode_enemy_state(raw)
	var eid: String = state["id"]
	if _enemies.has(eid):
		var enemy = _enemies[eid]
		if is_instance_valid(enemy):
			enemy.apply_server_state(state)

## Fase 6 — OpEnemySpawn (opcode 41).
## Cobre dois casos:
##   • Primeiro spawn: instancia Enemy.tscn, chama setup() e registra no dict.
##   • Respawn: enemy_id já existe no dict → chama setup() com novos dados
##     (nova aparência por seed) sem recriar o nó.
func _handle_enemy_spawn(raw: Variant) -> void:
	if not raw is Dictionary:
		return

	# Lê campos diretamente do dicionário (o servidor usa "enemy_id" desde a Fase 6).
	var eid:        String     = str(raw.get("enemy_id", raw.get("id", "")))
	var arch:       String     = str(raw.get("archetype", ""))
	var appearance: Dictionary = raw.get("appearance", {})
	var px:         float      = float(raw.get("x", 0.0))
	var py:         float      = float(raw.get("y", 0.0))
	var hp:         int        = int(raw.get("hp", 60))

	if eid.is_empty():
		return

	if _enemies.has(eid):
		# ── Respawn: reutiliza o nó existente, atualiza visual e estado ───────
		var existing_enemy = _enemies[eid]
		if is_instance_valid(existing_enemy):
			existing_enemy.setup(eid, arch, appearance, px, py, hp)
		return

	# ── Primeiro spawn: instancia e registra ──────────────────────────────────
	var spawned_enemy = ENEMY_SCENE.instantiate()
	enemies_container.add_child(spawned_enemy)
	spawned_enemy.setup(eid, arch, appearance, px, py, hp)
	_enemies[eid] = spawned_enemy

## Fase 4/6 — OpEnemyDeath (opcode 42).
## Executa animação de morte mas NÃO remove o nó do dicionário nem chama
## queue_free. O nó fica "morto" (sprite fadeado, _is_dead=true) e será
## reaproveitado quando o servidor enviar OpEnemySpawn (respawn) com o mesmo
## enemy_id, chamando setup() para restaurar o estado visual.
func _handle_enemy_death(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	# Servidor envia { "enemy_id": "...", "killer_id": "..." }
	var eid: String = str(raw.get("enemy_id", raw.get("id", "")))
	if _enemies.has(eid):
		var enemy = _enemies[eid]
		if is_instance_valid(enemy):
			enemy.play_death()
		# Não apaga do dict: o OpEnemySpawn de respawn vai chamar setup() neste nó.

# ─── HUD signals ────────────────────────────────────────────────────────────

## HUD emite slot 1/2 → índices 0/1 no Player.skill_slots.
func _on_skill_pressed(slot: int) -> void:
	if not is_instance_valid(_local_player):
		return
	var idx := clampi(slot - 1, 0, 1)
	if _local_player.has_method("use_skill_slot"):
		_local_player.use_skill_slot(idx)
	else:
		# Fallback mínimo
		var skill_id := "punch"
		if _local_player.skill_slots.size() > idx:
			skill_id = str(_local_player.skill_slots[idx])
		var aim := Vector2(_local_player.position.x, _local_player.position.z)
		if _local_player.has_method("_get_aim_world_position"):
			aim = _local_player._get_aim_world_position()
		NetworkManager.send_attack_intent(skill_id, aim.x, aim.y)

func _on_allocate_stat_pressed(stat_name: String) -> void:
	NetworkManager.send_allocate_stat(stat_name)

func _on_equip_item_pressed(item_id: String) -> void:
	if is_instance_valid(_local_player):
		_local_player.equip_item(item_id)

# ─── Helpers visuais ────────────────────────────────────────────────────────

## Spawna projétil via Projectile.launch() — usa aim world coords.
## speed > 0 → projétil voador; speed == 0 → flash melee estático.
func _spawn_projectile(from_pos: Vector3, aim: Vector2, speed: float = 0.0) -> void:
	var proj: Node3D = PROJECTILE_SCENE.instantiate()
	add_child(proj)
	# launch() só funciona após add_child (posição global disponível)
	if proj.has_method("launch"):
		proj.launch(from_pos, aim, speed)

## Exibe número de dano flutuante acima da entidade afetada.
func _show_damage_number(target_id: String, amount: int) -> void:
	var target_node: Node3D = null

	if target_id == NetworkManager.local_user_id:
		target_node = _local_player
	elif _remote_players.has(target_id):
		target_node = _remote_players[target_id]
	elif _enemies.has(target_id):
		target_node = _enemies[target_id]

	if target_node == null or not is_instance_valid(target_node):
		return

	var dmg_label := Label3D.new()
	dmg_label.text      = str(amount)
	dmg_label.modulate  = Color.RED if amount > 0 else Color.GREEN
	dmg_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dmg_label.font_size = 96
	dmg_label.position  = target_node.position + Vector3(0.0, 1.5, 0.0)
	add_child(dmg_label)

	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(dmg_label):
		dmg_label.queue_free()
