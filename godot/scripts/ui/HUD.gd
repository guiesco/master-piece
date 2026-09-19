extends CanvasLayer
class_name HUD
## HUD — Interface do jogador durante o jogo.
## Exibe HP, XP, nível, slots de skill, atributos e inventário (tecla I).

## Emitido quando o jogador pressiona um slot de skill.
signal skill_pressed(slot: int)
## Emitido quando o jogador clica em +1 de um atributo.
signal allocate_stat_pressed(stat_name: String)
## Emitido quando o jogador clica em equipar item no inventário.
signal equip_item_pressed(item_id: String)

@onready var hp_bar: ProgressBar = $HUDContainer/TopLeft/HPContainer/HPBar
@onready var hp_label: Label = $HUDContainer/TopLeft/HPContainer/HPLabel
@onready var xp_bar: ProgressBar = $HUDContainer/TopLeft/XPContainer/XPBar
@onready var xp_label: Label = $HUDContainer/TopLeft/XPContainer/XPLabel
@onready var level_label: Label = $HUDContainer/TopLeft/LevelLabel

@onready var skill_1_btn: TextureButton = $HUDContainer/BottomBar/Skills/Skill1
@onready var skill_2_btn: TextureButton = $HUDContainer/BottomBar/Skills/Skill2

@onready var attr_btn: Button = $HUDContainer/BottomBar/AttrButton
@onready var attr_panel: PanelContainer = $HUDContainer/AttrPanel

@onready var str_value_lbl: Label = $HUDContainer/AttrPanel/Margin/AttrBox/STRRow/STRValue
@onready var agi_value_lbl: Label = $HUDContainer/AttrPanel/Margin/AttrBox/AGIRow/AGIValue
@onready var int_value_lbl: Label = $HUDContainer/AttrPanel/Margin/AttrBox/INTRow/INTValue
@onready var str_btn: Button = $HUDContainer/AttrPanel/Margin/AttrBox/STRRow/STRBtn
@onready var agi_btn: Button = $HUDContainer/AttrPanel/Margin/AttrBox/AGIRow/AGIBtn
@onready var int_btn: Button = $HUDContainer/AttrPanel/Margin/AttrBox/INTRow/INTBtn

@onready var inv_panel: PanelContainer = $HUDContainer/InventoryPanel
@onready var inv_list: VBoxContainer   = $HUDContainer/InventoryPanel/Margin/InvBox/InvList
@onready var inv_btn: Button           = $HUDContainer/BottomBar/InvButton

var _stat_points_available: int = 0
var _inventory: Array  = []
var _equipped:  String = ""

# ─── Lifecycle ──────────────────────────────────────────────────────────────

