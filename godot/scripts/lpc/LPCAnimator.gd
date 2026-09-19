class_name LPCAnimator
extends RefCounted
## LPCAnimator — Animação baseada no formato LPC (Universal LPC Spritesheet).
##
## Camadas (índices): body, head, eyes, hair, outfit, weapon(FG), weapon_behind(BG)
##
## Anims: idle | walk | slash | backslash | hurt | thrust | shoot
## Walk: 4 rows × N frames (default 64×64, 8 frames)
## Attack sheets podem ser 64×64 ou 128×128 — detectados via metadados da textura.
##
## Uso:
##   anim.setup_layers([...])
##   anim.snapshot_walk_textures()
##   anim.load_anim_textures(appearance_ids)
##   anim.update(delta, velocity)
##   anim.play_slash() / play_backslash() / play_hurt() / play_thrust() / play_shoot()

# ─── Constantes ─────────────────────────────────────────────────────────────

const FRAME_W := 64
const FRAME_H := 64
const WALK_FRAMES  := 8
const SLASH_FRAMES := 6
const BACKSLASH_FRAMES := 13
const HURT_FRAMES  := 6
const THRUST_FRAMES := 8
const SHOOT_FRAMES := 13
const FRAME_RATE   := 8.0

const DIR_ROW := {
	"up": 0,
	"left": 1,
	"down": 2,
	"right": 3,
}

const IDX_BODY          := 0
const IDX_HEAD          := 1
const IDX_EYES          := 2
const IDX_HAIR          := 3
const IDX_OUTFIT        := 4
const IDX_WEAPON        := 5
const IDX_WEAPON_BEHIND := 6

const LAYER_FOLDERS := ["body", "head", "eyes", "hair", "outfit", "weapon", "weapon"]

# ─── Estado ─────────────────────────────────────────────────────────────────

var _sprites: Array = []
var _walk_tex: Array = []

## Texturas por anim: { "slash": Array, "backslash": Array, ... }
var _anim_tex: Dictionary = {}

## Metadados por anim: { "slash": {frame_w, frame_h, frames, rows}, ... }
var _anim_meta: Dictionary = {}

var dir: String = "down"
## idle | walk | slash | backslash | hurt | thrust | shoot
var state: String = "idle"

var _anim_time: float = 0.0
var _action_time: float = 0.0
var _busy: bool = false
var _busy_duration: float = 0.0

# ─── Setup ──────────────────────────────────────────────────────────────────

## Configura sprites: [body, head, eyes, hair, outfit, weapon, weapon_behind?]
func setup_layers(p_sprites: Array) -> void:
	_sprites = p_sprites.duplicate()
	_walk_tex.resize(_sprites.size())
	_walk_tex.fill(null)
	for anim_name in ["slash", "backslash", "hurt", "thrust", "shoot"]:
		var arr: Array = []
		arr.resize(_sprites.size())
		arr.fill(null)
		_anim_tex[anim_name] = arr
		_anim_meta[anim_name] = _default_meta(anim_name)

## Lê texturas de walk dos Sprite3D atuais (após LPCComposer.apply_appearance).
func snapshot_walk_textures() -> void:
	if _walk_tex.size() != _sprites.size():
		_walk_tex.resize(_sprites.size())
	for i in _sprites.size():
		var sp = _sprites[i]
		if sp != null and is_instance_valid(sp as Sprite3D):
			_walk_tex[i] = (sp as Sprite3D).texture
		else:
			_walk_tex[i] = null
	_anim_meta["walk"] = _meta_from_texture(_first_non_null(_walk_tex), WALK_FRAMES, 4)

## Compat: carrega só slash de body/head (preferir load_anim_textures).
func load_slash_textures(body_id: String, head_id: String) -> void:
	load_anim_textures({
		"body": body_id,
		"head": head_id,
		"eyes": "",
		"hair": "",
		"outfit": "",
		"weapon": "",
		"weapon_behind": "",
	})

## Carrega sheets de animação para todas as camadas.
## appearance_ids: { body, head, eyes, hair, outfit, weapon, weapon_behind }
## Convenção de arquivo: `{base}_{anim}.png` com fallbacks ResourceLoader.exists.
func load_anim_textures(appearance_ids: Dictionary) -> void:
	var layer_ids: Array = [
		str(appearance_ids.get("body", "")),
		str(appearance_ids.get("head", "")),
		str(appearance_ids.get("eyes", "")),
		str(appearance_ids.get("hair", "")),
		str(appearance_ids.get("outfit", "")),
		str(appearance_ids.get("weapon", "")),
		str(appearance_ids.get("weapon_behind", appearance_ids.get("weapon", ""))),
	]

	for anim_name in ["slash", "backslash", "hurt", "thrust", "shoot"]:
		var arr: Array = _anim_tex[anim_name]
		arr.fill(null)
		for i in mini(layer_ids.size(), _sprites.size()):
			var folder: String = LAYER_FOLDERS[i] if i < LAYER_FOLDERS.size() else "body"
			var base_id: String = str(layer_ids[i])
			if base_id == "" or base_id == "none" or base_id == "weapon_none" or base_id == "hair_bald":
				continue
			arr[i] = _load_layer_anim_tex(folder, base_id, anim_name, i)
		_anim_tex[anim_name] = arr
		# Sem fallback backslash→slash: poses/frame counts diferem (13 vs 6).
		# Layers sem sheet usam walk em _apply_action_frame.
		_anim_meta[anim_name] = _meta_from_texture(
			_first_non_null(arr),
			_default_frame_count(anim_name),
			1 if anim_name == "hurt" else 4
		)

