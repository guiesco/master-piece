package match

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/heroiclabs/nakama-common/runtime"
)

const (
	mapMinX = 0.0
	mapMaxX = 50.0
	mapMinY = 0.0
	mapMaxY = 50.0
)

// MoveIntent is decoded from an incoming OpMove message sent by the client.
type MoveIntent struct {
	PlayerID string  `json:"player_id"`
	X        float64 `json:"x"`
	Y        float64 `json:"y"`
	Seq      int64   `json:"seq"`
}

// playerStateMsg is the payload broadcast as OpPlayerState after position update.
type playerStateMsg struct {
	PlayerID string  `json:"player_id"`
	X        float64 `json:"x"`
	Y        float64 `json:"y"`
	Seq      int64   `json:"seq"`
}

// HandleMovement validates a move intent, updates the player's position in the
// match state and broadcasts OpPlayerState to all connected presences.
func HandleMovement(
	ctx context.Context,
	logger runtime.Logger,
	dispatcher runtime.MatchDispatcher,
	state *MatchState,
	msg runtime.MatchData,
) error {
	var intent MoveIntent
	if err := json.Unmarshal(msg.GetData(), &intent); err != nil {
		return fmt.Errorf("decode MoveIntent: %w", err)
	}

	// Derive authoritative user ID from the message presence (not the payload).
	userID := msg.GetUserId()

	ps, ok := state.Players[userID]
	if !ok {
		// Player left between MatchLeave and this message; ignore silently.
		return nil
	}

	// Clamp to map bounds [0, 50] on both axes.
	ps.X = clampF(intent.X, mapMinX, mapMaxX)
	ps.Y = clampF(intent.Y, mapMinY, mapMaxY)

	// Broadcast validated state to every connected presence.
	out := playerStateMsg{
		PlayerID: userID,
		X:        ps.X,
		Y:        ps.Y,
		Seq:      intent.Seq,
	}

	data, err := json.Marshal(out)
	if err != nil {
		return fmt.Errorf("marshal playerStateMsg: %w", err)
	}

	// nil presences → broadcast to all; movement is unreliable (UDP-like).
	if err := dispatcher.BroadcastMessage(OpPlayerState, data, nil, nil, false); err != nil {
		return fmt.Errorf("broadcast OpPlayerState: %w", err)
	}

	return nil
}

// clampF returns v constrained to [min, max].
func clampF(v, min, max float64) float64 {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}
