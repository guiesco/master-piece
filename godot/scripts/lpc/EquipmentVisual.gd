## GDScript: EquipmentVisual.gd
## Atualização visual de equipamento e mapeamento item → skills dual (LMB/RMB) / camada LPC.
## Contrato esperado (weapons.json): skill_primary + skill_secondary.

class_name EquipmentVisual
extends RefCounted

## item_id → skill LMB (slot 0 / primary)
const WEAPON_PRIMARY_SKILL: Dictionary = {
	"wooden_sword": "sword_slash",
	"wooden_bow": "bow_shot",
	"weapon_sword_wood": "sword_slash",
	"weapon_bow_wood": "bow_shot",
	"weapon_club_iron": "punch",
	"weapon_dagger_steel": "sword_slash",
	"weapon_none": "punch",
	"": "punch",
}

## item_id → skill RMB (slot 1 / secondary)
const WEAPON_SECONDARY_SKILL: Dictionary = {
	"wooden_sword": "sword_backslash",
	"wooden_bow": "bow_aimed",
	"weapon_sword_wood": "sword_backslash",
	"weapon_bow_wood": "bow_aimed",
	"weapon_club_iron": "punch",
	"weapon_dagger_steel": "sword_backslash",
	"weapon_none": "punch",
	"": "punch",
}

## Compat legado (retorna secondary / skill única antiga).
const WEAPON_SKILL_MAP: Dictionary = WEAPON_SECONDARY_SKILL

## item_id → id do arquivo em assets/lpc/weapon/
const ITEM_TO_LPC_LAYER: Dictionary = {
	"wooden_sword": "weapon_sword_wood",
	"wooden_bow": "weapon_bow_wood",
	"weapon_sword_wood": "weapon_sword_wood",
	"weapon_bow_wood": "weapon_bow_wood",
	"weapon_club_iron": "weapon_club_iron",
	"weapon_dagger_steel": "weapon_dagger_steel",
	"weapon_none": "weapon_none",
	"": "weapon_none",
}

## skill_id → nome de anim LPC (espelha skills.json "anim")
const SKILL_ANIM_MAP: Dictionary = {
	"punch": "slash",
	"sword_slash": "slash",
	"sword_backslash": "backslash",
	"bow_shot": "shoot",
	"bow_aimed": "shoot",
}

## skill_id → cooldown local em ms (espelha skills.json cooldown_ms)
const SKILL_COOLDOWN_MS: Dictionary = {
	"punch": 800,
	"sword_slash": 1200,
	"sword_backslash": 1100,
	"bow_shot": 900,
	"bow_aimed": 1200,
}

## skill_id → is_ranged (cliente; servidor manda no evento)
const SKILL_IS_RANGED: Dictionary = {
	"punch": false,
	"sword_slash": false,
	"sword_backslash": false,
	"bow_shot": true,
	"bow_aimed": true,
}

## Resolve item_id ou layer id para o nome do PNG em assets/lpc/weapon/.
static func resolve_weapon_layer(weapon_id: String) -> String:
	return str(ITEM_TO_LPC_LAYER.get(weapon_id, weapon_id))

## Atualiza camadas FG+BG de arma no LPCComposer.
static func update_weapon_layer(composer: LPCComposer, weapon_id: String) -> void:
	if composer == null:
		push_warning("EquipmentVisual.update_weapon_layer: composer é null")
		return
	var layer_id := resolve_weapon_layer(weapon_id)
	composer._apply_weapon_layers(layer_id)

## Retorna [primary, secondary]. Sem arma: ["punch","punch"].
static func get_skill_slots(weapon_id: String) -> Array:
	if weapon_id == "" or weapon_id == "weapon_none" or weapon_id == "none":
		return ["punch", "punch"]
	var primary := str(WEAPON_PRIMARY_SKILL.get(weapon_id, "punch"))
	var secondary := str(WEAPON_SECONDARY_SKILL.get(weapon_id, "punch"))
	return [primary, secondary]

## Compat: retorna skill secondary (legado).
static func get_skill_for_weapon(weapon_id: String) -> String:
	return str(WEAPON_SECONDARY_SKILL.get(weapon_id, "punch"))

static func get_primary_skill(weapon_id: String) -> String:
	return str(WEAPON_PRIMARY_SKILL.get(weapon_id, "punch"))

static func get_secondary_skill(weapon_id: String) -> String:
	return str(WEAPON_SECONDARY_SKILL.get(weapon_id, "punch"))

static func get_anim_for_skill(skill_id: String) -> String:
	return str(SKILL_ANIM_MAP.get(skill_id, "slash"))

static func get_cooldown_ms(skill_id: String) -> int:
	return int(SKILL_COOLDOWN_MS.get(skill_id, 800))

static func is_skill_ranged(skill_id: String) -> bool:
	return bool(SKILL_IS_RANGED.get(skill_id, false))
