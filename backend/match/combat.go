package match

// combat.go — Módulo de combate autoritativo e IA de inimigos.
//
// Responsabilidades:
//   - Carregar archetypes.json e skills.json (via package content, embed em compile-time).
//   - HandleCombat: processar OpAttack, validar cooldown/range, aplicar dano, broadcast.
//   - TickAI: loop de IA dos inimigos (Wander → Chase → Attack) a cada tick.
//
// XP, loot e progressão NÃO são tratados aqui — ficam para a Fase 5.

import (
	"encoding/json"
	"fmt"
	"math"
	"math/rand"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/op-mmo/alvida-hold/content"
)

// ─── Tipos de dados ───────────────────────────────────────────────────────────

// EnemyState é a representação canônica server-side de um inimigo no match.
type EnemyState struct {
	ID             string        `json:"id"`
	Archetype      string        `json:"archetype"`
	HP             int           `json:"hp"`
	MaxHP          int           `json:"max_hp"`
	X              float64       `json:"x"`
	Y              float64       `json:"y"`
	AIState        string        `json:"ai_state"` // Wander | Chase | Attack
	TargetID       string        `json:"target_id"`
	LastAttackTick int64         `json:"last_attack_tick"` // Unix ms do último ataque
	SpawnIndex     int           `json:"spawn_index"`
	// Fase 6: campos de respawn e aparência gerada por seed.
	RespawnCount int           `json:"respawn_count"`
	SpawnX       float64       `json:"spawn_x"` // posição original para respawn
	SpawnY       float64       `json:"spawn_y"`
	Appearance   AppearanceDef `json:"appearance"`
}

// LootEntry representa um item na drop table de um archetype.
type LootEntry struct {
	ItemID     string  `json:"item_id"`
	DropChance float64 `json:"drop_chance"`
}

// Archetype é a definição imutável de um tipo de inimigo, carregada de archetypes.json.
type Archetype struct {
	ID          string      `json:"id"`
	MaxHP       int         `json:"hp"`
	Damage      int         `json:"base_damage"`
	Speed       float64     `json:"speed"`
	XPReward    int         `json:"xp_reward"`
	LootTable   []LootEntry `json:"loot_table"`
	DetectRange float64     `json:"detect_range"`
	AttackRange float64     `json:"attack_range"`
	IsRanged    bool        `json:"is_ranged"`
	Anim        string      `json:"anim"`
}

// Skill é a definição imutável de uma habilidade do jogador, carregada de skills.json.
type Skill struct {
	ID             string  `json:"id"`
	Damage         int     `json:"damage"`
	Range          float64 `json:"range"`
	CooldownMs     int64   `json:"cooldown_ms"`
	RequiresWeapon *string `json:"requires_weapon"` // nil = unarmed (punch)
	Anim           string  `json:"anim"`            // slash | backslash | thrust
	IsRanged       bool    `json:"is_ranged"`
}

// ─── Loaders de conteúdo ──────────────────────────────────────────────────────

type archetypeFile struct {
	Archetypes []Archetype `json:"archetypes"`
}

// LoadArchetypes parseia archetypes.json (embutido no binário) e retorna um mapa
// indexado pelo ID do archetype.
func LoadArchetypes() (map[string]Archetype, error) {
	var af archetypeFile
	if err := json.Unmarshal(content.ArchetypesJSON, &af); err != nil {
		return nil, fmt.Errorf("parse archetypes.json: %w", err)
	}
	m := make(map[string]Archetype, len(af.Archetypes))
	for _, a := range af.Archetypes {
		m[a.ID] = a
	}
	return m, nil
}

type skillFile struct {
	Skills []Skill `json:"skills"`
}

// LoadSkills parseia skills.json (embutido no binário) e retorna um mapa
// indexado pelo ID da skill.
func LoadSkills() (map[string]Skill, error) {
	var sf skillFile
	if err := json.Unmarshal(content.SkillsJSON, &sf); err != nil {
		return nil, fmt.Errorf("parse skills.json: %w", err)
	}
	m := make(map[string]Skill, len(sf.Skills))
	for _, s := range sf.Skills {
		m[s.ID] = s
	}
	return m, nil
}

// ─── Payloads de mensagens ────────────────────────────────────────────────────

// attackIntent é decodificado de uma mensagem OpAttack enviada pelo cliente.
type attackIntent struct {
	SkillID string  `json:"skill_id"`
	AimX    float64 `json:"aim_x"`
	AimY    float64 `json:"aim_y"`
}

