#Requires -Version 5.1
<#
.SYNOPSIS
  Copia spritesheets Universal LPC (vendor) → godot/assets/lpc/ e regenera SOURCE_MAP.json.

.DESCRIPTION
  Fase 1 do plano fix_combat_animations (+ hurt/thrust sync):
  - Walk (SOURCE_MAP base) + slash / hurt / backslash / thrust onde existir
  - body/head: slash, backslash, hurt, thrust, shoot
  - hair: slash, hurt, thrust, shoot
  - eyes: walk + hurt + thrust + shoot
  - outfit: slash / hurt / backslash / thrust / shoot (onde existir no vendor)
  - weapon_sword_wood → arming universal fg|bg walk + attack_slash + attack_backslash (brass)
  - weapon_bow_wood → normal bow medium FG|BG walk + shoot
  - godot/assets/fx/arrow.png from bow arrow shoot sheet
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDir)) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    if ([string]::IsNullOrWhiteSpace($scriptDir)) {
        $scriptDir = (Get-Location).Path
    }
    $RepoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
}

$VendorSheets = Join-Path $RepoRoot "vendor\Universal-LPC-Spritesheet-Character-Generator\spritesheets"
$DestRoot     = Join-Path $RepoRoot "godot\assets\lpc"
$SourceMapOut = Join-Path $DestRoot "SOURCE_MAP.json"
$CreditsOut   = Join-Path $DestRoot "CREDITS.txt"

if (-not (Test-Path $VendorSheets)) {
    throw "Vendor spritesheets not found: $VendorSheets"
}

# ---------------------------------------------------------------------------
# Canonical walk sources (relative to spritesheets/)
# ---------------------------------------------------------------------------
$WalkEntries = @(
    @{ id = "body_male_light";      layer = "body";   source = "body\bodies\male\walk.png" }
    @{ id = "body_male_medium";     layer = "body";   source = "body\bodies\male\walk.png" }
    @{ id = "body_male_dark";       layer = "body";   source = "body\bodies\male\walk.png" }
    @{ id = "body_female_light";    layer = "body";   source = "body\bodies\female\walk.png" }
    @{ id = "body_female_medium";   layer = "body";   source = "body\bodies\female\walk.png" }
    @{ id = "hair_short_brown";     layer = "hair";   source = "hair\plain\adult\walk.png" }
    @{ id = "hair_long_black";      layer = "hair";   source = "hair\long\adult\walk.png" }
    @{ id = "hair_mohawk_red";      layer = "hair";   source = "hair\shorthawk\adult\walk.png" }
    @{ id = "hair_curly_blonde";    layer = "hair";   source = "hair\curly_short\adult\walk.png" }
    @{ id = "outfit_pirate_a";      layer = "outfit"; source = "torso\jacket\trench\male\walk\dark_gray.png" }
    @{ id = "outfit_pirate_b";      layer = "outfit"; source = "torso\jacket\tabard\male\walk\navy.png" }
    @{ id = "outfit_guard_a";       layer = "outfit"; source = "torso\armour\leather\male\walk.png" }
    @{ id = "outfit_rags_a";        layer = "outfit"; source = "torso\clothes\sleeveless\sleeveless1\male\walk.png" }
    @{ id = "outfit_sailor_a";      layer = "outfit"; source = "torso\clothes\shortsleeve\shortsleeve\male\walk.png" }
    @{ id = "weapon_club_iron";     layer = "weapon"; source = "weapon\blunt\mace\walk\mace.png" }
    @{ id = "weapon_dagger_steel";  layer = "weapon"; source = "weapon\sword\dagger\walk\dagger.png" }
    @{ id = "head_male";            layer = "head";   source = "head\heads\human\male\walk.png" }
    @{ id = "head_female";          layer = "head";   source = "head\heads\human\female\walk.png" }
    @{ id = "eyes_default";         layer = "eyes";   source = "eyes\human\adult\default\walk.png" }
)

