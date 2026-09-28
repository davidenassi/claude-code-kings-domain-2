<#
.SYNOPSIS
  Builds ISPEZIONE_AI\ and ISPEZIONE_AI.zip in the project folder: every text file of the project (code, scenes,
  shaders, data, tests, tools, documents), the same files joined into five single text files, the standard
  screenshots as JPG and the sprite atlases — light enough to hand to an AI for an inspection.
  The screenshots are taken from tests\output (tools\audit_shots.ps1 -Prefix fa0 -Set all makes them).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\make_inspection_pack.ps1
#>
param(
    [string]$ShotPrefix = "fa0",
    [int]$JpgQuality = 82
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Out = Join-Path $Root "ISPEZIONE_AI"
$Zip = Join-Path $Root "ISPEZIONE_AI.zip"
$Python = "C:\Program Files\Blender Foundation\Blender 5.2\5.2\python\bin\python.exe"
$Utf8 = New-Object System.Text.UTF8Encoding $false
$BigJson = 300KB

if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
if (Test-Path $Zip) { Remove-Item $Zip -Force }
New-Item -ItemType Directory -Force -Path $Out, "$Out\progetto", "$Out\foto", "$Out\grafica" | Out-Null

# --- the text files of the project: what git tracks, plus the new files not yet committed --------------------------
$textExt = @('.gd', '.gdshader', '.tscn', '.tres', '.json', '.py', '.ps1', '.md', '.godot', '.cfg', '.gitignore', '.gitattributes')
$all = & git -C $Root ls-files --cached --others --exclude-standard
$files = @($all | Where-Object { $textExt -contains [System.IO.Path]::GetExtension($_).ToLower() -or $_ -eq '.gitignore' } |
    Where-Object { -not $_.StartsWith('ISPEZIONE_AI') -and -not $_.StartsWith('tools/inspection/') } | Sort-Object -Unique)
$excluded = @($all | Where-Object { $files -notcontains $_ } | Where-Object { -not $_.EndsWith('.uid') -and -not $_.EndsWith('.import') })

$packed = @()      # [path inside progetto, source description]
$sampled = @()
foreach ($rel in $files) {
    $src = Join-Path $Root $rel
    if (-not (Test-Path $src)) { continue }
    $size = (Get-Item $src).Length
    if ($rel.EndsWith('.json') -and $size -gt $BigJson) {
        # a large JSON of the world: its structure with the first entries of every list
        $sample = $rel.Substring(0, $rel.Length - 5) + '.ESEMPIO.json'
        $dst = Join-Path "$Out\progetto" $sample
        New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
        if (Test-Path $Python) {
            & $Python (Join-Path $Root "tools\sample_json.py") $src $dst 3
            $packed += $sample
            $sampled += "$rel ($([math]::Round($size / 1KB)) KB) -> $sample"
        } else {
            $excluded += $rel
        }
        continue
    }
    $dst = Join-Path "$Out\progetto" $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item $src $dst
    $packed += $rel
}

# --- the same files joined into five texts, for the AIs that take single files only ----------------------------
$groups = [ordered]@{
    "1_documenti.txt"                  = '^[^/]+\.md$'
    "2_codice_simulazione.txt"         = '^(project\.godot|(ai|characters|core|culture|diplomacy|economy|events|kingdoms|military|provinces|religion|research|save|settlement|war|world)/)'
    "3_codice_mappa_interfaccia.txt"   = '^(map|shaders|scenes|ui)/'
    "4_dati_e_test.txt"                = '^(data|tests)/'
    "5_strumenti.txt"                  = '.'
}
$taken = @{}
foreach ($name in $groups.Keys) {
    $sb = New-Object System.Text.StringBuilder
    $count = 0
    foreach ($rel in $packed) {
        if ($taken.ContainsKey($rel) -or $rel -notmatch $groups[$name]) { continue }
        $taken[$rel] = $true
        $text = [System.IO.File]::ReadAllText((Join-Path "$Out\progetto" $rel), [System.Text.Encoding]::UTF8)
        $lines = ($text -split "`n").Count
        [void]$sb.Append("`n" + ('=' * 100) + "`nFILE: $rel   ($lines righe)`n" + ('=' * 100) + "`n")
        [void]$sb.Append($text.TrimEnd() + "`n")
        $count += 1
    }
    $head = "KING'S DOMAIN — $name — $count file del progetto, uno dopo l'altro. Ogni file comincia con una riga FILE:.`n"
    [System.IO.File]::WriteAllText((Join-Path $Out $name), $head + $sb.ToString(), $Utf8)
}

# --- the screenshots, as JPG ---------------------------------------------------------------------------------
Add-Type -AssemblyName System.Drawing
$jpeg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$params = New-Object System.Drawing.Imaging.EncoderParameters(1)
$params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$JpgQuality)
$p = $ShotPrefix
$photos = @(
    @("$($p)_K_avvio", "01_avvio_reale", "Nuova partita come la vede chi gioca, senza opzioni di prova (in basso a sinistra il riquadro di debug)"),
    @("$($p)_A_comunita", "02_comunita_iniziale", "I sei fondatori il primo giorno, 0,35 m/px"),
    @("$($p)_B_villaggio", "03_villaggio_100", "Villaggio di 91 abitanti (1241), 0,6 m/px"),
    @("$($p)_ZC_villaggio_vicino", "04_villaggio_vicino", "Lo stesso villaggio da vicino, 0,2 m/px: case, campi, sentieri, abitanti"),
    @("$($p)_C_campi", "05_campi", "Cittadina di 287 abitanti (1274): i campi a ovest del fiume, 0,7 m/px"),
    @("$($p)_D_foresta", "06_foresta", "Bosco vicino alla cittadina, 0,8 m/px"),
    @("$($p)_E_fiume", "07_fiume", "Il fiume che attraversa la cittadina, 0,35 m/px"),
    @("$($p)_J_strategico", "08_zoom_strategico", "Zoom strategico, 12 m/px: province, confini, nomi, eserciti"),
    @("$($p)_ZA_mappa_terreno", "09_mappa_terreno", "Modalità mappa Terreno, 12 m/px"),
    @("$($p)_Z_mappa_risorse", "10_mappa_risorse", "Modalità mappa Risorse, 12 m/px"),
    @("$($p)_ZB_continente", "11_continente", "Il continente, 60 m/px"),
    @("$($p)_L_menu", "12_menu_principale", "Menu principale"),
    @("$($p)_M_pausa", "13_menu_pausa", "Menu di pausa in partita"),
    @("$($p)_N_comunita_scheda", "14_scheda_comunita", "La mia comunità prima della corona, con le condizioni del Regno"),
    @("$($p)_O_ceti_comunita", "15_ceti_prima_della_corona", "Ceti prima della corona: famiglie per lavoro e scelta della casa reale"),
    @("$($p)_P_consuetudini", "16_consuetudini", "Consuetudini (il Governo prima della corona)"),
    @("$($p)_G_regno", "17_scheda_regno", "Il mio regno: casa reale, crisi, obiettivi"),
    @("$($p)_F_ceti", "18_ceti_dopo_la_corona", "Ceti dopo la corona: i cinque poteri con le famiglie di spicco"),
    @("$($p)_Q_corte", "19_corte", "Corte: sovrano, legittimità, casata"),
    @("$($p)_R_governo", "20_governo", "Governo: leggi ed editti"),
    @("$($p)_H_economia", "21_economia", "Economia: cosa manca, tesoro, depositi, lavoro"),
    @("$($p)_S_ricerca", "22_ricerca", "Ricerca"),
    @("$($p)_T_diplomazia", "23_diplomazia", "Diplomazia"),
    @("$($p)_U_religione", "24_religione", "Religione"),
    @("$($p)_V_esercito_scheda", "25_esercito_scheda", "Scheda Esercito: leva e schiere"),
    @("$($p)_W_cronaca", "26_cronaca", "Cronaca"),
    @("$($p)_X_costruzioni", "27_costruzioni", "Colonna Costruzioni aperta sulla cittadina"),
    @("$($p)_Y_abitanti", "28_abitanti", "Abitanti: mani ai cantieri e nome per nome"),
    @("$($p)_I_esercito", "29_esercito_in_campo", "La prima schiera in campo, 0,3 m/px"),
    @("$($p)_ZD_battaglia", "30_scenario_guerra", "Scenario di guerra: la schiera davanti al villaggio, 0,4 m/px"),
    @("soak0_coronation", "31_evento", "Carta evento (Un maestro d'armi) sopra il villaggio da vicino, 0,13 m/px"),
    @("$($p)_ZE_evento", "32_dopo_40_giorni", "Nuova partita dopo 40 giorni")
)
$photoRows = @()
foreach ($ph in $photos) {
    $src = Join-Path $Root "tests\output\$($ph[0]).png"
    if (-not (Test-Path $src)) { continue }
    $img = [System.Drawing.Image]::FromFile($src)
    $img.Save((Join-Path "$Out\foto" "$($ph[1]).jpg"), $jpeg, $params)
    $img.Dispose()
    $photoRows += "| ``foto/$($ph[1]).jpg`` | $($ph[2]) |"
}