func _ready() -> void:
	if is_instance_valid(attr_panel):
		attr_panel.visible = false
	if is_instance_valid(inv_panel):
		inv_panel.visible = false

	skill_1_btn.pressed.connect(func(): emit_signal("skill_pressed", 1))
	skill_2_btn.pressed.connect(func(): emit_signal("skill_pressed", 2))
	attr_btn.pressed.connect(_toggle_attr_panel)
	if is_instance_valid(inv_btn):
		inv_btn.pressed.connect(_toggle_inv_panel)

	str_btn.pressed.connect(func(): emit_signal("allocate_stat_pressed", "str"))
	agi_btn.pressed.connect(func(): emit_signal("allocate_stat_pressed", "agi"))
	int_btn.pressed.connect(func(): emit_signal("allocate_stat_pressed", "int"))

	update_hp(100, 100)
	update_xp(0, 100)
	update_level(1)
	update_stats(1, 1, 1, 0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		_toggle_inv_panel()

# ─── API pública ─────────────────────────────────────────────────────────────

## Atualiza barra de HP.
func update_hp(current: int, max_hp: int) -> void:
	if is_instance_valid(hp_bar):
		hp_bar.max_value = max_hp
		hp_bar.value = current
	if is_instance_valid(hp_label):
		hp_label.text = "%d / %d" % [current, max_hp]

## Atualiza barra de XP.
func update_xp(current: int, xp_to_next: int) -> void:
	if is_instance_valid(xp_bar):
		xp_bar.max_value = xp_to_next if xp_to_next > 0 else 1
		xp_bar.value = current
	if is_instance_valid(xp_label):
		xp_label.text = "XP: %d / %d" % [current, xp_to_next]

## Atualiza label de nível.
func update_level(lvl: int) -> void:
	if is_instance_valid(level_label):
		level_label.text = "Nível %d" % lvl

## Atualiza painel de atributos e botões de alocação.
func update_stats(str_val: int, agi_val: int, int_val: int, pending: int) -> void:
	_stat_points_available = pending
	if is_instance_valid(str_value_lbl):
		str_value_lbl.text = str(str_val)
	if is_instance_valid(agi_value_lbl):
		agi_value_lbl.text = str(agi_val)
	if is_instance_valid(int_value_lbl):
		int_value_lbl.text = str(int_val)
	var has_points := pending > 0
	if is_instance_valid(str_btn):
		str_btn.disabled = not has_points
	if is_instance_valid(agi_btn):
		agi_btn.disabled = not has_points
	if is_instance_valid(int_btn):
		int_btn.disabled = not has_points

## Alias de compatibilidade.
func update_attributes(str_val: int, agi_val: int, int_val: int, stat_points: int) -> void:
	update_stats(str_val, agi_val, int_val, stat_points)

## Atualiza tooltips dos botões de skill (slot1=LMB primary, slot2=RMB secondary).
func update_skills(slot1_id: String, slot2_id: String) -> void:
	if is_instance_valid(skill_1_btn):
		skill_1_btn.tooltip_text = "LMB: %s" % slot1_id
	if is_instance_valid(skill_2_btn):
		skill_2_btn.tooltip_text = "RMB: %s" % slot2_id

## Atualiza o painel de inventário com a lista atual de itens.
func refresh_inventory(items: Array, equipped_id: String) -> void:
	_inventory = items.duplicate()
	_equipped  = equipped_id
	if is_instance_valid(inv_panel) and inv_panel.visible:
		_rebuild_inv_list()

## Exibe animação "LEVEL UP!" no centro da tela por 1.5 s.
func show_level_up() -> void:
	var label := Label.new()
	label.text = "LEVEL UP!"
	label.modulate = Color(1.0, 0.85, 0.0, 1.0)
	label.add_theme_font_size_override("font_size", 48)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(label):
		label.queue_free()

## Exibe notificação flutuante de loot por 2 s.
func show_loot_notification(item_name: String) -> void:
	var label := Label.new()
	label.text = "+ %s" % item_name
	label.modulate = Color(1.0, 0.9, 0.3, 1.0)
	label.add_theme_font_size_override("font_size", 20)
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.position = Vector2(-220.0, -80.0)
	add_child(label)
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(label):
		label.queue_free()

# ─── Inventário ──────────────────────────────────────────────────────────────

func _toggle_inv_panel() -> void:
	if not is_instance_valid(inv_panel):
		return
	inv_panel.visible = not inv_panel.visible
	if inv_panel.visible:
		_rebuild_inv_list()

func _rebuild_inv_list() -> void:
	if not is_instance_valid(inv_list):
		return
	# Remove itens antigos
	for child in inv_list.get_children():
		child.queue_free()

	if _inventory.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(inventário vazio)"
		empty_lbl.modulate = Color(0.6, 0.6, 0.6, 1)
		inv_list.add_child(empty_lbl)
		return

	for item_id in _inventory:
		var row := HBoxContainer.new()
		inv_list.add_child(row)

		var lbl := Label.new()
		lbl.text = str(item_id)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		# Destaque se equipado
		if str(item_id) == _equipped:
			lbl.modulate = Color(1.0, 0.85, 0.2, 1.0)
			var eq_lbl := Label.new()
			eq_lbl.text = " ✓"
			eq_lbl.modulate = Color(0.2, 1.0, 0.2, 1.0)
			row.add_child(eq_lbl)
		else:
			var eq_btn := Button.new()
			eq_btn.text = "Equipar"
			eq_btn.add_theme_font_size_override("font_size", 12)
			var captured_id := str(item_id)
			eq_btn.pressed.connect(func(): emit_signal("equip_item_pressed", captured_id))
			row.add_child(eq_btn)

# ─── Helpers ─────────────────────────────────────────────────────────────────

func _toggle_attr_panel() -> void:
	if is_instance_valid(attr_panel):
		attr_panel.visible = not attr_panel.visible
