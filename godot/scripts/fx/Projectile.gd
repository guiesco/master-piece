extends Node3D
class_name Projectile
## Projectile — Efeito visual de projétil ou slash.
##
## Uso:
##   var p = PROJECTILE_SCENE.instantiate()
##   add_child(p)
##   p.launch(from_pos, aim_world_vec2, speed)   # ranged (speed > 0)
##   p.launch(from_pos, aim_world_vec2, 0.0)     # melee flash estático

@onready var sprite: Sprite3D = $Sprite

const LIFETIME_RANGED := 0.55
const LIFETIME_MELEE  := 0.22

const TEX_ARROW := preload("res://assets/fx/arrow.png")
const TEX_MELEE_PATH := "res://assets/fx/projectile.png"
const MELEE_MODULATE := Color(1.0, 0.85, 0.2, 1.0)

# LPC arrow shoot sheet: 832×256 → 13×4 cells @ 64×64 (see task-2 sync notes).
const ARROW_CELL := 64
const ARROW_MID_COL := 6
const ARROW_MID_ROW := 1

var _tex_melee: Texture2D

func _melee_texture() -> Texture2D:
	if _tex_melee == null and ResourceLoader.exists(TEX_MELEE_PATH):
		_tex_melee = load(TEX_MELEE_PATH) as Texture2D
	return _tex_melee

var _velocity: Vector3 = Vector3.ZERO
var _age:      float   = 0.0
var _lifetime: float   = LIFETIME_MELEE

func launch(from: Vector3, aim: Vector2, speed: float = 0.0) -> void:
	global_position = from + Vector3(0, 0.5, 0)
	if speed > 0.001:
		var to  := Vector3(aim.x, from.y, aim.y)
		var dir := (to - global_position)
		if dir.length_squared() > 0.001:
			dir = dir.normalized()
		else:
			dir = Vector3(0, 0, -1)
		_velocity = dir * speed
		_lifetime = LIFETIME_RANGED
		if is_instance_valid(sprite):
			sprite.texture = TEX_ARROW
			sprite.modulate = Color.WHITE
			sprite.region_enabled = true
			sprite.region_rect = Rect2(
				ARROW_MID_COL * ARROW_CELL,
				ARROW_MID_ROW * ARROW_CELL,
				ARROW_CELL,
				ARROW_CELL
			)
			var flat := Vector3(_velocity.x, 0.0, _velocity.z)
			if flat.length_squared() > 0.001:
				sprite.rotation.y = atan2(-flat.z, flat.x)
				sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	else:
		# Melee: coloca o flash a 0.8 u na direção do alvo
		var to   := Vector3(aim.x, global_position.y, aim.y)
		var dir  := (to - global_position)
		if dir.length_squared() > 0.001:
			dir = dir.normalized()
		else:
			dir = Vector3(0, 0, -1)
		global_position = global_position + dir * 0.8
		_velocity = Vector3.ZERO
		_lifetime = LIFETIME_MELEE
		if is_instance_valid(sprite):
			var melee_tex := _melee_texture()
			if melee_tex:
				sprite.texture = melee_tex
			sprite.region_enabled = false
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.modulate = MELEE_MODULATE

func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return
	if _velocity.length_squared() > 0.001:
		position += _velocity * delta
	# Fade out gradual
	var alpha := 1.0 - (_age / _lifetime)
	if is_instance_valid(sprite):
		sprite.modulate.a = alpha