# --- the sprite atlases ---------------------------------------------------------------------------------------
foreach ($a in @('assets\buildings\building_atlas.png', 'assets\buildings\props_atlas.png',
        'assets\environment\vegetation\vegetation_atlas.png', 'assets\people\people_atlas.png')) {
    $src = Join-Path $Root $a
    if (Test-Path $src) { Copy-Item $src (Join-Path "$Out\grafica" (Split-Path $a -Leaf)) }
}

# --- the guide: the written part, then what this run put in -----------------------------------------------------
$commit = (& git -C $Root log -1 --format="%h %ad %s" --date=short)
$dirty = @(& git -C $Root status --porcelain).Count
$guide = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "inspection\LEGGIMI.md"), [System.Text.Encoding]::UTF8)
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append($guide.TrimEnd() + "`n`n## Contenuto di questo pacchetto`n`n")
[void]$sb.Append("Generato il $(Get-Date -Format 'dd/MM/yyyy HH:mm') da ``tools/make_inspection_pack.ps1``. Ultimo commit: ``$commit``")
if ($dirty -gt 0) { [void]$sb.Append(" (più $dirty file modificati o nuovi non ancora nel commit)") }
[void]$sb.Append(".`n`n| File | Dimensione |`n|---|---|`n")
foreach ($name in $groups.Keys) {
    [void]$sb.Append("| ``$name`` | $([math]::Round((Get-Item (Join-Path $Out $name)).Length / 1KB)) KB |`n")
}
[void]$sb.Append("| ``progetto/`` | $($packed.Count) file |`n| ``foto/`` | $($photoRows.Count) schermate JPG |`n")
[void]$sb.Append("| ``grafica/`` | atlanti di edifici, oggetti di scena, vegetazione, persone |`n`n")
[void]$sb.Append("### Le foto`n`n| Foto | Cosa mostra |`n|---|---|`n" + ($photoRows -join "`n") + "`n`n")
[void]$sb.Append("### JSON grandi ridotti a un esempio`n`nStessa struttura, solo i primi elementi di ogni lista:`n`n")
foreach ($s in $sampled) { [void]$sb.Append("- $s`n") }
[void]$sb.Append("`n### Esclusi`n`n")
[void]$sb.Append("- **Non inclusi:**`n")
[void]$sb.Append("  - la cache di Godot (``.godot/``);`n")
[void]$sb.Append("  - l'eseguibile ``KingsDomain.exe``;`n")
[void]$sb.Append("  - le foto storiche e i mondi di prova (``tests/output/``, circa 460 MB);`n")
[void]$sb.Append("  - i registri (``logs/``);`n")
[void]$sb.Append("  - i file ``.uid`` e ``.import`` di Godot.`n")
[void]$sb.Append("- **File binari o immagini** (mappa in griglie binarie, texture, fonti grafiche):`n`n")
foreach ($e in ($excluded | Sort-Object)) {
    $full = Join-Path $Root $e
    $kb = if (Test-Path $full) { [math]::Round((Get-Item $full).Length / 1KB) } else { 0 }
    $copy = if (Test-Path (Join-Path "$Out\grafica" (Split-Path $e -Leaf))) { " - copia in ``grafica/``" } else { "" }
    [void]$sb.Append("  - ``$e`` ($kb KB)$copy`n")
}
[System.IO.File]::WriteAllText((Join-Path $Out "LEGGIMI.md"), $sb.ToString(), $Utf8)

Compress-Archive -Path $Out -DestinationPath $Zip -CompressionLevel Optimal
$folderKb = [math]::Round(((Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum) / 1KB)
Write-Host "ISPEZIONE_AI: $folderKb KB, $($packed.Count) file di testo, $($photoRows.Count) foto"
Write-Host "ISPEZIONE_AI.zip: $([math]::Round((Get-Item $Zip).Length / 1KB)) KB"

