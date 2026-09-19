package match

// enemy_gen.go — Fase 6: gerador automático de inimigos LPC por seed determinística.
//
// Responsabilidades:
//   - Definir os 6 SpawnPoints distribuídos no porão da Alvida.
//   - Gerar AppearanceDef determinística a partir de hash(matchID + spawnIndex + respawnCount).
//   - Spawn inicial de todos os inimigos no MatchInit.
//   - Respawn individual com nova aparência e HP restaurado.

import (
	"encoding/json"
	"fmt"
	"hash/fnv"
	"math/rand"

	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/op-mmo/alvida-hold/content"
)

// ─── Spawn points ────────────────────────────────────────────────────────────

// SpawnPoint descreve um ponto de spawn no mapa do porão.
type SpawnPoint struct {
	Index int
	X     float64
	Y     float64
}

// SpawnPoints são os 6 pontos fixos de spawn distribuídos no porão da Alvida.
// Coordenadas entre 5 e 45 para manter afastamento das paredes (mapa 50×50).
var SpawnPoints = []SpawnPoint{
	{Index: 0, X: 8.0, Y: 10.0},
	{Index: 1, X: 25.0, Y: 8.0},
	{Index: 2, X: 42.0, Y: 10.0},
	{Index: 3, X: 8.0, Y: 40.0},
	{Index: 4, X: 25.0, Y: 42.0},
	{Index: 5, X: 42.0, Y: 40.0},
}

// ─── LPC catalog loader ──────────────────────────────────────────────────────

// lpcCatalogFile é a estrutura interna para parsear lpc_catalog.json.
type lpcCatalogFile struct {
	Catalog struct {
		Bodies  []string `json:"bodies"`
		Hairs   []string `json:"hairs"`
		Outfits []string `json:"outfits"`
		Weapons []string `json:"weapons"`
	} `json:"catalog"`
}

// LoadLPCCatalog lê lpc_catalog.json embutido em compile-time e retorna
// as listas de bodies, hairs, outfits e weapons disponíveis.
func LoadLPCCatalog() (bodies, hairs, outfits, weapons []string, err error) {
	var f lpcCatalogFile
	if err = json.Unmarshal(content.LPCCatalogJSON, &f); err != nil {
		return nil, nil, nil, nil, fmt.Errorf("parse lpc_catalog.json: %w", err)
	}
	return f.Catalog.Bodies, f.Catalog.Hairs, f.Catalog.Outfits, f.Catalog.Weapons, nil
}

// ─── Geração de aparência ────────────────────────────────────────────────────

// GenerateEnemyAppearance produz um AppearanceDef determinístico baseado em
// hash(matchID + spawnIndex + respawnCount). O mesmo conjunto de parâmetros
// sempre gera a mesma aparência; incrementar respawnCount muda o visual.
//
// Parâmetros:
//   - matchID:      ID único do match (evita colisão entre matches).
//   - spawnIndex:   índice do spawn point (0–5).
//   - respawnCount: quantas vezes este inimigo já ressurgiu.
//   - bodies, hairs, outfits, weapons: fatias do catálogo LPC.
func GenerateEnemyAppearance(
	matchID string,
	spawnIndex int,
	respawnCount int,
	bodies, hairs, outfits, weapons []string,
) AppearanceDef {
	// Seed determinística via FNV-1a.
	h := fnv.New64a()
	h.Write([]byte(fmt.Sprintf("%s:%d:%d", matchID, spawnIndex, respawnCount)))
	seed := int64(h.Sum64()) //nolint:gosec // hash de string de jogo, não criptográfico

	r := rand.New(rand.NewSource(seed)) //nolint:gosec

	// Garante fallbacks caso o catálogo esteja vazio.
	body := pickRandom(r, bodies, "body_male_light")
	hair := pickRandom(r, hairs, "hair_short_brown")
	outfit := pickRandom(r, outfits, "outfit_pirate_a")
	weapon := pickRandom(r, weapons, "weapon_none")

	// Tom de pele: matiz 20–50 (warm/brownish), saturação 40–80%, luminosidade 40–70%.
	skinHue := 20.0 + r.Float64()*30.0
	skinSat := 0.40 + r.Float64()*0.40
	skinLit := 0.40 + r.Float64()*0.30
	bodyTint := hslToHex(skinHue, skinSat, skinLit)

	// Cor de cabelo: matiz livre 0–360°.
	hairHue := r.Float64() * 360.0
	hairSat := 0.30 + r.Float64()*0.50
	hairLit := 0.20 + r.Float64()*0.40
	hairTint := hslToHex(hairHue, hairSat, hairLit)

	return AppearanceDef{
		Body:        body,
		Hair:        hair,
		Outfit:      outfit,
		WeaponLayer: weapon,
		BodyTint:    bodyTint,
		HairTint:    hairTint,
	}
}