# Shared body/head anim sheets (tint variants share the same PNG)
$BodyHeadAnims = @(
    @{ id = "body_male";   layer = "body"; base = "body\bodies\male" }
    @{ id = "body_female"; layer = "body"; base = "body\bodies\female" }
    @{ id = "head_male";   layer = "head"; base = "head\heads\human\male" }
    @{ id = "head_female"; layer = "head"; base = "head\heads\human\female" }
)
$BodyHeadAnimNames = @("slash", "backslash", "hurt", "thrust", "shoot")

# Hair: slash / backslash / hurt / thrust (same 4 project styles)
$HairStyles = @(
    @{ id = "hair_short_brown";  base = "hair\plain\adult" }
    @{ id = "hair_long_black";   base = "hair\long\adult" }
    @{ id = "hair_mohawk_red";   base = "hair\shorthawk\adult" }
    @{ id = "hair_curly_blonde"; base = "hair\curly_short\adult" }
)
$HairAnimNames = @("slash", "backslash", "hurt", "thrust", "shoot")

# Eyes: slash / backslash / hurt / thrust (walk already in $WalkEntries)
$EyesAnimCopies = @(
    @{ id = "eyes_default"; anim = "slash";     source = "eyes\human\adult\default\slash.png" }
    @{ id = "eyes_default"; anim = "backslash"; source = "eyes\human\adult\default\backslash.png" }
    @{ id = "eyes_default"; anim = "hurt";      source = "eyes\human\adult\default\hurt.png" }
    @{ id = "eyes_default"; anim = "thrust";    source = "eyes\human\adult\default\thrust.png" }
    @{ id = "eyes_default"; anim = "shoot";     source = "eyes\human\adult\default\shoot.png" }
)

# Sword: arming brass (no wood palette in vendor) — FG + BG
$SwordMetal = "brass"
$SwordCopies = @(
    @{ id = "weapon_sword_wood";             anim = "walk";      source = "weapon\sword\arming\universal\fg\walk\$SwordMetal.png";           role = "fg" }
    @{ id = "weapon_sword_wood_bg";          anim = "walk";      source = "weapon\sword\arming\universal\bg\walk\$SwordMetal.png";           role = "bg" }
    @{ id = "weapon_sword_wood_slash";       anim = "slash";     source = "weapon\sword\arming\attack_slash\fg\$SwordMetal.png";             role = "fg" }
    @{ id = "weapon_sword_wood_bg_slash";    anim = "slash";     source = "weapon\sword\arming\attack_slash\bg\$SwordMetal.png";             role = "bg" }
    @{ id = "weapon_sword_wood_backslash";   anim = "backslash"; source = "weapon\sword\arming\attack_backslash\fg\$SwordMetal.png";         role = "fg" }
    @{ id = "weapon_sword_wood_bg_backslash";anim = "backslash"; source = "weapon\sword\arming\attack_backslash\bg\$SwordMetal.png";         role = "bg" }
)

# Bow: normal medium FG + BG walk + shoot
$BowCopies = @(
    @{ id = "weapon_bow_wood";          anim = "walk";  source = "weapon\ranged\bow\normal\walk\foreground\medium.png"; role = "fg" }
    @{ id = "weapon_bow_wood_bg";       anim = "walk";  source = "weapon\ranged\bow\normal\walk\background\medium.png"; role = "bg" }
    @{ id = "weapon_bow_wood_shoot";    anim = "shoot"; source = "weapon\ranged\bow\normal\universal\foreground\shoot\medium.png"; role = "fg" }
    @{ id = "weapon_bow_wood_bg_shoot"; anim = "shoot"; source = "weapon\ranged\bow\normal\universal\background\shoot\medium.png"; role = "bg" }
)

$Missing = [System.Collections.Generic.List[string]]::new()
$Copied  = [System.Collections.Generic.List[hashtable]]::new()
$MapEntries = [System.Collections.Generic.List[object]]::new()

