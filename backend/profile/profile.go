package profile

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

const (
	collectionPlayerProfiles = "player_profiles"
	keyProfile               = "profile"

	// collectionCharacters / keyAccount — sistema de 3 slots de personagem.
	collectionCharacters = "characters"
	keyAccount           = "account"

	// NumCharacterSlots é o número máximo de personagens por conta.
	NumCharacterSlots = 3
)

// ProfileStats mirrors match.Stats but lives in the profile package to avoid
// import cycles (match imports profile, not the other way around).
type ProfileStats struct {
	Strength     int `json:"strength"`
	Agility      int `json:"agility"`
	Intelligence int `json:"intelligence"`
}

// AppearanceData contém as camadas visuais LPC do personagem, persistidas no Storage.
type AppearanceData struct {
	Body        string `json:"body"`
	Hair        string `json:"hair"`
	Outfit      string `json:"outfit"`
	WeaponLayer string `json:"weapon_layer,omitempty"`
	BodyTint    string `json:"body_tint"`
	HairTint    string `json:"hair_tint"`
}

// PlayerProfile is persisted in Nakama Storage under
// collection="player_profiles" / key="profile" (legacy) OR
// collection="characters" / key="slot_N" (multi-slot, new).
type PlayerProfile struct {
	Level             int            `json:"level"`
	XP                int            `json:"xp"`
	Stats             ProfileStats   `json:"stats"`
	Inventory         []string       `json:"inventory"`
	Equipped          string         `json:"equipped"`
	PendingStatPoints int            `json:"pending_stat_points"` // Fase 5: pontos de atributo não alocados
	Appearance        AppearanceData `json:"appearance"`           // Fase 7: aparência LPC persistida

	// Campos de multi-slot (adicionados no sistema de 3 personagens).
	Name      string `json:"name,omitempty"`       // nome do personagem
	Slot      int    `json:"slot,omitempty"`       // índice do slot (0–2)
	UpdatedAt int64  `json:"updated_at,omitempty"` // Unix timestamp da última gravação
}

// ActiveSlotRecord é gravado em characters/account para rastrear o slot ativo.
type ActiveSlotRecord struct {
	ActiveSlot int `json:"active_slot"`
}

// DefaultProfile returns a brand-new Level 1 profile with balanced base stats.
func DefaultProfile() *PlayerProfile {
	return &PlayerProfile{
		Level: 1,
		XP:    0,
		Stats: ProfileStats{
			Strength:     5,
			Agility:      5,
			Intelligence: 5,
		},
		Inventory: []string{},
		Equipped:  "",
		Appearance: AppearanceData{
			Body:     "body_male_light",
			Hair:     "hair_short_brown",
			Outfit:   "outfit_pirate_a",
			BodyTint: "#CCAA88",
			HairTint: "#3B2314",
		},
	}
}

// GetOrCreateProfile reads the player's profile from Nakama Storage.
// If no record exists, it writes and returns a DefaultProfile.
func GetOrCreateProfile(
	ctx context.Context,
	logger runtime.Logger,
	nk runtime.NakamaModule,
	userID string,
) (*PlayerProfile, error) {
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{
		{
			Collection: collectionPlayerProfiles,
			Key:        keyProfile,
			UserID:     userID,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("StorageRead profile user=%s: %w", userID, err)
	}

	if len(objects) > 0 {
		var p PlayerProfile
		if err := json.Unmarshal([]byte(objects[0].Value), &p); err != nil {
			return nil, fmt.Errorf("unmarshal profile user=%s: %w", userID, err)
		}
		return &p, nil
	}

	// First login — create and persist the default profile.
	p := DefaultProfile()
	if err := SaveProfile(ctx, nk, userID, p); err != nil {
		return nil, err
	}

	logger.Info("Created default profile for user=%s", userID)
	return p, nil
}

// SaveProfile serialises the profile and upserts it into Nakama Storage.
// Owner-only read/write permissions (1/1).
func SaveProfile(
	ctx context.Context,
	nk runtime.NakamaModule,
	userID string,
	p *PlayerProfile,
) error {
	data, err := json.Marshal(p)
	if err != nil {
		return fmt.Errorf("marshal profile user=%s: %w", userID, err)
	}

	_, err = nk.StorageWrite(ctx, []*runtime.StorageWrite{
		{
			Collection:      collectionPlayerProfiles,
			Key:             keyProfile,
			UserID:          userID,
			Value:           string(data),
			PermissionRead:  1, // owner read
			PermissionWrite: 1, // owner write
		},
	})
	if err != nil {
		return fmt.Errorf("StorageWrite profile user=%s: %w", userID, err)
	}

	return nil
}

// RpcGetOrCreateProfile is the handler for the "rpc_get_or_create_profile" RPC.
// It returns the player's current profile as a JSON string.
func RpcGetOrCreateProfile(
	ctx context.Context,
	logger runtime.Logger,
	nk runtime.NakamaModule,
	_ string, // payload unused
) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("unauthenticated", 16)
	}

	p, err := GetOrCreateProfile(ctx, logger, nk, userID)
	if err != nil {
		return "", err
	}

	out, err := json.Marshal(p)
	if err != nil {
		return "", fmt.Errorf("marshal rpc response: %w", err)
	}

	return string(out), nil
}