// combatEventMsg é enviado como OpCombatEvent para todos os clientes.
type combatEventMsg struct {
	AttackerID string  `json:"attacker_id"`
	TargetID   string  `json:"target_id"`
	Damage     int     `json:"damage"`
	TargetHP   int     `json:"target_hp"`
	SkillID    string  `json:"skill_id"`
	Anim       string  `json:"anim"`
	IsRanged   bool    `json:"is_ranged"`
	FromX      float64 `json:"from_x"`
	FromY      float64 `json:"from_y"`
	ToX        float64 `json:"to_x"`
	ToY        float64 `json:"to_y"`
}

// enemyDeathMsg é enviado como OpEnemyDeath quando um inimigo morre.
// XP e loot são calculados na Fase 5 — este payload apenas notifica a morte.
type enemyDeathMsg struct {
	EnemyID  string `json:"enemy_id"`
	KillerID string `json:"killer_id"`
}

// enemyStateSnapshotMsg é enviado como OpEnemyState a cada tick.
type enemyStateSnapshotMsg struct {
	EnemyID string  `json:"enemy_id"`
	X       float64 `json:"x"`
	Y       float64 `json:"y"`
	AIState string  `json:"ai_state"`
	HP      int     `json:"hp"`
}

// playerDeathMsg é enviado como OpPlayerDeath quando um jogador morre.
// Respawn simples: cliente restaura HP ao max e mantém posição.
type playerDeathMsg struct {
	PlayerID string `json:"player_id"`
}

// ─── HandleCombat ─────────────────────────────────────────────────────────────