function Get-AnimSourcePath {
    param([string]$WalkRel, [string]$Anim)
    if ($WalkRel -match '(?i)([\\/])walk([\\/])') {
        return ($WalkRel -replace '(?i)([\\/])walk([\\/])', "`$1$Anim`$2")
    }
    if ($WalkRel -match '(?i)([\\/])walk\.png$') {
        return ($WalkRel -replace '(?i)([\\/])walk\.png$', "`$1$Anim.png")
    }
    return $null
}

function Get-SheetMeta {
    param([string]$FullPath, [string]$AnimHint = "walk")
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    $img = [System.Drawing.Image]::FromFile($FullPath)
    try {
        $w = $img.Width
        $h = $img.Height
    } finally {
        $img.Dispose()
    }

    # Prefer frame size that divides both dimensions cleanly.
    $candidates = @(64, 128, 192, 256)
    $frame = $null
    foreach ($c in $candidates) {
        if (($w % $c -eq 0) -and ($h % $c -eq 0) -and ($w / $c -ge 1) -and ($h / $c -ge 1)) {
            # Hurt sheets are often a single row (height == frame).
            if ($AnimHint -eq "hurt" -and $h -eq $c) { $frame = $c; break }
            if ($AnimHint -ne "hurt" -and ($h / $c) -in 1, 4) { $frame = $c; break }
        }
    }
    if (-not $frame) {
        # Fallback: largest candidate that divides both
        foreach ($c in ($candidates | Sort-Object -Descending)) {
            if (($w % $c -eq 0) -and ($h % $c -eq 0)) { $frame = $c; break }
        }
    }
    if (-not $frame) { $frame = 64 }

    return @{
        width   = $w
        height  = $h
        frame_w = $frame
        frame_h = $frame
        frames  = [int]($w / $frame)
        rows    = [int]($h / $frame)
        bytes   = (Get-Item $FullPath).Length
    }
}

function Copy-LpcSheet {
    param(
        [string]$Id,
        [string]$Layer,
        [string]$RelSource,
        [string]$Anim = "walk",
        [string]$DestFileName = $null,
        [hashtable]$Extra = @{}
    )

    $src = Join-Path $VendorSheets $RelSource
    if (-not (Test-Path $src)) {
        $Missing.Add("$Id ($Anim) ← $RelSource") | Out-Null
        Write-Warning "MISSING: $RelSource"
        return $false
    }

    $layerDir = Join-Path $DestRoot $Layer
    if (-not (Test-Path $layerDir)) {
        New-Item -ItemType Directory -Path $layerDir -Force | Out-Null
    }

    if (-not $DestFileName) {
        if ($Anim -eq "walk") { $DestFileName = "$Id.png" }
        else { $DestFileName = "${Id}_${Anim}.png" }
    }

    $dest = Join-Path $layerDir $DestFileName
    Copy-Item -LiteralPath $src -Destination $dest -Force

    $meta = Get-SheetMeta -FullPath $dest -AnimHint $Anim
    $entryId = if ($Anim -eq "walk") {
        $Id
    } elseif ($DestFileName -match '^(.*)\.png$') {
        $Matches[1]
    } else {
        "${Id}_${Anim}"
    }

    $props = [ordered]@{
        id      = $entryId
        layer   = $Layer
        source  = $RelSource
        anim    = $Anim
        frames  = $meta.frames
        rows    = $meta.rows
        frame_w = $meta.frame_w
        frame_h = $meta.frame_h
        bytes   = $meta.bytes
    }
    foreach ($k in ($Extra.Keys | Sort-Object)) { $props[$k] = $Extra[$k] }

    $MapEntries.Add([pscustomobject]$props) | Out-Null
    $Copied.Add(@{ id = $entryId; dest = $dest; source = $RelSource }) | Out-Null
    Write-Host "OK  $entryId  <-  $RelSource  ($($meta.width)x$($meta.height), fw=$($meta.frame_w))"
    return $true
}

