// Package content embeds the game-data JSON files into the plugin binary at
// compile time so Nakama does not need to access the filesystem at runtime.
package content

import _ "embed"

// ArchetypesJSON holds the raw bytes of archetypes.json, embedded at compile time.
//
//go:embed archetypes.json
var ArchetypesJSON []byte

// SkillsJSON holds the raw bytes of skills.json, embedded at compile time.
//
//go:embed skills.json
var SkillsJSON []byte

// WeaponsJSON holds the raw bytes of weapons.json, embedded at compile time.
//
//go:embed weapons.json
var WeaponsJSON []byte

// LPCCatalogJSON holds the raw bytes of lpc_catalog.json, embedded at compile time.
// Usado por enemy_gen para gerar aparências LPC determinísticas por seed.
//
//go:embed lpc_catalog.json
var LPCCatalogJSON []byte