// pickRandom retorna um elemento aleatório da fatia usando r, ou fallback se vazia.
func pickRandom(r *rand.Rand, slice []string, fallback string) string {
	if len(slice) == 0 {
		return fallback
	}
	return slice[r.Intn(len(slice))]
}

// ─── Conversão HSL → Hex ─────────────────────────────────────────────────────

// hslToHex converte HSL (h em graus 0–360, s e l em 0–1) para string "#RRGGBB".
func hslToHex(h, s, l float64) string {
	r, g, b := hslToRGB(h, s, l)
	return fmt.Sprintf("#%02X%02X%02X", r, g, b)
}

func hslToRGB(h, s, l float64) (uint8, uint8, uint8) {
	if s == 0 {
		v := uint8(clampF(l, 0, 1) * 255)
		return v, v, v
	}
	var q float64
	if l < 0.5 {
		q = l * (1 + s)
	} else {
		q = l + s - l*s
	}
	p := 2*l - q
	hNorm := h / 360.0
	rf := hueToRGBComponent(p, q, hNorm+1.0/3.0)
	gf := hueToRGBComponent(p, q, hNorm)
	bf := hueToRGBComponent(p, q, hNorm-1.0/3.0)
	return uint8(rf * 255), uint8(gf * 255), uint8(bf * 255)
}

func hueToRGBComponent(p, q, t float64) float64 {
	if t < 0 {
		t++
	}
	if t > 1 {
		t--
	}
	switch {
	case t < 1.0/6.0:
		return p + (q-p)*6*t
	case t < 1.0/2.0:
		return q
	case t < 2.0/3.0:
		return p + (q-p)*(2.0/3.0-t)*6
	default:
		return p
	}
}

// ─── enemySpawnMsg ────────────────────────────────────────────────────────────

// enemySpawnMsg é o payload de OpEnemySpawn enviado para todos os clientes.
type enemySpawnMsg struct {
	EnemyID    string        `json:"enemy_id"`
	Archetype  string        `json:"archetype"`
	Appearance AppearanceDef `json:"appearance"`
	X          float64       `json:"x"`
	Y          float64       `json:"y"`
	HP         int           `json:"hp"`
	MaxHP      int           `json:"max_hp"`
}

// ─── SpawnAllEnemies ──────────────────────────────────────────────────────────

// SpawnAllEnemies popula state.Enemies com os 6 inimigos iniciais.
// Se dispatcher não for nil, faz broadcast de OpEnemySpawn para todos.
// Quando chamado do MatchInit (dispatcher=nil), apenas popula o estado;
// o broadcast ocorre via BroadcastAllEnemySpawns quando players entram.
//
// Archetypes alternados: índices pares → goon_melee, ímpares → goon_ranged_weak.
func SpawnAllEnemies(state *MatchState, dispatcher runtime.MatchDispatcher, logger runtime.Logger) error {
	archetypeIDs := []string{"goon_melee", "goon_ranged_weak"}

	for _, sp := range SpawnPoints {
		archetypeID := archetypeIDs[sp.Index%2]
		arch, ok := state.Archetypes[archetypeID]
		if !ok {
			logger.Warn("SpawnAllEnemies: archetype %q não encontrado, pulando spawn %d", archetypeID, sp.Index)
			continue
		}

		enemyID := fmt.Sprintf("enemy_%d", sp.Index)
		appearance := GenerateEnemyAppearance(
			state.MatchID, sp.Index, 0,
			state.LPCBodies, state.LPCHairs, state.LPCOutfits, state.LPCWeapons,
		)
		// Inimigos ranged sempre carregam o arco de madeira.
		if arch.IsRanged {
			appearance.WeaponLayer = "weapon_bow_wood"
		}

		enemy := &EnemyState{
			ID:           enemyID,
			Archetype:    archetypeID,
			HP:           arch.MaxHP,
			MaxHP:        arch.MaxHP,
			X:            sp.X,
			Y:            sp.Y,
			AIState:      "Wander",
			SpawnIndex:   sp.Index,
			SpawnX:       sp.X,
			SpawnY:       sp.Y,
			RespawnCount: 0,
			Appearance:   appearance,
		}
		state.Enemies[enemyID] = enemy

		// Broadcast opcional (dispatcher é nil durante o MatchInit).
		if dispatcher != nil {
			msg := enemySpawnMsg{
				EnemyID:    enemyID,
				Archetype:  archetypeID,
				Appearance: appearance,
				X:          sp.X,
				Y:          sp.Y,
				HP:         arch.MaxHP,
				MaxHP:      arch.MaxHP,
			}
			if err := broadcastJSON(dispatcher, OpEnemySpawn, msg); err != nil {
				logger.Error("SpawnAllEnemies broadcast enemy=%s: %v", enemyID, err)
			}
		}

		logger.Info("Spawned enemy=%s archetype=%s pos=(%.1f,%.1f)", enemyID, archetypeID, sp.X, sp.Y)
	}
	return nil
}

