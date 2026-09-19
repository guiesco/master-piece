extends Node3D
## Enemy — visual client-side; estado vem do servidor.
## Usa as mesmas camadas LPC do player + LPCAnimator (walk/idle/ataque/hurt).

var enemy_id:  String = ""
var archetype: String = ""

const LERP_SPEED := 8.0

@onready var weapon_behind_sprite: Sprite3D = $WeaponBehindSprite
@onready var body_sprite:   Sprite3D = $BodySprite
@onready var head_sprite:   Sprite3D = $HeadSprite
@onready var eyes_sprite:   Sprite3D = $EyesSprite
@onready var hair_sprite:   Sprite3D = $HairSprite
@onready var outfit_sprite: Sprite3D = $OutfitSprite
@onready var weapon_sprite: Sprite3D = $WeaponSprite
@onready var hp_label: Label3D  = $HPLabel
@onready var sprite: Sprite3D = $BodySprite

var _composer: LPCComposer = LPCComposer.new()
var _animator: LPCAnimator = LPCAnimator.new()
var _last_appearance: Dictionary = {}
var _target_position: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _current_hp: int = 60
var _max_hp:     int = 60
var _is_dead:    bool = false

func _ready() -> void:
	_target_position = position
	_setup_visuals()
	_update_hp_label()

func _setup_visuals() -> void:
	_composer.setup_nodes(
		body_sprite, hair_sprite, outfit_sprite, weapon_sprite,
		head_sprite, eyes_sprite, weapon_behind_sprite
	)
	_animator.setup_layers([
		body_sprite, head_sprite, eyes_sprite, hair_sprite,
		outfit_sprite, weapon_sprite, weapon_behind_sprite
	])

func _process(delta: float) -> void:
	if _is_dead:
		return
	var prev := position
	position = position.lerp(_target_position, LERP_SPEED * delta)
	_velocity = (position - prev) / delta if delta > 0.0 else Vector3.ZERO
	_animator.update(delta, _velocity)

func setup(
	p_enemy_id:   String,
	p_archetype:  String,
	p_appearance: Dictionary,
	p_x:          float,
	p_y:          float,
	p_hp:         int
) -> void:
	enemy_id  = p_enemy_id
	archetype = p_archetype
	_current_hp = p_hp
	_max_hp     = p_hp
	_is_dead    = false
	_velocity   = Vector3.ZERO

	var world_pos := Vector3(p_x, 0.0, p_y)
	position         = world_pos
	_target_position = world_pos

	if body_sprite == null:
		weapon_behind_sprite = $WeaponBehindSprite
		body_sprite = $BodySprite
		head_sprite = $HeadSprite
		eyes_sprite = $EyesSprite
		hair_sprite = $HairSprite
		outfit_sprite = $OutfitSprite
		weapon_sprite = $WeaponSprite
		_setup_visuals()

	apply_appearance(p_appearance)
	_update_hp_label()

func apply_server_state(state: Dictionary) -> void:
	_target_position = Vector3(
		float(state.get("x", position.x)),
		0.0,
		float(state.get("y", position.z))
	)
	update_hp(state.get("hp", _current_hp), state.get("max_hp", _max_hp))

func receive_combat_event(data: Dictionary) -> void:
	var new_hp: int = data.get("target_hp", _current_hp)
	var damage: int = data.get("damage", 0)
	update_hp(new_hp, _max_hp)
	if damage > 0:
		# Hit = flash só; hurt (knockdown LPC) só em play_death().
		play_hit_flash()

## Ataque do inimigo (chamado quando ele é o attacker_id no OpCombatEvent).
func play_attack_anim(anim_hint: String = "", face_dx: float = 0.0, face_dz: float = 0.0) -> void:
	if _is_dead:
		return
	if abs(face_dx) > 0.001 or abs(face_dz) > 0.001:
		_animator.face_toward(face_dx, face_dz)
	var anim_name := anim_hint
	if anim_name == "":
		if _is_ranged_archetype():
			anim_name = "shoot"
		else:
			anim_name = "slash"
	_animator.play_anim(anim_name)

func _is_ranged_archetype() -> bool:
	return archetype.contains("ranged") or archetype.contains("archer") \
		or archetype.contains("gunner") or archetype.contains("shoot")

func play_hit_flash() -> void:
	if _is_dead:
		return
	var layers: Array[Sprite3D] = [
		weapon_behind_sprite, body_sprite, head_sprite, eyes_sprite,
		hair_sprite, outfit_sprite, weapon_sprite
	]
	var originals: Array[Color] = []
	for layer in layers:
		if is_instance_valid(layer):
			originals.append(layer.modulate)
			layer.modulate = Color(1.0, 0.15, 0.15, 1.0)
		else:
			originals.append(Color.WHITE)
	await get_tree().create_timer(0.15).timeout
	for i in layers.size():
		if is_instance_valid(layers[i]) and not _is_dead:
			layers[i].modulate = originals[i]
	if not _last_appearance.is_empty():
		_composer.apply_tints(
			str(_last_appearance.get("body_tint", "")),
			str(_last_appearance.get("hair_tint", ""))
		)

func apply_appearance(data: Dictionary) -> void:
	_last_appearance = data.duplicate(true)
	var body_id := str(data.get("body", data.get("Body", "")))
	var hair_id := str(data.get("hair", data.get("Hair", "")))
	var outfit_id := str(data.get("outfit", data.get("Outfit", "")))
	var weapon_layer := str(data.get("weapon_layer", data.get("WeaponLayer", "")))
	_composer.apply_appearance({
		"body": body_id,
		"hair": hair_id,
		"outfit": outfit_id,
		"weapon_layer": weapon_layer,
		"body_tint": data.get("body_tint", data.get("BodyTint", "")),
		"hair_tint": data.get("hair_tint", data.get("HairTint", "")),
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

func play_death() -> void:
	_is_dead = true
	_animator.play_hurt()
	var layers: Array[Sprite3D] = [
		weapon_behind_sprite, body_sprite, head_sprite, eyes_sprite,
		hair_sprite, outfit_sprite, weapon_sprite
	]
	var tween := create_tween()
	for layer in layers:
		if is_instance_valid(layer):
			tween.parallel().tween_property(layer, "modulate:a", 0.0, 0.7)

func update_hp(hp: int, max_hp: int) -> void:
	_current_hp = hp
	_max_hp     = max_hp
	_update_hp_label()

func _update_hp_label() -> void:
	if is_instance_valid(hp_label):
		hp_label.text = "%d/%d" % [_current_hp, _max_hp]
		var ratio := float(_current_hp) / float(_max_hp) if _max_hp > 0 else 0.0
		hp_label.modulate = Color(1.0 - ratio, ratio, 0.0)
