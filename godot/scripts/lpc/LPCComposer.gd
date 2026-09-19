## GDScript: LPCComposer.gd
## Composição visual LPC em camadas.
## Ordem visual: weapon_behind → body → head → eyes → outfit → hair → weapon (FG)
## No Universal LPC o corpo NÃO inclui a cabeça — head/eyes são obrigatórios.

class_name LPCComposer
extends RefCounted

const FRAME_DOWN := Rect2(0, 128, 64, 64)

var body_sprite:          Sprite3D
var head_sprite:          Sprite3D
var eyes_sprite:          Sprite3D
var hair_sprite:          Sprite3D
var outfit_sprite:        Sprite3D
var weapon_sprite:        Sprite3D
var weapon_behind_sprite: Sprite3D

## Configura as camadas. head/eyes/weapon_behind podem ser null.
func setup_nodes(
	body_node: Sprite3D,
	hair_node: Sprite3D,
	outfit_node: Sprite3D,
	weapon_node: Sprite3D,
	head_node: Sprite3D = null,
	eyes_node: Sprite3D = null,
	weapon_behind_node: Sprite3D = null
) -> void:
	body_sprite = body_node
	hair_sprite = hair_node
	outfit_sprite = outfit_node
	weapon_sprite = weapon_node
	head_sprite = head_node
	eyes_sprite = eyes_node
	weapon_behind_sprite = weapon_behind_node

## Deriva head_male / head_female a partir do id do corpo.
static func head_id_for_body(body_id: String) -> String:
	if body_id.contains("female"):
		return "head_female"
	return "head_male"

func apply_appearance(data: Dictionary) -> void:
	var body_id: String = str(data.get("body", ""))
	var hair_id: String = str(data.get("hair", ""))
	var outfit_id: String = str(data.get("outfit", ""))
	var weapon_id: String = str(data.get("weapon_layer", ""))
	var head_id: String = str(data.get("head", ""))
	var eyes_id: String = str(data.get("eyes", "eyes_default"))
	var body_tint: String = str(data.get("body_tint", ""))
	var hair_tint: String = str(data.get("hair_tint", ""))

	if head_id == "" and body_id != "":
		head_id = head_id_for_body(body_id)
	if eyes_id == "":
		eyes_id = "eyes_default"

	_apply_layer(body_sprite, "body", body_id)
	_apply_layer(head_sprite, "head", head_id)
	_apply_layer(eyes_sprite, "eyes", eyes_id)
	_apply_layer(outfit_sprite, "outfit", outfit_id)
	_apply_layer(hair_sprite, "hair", hair_id)
	_apply_weapon_layers(weapon_id)

	apply_tints(body_tint, hair_tint)

func set_weapon_visible(p_visible: bool) -> void:
	if weapon_sprite:
		weapon_sprite.visible = p_visible
	if weapon_behind_sprite:
		weapon_behind_sprite.visible = p_visible

func get_layer_texture_path(layer: String, id: String) -> String:
	return "res://assets/lpc/%s/%s.png" % [layer, id]

## Aplica FG + BG da arma. Aceita:
##   - {id}_fg + {id}_bg
##   - {id} (FG) + {id}_bg (BG)
##   - só {id} (FG; BG fica vazio)
func _apply_weapon_layers(weapon_id: String) -> void:
	if weapon_id == "" or weapon_id == "none" or weapon_id == "weapon_none":
		_clear_sprite(weapon_sprite)
		_clear_sprite(weapon_behind_sprite)
		if weapon_sprite:
			weapon_sprite.visible = false
		if weapon_behind_sprite:
			weapon_behind_sprite.visible = false
		return

	var fg_id := weapon_id
	var bg_id := weapon_id + "_bg"
	if ResourceLoader.exists(get_layer_texture_path("weapon", weapon_id + "_fg")):
		fg_id = weapon_id + "_fg"
	if ResourceLoader.exists(get_layer_texture_path("weapon", weapon_id + "_bg")):
		bg_id = weapon_id + "_bg"
	elif not ResourceLoader.exists(get_layer_texture_path("weapon", bg_id)):
		bg_id = ""

	_apply_layer(weapon_sprite, "weapon", fg_id)
	if weapon_sprite:
		weapon_sprite.visible = true

	if bg_id != "":
		_apply_layer(weapon_behind_sprite, "weapon", bg_id)
		if weapon_behind_sprite:
			weapon_behind_sprite.visible = true
	else:
		_clear_sprite(weapon_behind_sprite)
		if weapon_behind_sprite:
			weapon_behind_sprite.visible = false

func _clear_sprite(sprite: Sprite3D) -> void:
	if sprite == null:
		return
	sprite.texture = null

func _apply_layer(sprite: Sprite3D, layer: String, id: String) -> void:
	if sprite == null:
		return

	if id == "" or id == "none" or id == "hair_bald" or id == "weapon_none":
		sprite.texture = null
		if layer == "hair" or layer == "weapon":
			sprite.visible = false
		return

	if layer == "hair" or layer == "head" or layer == "eyes" or layer == "weapon":
		sprite.visible = true

	var path: String = get_layer_texture_path(layer, id)
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
		sprite.modulate = Color.WHITE
		sprite.region_enabled = true
		sprite.region_rect = FRAME_DOWN
	else:
		sprite.texture = null
		sprite.modulate = _placeholder_color(layer, id)

func apply_tints(body_tint: String, hair_tint: String) -> void:
	if body_tint != "":
		var skin := Color(body_tint)
		if body_sprite:
			body_sprite.modulate = skin
		if head_sprite:
			head_sprite.modulate = skin
	# Olhos mantêm cor do sheet (não recebe tint de pele).
	if hair_sprite and hair_tint != "":
		hair_sprite.modulate = Color(hair_tint)

func _placeholder_color(layer: String, id: String) -> Color:
	match layer:
		"body", "head":
			if id.contains("light"):
				return Color(0.96, 0.80, 0.65)
			elif id.contains("dark"):
				return Color(0.55, 0.38, 0.28)
			elif id.contains("medium"):
				return Color(0.83, 0.57, 0.42)
			else:
				return Color(0.80, 0.60, 0.50)
		"eyes":
			return Color(0.2, 0.35, 0.55)
		"hair":
			if id.contains("blonde"):
				return Color(0.96, 0.82, 0.25)
			elif id.contains("brown"):
				return Color(0.43, 0.29, 0.17)
			elif id.contains("red"):
				return Color(0.75, 0.22, 0.17)
			elif id.contains("bald"):
				return Color(0.0, 0.0, 0.0, 0.0)
			else:
				return Color(0.50, 0.35, 0.20)
		"outfit":
			if id.contains("pirate"):
				return Color(0.10, 0.10, 0.15)
			elif id.contains("sailor"):
				return Color(0.85, 0.85, 0.90)
			elif id.contains("guard"):
				return Color(0.45, 0.35, 0.25)
			else:
				return Color(0.50, 0.50, 0.50)
		"weapon":
			return Color(0.70, 0.70, 0.70)
		_:
			return Color(0.80, 0.80, 0.80)