// ─── Helpers de multi-slot ────────────────────────────────────────────────────

// slotKey retorna a chave de Storage para o slot N (e.g. "slot_0").
func slotKey(slot int) string {
	return fmt.Sprintf("slot_%d", slot)
}

// GetActiveSlot lê o slot ativo da conta. Retorna 0 se não estiver definido.
func GetActiveSlot(ctx context.Context, nk runtime.NakamaModule, userID string) (int, error) {
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{
		Collection: collectionCharacters,
		Key:        keyAccount,
		UserID:     userID,
	}})
	if err != nil {
		return 0, fmt.Errorf("StorageRead active_slot user=%s: %w", userID, err)
	}
	if len(objects) == 0 {
		return 0, nil
	}
	var rec ActiveSlotRecord
	if err := json.Unmarshal([]byte(objects[0].Value), &rec); err != nil {
		return 0, nil // registro corrompido → fallback 0
	}
	return rec.ActiveSlot, nil
}

// SetActiveSlot grava o slot ativo no Storage.
func SetActiveSlot(ctx context.Context, nk runtime.NakamaModule, userID string, slot int) error {
	data, _ := json.Marshal(ActiveSlotRecord{ActiveSlot: slot})
	_, err := nk.StorageWrite(ctx, []*runtime.StorageWrite{{
		Collection:      collectionCharacters,
		Key:             keyAccount,
		UserID:          userID,
		Value:           string(data),
		PermissionRead:  1,
		PermissionWrite: 1,
	}})
	if err != nil {
		return fmt.Errorf("StorageWrite active_slot user=%s: %w", userID, err)
	}
	return nil
}

// GetCharacterSlot lê um slot de personagem. Retorna nil, nil se o slot estiver vazio.
func GetCharacterSlot(ctx context.Context, nk runtime.NakamaModule, userID string, slot int) (*PlayerProfile, error) {
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{
		Collection: collectionCharacters,
		Key:        slotKey(slot),
		UserID:     userID,
	}})
	if err != nil {
		return nil, fmt.Errorf("StorageRead slot=%d user=%s: %w", slot, userID, err)
	}
	if len(objects) == 0 {
		return nil, nil
	}
	var p PlayerProfile
	if err := json.Unmarshal([]byte(objects[0].Value), &p); err != nil {
		return nil, fmt.Errorf("unmarshal slot=%d user=%s: %w", slot, userID, err)
	}
	return &p, nil
}

// SaveCharacterSlot persiste um PlayerProfile no slot especificado da coleção "characters".
func SaveCharacterSlot(ctx context.Context, nk runtime.NakamaModule, userID string, slot int, p *PlayerProfile) error {
	p.Slot = slot
	p.UpdatedAt = time.Now().Unix()
	data, err := json.Marshal(p)
	if err != nil {
		return fmt.Errorf("marshal slot=%d user=%s: %w", slot, userID, err)
	}
	_, err = nk.StorageWrite(ctx, []*runtime.StorageWrite{{
		Collection:      collectionCharacters,
		Key:             slotKey(slot),
		UserID:          userID,
		Value:           string(data),
		PermissionRead:  1,
		PermissionWrite: 1,
	}})
	if err != nil {
		return fmt.Errorf("StorageWrite slot=%d user=%s: %w", slot, userID, err)
	}
	return nil
}

// ─── RPCs de multi-slot ───────────────────────────────────────────────────────

