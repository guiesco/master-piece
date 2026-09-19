package match

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/op-mmo/alvida-hold/profile"
)

const matchLabel = "AlvidaHold_01"

// defaultSpawnX / Y: centre of the 50×50 map.
const (
	defaultSpawnX = 25.0
	defaultSpawnY = 25.0
)

// AlvidaHoldMatch implements runtime.Match for the Alvida Hold dungeon.
type AlvidaHoldMatch struct{}

// MatchInit initialises state and sets the tick rate to 20 Hz.
// Fase 4: carrega archetypes.json e skills.json via embed no MatchState.
// Fase 6: carrega lpc_catalog.json e spawna os 6 inimigos iniciais.
func (m *AlvidaHoldMatch) MatchInit(
	ctx context.Context,
	logger runtime.Logger,
	db *sql.DB,
	nk runtime.NakamaModule,
	params map[string]interface{},
) (interface{}, int, string) {

	archetypes, err := LoadArchetypes()
	if err != nil {
		logger.Error("MatchInit LoadArchetypes: %v — usando mapa vazio", err)
		archetypes = make(map[string]Archetype)
	}

	skills, err := LoadSkills()
	if err != nil {
		logger.Error("MatchInit LoadSkills: %v — usando mapa vazio", err)
		skills = make(map[string]Skill)
	}

	// Fase 5: carrega tabela de armas equipáveis.
	equipWeapons, err := LoadWeapons()
	if err != nil {
		logger.Error("MatchInit LoadWeapons: %v — usando mapa vazio", err)
		equipWeapons = make(map[string]Weapon)
	}

	// Fase 6: carrega catálogo LPC para geração de aparência por seed.
	lpcBodies, lpcHairs, lpcOutfits, lpcWeaponSprites, err := LoadLPCCatalog()
	if err != nil {
		logger.Error("MatchInit LoadLPCCatalog: %v — usando catálogo vazio", err)
	}

	// ID único do match — usa nanosegundos como entropia garantida por instância.
	matchID := fmt.Sprintf("match_%d", time.Now().UnixNano())

	state := &MatchState{
		Players:       make(map[string]*PlayerState),
		Enemies:       make(map[string]*EnemyState),
		Archetypes:    archetypes,
		Skills:        skills,
		Weapons:       equipWeapons,
		KillerOf:      make(map[string]string),
		MatchID:       matchID,
		LPCBodies:     lpcBodies,
		LPCHairs:      lpcHairs,
		LPCOutfits:    lpcOutfits,
		LPCWeapons:    lpcWeaponSprites,
		RespawnQueue:  make(map[int64][]string),
		KilledEnemies: []string{},
		PendingHits:   []PendingHit{},
	}

	logger.Info("AlvidaHold MatchInit: %d archetypes, %d skills, %d weapons, %d bodies LPC carregados",
		len(archetypes), len(skills), len(equipWeapons), len(lpcBodies))

	// Fase 6: spawna todos os inimigos iniciais (broadcast vazio pois sem players ainda).
	if err := SpawnAllEnemies(state, nil, logger); err != nil {
		logger.Error("MatchInit SpawnAllEnemies: %v", err)
	}

	return state, 20, matchLabel // 20 Hz tick rate
}

// MatchJoinAttempt always accepts new presences (no password / capacity check).
func (m *AlvidaHoldMatch) MatchJoinAttempt(
	ctx context.Context,
	logger runtime.Logger,
	db *sql.DB,
	nk runtime.NakamaModule,
	dispatcher runtime.MatchDispatcher,
	tick int64,
	state interface{},
	presence runtime.Presence,
	metadata map[string]string,
) (interface{}, bool, string) {
	return state, true, ""
}