// HandleCombat processa todas as mensagens OpAttack do tick atual.
//
// Para cada intenção de ataque válida:
//   - Valida o cooldown da skill (em ms).
//   - Verifica o range contra todos os inimigos vivos do match.
//   - Aplica dano e faz broadcast de OpCombatEvent.
//   - Se HP do inimigo cair a 0, faz broadcast de OpEnemyDeath.
//     XP/loot são delegados à Fase 5.
//
// Sem friendly fire: jogadores não se atacam.
func HandleCombat(
	state *MatchState,
	msgs []runtime.MatchData,
	dispatcher runtime.MatchDispatcher,
	tick int64,
	logger runtime.Logger,
) error {
	nowMs := time.Now().UnixMilli()

	for _, msg := range msgs {
		if msg.GetOpCode() != OpAttack {
			continue
		}

		userID := msg.GetUserId()
		ps, ok := state.Players[userID]
		if !ok {
			continue
		}

		var intent attackIntent
		if err := json.Unmarshal(msg.GetData(), &intent); err != nil {
			logger.Warn("HandleCombat decode AttackIntent user=%s: %v", userID, err)
			continue
		}

		skill, ok := state.Skills[intent.SkillID]
		if !ok {
			logger.Warn("HandleCombat skill_id=%q desconhecida user=%s", intent.SkillID, userID)
			continue
		}

		// Valida arma exigida pela skill vs equipamento atual.
		if skill.RequiresWeapon != nil {
			if ps.Equipped == "" || ps.Equipped != *skill.RequiresWeapon {
				logger.Warn("HandleCombat skill=%q requer arma=%q mas equipped=%q user=%s",
					intent.SkillID, *skill.RequiresWeapon, ps.Equipped, userID)
				continue
			}
		}

		// Valida cooldown da skill.
		if lastUsed, exists := ps.SkillCooldowns[intent.SkillID]; exists {
			if nowMs-lastUsed < skill.CooldownMs {
				// Silently ignore; o cliente não deveria enviar antes de expirar.
				continue
			}
		}
		ps.SkillCooldowns[intent.SkillID] = nowMs

		// Dano = skill base + bônus da arma equipada (se houver).
		dmg := skill.Damage
		if ps.Equipped != "" {
			if w, wok := state.Weapons[ps.Equipped]; wok {
				dmg += w.DamageBonus
			}
		}

		// Verifica range e cone contra todos os inimigos vivos.
		for _, enemy := range state.Enemies {
			if enemy.HP <= 0 {
				continue
			}

			dist := dist2D(ps.X, ps.Y, enemy.X, enemy.Y)
			if dist > skill.Range {
				continue
			}

			// Cone check: inimigo deve estar dentro do meio-ângulo de ~50° em relação ao aim.
			if !inAttackCone(ps.X, ps.Y, intent.AimX, intent.AimY, enemy.X, enemy.Y) {
				continue
			}

			if skill.IsRanged {
				// Ranged: broadcast de lançamento (dano 0) + agenda hit no tick de impacto.
				launch := combatEventMsg{
					AttackerID: userID,
					TargetID:   enemy.ID,
					Damage:     0,
					TargetHP:   enemy.HP,
					SkillID:    intent.SkillID,
					Anim:       skill.Anim,
					IsRanged:   true,
					FromX:      ps.X,
					FromY:      ps.Y,
					ToX:        enemy.X,
					ToY:        enemy.Y,
				}
				if err := broadcastJSON(dispatcher, OpCombatEvent, launch); err != nil {
					logger.Error("HandleCombat broadcast ranged launch OpCombatEvent: %v", err)
				}

				const projectileSpeed = 10.0 // u/s — alinhado ao cliente
				flightSec := dist / projectileSpeed
				if flightSec < 0.15 {
					flightSec = 0.15
				}
				if flightSec > 0.55 {
					flightSec = 0.55 // LIFETIME_RANGED do cliente
				}
				delayTicks := int64(math.Ceil(flightSec * 20.0)) // tick rate 20 Hz
				if delayTicks < 1 {
					delayTicks = 1
				}
				state.PendingHits = append(state.PendingHits, PendingHit{
					ApplyAtTick: tick + delayTicks,
					AttackerID:  userID,
					TargetID:    enemy.ID,
					Damage:      dmg,
					Anim:        skill.Anim,
					IsRanged:    true,
					FromX:       ps.X,
					FromY:       ps.Y,
					ToX:         enemy.X,
					ToY:         enemy.Y,
				})
				continue // dano será aplicado no tick de impacto
			}

			// Melee: aplica dano imediatamente.
			enemy.HP -= dmg
			if enemy.HP < 0 {
				enemy.HP = 0
			}

			// Broadcast OpCombatEvent (inclui campos de VFX para o cliente).
			evt := combatEventMsg{
				AttackerID: userID,
				TargetID:   enemy.ID,
				Damage:     dmg,
				TargetHP:   enemy.HP,
				SkillID:    intent.SkillID,
				Anim:       skill.Anim,
				IsRanged:   false,
				FromX:      ps.X,
				FromY:      ps.Y,
				ToX:        intent.AimX,
				ToY:        intent.AimY,
			}
			if err := broadcastJSON(dispatcher, OpCombatEvent, evt); err != nil {
				logger.Error("HandleCombat broadcast OpCombatEvent: %v", err)
			}

			// Morte do inimigo — XP/loot ficam para a Fase 5; respawn agendado no MatchLoop.
			if enemy.HP <= 0 {
				death := enemyDeathMsg{EnemyID: enemy.ID, KillerID: userID}
				if err := broadcastJSON(dispatcher, OpEnemyDeath, death); err != nil {
					logger.Error("HandleCombat broadcast OpEnemyDeath: %v", err)
				}
				// Fase 5: registra matador para progressão de XP/loot.
				if state.KillerOf == nil {
					state.KillerOf = make(map[string]string)
				}
				state.KillerOf[enemy.ID] = userID
				// Fase 6: registra morte para agendamento de respawn no MatchLoop.
				state.KilledEnemies = append(state.KilledEnemies, enemy.ID)
			}
		}
	}
	return nil
}

// ─── TickAI ───────────────────────────────────────────────────────────────────

const (
	aiAttackCooldownMs int64   = 1000  // cooldown de ataque do inimigo em ms
	tickRateHz         float64 = 20.0  // taxa de tick do match (20 Hz)
)