// RpcListCharacters lista os 3 slots de personagem do jogador.
// Realiza migração automática do perfil legado (player_profiles/profile → slot_0)
// se nenhum slot existir ainda.
// Resposta: { "slots": [ null | { slot, name, level, appearance }, ... ] }
func RpcListCharacters(ctx context.Context, logger runtime.Logger, nk runtime.NakamaModule, _ string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("unauthenticated", 16)
	}

	// Lê todos os 3 slots em lote.
	reads := make([]*runtime.StorageRead, NumCharacterSlots)
	for i := range reads {
		reads[i] = &runtime.StorageRead{
			Collection: collectionCharacters,
			Key:        slotKey(i),
			UserID:     userID,
		}
	}
	objects, err := nk.StorageRead(ctx, reads)
	if err != nil {
		return "", fmt.Errorf("StorageRead characters user=%s: %w", userID, err)
	}

	slotMap := make(map[string]*PlayerProfile, NumCharacterSlots)
	for _, obj := range objects {
		var p PlayerProfile
		if jsonErr := json.Unmarshal([]byte(obj.Value), &p); jsonErr == nil {
			slotMap[obj.Key] = &p
		}
	}

	// Migração: se todos os slots estão vazios, importar perfil legado para slot_0.
	if len(slotMap) == 0 {
		legacy, legacyErr := GetOrCreateProfile(ctx, logger, nk, userID)
		if legacyErr == nil && legacy != nil {
			legacy.Slot = 0
			if legacy.Name == "" {
				legacy.Name = "Captain"
			}
			if saveErr := SaveCharacterSlot(ctx, nk, userID, 0, legacy); saveErr != nil {
				logger.Warn("RpcListCharacters migrate slot_0 user=%s: %v", userID, saveErr)
			} else {
				slotMap[slotKey(0)] = legacy
				logger.Info("Perfil legado migrado para slot_0 user=%s", userID)
			}
		}
	}

	// Constrói resposta: array de 3 elementos (null ou resumo).
	type SlotSummary struct {
		Slot       int            `json:"slot"`
		Name       string         `json:"name"`
		Level      int            `json:"level"`
		Appearance AppearanceData `json:"appearance"`
	}
	slots := make([]*SlotSummary, NumCharacterSlots)
	for i := 0; i < NumCharacterSlots; i++ {
		if p, exists := slotMap[slotKey(i)]; exists {
			slots[i] = &SlotSummary{
				Slot:       i,
				Name:       p.Name,
				Level:      p.Level,
				Appearance: p.Appearance,
			}
		}
	}

	out, _ := json.Marshal(map[string]interface{}{"slots": slots})
	return string(out), nil
}

// RpcCreateCharacter cria um novo personagem no slot especificado.
// Payload: { "slot": 0, "name": "Zoro", "appearance": { "body": "...", ... } }
// Resposta: { "ok": true }
func RpcCreateCharacter(ctx context.Context, logger runtime.Logger, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("unauthenticated", 16)
	}

	var req struct {
		Slot       int            `json:"slot"`
		Name       string         `json:"name"`
		Appearance AppearanceData `json:"appearance"`
	}
	if err := json.Unmarshal([]byte(payload), &req); err != nil {
		return "", runtime.NewError("payload inválido", 3)
	}
	if req.Slot < 0 || req.Slot >= NumCharacterSlots {
		return "", runtime.NewError(fmt.Sprintf("slot deve estar entre 0 e %d", NumCharacterSlots-1), 3)
	}
	if req.Name == "" {
		return "", runtime.NewError("name é obrigatório", 3)
	}

	// Verifica se o slot já está ocupado.
	existing, err := GetCharacterSlot(ctx, nk, userID, req.Slot)
	if err != nil {
		return "", err
	}
	if existing != nil {
		return "", runtime.NewError(fmt.Sprintf("slot %d já está ocupado", req.Slot), 6)
	}

	// Cria perfil padrão com nome e aparência personalizados.
	p := DefaultProfile()
	p.Name = req.Name
	p.Slot = req.Slot
	if req.Appearance.Body != "" {
		p.Appearance = req.Appearance
	}

	if err := SaveCharacterSlot(ctx, nk, userID, req.Slot, p); err != nil {
		return "", err
	}
	// Seleciona automaticamente o slot recém-criado.
	if err := SetActiveSlot(ctx, nk, userID, req.Slot); err != nil {
		logger.Warn("RpcCreateCharacter SetActiveSlot user=%s: %v", userID, err)
	}

	logger.Info("Personagem criado slot=%d name=%q user=%s", req.Slot, req.Name, userID)
	return `{"ok":true}`, nil
}

// RpcSelectCharacter seleciona um slot e retorna o perfil completo do personagem.
// Payload: { "slot": 0 }
// Resposta: PlayerProfile completo (com name, slot, etc.)
func RpcSelectCharacter(ctx context.Context, logger runtime.Logger, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("unauthenticated", 16)
	}

	var req struct {
		Slot int `json:"slot"`
	}
	if err := json.Unmarshal([]byte(payload), &req); err != nil {
		return "", runtime.NewError("payload inválido", 3)
	}
	if req.Slot < 0 || req.Slot >= NumCharacterSlots {
		return "", runtime.NewError(fmt.Sprintf("slot deve estar entre 0 e %d", NumCharacterSlots-1), 3)
	}

	p, err := GetCharacterSlot(ctx, nk, userID, req.Slot)
	if err != nil {
		return "", err
	}
	if p == nil {
		return "", runtime.NewError(fmt.Sprintf("slot %d está vazio", req.Slot), 5)
	}

	if err := SetActiveSlot(ctx, nk, userID, req.Slot); err != nil {
		logger.Warn("RpcSelectCharacter SetActiveSlot user=%s: %v", userID, err)
	}

	logger.Info("Slot %d selecionado para user=%s (name=%q level=%d)", req.Slot, userID, p.Name, p.Level)
	out, _ := json.Marshal(p)
	return string(out), nil
}
