extends Control
## CharacterCreator — criação de personagem: nome, corpo / cabelo / roupa / cores.
## Ao confirmar, chama rpc_create_character no slot definido por NetworkManager.target_slot
## e rpc_select_character para ativar o perfil, depois vai para AlvidaHold.

const SCENE_ALVIDA_HOLD  := "res://scenes/world/AlvidaHold.tscn"
const SCENE_CHAR_SELECT  := "res://scenes/ui/CharacterSelect.tscn"

## Pares { label, catalog_id }. Índices alinhados aos OptionButtons.
const BODY_OPTIONS: Array[Dictionary] = [
	{"label": "Homem — pele clara", "id": "body_male_light", "tint": "#F5CBA7"},
	{"label": "Homem — pele média", "id": "body_male_medium", "tint": "#C68642"},
	{"label": "Homem — pele escura", "id": "body_male_dark", "tint": "#8B6048"},
	{"label": "Mulher — pele clara", "id": "body_female_light", "tint": "#F5CBA7"},
	{"label": "Mulher — pele média", "id": "body_female_medium", "tint": "#C68642"},
]

const HAIR_OPTIONS: Array[Dictionary] = [
	{"label": "Curto", "id": "hair_short_brown", "tint": "#6E4B2A"},
	{"label": "Longo", "id": "hair_long_black", "tint": "#1A1A1A"},
	{"label": "Mohawk", "id": "hair_mohawk_red", "tint": "#B22222"},
	{"label": "Cacheado", "id": "hair_curly_blonde", "tint": "#F4D03F"},
	{"label": "Careca", "id": "hair_bald", "tint": "#00000000"},
]

const OUTFIT_OPTIONS: Array[Dictionary] = [
	{"label": "Casaco pirata", "id": "outfit_pirate_a"},
	{"label": "Tabardo navy", "id": "outfit_pirate_b"},
	{"label": "Couraça de guarda", "id": "outfit_guard_a"},
	{"label": "Trapos", "id": "outfit_rags_a"},
	{"label": "Camisa de marinheiro", "id": "outfit_sailor_a"},
]

@onready var name_input:    LineEdit      = $Panel/Margin/VBox/Content/Controls/NameInput
@onready var body_option:   OptionButton  = $Panel/Margin/VBox/Content/Controls/BodyOption
@onready var hair_option:   OptionButton  = $Panel/Margin/VBox/Content/Controls/HairOption
@onready var outfit_option: OptionButton  = $Panel/Margin/VBox/Content/Controls/OutfitOption
@onready var body_tint_btn: ColorPickerButton = $Panel/Margin/VBox/Content/Controls/BodyTint
@onready var hair_tint_btn: ColorPickerButton = $Panel/Margin/VBox/Content/Controls/HairTint
@onready var start_button:  Button        = $Panel/Margin/VBox/Content/Controls/StartButton
@onready var back_button:   Button        = $Panel/Margin/VBox/Content/Controls/BackButton
@onready var preview_sprite:  Sprite2D   = $Panel/Margin/VBox/Content/PreviewArea/PreviewFrame/PreviewSprite
@onready var preview_head:    Sprite2D   = $Panel/Margin/VBox/Content/PreviewArea/PreviewFrame/PreviewHead
@onready var preview_eyes:    Sprite2D   = $Panel/Margin/VBox/Content/PreviewArea/PreviewFrame/PreviewEyes
@onready var preview_hair:    Sprite2D   = $Panel/Margin/VBox/Content/PreviewArea/PreviewFrame/PreviewHair
@onready var preview_outfit:  Sprite2D   = $Panel/Margin/VBox/Content/PreviewArea/PreviewFrame/PreviewOutfit
@onready var status_label:   Label       = $Panel/Margin/VBox/StatusLabel

const PREVIEW_FRAME := Rect2(0, 128, 64, 64)

func _ready() -> void:
	_populate_options()
	_connect_signals()
	_sync_default_tints()
	_update_preview()
	# Mostra o número do slot atual no título
	var slot_lbl: Label = $Panel/Margin/VBox/Title
	if slot_lbl:
		slot_lbl.text = "— Criar Personagem (Slot %d) —" % (NetworkManager.target_slot + 1)

func _populate_options() -> void:
	body_option.clear()
	for opt in BODY_OPTIONS:
		body_option.add_item(opt["label"])

	hair_option.clear()
	for opt in HAIR_OPTIONS:
		hair_option.add_item(opt["label"])

	outfit_option.clear()
	for opt in OUTFIT_OPTIONS:
		outfit_option.add_item(opt["label"])