Write-Host "=== sync_lpc_assets ==="
Write-Host "Vendor: $VendorSheets"
Write-Host "Dest:   $DestRoot"
Write-Host ""

# --- Walk sheets ---
Write-Host "-- walk --"
foreach ($e in $WalkEntries) {
    Copy-LpcSheet -Id $e.id -Layer $e.layer -RelSource $e.source -Anim "walk" | Out-Null
}

# --- Outfit slash / hurt / backslash / thrust ---
Write-Host "-- outfit anims --"
$OutfitWalk = $WalkEntries | Where-Object { $_.layer -eq "outfit" }
foreach ($e in $OutfitWalk) {
    foreach ($anim in @("slash", "hurt", "backslash", "thrust", "shoot")) {
        $animSrc = Get-AnimSourcePath -WalkRel $e.source -Anim $anim
        if (-not $animSrc) { continue }
        $full = Join-Path $VendorSheets $animSrc
        if (-not (Test-Path $full)) {
            Write-Host "SKIP $($e.id)_$anim (no vendor file)"
            continue
        }
        Copy-LpcSheet -Id $e.id -Layer "outfit" -RelSource $animSrc -Anim $anim | Out-Null
    }
}

# --- Body / head slash, backslash, hurt, thrust ---
Write-Host "-- body/head anims --"
foreach ($b in $BodyHeadAnims) {
    foreach ($anim in $BodyHeadAnimNames) {
        $rel = Join-Path $b.base "$anim.png"
        $destName = "$($b.id)_$anim.png"
        Copy-LpcSheet -Id $b.id -Layer $b.layer -RelSource $rel -Anim $anim -DestFileName $destName | Out-Null
    }
}

# --- Hair slash / backslash / hurt / thrust ---
Write-Host "-- hair anims --"
foreach ($h in $HairStyles) {
    foreach ($anim in $HairAnimNames) {
        $rel = Join-Path $h.base "$anim.png"
        Copy-LpcSheet -Id $h.id -Layer "hair" -RelSource $rel -Anim $anim | Out-Null
    }
}

# --- Eyes slash / backslash / hurt / thrust ---
Write-Host "-- eyes anims --"
foreach ($e in $EyesAnimCopies) {
    Copy-LpcSheet -Id $e.id -Layer "eyes" -RelSource $e.source -Anim $e.anim | Out-Null
}

# --- Sword arming FG/BG ---
Write-Host "-- weapon sword (arming brass) --"
foreach ($s in $SwordCopies) {
    $extra = @{ weapon_role = $s.role; weapon_family = "arming"; metal = $SwordMetal }
    Copy-LpcSheet -Id $s.id -Layer "weapon" -RelSource $s.source -Anim $s.anim -DestFileName "$($s.id).png" -Extra $extra | Out-Null
}

# --- Bow normal medium FG/BG ---
Write-Host "-- weapon bow (normal medium) --"
foreach ($s in $BowCopies) {
    $extra = @{ weapon_role = $s.role; weapon_family = "bow_normal"; palette = "medium" }
    Copy-LpcSheet -Id $s.id -Layer "weapon" -RelSource $s.source -Anim $s.anim -DestFileName "$($s.id).png" -Extra $extra | Out-Null
}

# --- Arrow VFX (not under lpc/weapon) ---
Write-Host "-- fx arrow --"
$FxDir = Join-Path $RepoRoot "godot\assets\fx"
if (-not (Test-Path $FxDir)) {
    New-Item -ItemType Directory -Path $FxDir -Force | Out-Null
}
$ArrowSrc = Join-Path $VendorSheets "weapon\ranged\bow\arrow\shoot\arrow.png"
$ArrowDest = Join-Path $FxDir "arrow.png"
if (-not (Test-Path $ArrowSrc)) {
    $Missing.Add("arrow fx <- weapon\ranged\bow\arrow\shoot\arrow.png") | Out-Null
    Write-Warning "MISSING: weapon\ranged\bow\arrow\shoot\arrow.png"
} else {
    Copy-Item -LiteralPath $ArrowSrc -Destination $ArrowDest -Force
    Write-Host "OK  fx/arrow.png  <-  weapon\ranged\bow\arrow\shoot\arrow.png"
}