// MatchJoin creates a PlayerState for each arriving presence, loads its Storage
// profile and broadcasts OpPlayerJoined so every client can render the newcomer.
func (m *AlvidaHoldMatch) MatchJoin(
	ctx context.Context,
	logger runtime.Logger,
	db *sql.DB,
	nk runtime.NakamaModule,
	dispatcher runtime.MatchDispatcher,
	tick int64,
	state interface{},
	presences []runtime.Presence,
) interface{} {
	ms := state.(*MatchState)

	for _, presence := range presences {
		userID := presence.GetUserId()

		// Determina o slot ativo do jogador; padrão é 0 em caso de erro.
		activeSlot, slotErr := profile.GetActiveSlot(ctx, nk, userID)
		if slotErr != nil {
			logger.Warn("MatchJoin GetActiveSlot user=%s: %v — usando slot 0", userID, slotErr)
			activeSlot = 0
		}

		// Carrega o perfil do slot ativo. Cai em GetOrCreateProfile (legado) se vazio.
		p, err := profile.GetCharacterSlot(ctx, nk, userID, activeSlot)
		if err != nil {
			logger.Warn("MatchJoin GetCharacterSlot slot=%d user=%s: %v — fallback legado", activeSlot, userID, err)
			p = nil
		}
		if p == nil {
			p, err = profile.GetOrCreateProfile(ctx, logger, nk, userID)
			if err != nil {
				logger.Error("MatchJoin GetOrCreateProfile failed user=%s: %v", userID, err)
				p = profile.DefaultProfile()
			}
		}

		// HP máximo: 100 + Força×5 (Fase 4).
		maxHP := 100 + p.Stats.Strength*5

		inv := p.Inventory
		if inv == nil {
			inv = []string{}
		}

		// Recalcula WeaponLayer se o jogador já tem arma equipada.
		weaponLayer := ""
		if p.Equipped != "" {
			if w, wok := ms.Weapons[p.Equipped]; wok {
				weaponLayer = w.LPCLayer
			}
		}

		// Usa aparência salva no perfil (ou defaults se profile for novo).
		savedAppearance := AppearanceDef{
			Body:        "body_male_light",
			Hair:        "hair_short_brown",
			Outfit:      "outfit_pirate_a",
			WeaponLayer: weaponLayer,
			BodyTint:    "#CCAA88",
			HairTint:    "#3B2314",
		}
		if p.Appearance.Body != "" {
			savedAppearance = AppearanceDef{
				Body:        p.Appearance.Body,
				Hair:        p.Appearance.Hair,
				Outfit:      p.Appearance.Outfit,
				WeaponLayer: weaponLayer, // weapon_layer vem do item equipado, não da aparência salva
				BodyTint:    p.Appearance.BodyTint,
				HairTint:    p.Appearance.HairTint,
			}
		}

		ps := &PlayerState{
			UserID:     userID,
			X:          defaultSpawnX,
			Y:          defaultSpawnY,
			Level:      p.Level,
			XP:         p.XP,
			Stats:      Stats(p.Stats),
			Equipped:   p.Equipped,
			Appearance: savedAppearance,
			HP:                maxHP,
			MaxHP:             maxHP,
			SkillCooldowns:    make(map[string]int64),
			Inventory:         inv,
			PendingStatPoints: p.PendingStatPoints,
			CharacterSlot:     activeSlot,
			CharacterName:     p.Name,
		}
		ms.Players[userID] = ps

		// Notify all presences (including newcomer) that this player joined.
		data, err := json.Marshal(ps)
		if err != nil {
			logger.Error("MatchJoin marshal PlayerState: %v", err)
			continue
		}
		if err := dispatcher.BroadcastMessage(OpPlayerJoined, data, nil, nil, true); err != nil {
			logger.Error("MatchJoin broadcast OpPlayerJoined: %v", err)
		}

		// Send the newcomer the current state of every already-connected player.
		for uid, existing := range ms.Players {
			if uid == userID {
				continue // already sent above
			}
			existingData, err := json.Marshal(existing)
			if err != nil {
				continue
			}
			// Send only to the single arriving presence.
			if err := dispatcher.BroadcastMessage(OpPlayerJoined, existingData, []runtime.Presence{presence}, nil, true); err != nil {
				logger.Error("MatchJoin send existing player to newcomer: %v", err)
			}
		}

		// Fase 6: envia OpEnemySpawn de todos os inimigos vivos para o recém-chegado.
		BroadcastAllEnemySpawns(ms, []runtime.Presence{presence}, dispatcher, logger)

		logger.Info("Player joined AlvidaHold: %s (level %d, maxHP %d)", userID, ps.Level, maxHP)
	}

	return ms
}

// MatchLeave removes departed presences from state and notifies remaining players.
func (m *AlvidaHoldMatch) MatchLeave(
	ctx context.Context,
	logger runtime.Logger,
	db *sql.DB,
	nk runtime.NakamaModule,
	dispatcher runtime.MatchDispatcher,
	tick int64,
	state interface{},
	presences []runtime.Presence,
) interface{} {
	ms := state.(*MatchState)

	for _, presence := range presences {
		userID := presence.GetUserId()
		delete(ms.Players, userID)

		payload, _ := json.Marshal(map[string]string{"player_id": userID})
		if err := dispatcher.BroadcastMessage(OpPlayerLeft, payload, nil, nil, true); err != nil {
			logger.Error("MatchLeave broadcast OpPlayerLeft: %v", err)
		}

		logger.Info("Player left AlvidaHold: %s", userID)
	}

	return ms
}

