package match

// progression.go — Módulo de progressão, loot e equipamento (Fase 5).
//
// Responsabilidades:
//   - HandleProgression: XP, level up, pontos de atributo e loot ao matar inimigos.
//   - HandleAllocateStat: aloca pontos de atributo (str/agi/int) via OpAllocateStat.
//   - HandleEquip: equipa item do inventário via OpEquip e atualiza camada visual.

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"

	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/op-mmo/alvida-hold/content"
	"github.com/op-mmo/alvida-hold/profile"
)

// ─── Tipos de dados ───────────────────────────────────────────────────────────

// Weapon representa uma arma carregada de weapons.json.
type Weapon struct {
	ID             string `json:"id"`
	DisplayName    string `json:"display_name"`
	DamageBonus    int    `json:"damage_bonus"`
	SkillPrimary   string `json:"skill_primary"`
	SkillSecondary string `json:"skill_secondary"`
	LPCLayer       string `json:"lpc_layer"`
}

type weaponFile struct {
	Weapons []Weapon `json:"weapons"`
}

// LoadWeapons parseia weapons.json (embutido no binário) e retorna um mapa indexado pelo ID.
func LoadWeapons() (map[string]Weapon, error) {
	var wf weaponFile
	if err := json.Unmarshal(content.WeaponsJSON, &wf); err != nil {
		return nil, fmt.Errorf("parse weapons.json: %w", err)
	}
	m := make(map[string]Weapon, len(wf.Weapons))
	for _, w := range wf.Weapons {
		m[w.ID] = w
	}
	return m, nil
}

// ─── Payloads de broadcast ────────────────────────────────────────────────────

// xpEventMsg é enviado como OpXPEvent (opcode 30) após ganho de XP ou alocação de stat.
type xpEventMsg struct {
	PlayerID      string `json:"player_id"`
	XPGained      int    `json:"xp_gained"`
	TotalXP       int    `json:"total_xp"`
	Level         int    `json:"level"`
	PendingPoints int    `json:"pending_points"`
	XPToNext      int    `json:"xp_to_next"`
	Strength      int    `json:"strength"`
	Agility       int    `json:"agility"`
	Intelligence  int    `json:"intelligence"`
	// HP sync: inclui HP atual e máximo para o cliente atualizar a barra de vida.
	HP    int `json:"hp"`
	MaxHP int `json:"max_hp"`
}

// levelUpMsg é enviado como OpLevelUp (opcode 31) quando o jogador sobe de nível.
type levelUpMsg struct {
	PlayerID      string `json:"player_id"`
	NewLevel      int    `json:"new_level"`
	PendingPoints int    `json:"pending_points"`
}

// lootMsg é enviado como OpLoot (opcode 20) quando um item dropa para o jogador.
type lootMsg struct {
	PlayerID string `json:"player_id"`
	ItemID   string `json:"item_id"`
}

// equipBroadcastMsg é enviado como OpEquip (opcode 21) para notificar todos da troca de arma.
type equipBroadcastMsg struct {
	PlayerID       string `json:"player_id"`
	ItemID         string `json:"item_id"`
	WeaponLayer    string `json:"weapon_layer"`
	SkillPrimary   string `json:"skill_primary"`
	SkillSecondary string `json:"skill_secondary"`
	// SkillID espelha skill_primary (compat transitória com clientes antigos).
	SkillID string `json:"skill_id"`
}

// ─── HandleProgression ────────────────────────────────────────────────────────

