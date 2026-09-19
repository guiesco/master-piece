extends CharacterBody3D
## Player — Representa um jogador (local ou remoto) no mundo.
##
## Fluxo local:
##   Input WASD/setas → velocity → move_and_slide() (CharacterBody3D).
##   Envia send_move_intent a cada 50 ms (20 Hz).
##   LMB → skill slot 0; RMB → skill slot 1 (gate: anim busy OR local CD).
##
## Fluxo remoto:
##   Recebe apply_server_state(state) → interpola posição via lerp.
##
## Animação: LPCAnimator walk/idle/slash/backslash/hurt/thrust.

## Se true, este node representa o jogador controlado localmente.
var is_local: bool = false
## ID único do jogador (user_id do Nakama).
var player_id: String = ""

## Referência ao HUD (atribuída por AlvidaHold ao spawnar o jogador local).
var hud: Node = null

# ─── Constantes ─────────────────────────────────────────────────────────────

const MOVE_SPEED    := 5.0
const SEND_INTERVAL := 0.05   # 20 Hz
const LERP_SPEED    := 10.0

# ─── Refs de nós ─────────────────────────────────────────────────────────────

@onready var weapon_behind_sprite: Sprite3D = $WeaponBehindSprite
@onready var body_sprite:   Sprite3D = $BodySprite
@onready var head_sprite:   Sprite3D = $HeadSprite
@onready var eyes_sprite:   Sprite3D = $EyesSprite
@onready var hair_sprite:   Sprite3D = $HairSprite
@onready var outfit_sprite: Sprite3D = $OutfitSprite
@onready var weapon_sprite: Sprite3D = $WeaponSprite
@onready var hp_label: Label3D  = $HPLabel

## Compat: alguns efeitos antigos usavam `sprite`; aponta para o corpo.
@onready var sprite: Sprite3D = $BodySprite

var _composer: LPCComposer   = LPCComposer.new()
var _animator: LPCAnimator   = LPCAnimator.new()
var _last_appearance: Dictionary = {}

# ─── Estado ──────────────────────────────────────────────────────────────────

## HP e MaxHP públicos.
var hp:     int = 100
var max_hp: int = 100

## Slots de skill: [primary/LMB, secondary/RMB].
var skill_slots: Array = ["punch", "punch"]

## Progressão e inventário.
var xp:             int    = 0
var level:          int    = 1
var pending_points: int    = 0
var stats_str:      int    = 1
var stats_agi:      int    = 1
var stats_int:      int    = 1
var inventory:      Array  = []
var equipped_weapon: String = ""

var _move_seq:        int    = 0
var _send_timer:      float  = 0.0
var _target_position: Vector3 = Vector3.ZERO
var _spawn_position:  Vector3 = Vector3.ZERO

## Cooldown local por skill_id → Time.get_ticks_msec() em que libera.
var _skill_ready_at: Dictionary = {}

# ─── Lifecycle ──────────────────────────────────────────────────────────────

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	_spawn_position  = position
	_target_position = position
	_composer.setup_nodes(
		body_sprite, hair_sprite, outfit_sprite, weapon_sprite,
		head_sprite, eyes_sprite, weapon_behind_sprite
	)
	_animator.setup_layers([
		body_sprite, head_sprite, eyes_sprite, hair_sprite,
		outfit_sprite, weapon_sprite, weapon_behind_sprite
	])
	_update_hp_label()

func _physics_process(delta: float) -> void:
	if is_local:
		_handle_local_movement(delta)
	else:
		_interpolate_remote(delta)

func _process(delta: float) -> void:
	_animator.update(delta, velocity)

# ─── Controle local ─────────────────────────────────────────────────────────

func _handle_local_movement(delta: float) -> void:
	# Ataque/hurt: trava movimento e não envia move intent.
	if _animator.is_busy():
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var input_dir := Vector3.ZERO

	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input_dir.z += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input_dir.z -= 1.0

	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()

	velocity = input_dir * MOVE_SPEED
	move_and_slide()

	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = SEND_INTERVAL
		_move_seq  += 1
		NetworkManager.send_move_intent(position.x, position.z, _move_seq)

## LMB → slot 0; RMB → slot 1; gamepad A → slot 0.
func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_send_attack_intent(0)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_send_attack_intent(1)
	elif event is InputEventJoypadButton \
			and event.button_index == JOY_BUTTON_A \
			and event.pressed:
		_send_attack_intent(0)

## Envia ataque do slot indicado. Gate: anim busy OU cooldown local.
func _send_attack_intent(slot: int = 0) -> void:
	var skill_id: String = "punch"
	if slot >= 0 and slot < skill_slots.size():
		skill_id = str(skill_slots[slot])
	elif skill_slots.size() > 0:
		skill_id = str(skill_slots[0])

	if _animator.is_busy():
		return
	if _is_skill_on_cooldown(skill_id):
		return

	var aim := _get_aim_world_position()
	_animator.face_toward(aim.x - position.x, aim.y - position.z)
	NetworkManager.send_attack_intent(skill_id, aim.x, aim.y)
	_mark_skill_cooldown(skill_id)
	play_skill_anim(skill_id)