# --- Write SOURCE_MAP.json (stable key order via PSCustomObject) ---
$json = @($MapEntries.ToArray()) | ConvertTo-Json -Depth 6
if ($MapEntries.Count -eq 1) { $json = "[$json]" }
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($SourceMapOut, $json + "`r`n", $utf8NoBom)

# --- Update CREDITS.txt (UTF-8, ASCII-safe accents to survive PS5.1 script encoding) ---
$credits = @"
# LPC Assets - Credits

Este projeto inclui sprites derivados do Universal LPC Spritesheet Character Generator
(Liberated Pixel Cup / OpenGameArt contributors).

## Fonte

- Repositorio: https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator
- Clone local: ``vendor/Universal-LPC-Spritesheet-Character-Generator/``
- Mapa de copias usadas no jogo: ``godot/assets/lpc/SOURCE_MAP.json``
- Script de sync: ``tools/sync_lpc_assets.ps1``

## Licencas

Os assets LPC usados aqui estao sob combinacoes de:

- OGA-BY 3.0
- CC-BY-SA 3.0
- GPL 3.0

A atribuicao completa por arquivo esta em:

``vendor/Universal-LPC-Spritesheet-Character-Generator/CREDITS.csv``

## Subset embutido em ``godot/assets/lpc/``

Camadas walk (ciclo tipico 576x256, frame 64x64) + animacoes de combate:

| Camada | IDs / animacoes |
|--------|-----------------|
| body | body_male_*/body_female_* walk; body_male/female_{slash,backslash,hurt,thrust,shoot} |
| head | head_male/female walk + _{slash,backslash,hurt,thrust,shoot} |
| hair | hair_* walk + *_slash / *_backslash / *_hurt / *_thrust / *_shoot |
| outfit | outfit_* walk + *_slash / *_hurt / *_backslash / *_thrust / *_shoot (onde existir no vendor) |
| weapon | weapon_sword_wood{,_bg} walk + slash/backslash (arming brass FG/BG); weapon_bow_wood{,_bg} walk + shoot (normal medium FG/BG); club/dagger walk |
| eyes | eyes_default walk + *_slash / *_backslash / *_hurt / *_thrust / *_shoot |
| fx | arrow.png (bow arrow shoot) |

Notas de frame size (ver ``frame_w``/``frame_h`` no SOURCE_MAP):

- walk / slash / hurt / backslash / thrust padrao corpo/roupa: 64x64
- arming attack_slash / attack_backslash: tipicamente 128x128
- gnarled thrust: tipicamente 192x192

``weapon_sword_wood`` usa paleta **brass** do arming sword (nao ha variante wood no vendor ULPC).

Autores base (corpo LPC): Stephen Challener (Redshrike), Johannes Sjolund (wulax),
bluecarrot16, Benjamin K. Smith (BenCreating), ElizaWy, e demais listados no CREDITS.csv
para cada sheet.

## Skills / ferramentas do repositorio oficial

O clone em ``vendor/`` tambem contem skills de agente em ``.agents/skills/``
(canvas-render, catalog, sheet-definition, visual-test, etc.) e ferramentas em
``tools/`` / ``scripts/`` uteis para gerar sheets, credits e metadados no futuro.

Synced: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@
[System.IO.File]::WriteAllText($CreditsOut, $credits, $utf8NoBom)

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "Copied: $($Copied.Count) files"
Write-Host "SOURCE_MAP: $SourceMapOut ($($MapEntries.Count) entries)"
if ($Missing.Count -gt 0) {
    Write-Host "MISSING ($($Missing.Count)):"
    $Missing | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host "No missing required vendor sources."
exit 0