// HandleProgression processa XP e loot para cada inimigo morto por killerID no tick.
//
// Para cada inimigo:
//   - Calcula XP do archetype e adiciona ao PlayerState.XP.
//   - Verifica level up (threshold = Level×100); incrementa Level, PendingStatPoints, recalcula MaxHP.
//   - Faz broadcast de OpLevelUp se subiu de nível.
//   - Faz broadcast de OpXPEvent com estado atualizado.
//   - Rola loot: para cada LootEntry, gera float aleatório; se menor que DropChance, adiciona ao inventário.
//   - Faz broadcast de OpLoot para cada item dropado.
//   - Persiste perfil no Nakama Storage.
func HandleProgression(
	state *MatchState,
	killedEnemies []string,
	killerID string,
	dispatcher runtime.MatchDispatcher,
	nk runtime.NakamaModule,
	ctx context.Context,
	logger runtime.Logger,
) error {
	ps, ok := state.Players[killerID]
	if !ok {
		return nil
	}

	for _, enemyID := range killedEnemies {
		enemy, ok := state.Enemies[enemyID]
		if !ok {
			continue
		}
		arch, ok := state.Archetypes[enemy.Archetype]
		if !ok {
			logger.Warn("HandleProgression archetype=%q desconhecido para enemy=%s", enemy.Archetype, enemyID)
			continue
		}

		// ── XP ────────────────────────────────────────────────────────────────
		xpGained := arch.XPReward
		ps.XP += xpGained

		// ── Level up em loop (acumulação de múltiplos kills) ─────────────────
		for {
			threshold := ps.Level * 100
			if ps.XP < threshold {
				break
			}
			ps.XP -= threshold
			ps.Level++
			ps.PendingStatPoints++
			ps.MaxHP = 100 + ps.Stats.Strength*5
			// HP corrente não ultrapassa o novo máximo.
			if ps.HP > ps.MaxHP {
				ps.HP = ps.MaxHP
			}

			luMsg := levelUpMsg{
				PlayerID:      killerID,
				NewLevel:      ps.Level,
				PendingPoints: ps.PendingStatPoints,
			}
			if err := broadcastJSON(dispatcher, OpLevelUp, luMsg); err != nil {
				logger.Error("HandleProgression OpLevelUp player=%s: %v", killerID, err)
			}
		}

		// ── Broadcast OpXPEvent ───────────────────────────────────────────────
		if err := broadcastJSON(dispatcher, OpXPEvent, buildXPEvent(killerID, xpGained, ps)); err != nil {
			logger.Error("HandleProgression OpXPEvent player=%s: %v", killerID, err)
		}

		// ── Loot ──────────────────────────────────────────────────────────────
		for _, entry := range arch.LootTable {
			if rand.Float64() < entry.DropChance {
				ps.Inventory = append(ps.Inventory, entry.ItemID)
				drop := lootMsg{PlayerID: killerID, ItemID: entry.ItemID}
				if err := broadcastJSON(dispatcher, OpLoot, drop); err != nil {
					logger.Error("HandleProgression OpLoot player=%s item=%s: %v", killerID, entry.ItemID, err)
				}
			}
		}
	}

	// ── Persiste perfil no slot ativo ────────────────────────────────────────
	if err := profile.SaveCharacterSlot(ctx, nk, killerID, ps.CharacterSlot, playerStateToProfile(ps)); err != nil {
		logger.Error("HandleProgression SaveCharacterSlot player=%s slot=%d: %v", killerID, ps.CharacterSlot, err)
	}

	return nil
}

// ─── HandleAllocateStat ───────────────────────────────────────────────────────

// HandleAllocateStat processa OpAllocateStat (opcode 32).
//
// Payload esperado: { "stat_name": "str"|"agi"|"int" }
// (IntentCodec.encode_allocate_stat usa o campo "stat" — ambos são aceitos.)
//
//   - Valida que PlayerState.PendingStatPoints > 0.
//   - Incrementa o atributo correspondente.
//   - Recalcula MaxHP = 100 + Strength×5.
//   - Faz broadcast de OpXPEvent atualizado.
//   - Persiste perfil no Storage.
func HandleAllocateStat(
	state *MatchState,
	msg runtime.MatchData,
	dispatcher runtime.MatchDispatcher,
	nk runtime.NakamaModule,
	ctx context.Context,
	logger runtime.Logger,
) error {
	userID := msg.GetUserId()
	ps, ok := state.Players[userID]
	if !ok {
		return nil
	}
	if ps.PendingStatPoints <= 0 {
		logger.Warn("HandleAllocateStat: sem pontos disponíveis para user=%s", userID)
		return nil
	}

	var payload struct {
		StatName string `json:"stat_name"` // campo preferencial
		Stat     string `json:"stat"`      // alias usado por IntentCodec
	}
	if err := json.Unmarshal(msg.GetData(), &payload); err != nil {
		return fmt.Errorf("decode OpAllocateStat user=%s: %w", userID, err)
	}
	stat := payload.StatName
	if stat == "" {
		stat = payload.Stat
	}

	switch stat {
	case "str", "strength":
		ps.Stats.Strength++
	case "agi", "agility":
		ps.Stats.Agility++
	case "int", "intelligence":
		ps.Stats.Intelligence++
	default:
		logger.Warn("HandleAllocateStat atributo desconhecido=%q user=%s", stat, userID)
		return nil
	}

	ps.PendingStatPoints--
	ps.MaxHP = 100 + ps.Stats.Strength*5
	if ps.HP > ps.MaxHP {
		ps.HP = ps.MaxHP
	}

	if err := broadcastJSON(dispatcher, OpXPEvent, buildXPEvent(userID, 0, ps)); err != nil {
		logger.Error("HandleAllocateStat OpXPEvent user=%s: %v", userID, err)
	}

	if err := profile.SaveCharacterSlot(ctx, nk, userID, ps.CharacterSlot, playerStateToProfile(ps)); err != nil {
		logger.Error("HandleAllocateStat SaveCharacterSlot user=%s slot=%d: %v", userID, ps.CharacterSlot, err)
	}

	return nil
}