func use_skill_slot(slot: int) -> void:
	_send_attack_intent(slot)

func _is_skill_on_cooldown(skill_id: String) -> bool:
	var ready_at: int = int(_skill_ready_at.get(skill_id, 0))
	return Time.get_ticks_msec() < ready_at

func _mark_skill_cooldown(skill_id: String) -> void:
	var cd_ms := EquipmentVisual.get_cooldown_ms(skill_id)
	_skill_ready_at[skill_id] = Time.get_ticks_msec() + cd_ms

## Dispara animação conforme skill (slash/backslash/thrust).
func play_skill_anim(skill_id: String) -> void:
	var anim_name := EquipmentVisual.get_anim_for_skill(skill_id)
	_animator.play_anim(anim_name)

## Compat.
func play_slash_anim() -> void:
	_animator.play_slash()

func play_hurt_anim() -> void:
	_animator.play_hurt()

## Converte a posição do mouse para coordenadas de mundo (plano Y = 0).
func _get_aim_world_position() -> Vector2:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector2(position.x, position.z)
	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var ray_dir  := camera.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) < 0.001:
		return Vector2(position.x, position.z)
	var t := -from.y / ray_dir.y
	var world := from + ray_dir * t
	return Vector2(world.x, world.z)

# ─── Interpolação remota ─────────────────────────────────────────────────────

func _interpolate_remote(delta: float) -> void:
	var prev_pos := position
	position = position.lerp(_target_position, LERP_SPEED * delta)
	velocity = (position - prev_pos) / delta if delta > 0.0 else Vector3.ZERO

## Chamado por AlvidaHold quando chega snapshot de estado deste jogador.
func apply_server_state(state: Dictionary) -> void:
	if is_local:
		if state.get("hp", -1) >= 0:
			update_hp(state["hp"], state["max_hp"] if state.get("max_hp", -1) >= 0 else max_hp)
		return
	_target_position = Vector3(
		float(state.get("x", position.x)),
		0.0,
		float(state.get("z", position.z))
	)
	if state.get("hp", -1) >= 0:
		update_hp(state["hp"], state["max_hp"] if state.get("max_hp", -1) >= 0 else max_hp)

# ─── Combate ─────────────────────────────────────────────────────────────────

## Chamado por AlvidaHold ao receber OpCombatEvent cujo target_id é este jogador.
func receive_combat_event(data: Dictionary) -> void:
	var new_hp:  int = data.get("target_hp", hp)
	var damage:  int = data.get("damage", 0)
	update_hp(new_hp, max_hp)
	if damage > 0:
		# Hit = flash só; hurt (knockdown LPC) só na morte.
		_flash_red()

## Chamado quando este jogador é o atacante (remoto ou local via evento).
func play_attack_from_event(data: Dictionary) -> void:
	var from_x := float(data.get("from_x", position.x))
	var from_y := float(data.get("from_y", position.z))
	var to_x := float(data.get("to_x", from_x))
	var to_y := float(data.get("to_y", from_y))
	_animator.face_toward(to_x - from_x, to_y - from_y)
	var anim_name := str(data.get("anim", ""))
	if anim_name == "":
		anim_name = EquipmentVisual.get_anim_for_skill(str(data.get("skill_id", "")))
	_animator.play_anim(anim_name)

## Chamado por AlvidaHold ao receber OpPlayerDeath cujo player_id é este jogador.
func receive_death() -> void:
	_animator.play_hurt()
	var wait := _animator.busy_remaining()
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	update_hp(max_hp, max_hp)
	position         = _spawn_position
	_target_position = _spawn_position
	velocity         = Vector3.ZERO

## Flash vermelho nas camadas LPC por 0.2 s como feedback de dano.
func _flash_red() -> void:
	var layers: Array[Sprite3D] = [
		weapon_behind_sprite, body_sprite, head_sprite, eyes_sprite,
		hair_sprite, outfit_sprite, weapon_sprite
	]
	var originals: Array[Color] = []
	for layer in layers:
		if is_instance_valid(layer):
			originals.append(layer.modulate)
			layer.modulate = Color(1.0, 0.2, 0.2, 1.0)
		else:
			originals.append(Color.WHITE)
	await get_tree().create_timer(0.2).timeout
	for i in layers.size():
		if is_instance_valid(layers[i]):
			layers[i].modulate = originals[i]
	if not _last_appearance.is_empty():
		_composer.apply_tints(
			str(_last_appearance.get("body_tint", "")),
			str(_last_appearance.get("hair_tint", ""))
		)

# ─── Loot, XP e equip ────────────────────────────────────────────────────────

func receive_loot(data: Dictionary) -> void:
	var item_id: String = str(data.get("item_id", ""))
	if item_id == "":
		return
	if item_id not in inventory:
		inventory.append(item_id)
	if is_instance_valid(hud):
		hud.show_loot_notification(item_id)
		hud.refresh_inventory(inventory, equipped_weapon)