// ─── RespawnEnemy ─────────────────────────────────────────────────────────────

// RespawnEnemy restaura um inimigo morto: incrementa RespawnCount (gerando nova
// aparência), restaura HP máximo e posição original, redefine estado para Wander
// e faz broadcast de OpEnemySpawn com os novos dados visuais.
func RespawnEnemy(state *MatchState, enemyID string, dispatcher runtime.MatchDispatcher, logger runtime.Logger) error {
	enemy, ok := state.Enemies[enemyID]
	if !ok {
		return fmt.Errorf("RespawnEnemy: inimigo %q não encontrado no estado", enemyID)
	}

	arch, ok := state.Archetypes[enemy.Archetype]
	if !ok {
		return fmt.Errorf("RespawnEnemy: archetype %q não encontrado", enemy.Archetype)
	}

	// Nova aparência via seed que incorpora o contador de respawns.
	enemy.RespawnCount++
	newAppearance := GenerateEnemyAppearance(
		state.MatchID, enemy.SpawnIndex, enemy.RespawnCount,
		state.LPCBodies, state.LPCHairs, state.LPCOutfits, state.LPCWeapons,
	)
	// Inimigos ranged sempre carregam o arco de madeira.
	if arch.IsRanged {
		newAppearance.WeaponLayer = "weapon_bow_wood"
	}

	// Restaura estado completo.
	enemy.HP = arch.MaxHP
	enemy.MaxHP = arch.MaxHP
	enemy.X = enemy.SpawnX
	enemy.Y = enemy.SpawnY
	enemy.AIState = "Wander"
	enemy.TargetID = ""
	enemy.LastAttackTick = 0
	enemy.Appearance = newAppearance

	msg := enemySpawnMsg{
		EnemyID:    enemy.ID,
		Archetype:  enemy.Archetype,
		Appearance: newAppearance,
		X:          enemy.X,
		Y:          enemy.Y,
		HP:         enemy.HP,
		MaxHP:      enemy.MaxHP,
	}
	if err := broadcastJSON(dispatcher, OpEnemySpawn, msg); err != nil {
		return fmt.Errorf("RespawnEnemy broadcast OpEnemySpawn: %w", err)
	}

	logger.Info("Respawned enemy=%s (respawnCount=%d) archetype=%s pos=(%.1f,%.1f)",
		enemyID, enemy.RespawnCount, enemy.Archetype, enemy.X, enemy.Y)
	return nil
}

// BroadcastAllEnemySpawns envia OpEnemySpawn de todos os inimigos existentes
// para uma lista específica de presenças (usado quando um player entra no match).
func BroadcastAllEnemySpawns(state *MatchState, targets []runtime.Presence, dispatcher runtime.MatchDispatcher, logger runtime.Logger) {
	for _, enemy := range state.Enemies {
		if enemy.HP <= 0 {
			continue // inimigo já morto aguardando respawn — não envia
		}
		msg := enemySpawnMsg{
			EnemyID:    enemy.ID,
			Archetype:  enemy.Archetype,
			Appearance: enemy.Appearance,
			X:          enemy.X,
			Y:          enemy.Y,
			HP:         enemy.HP,
			MaxHP:      enemy.MaxHP,
		}
		data, err := json.Marshal(msg)
		if err != nil {
			logger.Error("BroadcastAllEnemySpawns marshal enemy=%s: %v", enemy.ID, err)
			continue
		}
		if err := dispatcher.BroadcastMessage(OpEnemySpawn, data, targets, nil, true); err != nil {
			logger.Error("BroadcastAllEnemySpawns broadcast enemy=%s: %v", enemy.ID, err)
		}
	}
}