// TickAI executa um passo de IA para cada inimigo vivo no match.
//
// Máquina de estados por inimigo:
//   - Wander: move aleatoriamente. Se jogador dentro de DetectRange → Chase.
//   - Chase: move em direção ao alvo (Speed/20 unidades/tick). Se alvo sair do dobro
//     de DetectRange → Wander. Se chegar a AttackRange → Attack.
//   - Attack: se dentro de AttackRange e cooldown passou → aplica dano ao jogador.
//     Se jogador morre → respawn simples (restaura HP, mantém posição).
//
// Broadcast de OpEnemyState a cada tick para todos os clientes.
func TickAI(
	state *MatchState,
	tick int64,
	dispatcher runtime.MatchDispatcher,
	logger runtime.Logger,
) error {
	nowMs := time.Now().UnixMilli()

	for _, enemy := range state.Enemies {
		if enemy.HP <= 0 {
			continue
		}

		arch, ok := state.Archetypes[enemy.Archetype]
		if !ok {
			continue
		}

		speedPerTick := arch.Speed / tickRateHz

		switch enemy.AIState {
		case "Wander":
			tickWander(enemy, arch, state, speedPerTick)
		case "Chase":
			tickChase(enemy, arch, state, speedPerTick)
		case "Attack":
			if err := tickAttack(enemy, arch, state, dispatcher, nowMs, tick, logger); err != nil {
				logger.Error("TickAI tickAttack enemy=%s: %v", enemy.ID, err)
			}
		default:
			enemy.AIState = "Wander"
		}

		// Broadcast snapshot de estado do inimigo a cada tick.
		snap := enemyStateSnapshotMsg{
			EnemyID: enemy.ID,
			X:       enemy.X,
			Y:       enemy.Y,
			AIState: enemy.AIState,
			HP:      enemy.HP,
		}
		if err := broadcastJSON(dispatcher, OpEnemyState, snap); err != nil {
			logger.Error("TickAI broadcast OpEnemyState enemy=%s: %v", enemy.ID, err)
		}
	}
	return nil
}

// tickWander move o inimigo aleatoriamente. Se algum jogador estiver dentro de
// DetectRange, transita para Chase e define o TargetID.
func tickWander(enemy *EnemyState, arch Archetype, state *MatchState, speedPerTick float64) {
	// Verifica se algum jogador entrou no DetectRange.
	if targetID := nearestPlayerInRange(enemy, arch.DetectRange, state); targetID != "" {
		enemy.AIState = "Chase"
		enemy.TargetID = targetID
		return
	}
	// Movimento aleatório dentro dos limites do mapa.
	angle := rand.Float64() * 2.0 * math.Pi
	enemy.X = clampF(enemy.X+math.Cos(angle)*speedPerTick, mapMinX, mapMaxX)
	enemy.Y = clampF(enemy.Y+math.Sin(angle)*speedPerTick, mapMinY, mapMaxY)
}

// tickChase move o inimigo em direção ao alvo. Transita para Wander se o alvo
// se afastar demais, ou para Attack ao chegar dentro do AttackRange.
func tickChase(enemy *EnemyState, arch Archetype, state *MatchState, speedPerTick float64) {
	target, ok := state.Players[enemy.TargetID]
	if !ok {
		// Alvo saiu do match.
		enemy.AIState = "Wander"
		enemy.TargetID = ""
		return
	}

	dist := dist2D(enemy.X, enemy.Y, target.X, target.Y)

	// Alvo fora do dobro do DetectRange → volta a vagar.
	if dist > arch.DetectRange*2.0 {
		enemy.AIState = "Wander"
		enemy.TargetID = ""
		return
	}

	// Chegou ao AttackRange → ataca.
	if dist <= arch.AttackRange {
		enemy.AIState = "Attack"
		return
	}

	// Move em direção ao alvo.
	enemy.X += (target.X-enemy.X) / dist * speedPerTick
	enemy.Y += (target.Y-enemy.Y) / dist * speedPerTick
}

