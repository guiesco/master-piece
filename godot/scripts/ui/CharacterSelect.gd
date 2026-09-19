extends Control
## CharacterSelect — Tela de seleção de personagem com 3 slots.
##
## Fluxo:
##   1. Aguarda NetworkManager estar conectado.
##   2. Chama list_characters() → preenche os 3 painéis de slot.
##   3. Slot ocupado: botão "Jogar" → select_character(slot) → AlvidaHold.
##   4. Slot vazio: botão "Criar" → define target_slot → CharacterCreator.

const SCENE_CREATOR := "res://scenes/ui/CharacterCreator.tscn"
const SCENE_WORLD   := "res://scenes/world/AlvidaHold.tscn"

@onready var slot_panels: Array = [
	$Background/Panel/Margin/VBox/Slots/Slot0,
	$Background/Panel/Margin/VBox/Slots/Slot1,
	$Background/Panel/Margin/VBox/Slots/Slot2,
]
@onready var status_label: Label = $Background/Panel/Margin/VBox/StatusLabel

var _slots: Array = [null, null, null]

# ─── Lifecycle ──────────────────────────────────────────────────────────────

func _ready() -> void:
	status_label.text = "Conectando ao servidor..."
	# Se já conectado, carrega direto; senão aguarda sinal.
	if NetworkManager.local_user_id != "":
		_load_slots()
	else:
		NetworkManager.connected.connect(_load_slots, CONNECT_ONE_SHOT)

# ─── Carregamento de slots ──────────────────────────────────────────────────

func _load_slots() -> void:
	status_label.text = "Carregando personagens..."
	_slots = await NetworkManager.list_characters()
	_refresh_ui()
	status_label.text = ""

func _refresh_ui() -> void:
	for i in 3:
		var panel: Node = slot_panels[i]
		if panel == null or not is_instance_valid(panel):
			continue
		# Nodes estão aninhados dentro de SlotMargin/SlotBox
		var name_lbl:  Label  = panel.get_node_or_null("SlotMargin/SlotBox/NameLabel")
		var level_lbl: Label  = panel.get_node_or_null("SlotMargin/SlotBox/LevelLabel")
		var play_btn:  Button = panel.get_node_or_null("SlotMargin/SlotBox/PlayButton")

		if play_btn == null:
			continue
		# Remove todas as conexões anteriores em pressed para evitar duplicação
		# (is_connected não detecta callables vinculadas com .bind())
		for conn in play_btn.pressed.get_connections():
			play_btn.pressed.disconnect(conn["callable"])

		var slot_data: Variant = _slots[i]
		var has_char: bool = slot_data != null and slot_data is Dictionary and str(slot_data.get("name", "")) != ""

		if has_char:
			if name_lbl:
				name_lbl.text = str(slot_data.get("name", "???"))
			if level_lbl:
				level_lbl.text = "Nível %d" % int(slot_data.get("level", 1))
			play_btn.text = "⚔ Jogar"
			play_btn.pressed.connect(_on_play_pressed.bind(i))
		else:
			if name_lbl:
				name_lbl.text = "— Vazio —"
			if level_lbl:
				level_lbl.text = ""
			play_btn.text = "+ Criar"
			play_btn.pressed.connect(_on_create_pressed.bind(i))

# ─── Handlers de slot ───────────────────────────────────────────────────────

func _on_play_pressed(slot: int) -> void:
	status_label.text = "Selecionando personagem..."
	_set_buttons_disabled(true)
	var profile: Dictionary = await NetworkManager.select_character(slot)
	if profile.is_empty():
		status_label.text = "Erro ao selecionar. Tente novamente."
		_set_buttons_disabled(false)
		return
	get_tree().change_scene_to_file(SCENE_WORLD)

func _on_create_pressed(slot: int) -> void:
	NetworkManager.target_slot = slot
	get_tree().change_scene_to_file(SCENE_CREATOR)

# ─── Helpers ────────────────────────────────────────────────────────────────

func _set_buttons_disabled(disabled: bool) -> void:
	for panel in slot_panels:
		if panel == null or not is_instance_valid(panel):
			continue
		var btn: Button = panel.get_node_or_null("SlotMargin/SlotBox/PlayButton")
		if btn:
			btn.disabled = disabled