func _load_layer_anim_tex(folder: String, base_id: String, anim_name: String, layer_idx: int) -> Texture2D:
	var candidates: Array[String] = []
	# Arma FG/BG: tenta suffixes _fg/_bg + anim
	if layer_idx == IDX_WEAPON:
		candidates.append("%s_fg_%s" % [base_id.trim_suffix("_fg"), anim_name])
		candidates.append("%s_%s" % [base_id, anim_name])
		if not base_id.ends_with("_fg"):
			candidates.append("%s_fg_%s" % [base_id, anim_name])
	elif layer_idx == IDX_WEAPON_BEHIND:
		var root := base_id.trim_suffix("_bg").trim_suffix("_fg")
		candidates.append("%s_bg_%s" % [root, anim_name])
		candidates.append("%s_%s" % [base_id, anim_name])
		candidates.append("%s_bg_%s" % [base_id, anim_name])
	else:
		# body_male_light → body_male_slash (strip skin suffix for body)
		candidates.append("%s_%s" % [base_id, anim_name])
		if folder == "body":
			if base_id.contains("female"):
				candidates.append("body_female_%s" % anim_name)
			else:
				candidates.append("body_male_%s" % anim_name)
		elif folder == "head":
			if base_id.contains("female"):
				candidates.append("head_female_%s" % anim_name)
			else:
				candidates.append("head_male_%s" % anim_name)

	for cand in candidates:
		var path := "res://assets/lpc/%s/%s.png" % [folder, cand]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null

# ─── Controle ───────────────────────────────────────────────────────────────

func is_busy() -> bool:
	return _busy

func busy_remaining() -> float:
	if not _busy:
		return 0.0
	return maxf(0.0, _busy_duration - _action_time)

func play_slash() -> void:
	_start_action("slash")

func play_backslash() -> void:
	_start_action("backslash")

func play_hurt() -> void:
	_start_action("hurt")

func play_thrust() -> void:
	_start_action("thrust")

func play_shoot() -> void:
	_start_action("shoot")

## Atualiza facing LPC a partir de um vetor no plano XZ (mundo).
func face_toward(dx: float, dz: float) -> void:
	if abs(dx) < 0.001 and abs(dz) < 0.001:
		return
	if abs(dx) >= abs(dz):
		dir = "right" if dx > 0.0 else "left"
	else:
		dir = "down" if dz > 0.0 else "up"

## Dispara animação a partir do nome da skill/anim do servidor.
func play_anim(anim_name: String) -> void:
	match anim_name:
		"backslash":
			play_backslash()
		"hurt":
			play_hurt()
		"thrust":
			play_thrust()
		"shoot":
			play_shoot()
		_:
			play_slash()

func _start_action(anim_name: String) -> void:
	_busy = true
	_action_time = 0.0
	state = anim_name
	var meta: Dictionary = _anim_meta.get(anim_name, _default_meta(anim_name))
	var frames: int = int(meta.get("frames", _default_frame_count(anim_name)))
	_busy_duration = float(frames) / FRAME_RATE

func update(delta: float, velocity: Vector3) -> void:
	var h := velocity.x
	var v := velocity.z

	if abs(h) > 0.01 or abs(v) > 0.01:
		if abs(h) >= abs(v):
			dir = "right" if h > 0 else "left"
		else:
			dir = "down" if v > 0 else "up"
		if not _busy:
			state = "walk"
	else:
		if not _busy:
			state = "idle"

	_anim_time += delta

	if _busy:
		_action_time += delta
		if _action_time >= _busy_duration:
			_busy = false
			state = "idle"
			_apply_idle_frame()
		else:
			_apply_action_frame(state)
	elif state == "walk":
		_apply_walk_frame()
	else:
		_apply_idle_frame()

# ─── Frame helpers ──────────────────────────────────────────────────────────

func _apply_walk_frame() -> void:
	var meta: Dictionary = _anim_meta.get("walk", _default_meta("walk"))
	var fw: int = int(meta.get("frame_w", FRAME_W))
	var fh: int = int(meta.get("frame_h", FRAME_H))
	var frames: int = int(meta.get("frames", WALK_FRAMES))
	var row_i: int = int(DIR_ROW.get(dir, 2))
	var frame_i: int = int(_anim_time * FRAME_RATE) % maxi(frames, 1)
	_apply_rect(Rect2(frame_i * fw, row_i * fh, fw, fh), _walk_tex)