// MatchLoop runs every ~50 ms (20 Hz).
// Ordem: movimento → combate → IA dos inimigos.
func (m *AlvidaHoldMatch) MatchLoop(
	ctx context.Context,
	logger runtime.Logger,
	db *sql.DB,
	nk runtime.NakamaModule,
	dispatcher runtime.MatchDispatcher,
	tick int64,
	state interface{},
	messages []runtime.MatchData,
) interface{} {
	ms := state.(*MatchState)

	// Set match label once (requires dispatcher, not available in MatchInit).
	if !ms.LabelSet {
		if err := dispatcher.MatchLabelUpdate(matchLabel); err != nil {
			logger.Error("MatchLabelUpdate: %v", err)
		} else {
			ms.LabelSet = true
		}
	}

	// ── Fase 1: movimento | Fase 5: equip e alocação de atributo ────────────
	for _, msg := range messages {
		switch msg.GetOpCode() {
		case OpMove:
			if err := HandleMovement(ctx, logger, dispatcher, ms, msg); err != nil {
				logger.Error("HandleMovement tick=%d: %v", tick, err)
			}
		case OpAttack:
			// Processado em lote por HandleCombat abaixo.
		case OpAllocateStat:
			if err := HandleAllocateStat(ms, msg, dispatcher, nk, ctx, logger); err != nil {
				logger.Error("HandleAllocateStat tick=%d user=%s: %v", tick, msg.GetUserId(), err)
			}
		case OpEquip:
			if err := HandleEquip(ms, msg, dispatcher, logger); err != nil {
				logger.Error("HandleEquip tick=%d user=%s: %v", tick, msg.GetUserId(), err)
			}
		default:
			logger.Debug("Unhandled opCode=%d from user=%s", msg.GetOpCode(), msg.GetUserId())
		}
	}

	// ── Fase 4: combate (player → inimigo) ──────────────────────────────────
	if err := HandleCombat(ms, messages, dispatcher, tick, logger); err != nil {
		logger.Error("HandleCombat tick=%d: %v", tick, err)
	}

	// ── Fase 5: progressão XP/loot para inimigos mortos neste tick ──────────
	if len(ms.KilledEnemies) > 0 {
		// Agrupa inimigos mortos por matador.
		killerGroups := make(map[string][]string)
		for _, eid := range ms.KilledEnemies {
			if killer, ok := ms.KillerOf[eid]; ok && killer != "" {
				killerGroups[killer] = append(killerGroups[killer], eid)
			}
		}
		for killerID, enemyIDs := range killerGroups {
			if err := HandleProgression(ms, enemyIDs, killerID, dispatcher, nk, ctx, logger); err != nil {
				logger.Error("HandleProgression tick=%d killer=%s: %v", tick, killerID, err)
			}
		}
		// Limpa KillerOf dos inimigos processados.
		for _, eid := range ms.KilledEnemies {
			delete(ms.KillerOf, eid)
		}
	}

	// ── Fase 4: IA dos inimigos ──────────────────────────────────────────────
	if err := TickAI(ms, tick, dispatcher, logger); err != nil {
		logger.Error("TickAI tick=%d: %v", tick, err)
	}

	// ── Projéteis: aplicar hits agendados ─────────────────────────────────────
	if err := ProcessPendingHits(ms, dispatcher, tick, logger); err != nil {
		logger.Error("ProcessPendingHits tick=%d: %v", tick, err)
	}

	// ── Fase 6: agendar respawn de inimigos mortos neste tick ────────────────
	// Drena KilledEnemies populado pelo HandleCombat e agenda cada um
	// para ressurgir em 100 ticks (≈ 5 s a 20 Hz).
	const respawnDelayTicks int64 = 100
	for _, eid := range ms.KilledEnemies {
		targetTick := tick + respawnDelayTicks
		ms.RespawnQueue[targetTick] = append(ms.RespawnQueue[targetTick], eid)
		logger.Info("Respawn agendado: enemy=%s no tick %d", eid, targetTick)
	}
	ms.KilledEnemies = ms.KilledEnemies[:0] // limpa sem realocar

	// ── Fase 6: processar respawns prontos ───────────────────────────────────
	for targetTick, eids := range ms.RespawnQueue {
		if tick >= targetTick {
			for _, eid := range eids {
				if err := RespawnEnemy(ms, eid, dispatcher, logger); err != nil {
					logger.Error("RespawnEnemy tick=%d enemy=%s: %v", tick, eid, err)
				}
			}
			delete(ms.RespawnQueue, targetTick)
		}
	}

	return ms
}

// MatchSignal handles out-of-band server signals (unused in Phase 1).
func (m *AlvidaHoldMatch) MatchSignal(
	ctx context.Context,
	logger runtime.Logger,
	db *sql.DB,
	nk runtime.NakamaModule,
	dispatcher runtime.MatchDispatcher,
	tick int64,
	state interface{},
	data string,
) (interface{}, string) {
	return state, ""
}

// MatchTerminate is called when the match is shut down (no connected players or
// server request). Logs the event; no cleanup required in Phase 1.
func (m *AlvidaHoldMatch) MatchTerminate(
	ctx context.Context,
	logger runtime.Logger,
	db *sql.DB,
	nk runtime.NakamaModule,
	dispatcher runtime.MatchDispatcher,
	tick int64,
	state interface{},
	graceSeconds int,
) interface{} {
	logger.Info("AlvidaHold match terminating, graceSeconds=%d", graceSeconds)
	return state
}
