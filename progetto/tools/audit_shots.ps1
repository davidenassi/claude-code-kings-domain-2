<#
.SYNOPSIS
  The standard photographs of the full audit: the same places, zooms and worlds every time, so that a "before" and
  an "after" set can be compared picture by picture (FULL_AUDIT_REPORT.md).
  -Set base  : the eleven views of the world and of the main sheets (default)
  -Set extra : every other sheet, the menu, the map modes, the close-ups (for the inspection pack)
  -Set all   : both
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\audit_shots.ps1 -Prefix fa0
  powershell -ExecutionPolicy Bypass -File tools\audit_shots.ps1 -Prefix fa9 -Only C_campi,D_foresta
#>
param(
    [string]$Prefix = "fa",
    [string]$Set = "base",
    [string[]]$Only = @(),
    [string]$EngineArgs = ""
)

$Root = Split-Path -Parent $PSScriptRoot
$town = "--kd-load=tests/output/world_saves/d_town.kdsave"
$village = "--kd-load=tests/output/world_saves/c_village100.kdsave"
$clean = "--kd-no-events --kd-hide-debug --kd-no-autosave"
$ready = "--kd-scenario=community_ready $clean"
$base = [ordered]@{
    "A_comunita"   = "$clean --kd-camera=settlement,0.35"
    "B_villaggio"  = "$village $clean --kd-hours=14 --kd-camera=home,0,0,0.6"
    "C_campi"      = "$town $clean --kd-hours=14 --kd-camera=home,-260,0,0.7"
    "D_foresta"    = "$town $clean --kd-camera=home,700,525,0.8"
    "E_fiume"      = "$town $clean --kd-hours=14 --kd-camera=home,120,200,0.35"
    "F_ceti"       = "$village $clean --kd-panel=estates"
    "G_regno"      = "$town $clean --kd-panel=realm"
    "H_economia"   = "$town $clean --kd-panel=economy"
    "I_esercito"   = "--kd-scenario=army $clean --kd-camera=army,0.3"
    "J_strategico" = "$town $clean --kd-camera=home,0,0,12"
    "K_avvio"      = "--kd-no-events --kd-no-autosave"
}
$extra = [ordered]@{
    "L_menu"              = "--kd-menu"
    "M_pausa"             = "$town $clean --kd-pause"
    "N_comunita_scheda"   = "$ready --kd-panel=realm"
    "O_ceti_comunita"     = "$ready --kd-panel=estates"
    "P_consuetudini"      = "$ready --kd-panel=government"
    "Q_corte"             = "$town $clean --kd-panel=court"
    "R_governo"           = "$town $clean --kd-panel=government"
    "S_ricerca"           = "$town $clean --kd-panel=knowledge"
    "T_diplomazia"        = "$town $clean --kd-panel=diplomacy"
    "U_religione"         = "$town $clean --kd-panel=religion"
    "V_esercito_scheda"   = "$town $clean --kd-panel=army"
    "W_cronaca"           = "$town $clean --kd-panel=chronicle"
    "X_costruzioni"       = "$town $clean --kd-panel=build --kd-hours=14 --kd-camera=home,0,0,0.5"
    "Y_abitanti"          = "$town $clean --kd-panel=people"
    "Z_mappa_risorse"     = "$town $clean --kd-camera=home,0,0,12 --kd-mapmode=resources"
    "ZA_mappa_terreno"    = "$town $clean --kd-camera=home,0,0,12 --kd-mapmode=terrain"
    "ZB_continente"       = "$town $clean --kd-camera=home,0,0,60"
    "ZC_villaggio_vicino" = "$village $clean --kd-hours=14 --kd-camera=home,0,0,0.2"
    "ZD_battaglia"        = "--kd-scenario=war $clean --kd-camera=army,0.4"
    "ZE_evento"           = "--kd-hide-debug --kd-no-autosave --kd-days=40"
}
$shots = [ordered]@{}
if ($Set -eq "base" -or $Set -eq "all") { foreach ($k in $base.Keys) { $shots[$k] = $base[$k] } }
if ($Set -eq "extra" -or $Set -eq "all") { foreach ($k in $extra.Keys) { $shots[$k] = $extra[$k] } }
foreach ($name in $shots.Keys) {
    if ($Only.Count -gt 0 -and -not ($Only -contains $name)) { continue }
    $shotArgs = @('-SkipImport', '-SkipTests', '-Screenshot', '-ShotName', "$($Prefix)_$name", '-Frames', '60',
        '-ExtraArgs', $shots[$name])
    if ($EngineArgs) { $shotArgs += @('-EngineArgs', $EngineArgs) }
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "check.ps1") @shotArgs | Select-Object -Last 2
}

