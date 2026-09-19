package main

import (
	"context"
	"database/sql"
	"encoding/json"

	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/op-mmo/alvida-hold/match"
	"github.com/op-mmo/alvida-hold/profile"
)

// alvidaMatchID guarda o ID do match singleton criado no InitModule.
// Usado pelo RPC rpc_get_alvida_match_id para retornar o ID aos clientes.
var alvidaMatchID string

// InitModule is the Nakama Go plugin entry point.
// It is called once at server startup and registers all match handlers,
// RPCs and lifecycle hooks for the Alvida Hold MVP.
func InitModule(
	ctx context.Context,
	logger runtime.Logger,
	db *sql.DB,
	nk runtime.NakamaModule,
	initializer runtime.Initializer,
) error {
	// ── Match handler ────────────────────────────────────────────────────────
	// Registers the "AlvidaHold" match handler so Nakama knows how to
	// instantiate AlvidaHoldMatch when a client creates or joins a match.
	if err := initializer.RegisterMatch("AlvidaHold", func(
		ctx context.Context,
		logger runtime.Logger,
		db *sql.DB,
		nk runtime.NakamaModule,
	) (runtime.Match, error) {
		return &match.AlvidaHoldMatch{}, nil
	}); err != nil {
		return err
	}

	// Auto-create the singleton AlvidaHold_01 match so clients can join
	// immediately without a separate create call (MVP convenience).
	mid, err := nk.MatchCreate(ctx, "AlvidaHold", map[string]interface{}{})
	if err != nil {
		logger.Warn("Auto-create AlvidaHold match failed (may already exist): %v", err)
	} else {
		alvidaMatchID = mid
		logger.Info("AlvidaHold_01 match created: %s", alvidaMatchID)
	}

	// ── RPC: rpc_get_or_create_profile ───────────────────────────────────────
	// Clients call this after auth to fetch (or bootstrap) their profile.
	if err := initializer.RegisterRpc("rpc_get_or_create_profile", func(
		ctx context.Context,
		logger runtime.Logger,
		db *sql.DB,
		nk runtime.NakamaModule,
		payload string,
	) (string, error) {
		return profile.RpcGetOrCreateProfile(ctx, logger, nk, payload)
	}); err != nil {
		return err
	}

	// ── RPC: rpc_get_alvida_match_id ─────────────────────────────────────────
	// Retorna o ID do match singleton AlvidaHold para que os clientes possam
	// entrar diretamente. Se o ID em cache não estiver disponível, lista os
	// matches ativos para encontrá-lo; caso não exista, cria um novo.
	if err := initializer.RegisterRpc("rpc_get_alvida_match_id", func(
		ctx context.Context,
		logger runtime.Logger,
		db *sql.DB,
		nk runtime.NakamaModule,
		payload string,
	) (string, error) {
		// Usa o ID em cache se disponível.
		if alvidaMatchID != "" {
			out, _ := json.Marshal(map[string]string{"match_id": alvidaMatchID})
			return string(out), nil
		}

		// Tenta listar matches ativos com label AlvidaHold_01.
		label := "AlvidaHold_01"
		matches, err := nk.MatchList(ctx, 1, true, label, nil, nil, "")
		if err == nil && len(matches) > 0 {
			alvidaMatchID = matches[0].MatchId
			out, _ := json.Marshal(map[string]string{"match_id": alvidaMatchID})
			return string(out), nil
		}

		// Cria um novo match se não encontrado.
		newID, createErr := nk.MatchCreate(ctx, "AlvidaHold", map[string]interface{}{})
		if createErr != nil {
			return "", runtime.NewError("falha ao criar match AlvidaHold", 13)
		}
		alvidaMatchID = newID
		out, _ := json.Marshal(map[string]string{"match_id": alvidaMatchID})
		return string(out), nil
	}); err != nil {
		return err
	}

	// ── RPC: rpc_save_appearance ─────────────────────────────────────────────
	// Salva a aparência LPC do personagem no slot ativo do jogador.
	// Payload: { "body": "...", "hair": "...", "outfit": "...",
	//            "body_tint": "#RRGGBB", "hair_tint": "#RRGGBB" }
	if err := initializer.RegisterRpc("rpc_save_appearance", func(
		ctx context.Context,
		logger runtime.Logger,
		db *sql.DB,
		nk runtime.NakamaModule,
		payload string,
	) (string, error) {
		userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
		if !ok || userID == "" {
			return "", runtime.NewError("unauthenticated", 16)
		}

		var appearance profile.AppearanceData
		if err := json.Unmarshal([]byte(payload), &appearance); err != nil {
			return "", runtime.NewError("payload de aparência inválido", 3)
		}

		// Lê o slot ativo; carrega o personagem desse slot.
		activeSlot, slotErr := profile.GetActiveSlot(ctx, nk, userID)
		if slotErr != nil {
			logger.Warn("rpc_save_appearance GetActiveSlot user=%s: %v — usando slot 0", userID, slotErr)
			activeSlot = 0
		}

		p, err := profile.GetCharacterSlot(ctx, nk, userID, activeSlot)
		if err != nil || p == nil {
			// Fallback: cria/carrega perfil legado e migra para o slot.
			p, err = profile.GetOrCreateProfile(ctx, logger, nk, userID)
			if err != nil {
				return "", err
			}
		}

		p.Appearance = appearance
		if err := profile.SaveCharacterSlot(ctx, nk, userID, activeSlot, p); err != nil {
			return "", err
		}

		logger.Info("Aparência salva para user=%s slot=%d body=%s", userID, activeSlot, appearance.Body)
		return `{"ok":true}`, nil
	}); err != nil {
		return err
	}

	// ── RPC: rpc_list_characters ──────────────────────────────────────────────
	// Lista os 3 slots de personagem do jogador (com migração automática do perfil legado).
	// Resposta: { "slots": [ null | { slot, name, level, appearance }, ... ] }
	if err := initializer.RegisterRpc("rpc_list_characters", func(
		ctx context.Context,
		logger runtime.Logger,
		db *sql.DB,
		nk runtime.NakamaModule,
		payload string,
	) (string, error) {
		return profile.RpcListCharacters(ctx, logger, nk, payload)
	}); err != nil {
		return err
	}

	// ── RPC: rpc_create_character ─────────────────────────────────────────────
	// Cria um novo personagem em um slot vazio.
	// Payload: { "slot": 0, "name": "Zoro", "appearance": { ... } }
	// Resposta: { "ok": true }
	if err := initializer.RegisterRpc("rpc_create_character", func(
		ctx context.Context,
		logger runtime.Logger,
		db *sql.DB,
		nk runtime.NakamaModule,
		payload string,
	) (string, error) {
		return profile.RpcCreateCharacter(ctx, logger, nk, payload)
	}); err != nil {
		return err
	}

	// ── RPC: rpc_select_character ─────────────────────────────────────────────
	// Seleciona um slot como personagem ativo e retorna o perfil completo.
	// Payload: { "slot": 0 }
	// Resposta: PlayerProfile completo (level, xp, stats, inventory, appearance, name, slot)
	if err := initializer.RegisterRpc("rpc_select_character", func(
		ctx context.Context,
		logger runtime.Logger,
		db *sql.DB,
		nk runtime.NakamaModule,
		payload string,
	) (string, error) {
		return profile.RpcSelectCharacter(ctx, logger, nk, payload)
	}); err != nil {
		return err
	}

	// ── After hook: authenticateDevice ───────────────────────────────────────
	// Ensures every device that authenticates has a profile record in Storage,
	// creating a default one on first login.
	if err := initializer.RegisterAfterAuthenticateDevice(func(
		ctx context.Context,
		logger runtime.Logger,
		db *sql.DB,
		nk runtime.NakamaModule,
		out *api.Session,
		in *api.AuthenticateDeviceRequest,
	) error {
		userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
		if !ok || userID == "" {
			return nil
		}
		_, err := profile.GetOrCreateProfile(ctx, logger, nk, userID)
		return err
	}); err != nil {
		return err
	}

	logger.Info("Alvida Hold plugin initialised — match handler, 6 RPCs e auth hook registrados")
	return nil
}