// ─── HandleEquip ─────────────────────────────────────────────────────────────

// HandleEquip processa OpEquip (opcode 21) enviado pelo cliente.
//
// Payload esperado: { "item_id": "wooden_sword" }
//
//   - Valida que item_id está no Inventory do jogador.
//   - Atualiza PlayerState.Equipped e PlayerState.Appearance.WeaponLayer.
//   - Faz broadcast de OpPlayerState com appearance atualizada para todos.
//   - Faz broadcast de OpEquip com player_id, item_id, weapon_layer,
//     skill_primary e skill_secondary.
func HandleEquip(
	state *MatchState,
	msg runtime.MatchData,
	dispatcher runtime.MatchDispatcher,
	logger runtime.Logger,
) error {
	userID := msg.GetUserId()
	ps, ok := state.Players[userID]
	if !ok {
		return nil
	}

	var payload struct {
		ItemID string `json:"item_id"`
	}
	if err := json.Unmarshal(msg.GetData(), &payload); err != nil {
		return fmt.Errorf("decode OpEquip user=%s: %w", userID, err)
	}

	// Valida que o item está no inventário do jogador.
	found := false
	for _, item := range ps.Inventory {
		if item == payload.ItemID {
			found = true
			break
		}
	}
	if !found {
		logger.Warn("HandleEquip item=%q não está no inventário do user=%s", payload.ItemID, userID)
		return nil
	}

	// Atualiza estado do equipamento.
	ps.Equipped = payload.ItemID

	var weaponLayer, skillPrimary, skillSecondary string
	if w, wok := state.Weapons[payload.ItemID]; wok {
		weaponLayer = w.LPCLayer
		skillPrimary = w.SkillPrimary
		skillSecondary = w.SkillSecondary
	}
	ps.Appearance.WeaponLayer = weaponLayer

	// Broadcast OpPlayerState com appearance atualizada (todos os clientes atualizam a entidade).
	if err := broadcastJSON(dispatcher, OpPlayerState, ps); err != nil {
		logger.Error("HandleEquip OpPlayerState user=%s: %v", userID, err)
	}

	// Broadcast OpEquip para que clientes apliquem visual + slots LMB/RMB.
	eqMsg := equipBroadcastMsg{
		PlayerID:       userID,
		ItemID:         payload.ItemID,
		WeaponLayer:    weaponLayer,
		SkillPrimary:   skillPrimary,
		SkillSecondary: skillSecondary,
		SkillID:        skillPrimary,
	}
	if err := broadcastJSON(dispatcher, OpEquip, eqMsg); err != nil {
		logger.Error("HandleEquip OpEquip user=%s: %v", userID, err)
	}

	return nil
}

// ─── Helpers internos ────────────────────────────────────────────────────────

// buildXPEvent constrói um xpEventMsg com o estado atual de XP, stats e HP do jogador.
func buildXPEvent(playerID string, xpGained int, ps *PlayerState) xpEventMsg {
	return xpEventMsg{
		PlayerID:      playerID,
		XPGained:      xpGained,
		TotalXP:       ps.XP,
		Level:         ps.Level,
		PendingPoints: ps.PendingStatPoints,
		XPToNext:      ps.Level * 100,
		Strength:      ps.Stats.Strength,
		Agility:       ps.Stats.Agility,
		Intelligence:  ps.Stats.Intelligence,
		HP:            ps.HP,
		MaxHP:         ps.MaxHP,
	}
}

// playerStateToProfile converte PlayerState → PlayerProfile para persistência no Storage.
func playerStateToProfile(ps *PlayerState) *profile.PlayerProfile {
	inv := ps.Inventory
	if inv == nil {
		inv = []string{}
	}
	return &profile.PlayerProfile{
		Level:             ps.Level,
		XP:                ps.XP,
		Stats:             profile.ProfileStats(ps.Stats),
		Inventory:         inv,
		Equipped:          ps.Equipped,
		PendingStatPoints: ps.PendingStatPoints,
		// Preserva aparência LPC para não perder customização ao salvar por progressão.
		Appearance: profile.AppearanceData{
			Body:        ps.Appearance.Body,
			Hair:        ps.Appearance.Hair,
			Outfit:      ps.Appearance.Outfit,
			WeaponLayer: ps.Appearance.WeaponLayer,
			BodyTint:    ps.Appearance.BodyTint,
			HairTint:    ps.Appearance.HairTint,
		},
		// Preserva campos de multi-slot.
		Name: ps.CharacterName,
		Slot: ps.CharacterSlot,
	}
}