// tickAttack verifica cooldown e aplica dano ao jogador alvo.
// Ranged: dispara VFX imediatamente e agenda o dano para o tick de impacto.
// Se o HP do jogador zerar, faz broadcast de OpPlayerDeath e reseta HP (respawn simples).
func tickAttack(
	enemy *EnemyState,
	arch Archetype,
	state *MatchState,
	dispatcher runtime.MatchDispatcher,
	nowMs int64,
	tick int64,
	logger runtime.Logger,
) error {
	target, ok := state.Players[enemy.TargetID]
	if !ok {
		enemy.AIState = "Wander"
		enemy.TargetID = ""
		return nil
	}

	dist := dist2D(enemy.X, enemy.Y, target.X, target.Y)

	// Alvo saiu do AttackRange → persegue novamente.
	if dist > arch.AttackRange {
		enemy.AIState = "Chase"
		return nil
	}

	// Verifica cooldown de ataque.
	if nowMs-enemy.LastAttackTick < aiAttackCooldownMs {
		return nil
	}
	enemy.LastAttackTick = nowMs

	anim := arch.Anim
	if anim == "" {
		if arch.IsRanged {
			anim = "shoot"
		} else {
			anim = "slash"
		}
	}

	// Ranged: broadcast de lançamento (dano 0) + agenda hit pelo tempo de voo.
	if arch.IsRanged {
		launch := combatEventMsg{
			AttackerID: enemy.ID,
			TargetID:   target.UserID,
			Damage:     0,
			TargetHP:   target.HP,
			SkillID:    "",
			Anim:       anim,
			IsRanged:   true,
			FromX:      enemy.X,
			FromY:      enemy.Y,
			ToX:        target.X,
			ToY:        target.Y,
		}
		if err := broadcastJSON(dispatcher, OpCombatEvent, launch); err != nil {
			return fmt.Errorf("broadcast OpCombatEvent launch: %w", err)
		}

		const projectileSpeed = 10.0 // u/s — alinhado ao cliente
		flightSec := dist / projectileSpeed
		if flightSec < 0.15 {
			flightSec = 0.15
		}
		if flightSec > 0.55 {
			flightSec = 0.55 // LIFETIME_RANGED do cliente
		}
		delayTicks := int64(math.Ceil(flightSec * 20.0)) // tick rate 20 Hz
		if delayTicks < 1 {
			delayTicks = 1
		}
		state.PendingHits = append(state.PendingHits, PendingHit{
			ApplyAtTick: tick + delayTicks,
			AttackerID:  enemy.ID,
			TargetID:    target.UserID,
			Damage:      arch.Damage,
			Anim:        anim,
			IsRanged:    true,
			FromX:       enemy.X,
			FromY:       enemy.Y,
			ToX:         target.X,
			ToY:         target.Y,
		})
		return nil
	}

	return applyPlayerHit(state, dispatcher, enemy.ID, target, arch.Damage, anim, false,
		enemy.X, enemy.Y, target.X, target.Y)
}

// applyPlayerHit aplica dano a um jogador e faz broadcast de OpCombatEvent / OpPlayerDeath.
func applyPlayerHit(
	state *MatchState,
	dispatcher runtime.MatchDispatcher,
	attackerID string,
	target *PlayerState,
	damage int,
	anim string,
	isRanged bool,
	fromX, fromY, toX, toY float64,
) error {
	target.HP -= damage
	if target.HP < 0 {
		target.HP = 0
	}

	evt := combatEventMsg{
		AttackerID: attackerID,
		TargetID:   target.UserID,
		Damage:     damage,
		TargetHP:   target.HP,
		SkillID:    "",
		Anim:       anim,
		IsRanged:   isRanged,
		FromX:      fromX,
		FromY:      fromY,
		ToX:        toX,
		ToY:        toY,
	}
	if err := broadcastJSON(dispatcher, OpCombatEvent, evt); err != nil {
		return fmt.Errorf("broadcast OpCombatEvent: %w", err)
	}

	if target.HP <= 0 {
		target.HP = target.MaxHP
		death := playerDeathMsg{PlayerID: target.UserID}
		if err := broadcastJSON(dispatcher, OpPlayerDeath, death); err != nil {
			return fmt.Errorf("broadcast OpPlayerDeath: %w", err)
		}
	}
	return nil
}

// applyEnemyHit aplica dano a um inimigo e faz broadcast de OpCombatEvent / OpEnemyDeath.
func applyEnemyHit(
	state *MatchState,
	dispatcher runtime.MatchDispatcher,
	attackerID string,
	enemy *EnemyState,
	damage int,
	anim string,
	isRanged bool,
	fromX, fromY, toX, toY float64,
) error {
	enemy.HP -= damage
	if enemy.HP < 0 {
		enemy.HP = 0
	}

	evt := combatEventMsg{
		AttackerID: attackerID,
		TargetID:   enemy.ID,
		Damage:     damage,
		TargetHP:   enemy.HP,
		SkillID:    "",
		Anim:       anim,
		IsRanged:   isRanged,
		FromX:      fromX,
		FromY:      fromY,
		ToX:        toX,
		ToY:        toY,
	}
	if err := broadcastJSON(dispatcher, OpCombatEvent, evt); err != nil {
		return fmt.Errorf("broadcast OpCombatEvent impact: %w", err)
	}

	if enemy.HP <= 0 {
		death := enemyDeathMsg{EnemyID: enemy.ID, KillerID: attackerID}
		if err := broadcastJSON(dispatcher, OpEnemyDeath, death); err != nil {
			return fmt.Errorf("broadcast OpEnemyDeath: %w", err)
		}
		if state.KillerOf == nil {
			state.KillerOf = make(map[string]string)
		}
		state.KillerOf[enemy.ID] = attackerID
		state.KilledEnemies = append(state.KilledEnemies, enemy.ID)
	}
	return nil
}

