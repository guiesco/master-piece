package match

// OpCode constants for match messages.
const (
	OpMove         int64 = 1
	OpPlayerState  int64 = 2
	OpPlayerJoined int64 = 3
	OpPlayerLeft   int64 = 4
	OpPlayerDeath  int64 = 5  // Fase 4: jogador morto pelo inimigo (respawn simples)
	OpAttack       int64 = 10
	OpCombatEvent  int64 = 11
	OpLoot         int64 = 20
	OpEquip        int64 = 21
	OpXPEvent      int64 = 30
	OpLevelUp      int64 = 31
	OpAllocateStat int64 = 32
	OpEnemyState   int64 = 40
	OpEnemySpawn   int64 = 41
	OpEnemyDeath   int64 = 42
)

// AppearanceDef holds all visual layer identifiers for an LPC character.
type AppearanceDef struct {
	Body        string `json:"body"`
	Hair        string `json:"hair"`
	Outfit      string `json:"outfit"`
	WeaponLayer string `json:"weapon_layer"`
	BodyTint    string `json:"body_tint"`
	HairTint    string `json:"hair_tint"`
}

// Stats holds the three base attributes for a player.
type Stats struct {
	Strength     int `json:"strength"`
	Agility      int `json:"agility"`
	Intelligence int `json:"intelligence"`
}

// PlayerState is the canonical server-side representation of a connected player.
type PlayerState struct {
	UserID     string        `json:"user_id"`
	X          float64       `json:"x"`
	Y          float64       `json:"y"`
	Level      int           `json:"level"`
	XP         int           `json:"xp"`
	Stats      Stats         `json:"stats"`
	Equipped   string        `json:"equipped"`
	Appearance AppearanceDef `json:"appearance"`

	// Fase 4: HP e cooldowns de skill.
	HP             int              `json:"hp"`
	MaxHP          int              `json:"max_hp"`
	SkillCooldowns map[string]int64 `json:"skill_cooldowns"` // skill_id → Unix ms do último uso

	// Fase 5: inventário, item equipado e pontos de atributo pendentes.
	Inventory         []string `json:"inventory"`
	PendingStatPoints int      `json:"pending_stat_points"`

	// Multi-slot: qual slot de personagem está ativo e nome do personagem.
	CharacterSlot int    `json:"character_slot"`
	CharacterName string `json:"character_name,omitempty"`
}

// MatchState is the full server-side state of one AlvidaHold match instance.
type MatchState struct {
	Players  map[string]*PlayerState // keyed by userID
	LabelSet bool                    // true after MatchLabelUpdate has been called

	// Fase 4: inimigos e tabelas de conteúdo imutáveis.
	Enemies    map[string]*EnemyState // keyed by enemy ID (population via Fase 6)
	Archetypes map[string]Archetype   // loaded from archetypes.json at MatchInit
	Skills     map[string]Skill       // loaded from skills.json at MatchInit

	// Fase 6: geração de aparência LPC por seed.
	MatchID    string   // ID único deste match, usado na seed determinística
	LPCBodies  []string // catálogo de corpos disponíveis
	LPCHairs   []string // catálogo de cabelos disponíveis
	LPCOutfits []string // catálogo de roupas disponíveis
	LPCWeapons []string // catálogo de armas disponíveis

	// Fase 5: progressão e loot.
	Weapons  map[string]Weapon // loaded from weapons.json at MatchInit
	KillerOf map[string]string // enemy_id → user_id do matador (limpo após progressão)

	// Fase 6: fila de respawn — chave = tick alvo, valor = lista de enemy IDs.
	RespawnQueue  map[int64][]string
	KilledEnemies []string // inimigos mortos neste tick (drenado pelo MatchLoop)

	// Projéteis ranged: dano aplicado no tick de impacto (não no disparo).
	PendingHits []PendingHit
}

// PendingHit é um hit agendado (ex.: projétil ranged em voo).
type PendingHit struct {
	ApplyAtTick int64
	AttackerID  string
	TargetID    string
	Damage      int
	Anim        string
	IsRanged    bool
	FromX       float64
	FromY       float64
	ToX         float64
	ToY         float64
}