func receive_xp_event(data: Dictionary) -> void:
	xp             = int(data.get("total_xp", xp))
	level          = int(data.get("level", level))
	pending_points = int(data.get("pending_points", pending_points))
	stats_str      = int(data.get("strength", stats_str))
	stats_agi      = int(data.get("agility", stats_agi))
	stats_int      = int(data.get("intelligence", stats_int))

	var new_hp     := int(data.get("hp", -1))
	var new_max_hp := int(data.get("max_hp", -1))
	if new_max_hp > 0:
		max_hp = new_max_hp
	if new_hp >= 0:
		hp = new_hp
	_update_hp_label()

	if is_instance_valid(hud):
		hud.update_xp(xp, int(data.get("xp_to_next", level * 100)))
		hud.update_level(level)
		hud.update_stats(stats_str, stats_agi, stats_int, pending_points)
		if new_hp >= 0 or new_max_hp > 0:
			hud.update_hp(hp, max_hp)

func receive_level_up(data: Dictionary) -> void:
	level          = int(data.get("new_level", level))
	pending_points = int(data.get("pending_points", pending_points))
	if is_instance_valid(body_sprite):
		var orig_color := body_sprite.modulate
		body_sprite.modulate = Color(1.0, 0.85, 0.0, 1.0)
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(body_sprite):
			body_sprite.modulate = orig_color
	if is_instance_valid(hud):
		hud.show_level_up()
		hud.update_stats(stats_str, stats_agi, stats_int, pending_points)

func equip_item(item_id: String) -> void:
	equipped_weapon = item_id
	apply_equipped_weapon(item_id)
	NetworkManager.send_equip_intent(item_id)
	if is_instance_valid(hud):
		hud.refresh_inventory(inventory, equipped_weapon)

# ─── Aparência LPC ───────────────────────────────────────────────────────────

func apply_appearance(data: Dictionary) -> void:
	_last_appearance = data.duplicate(true)
	var body_id := str(data.get("body", data.get("Body", "")))
	var hair_id := str(data.get("hair", data.get("Hair", "")))
	var outfit_id := str(data.get("outfit", data.get("Outfit", "")))
	var weapon_layer := str(data.get("weapon_layer", data.get("WeaponLayer", "")))
	_composer.apply_appearance({
		"body":         body_id,
		"hair":         hair_id,
		"outfit":       outfit_id,
		"weapon_layer": weapon_layer,
		"body_tint":    data.get("body_tint", data.get("BodyTint", "")),
		"hair_tint":    data.get("hair_tint", data.get("HairTint", "")),
	})
	_animator.snapshot_walk_textures()
	var head_id := LPCComposer.head_id_for_body(body_id)
	_animator.load_anim_textures({
		"body": body_id,
		"head": head_id,
		"eyes": "eyes_default",
		"hair": hair_id,
		"outfit": outfit_id,
		"weapon": weapon_layer,
		"weapon_behind": weapon_layer,
	})

## Troca visual da arma + dual skills + snapshot walk.
func apply_equipped_weapon(weapon_id: String, skill_primary: String = "", skill_secondary: String = "") -> void:
	var layer_id := EquipmentVisual.resolve_weapon_layer(weapon_id)
	equipped_weapon = weapon_id
	if not _last_appearance.is_empty():
		_last_appearance["weapon_layer"] = layer_id
	EquipmentVisual.update_weapon_layer(_composer, layer_id)
	var has_weapon := layer_id != "" and layer_id != "none" and layer_id != "weapon_none"
	_composer.set_weapon_visible(has_weapon)
	_animator.snapshot_walk_textures()

	var body_id := str(_last_appearance.get("body", _last_appearance.get("Body", "")))
	var hair_id := str(_last_appearance.get("hair", _last_appearance.get("Hair", "")))
	var outfit_id := str(_last_appearance.get("outfit", _last_appearance.get("Outfit", "")))
	var head_id := LPCComposer.head_id_for_body(body_id)
	_animator.load_anim_textures({
		"body": body_id,
		"head": head_id,
		"eyes": "eyes_default",
		"hair": hair_id,
		"outfit": outfit_id,
		"weapon": layer_id,
		"weapon_behind": layer_id,
	})

	if skill_primary != "" or skill_secondary != "":
		var defaults: Array = EquipmentVisual.get_skill_slots(weapon_id)
		skill_slots = [
			skill_primary if skill_primary != "" else str(defaults[0]),
			skill_secondary if skill_secondary != "" else str(defaults[1]),
		]
	else:
		skill_slots = EquipmentVisual.get_skill_slots(weapon_id)

	if is_instance_valid(hud):
		hud.update_skills(str(skill_slots[0]), str(skill_slots[1]))

# ─── HP ─────────────────────────────────────────────────────────────────────

func update_hp(new_hp: int, new_max_hp: int) -> void:
	hp     = new_hp
	max_hp = new_max_hp
	_update_hp_label()
	if is_instance_valid(hud) and is_local:
		hud.update_hp(hp, max_hp)

func _update_hp_label() -> void:
	if is_instance_valid(hp_label):
		hp_label.text = "%d/%d" % [hp, max_hp]
		var ratio := float(hp) / float(max_hp) if max_hp > 0 else 0.0
		hp_label.modulate = Color(1.0 - ratio, ratio, 0.0)