// ProcessPendingHits aplica hits agendados (projéteis) cujo tick chegou.
// O TargetID pode ser um inimigo (enemy_*) ou um jogador (UUID).
func ProcessPendingHits(
	state *MatchState,
	dispatcher runtime.MatchDispatcher,
	tick int64,
	logger runtime.Logger,
) error {
	if len(state.PendingHits) == 0 {
		return nil
	}
	remaining := state.PendingHits[:0]
	for _, hit := range state.PendingHits {
		if tick < hit.ApplyAtTick {
			remaining = append(remaining, hit)
			continue
		}
		// Tenta resolver como inimigo primeiro.
		if enemy, ok := state.Enemies[hit.TargetID]; ok {
			if enemy.HP > 0 {
				// Hit de impacto: anim vazio + is_ranged=false (sem re-VFX / re-anim).
				if err := applyEnemyHit(state, dispatcher, hit.AttackerID, enemy, hit.Damage, "", false,
					hit.FromX, hit.FromY, enemy.X, enemy.Y); err != nil {
					logger.Error("ProcessPendingHits enemy: %v", err)
				}
			}
			continue
		}
		// Resolve como jogador.
		target, ok := state.Players[hit.TargetID]
		if !ok {
			continue
		}
		// Hit de impacto: anim vazio + is_ranged=false (sem re-VFX / re-anim).
		if err := applyPlayerHit(state, dispatcher, hit.AttackerID, target, hit.Damage, "", false,
			hit.FromX, hit.FromY, target.X, target.Y); err != nil {
			logger.Error("ProcessPendingHits player: %v", err)
		}
	}
	state.PendingHits = remaining
	return nil
}

// ─── Helpers internos ────────────────────────────────────────────────────────

// dist2D calcula a distância euclidiana entre dois pontos no plano XY.
func dist2D(x1, y1, x2, y2 float64) float64 {
	dx := x2 - x1
	dy := y2 - y1
	return math.Sqrt(dx*dx + dy*dy)
}

// nearestPlayerInRange retorna o user_id do jogador mais próximo dentro de maxDist,
// ou "" se nenhum estiver no alcance.
func nearestPlayerInRange(enemy *EnemyState, maxDist float64, state *MatchState) string {
	nearest := ""
	nearestDist := math.MaxFloat64
	for uid, p := range state.Players {
		d := dist2D(enemy.X, enemy.Y, p.X, p.Y)
		if d <= maxDist && d < nearestDist {
			nearest = uid
			nearestDist = d
		}
	}
	return nearest
}

// broadcastJSON serializa v como JSON e faz broadcast para todas as presenças
// com o opcode informado (reliable=true).
func broadcastJSON(dispatcher runtime.MatchDispatcher, opCode int64, v interface{}) error {
	data, err := json.Marshal(v)
	if err != nil {
		return fmt.Errorf("marshal broadcast payload opCode=%d: %w", opCode, err)
	}
	return dispatcher.BroadcastMessage(opCode, data, nil, nil, true)
}

// coneHalfAngleRad é o meio-ângulo do cone de ataque em radianos (~50°).
// Cobre uma área ampla o suficiente para ataques corpo-a-corpo com precisão direcional.
const coneHalfAngleRad = 50.0 * math.Pi / 180.0

// inAttackCone retorna true se o alvo (tx, ty) está dentro do cone de ataque disparado
// da origem (ox, oy) na direção (aimX, aimY).
// Se aim ≈ origem (distância < 0.01), considera tudo dentro do alcance como acerto (fallback).
func inAttackCone(ox, oy, aimX, aimY, tx, ty float64) bool {
	// Vetor de mira.
	adx, ady := aimX-ox, aimY-oy
	alen := math.Sqrt(adx*adx + ady*ady)
	if alen < 0.01 {
		// Sem direção de mira válida: acerta tudo dentro do alcance.
		return true
	}
	adx /= alen
	ady /= alen

	// Vetor até o alvo.
	tdx, tdy := tx-ox, ty-oy
	tlen := math.Sqrt(tdx*tdx + tdy*tdy)
	if tlen < 0.001 {
		// Alvo na mesma posição: acerta.
		return true
	}
	tdx /= tlen
	tdy /= tlen

	// dot = cos(ângulo entre aim e alvo). Acerta se ≥ cos(halfAngle).
	dot := adx*tdx + ady*tdy
	if dot > 1.0 {
		dot = 1.0 // clamp por segurança de ponto flutuante
	}
	return dot >= math.Cos(coneHalfAngleRad)
}