func _connect_signals() -> void:
	body_option.item_selected.connect(_on_body_selected)
	hair_option.item_selected.connect(_on_hair_selected)
	outfit_option.item_selected.connect(_on_appearance_changed.unbind(1))
	body_tint_btn.color_changed.connect(_on_color_changed.unbind(1))
	hair_tint_btn.color_changed.connect(_on_color_changed.unbind(1))
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)

func _sync_default_tints() -> void:
	_on_body_selected(body_option.selected)
	_on_hair_selected(hair_option.selected)

func _on_body_selected(index: int) -> void:
	if index >= 0 and index < BODY_OPTIONS.size():
		body_tint_btn.color = Color(str(BODY_OPTIONS[index]["tint"]))
	_update_preview()

func _on_hair_selected(index: int) -> void:
	if index >= 0 and index < HAIR_OPTIONS.size():
		var tint_str := str(HAIR_OPTIONS[index]["tint"])
		if tint_str.length() >= 7:
			hair_tint_btn.color = Color(tint_str)
	_update_preview()

func _on_appearance_changed() -> void:
	_update_preview()

func _on_color_changed() -> void:
	_update_preview()

func _set_preview_layer(sprite: Sprite2D, layer: String, id: String, tint: Color) -> void:
	if not is_instance_valid(sprite):
		return
	if id == "" or id == "hair_bald":
		sprite.texture = null
		sprite.visible = false
		return
	var path := "res://assets/lpc/%s/%s.png" % [layer, id]
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
		sprite.region_enabled = true
		sprite.region_rect = PREVIEW_FRAME
		sprite.visible = true
		sprite.modulate = tint
	else:
		sprite.texture = null
		sprite.visible = false

func _update_preview() -> void:
	var body_id   := str(BODY_OPTIONS[body_option.selected]["id"])
	var hair_id   := str(HAIR_OPTIONS[hair_option.selected]["id"])
	var outfit_id := str(OUTFIT_OPTIONS[outfit_option.selected]["id"])
	var head_id   := LPCComposer.head_id_for_body(body_id)
	_set_preview_layer(preview_sprite, "body",   body_id,   body_tint_btn.color)
	_set_preview_layer(preview_head,   "head",   head_id,   body_tint_btn.color)
	_set_preview_layer(preview_eyes,   "eyes",   "eyes_default", Color.WHITE)
	_set_preview_layer(preview_outfit, "outfit", outfit_id, Color.WHITE)
	_set_preview_layer(preview_hair,   "hair",   hair_id,   hair_tint_btn.color)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(SCENE_CHAR_SELECT)

func _on_start_pressed() -> void:
	var char_name := name_input.text.strip_edges() if is_instance_valid(name_input) else ""
	if char_name == "":
		char_name = "Pirata"
	start_button.disabled = true
	status_label.text = "Criando personagem..."

	var appearance := _build_appearance_dict()
	var slot       := NetworkManager.target_slot

	# Cria personagem no slot
	var profile := await NetworkManager.create_character(slot, char_name, appearance)
	if profile.is_empty():
		# Fallback: tenta salvar aparência legada e ir direto
		push_warning("[CharacterCreator] create_character falhou; tentando save_appearance legado.")
		await NetworkManager.save_profile_appearance(appearance)
		get_tree().change_scene_to_file(SCENE_ALVIDA_HOLD)
		return

	# Seleciona o slot como ativo (obrigatório antes de entrar no mundo).
	var selected := await NetworkManager.select_character(slot)
	if selected.is_empty():
		# select_character falhou — NÃO propagar {"ok":true} como last_profile.
		# Apenas salva a aparência; AlvidaHold usa appearance_data como fallback.
		push_warning("[CharacterCreator] select_character falhou; entrando com aparência salva.")
		NetworkManager.appearance_data = appearance
		# last_profile permanece vazio — AlvidaHold lida com isso em _ready().

	get_tree().change_scene_to_file(SCENE_ALVIDA_HOLD)

func _build_appearance_dict() -> Dictionary:
	var body   := BODY_OPTIONS[body_option.selected]
	var hair   := HAIR_OPTIONS[hair_option.selected]
	var outfit := OUTFIT_OPTIONS[outfit_option.selected]
	return {
		"body":         str(body["id"]),
		"head":         LPCComposer.head_id_for_body(str(body["id"])),
		"eyes":         "eyes_default",
		"hair":         str(hair["id"]),
		"outfit":       str(outfit["id"]),
		"weapon_layer": "weapon_none",
		"body_tint":    _color_to_hex(body_tint_btn.color),
		"hair_tint":    _color_to_hex(hair_tint_btn.color),
	}

func _color_to_hex(c: Color) -> String:
	return "#" + c.to_html(false)