func _apply_idle_frame() -> void:
	var meta: Dictionary = _anim_meta.get("walk", _default_meta("walk"))
	var fw: int = int(meta.get("frame_w", FRAME_W))
	var fh: int = int(meta.get("frame_h", FRAME_H))
	var row_i: int = int(DIR_ROW.get(dir, 2))
	_apply_rect(Rect2(0, row_i * fh, fw, fh), _walk_tex)

func _apply_action_frame(anim_name: String) -> void:
	## Meta global só define timing; cada layer usa o tamanho do próprio sheet
	## (body 64, arming slash 128, gnarled thrust 192 podem coexistir).
	var meta: Dictionary = _anim_meta.get(anim_name, _default_meta(anim_name))
	var default_frames: int = int(meta.get("frames", _default_frame_count(anim_name)))
	var default_rows: int = int(meta.get("rows", 1 if anim_name == "hurt" else 4))
	var frame_i_global: int = mini(int(_action_time * FRAME_RATE), maxi(default_frames - 1, 0))
	var primary: Array = _anim_tex.get(anim_name, [])
	var walk_meta: Dictionary = _anim_meta.get("walk", _default_meta("walk"))

	for i in _sprites.size():
		var sp = _sprites[i]
		if sp == null or not is_instance_valid(sp as Sprite3D):
			continue
		var spr := sp as Sprite3D
		var tex = primary[i] if i < primary.size() else null
		var used_fallback := false
		if tex == null and i < _walk_tex.size():
			tex = _walk_tex[i]
			used_fallback = tex != null
		if tex != null:
			spr.texture = tex

		var local_meta: Dictionary = meta
		if tex != null:
			if used_fallback:
				local_meta = walk_meta
			else:
				local_meta = _meta_from_texture(tex, default_frames, default_rows)

		var fw: int = int(local_meta.get("frame_w", FRAME_W))
		var fh: int = int(local_meta.get("frame_h", FRAME_H))
		var frames: int = int(local_meta.get("frames", default_frames))
		var rows: int = int(local_meta.get("rows", default_rows))
		var frame_i: int = mini(frame_i_global, maxi(frames - 1, 0))
		var row_i: int = 0
		if rows > 1:
			row_i = int(DIR_ROW.get(dir, 2))
		spr.region_enabled = true
		spr.region_rect = Rect2(frame_i * fw, row_i * fh, fw, fh)

func _apply_rect(rect: Rect2, textures: Array) -> void:
	for i in _sprites.size():
		var sp = _sprites[i]
		if sp == null or not is_instance_valid(sp as Sprite3D):
			continue
		var spr := sp as Sprite3D
		var tex = textures[i] if i < textures.size() else null
		if tex != null:
			spr.texture = tex
			# FG/BG da arma: mantém visível no idle/walk após equip (snapshot).
			if i == IDX_WEAPON or i == IDX_WEAPON_BEHIND:
				spr.visible = true
		spr.region_enabled = true
		spr.region_rect = rect

# ─── Meta helpers ───────────────────────────────────────────────────────────

func _default_frame_count(anim_name: String) -> int:
	match anim_name:
		"walk":
			return WALK_FRAMES
		"thrust":
			return THRUST_FRAMES
		"hurt":
			return HURT_FRAMES
		"backslash":
			return BACKSLASH_FRAMES
		"shoot":
			return SHOOT_FRAMES
		_:
			return SLASH_FRAMES

func _default_meta(anim_name: String) -> Dictionary:
	return {
		"frame_w": FRAME_W,
		"frame_h": FRAME_H,
		"frames": _default_frame_count(anim_name),
		"rows": 1 if anim_name == "hurt" else 4,
	}

func _meta_from_texture(tex: Texture2D, default_frames: int, default_rows: int) -> Dictionary:
	if tex == null:
		return {
			"frame_w": FRAME_W,
			"frame_h": FRAME_H,
			"frames": default_frames,
			"rows": default_rows,
		}
	var tw: int = tex.get_width()
	var th: int = tex.get_height()
	var rows: int = default_rows
	var frame_h: int = FRAME_H
	var frame_w: int = FRAME_W

	if rows > 1 and th > 0:
		# LPC: frames quadrados; row height mede 64 / 128 / 192 (não forçar 128).
		var candidate_h := int(th / rows)
		if candidate_h > 0:
			frame_h = candidate_h
			frame_w = candidate_h
			rows = maxi(1, int(th / frame_h))
	elif th > 0:
		# hurt (1 row): frames quadrados pela altura da faixa.
		frame_h = th
		frame_w = th
		if frame_w <= 0:
			frame_w = FRAME_W
			frame_h = FRAME_H if th >= FRAME_H else th

	var frames: int = default_frames
	if frame_w > 0:
		frames = maxi(1, int(tw / frame_w))
	return {
		"frame_w": frame_w,
		"frame_h": frame_h,
		"frames": frames,
		"rows": rows,
	}

func _first_non_null(arr: Array) -> Texture2D:
	for t in arr:
		if t != null:
			return t as Texture2D
	return null
