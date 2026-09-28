# WORLD ART REPORT — da «simulazione visibile» a «mondo visibile»

L'audit iniziale è in `WORLD_ART_AUDIT.md`. Foto standard, sempre gli stessi punti e zoom:
**prima** `tests/output/wa0_*.png`, **dopo** `tests/output/wa9_*.png` (A comunità di 6 · B villaggio ~30 ·
C villaggio ~100 · D centro più sviluppato · E fiume · F foresta · G campi · H zoom strategico · I esercito ·
J continente · K centro a zoom medio; in più L villaggio da vicinissimo, M bosco da vicino, N riva da vicino). I mondi di prova sono salvati in `tests/output/world_saves/` e caricati
con `--kd-load`: le foto si possono rifare identiche.

> Nota onesta sui mondi B–D: il pianificatore del pilota (che fa crescere i villaggi di prova) ora dispone gli
> edifici per zone, quindi le foto «dopo» di B, C, D mostrano villaggi rigenerati con la stessa simulazione e lo
> stesso seme, non gli stessi edifici della foto «prima». A, E–J confrontano lo stesso mondo.

## 1. Problemi iniziali

- Villaggi del pilota su **anelli concentrici** (16 raggi fissi a 12 m di distanza): case e campi a scacchiera.
- Sprite tutti dritti e uguali: tre case, un solo campo 26×30 m con i solchi orizzontali.
- Bosco vicino come campionamento uniforme (un albero ogni cella di 12 m, probabilità solo dalla densità):
  nessun nucleo, nessuna radura, margini lisci; a media distanza una carta da parati; da lontano palline verdi.
- Strade e sentieri come segmenti dritti; nessun centro del villaggio; niente attorno alle porte.
- Prato di un verde uniforme; riva del fiume identica per chilometri.
- Atlanti del mondo senza mipmap (granulosi quando rimpiccioliti).

## 2. Modifiche (per passo)

**Passo 1 — geometria anti-matematica**
- Trasformazione visiva deterministica di ogni edificio (spostamento ≤ 4%, rotazione ±2,5°, scala ±5%), anche nei
  blocchi della media distanza.
- Campi a strisce (`FieldPainter`), 2–4 strisce, colture diverse, prode erbose, bordi irregolari, ruotati.
- Pianificatore del pilota a **zone**: piazza e case al centro, distretto agricolo sul lato libero, depositi e
  laboratori in mezzo, taglialegna verso il bosco; niente più raggi fissi.
- Strade e sentieri curvi; sentieri che diventano strade secondo il traffico (quante porte servono).
- Bosco con nuclei, radure, margini frastagliati e boschetti; stesso numero di alberi entro l'8%.

**Passo 2 — ambiente**
- Prato a macchie ampie e morbide (scuro, secco, terra ricca), deformate: nessuna griglia.
- Riva variabile (ghiaia, fango, sabbia) e frangia di erba umida; canneti a gruppi e sassi sulle rive.
- Margine sfruttato del bosco attorno agli insediamenti (media distanza), bosco lontano affidato all'albedo.
- Piazza centrale che cresce, sentiero al fiume, terra battuta irregolare attorno alle porte.
- Oggetti di scena per contesto (26 sprite) e bancarelle sulla piazza dei borghi.

**Passo 3 — profondità**
- Mipmap sugli atlanti; ombre già dipinte con la stessa luce (alto-sinistra) per alberi, case, persone, oggetti;
  ombra di ogni edificio che segue il suo spostamento; tinta per persona.

**Passo 4 — scala**
- Verificato su 6, 30, ~100, ~300 abitanti (A–D) e a zoom medio (K): la piazza, le strade da traffico, le
  bancarelle, i distretti agricoli crescono con il luogo.

## 3. Nuovi asset

| Atlante | Script | Contenuto |
|---|---|---|
| `assets/buildings/building_atlas.*` (1024×1024, era 1024×512) | `tools/art/draw_buildings.py` | +2 case (con annesso e camino; in pietra con ardesia), 2 cascine senza campo, varianti di magazzino, granaio, fucina, caserma — 30 sprite |
| `assets/buildings/props_atlas.*` (512×128, nuovo) | `tools/art/draw_props.py` (nuovo) | legna, tronchi, ceppi (anche con l'ascia), casse, barili, sacchi, fieno, balle, carro (vuoto e carico), carbone, staccionata, bancarelle, canneti, sassi — 26 sprite |

Tutti disegnati a codice con lo stesso stile degli altri atlanti (numpy, luce da alto-sinistra, contorno a
inchiostro). Blender non è servito come scena 3D: bastava il suo Python.

## 4. Shader

- `terrain.gdshader`: macchie del prato (tre letture di rumore in più, solo sotto 12 m/px).
- `river.gdshader`: riva variabile lungo il corso, sabbia, frangia umida.
- `vegetation.gdshader`: invariato in questo passaggio (tinta per gruppi dalla Fase 18).

## 5. Sistemi di variazione (tutti deterministici)

| Cosa | Sorgente | Dove |
|---|---|---|
| spostamento/rotazione/scala degli edifici | id dell'edificio | `SettlementLayer.visual_of` |
| strisce, colture, solchi dei campi | id della fattoria | `FieldPainter.layout` |
| variante di casa e di cascina | id | `SettlementLayer.sprite_for/_variant` |
| oggetti di scena | id e tipo dell'edificio | `SettlementProps.props` |
| canneti e sassi | fiume, segmento, passo | `RiverBankProps.chunk_items` |
| forma del bosco | posizione | `LocalFeatures.glade_factor/margin_noise/grove_chance` |
| curve di strade e sentieri | id / estremi | `SettlementLayer._draw_track` |
| tinta degli abitanti | id della persona | `PeopleLayer.clothes_of` |

Prova: `tests/unit/test_visual.gd::test_the_picture_of_the_world_is_the_same_after_a_reload`.

## 6. LOD

| Zoom (m/px) | Cosa si vede |
|---|---|
| < 1,2–1,9 | oggetti di scena, canneti, abitanti come figure, solchi dei campi |
| < 1,7 | alberi veri (banda vicina) |
| < 2,7 | sprite degli edifici, strade, sentieri, piazza, orti |
| 2,2 – 40 | blocchi degli edifici e campi a tinte piatte (`SettlementMarks`) |
| 1,3 – 9,5 | cespi di alberi con radure e margine sfruttato |
| 7,5 – 22 | cespi a icona (era fino a 40) |
| > 9–26 | albedo dipinto, montagne, confini, nomi |

## 7. Ottimizzazioni

- Campi, oggetti di scena e sentieri ricalcolati solo quando cambiano gli edifici (`buildings_version`) o il mese.
- Canneti a chunk da 512 m, dimenticati quando la camera va lontano.
- Banda «carta» del bosco spenta a 22 m/px: meno istanze da lontano.

## 8. File

Nuovi: `map/settlement/field_painter.gd`, `map/settlement/settlement_props.gd`, `map/water/river_bank_props.gd`,
`tools/art/draw_props.py`, `assets/buildings/props_atlas.*`, `WORLD_ART_AUDIT.md`, `WORLD_ART_REPORT.md`.
Modificati: `map/settlement/settlement_layer.gd`, `settlement_marks.gd`, `people_layer.gd`,
`map/vegetation/vegetation_layer.gd`, `world/local/local_features.gd`, `settlement/settlement_planner.gd`,
`shaders/terrain.gdshader`, `shaders/river.gdshader`, `data/defs/vegetation.json`, `tools/art/draw_buildings.py`,
`assets/buildings/building_atlas.*`, gli `.import` degli atlanti (mipmap), `scenes/main.tscn`, `scenes/main.gd`,
`core/boot/boot_args.gd`, `ui/settlement/settlement_hud.gd` (aggiornamento una volta per fotogramma),
`tests/unit/test_visual.gd` (+2 prove: il disegno non cambia dopo un caricamento, il bosco tiene i suoi alberi).

## 9. Prestazioni prima / dopo

Misure con `--kd-benchmark=20` (volo della camera attraverso tutte le bande di zoom, stessa macchina, stesso mondo
salvato: la cittadina di quarant'anni `world_saves_old/d_town.kdsave`, ~290 abitanti, ~230 edifici). «Villaggio» =
`--kd-bench-home` (cerchi attorno a Valverde); «Continente» = attraversamento del continente. La macchina è
condivisa: fra due misure uguali la media varia di 1–3 fps.

| | Prima (villaggio) | Dopo (villaggio) | Prima (continente) | Dopo (continente) |
|---|---|---|---|---|
| FPS medi | 112,8 | **123,0** | 119,5 | **140,3** |
| fotogramma peggiore | 111,5 ms | 108,2 ms | 147,1 ms | **93,5 ms** |
| banda lontana > 20 m/px | 97,1 | 143,2 | 98,2 | 143,6 |
| banda strategica 5–20 | 88,3 | 106,2 | 108,5 | 135,3 |
| banda locale 1–5 | 97,2 | 111,8 | 112,1 | 136,5 |
| banda vicina < 1 | 131,0 | 130,8 | 133,2 | 143,3 |
| draw call medie / massime | 1225 / 2289 | **1147 / 1960** | 203 / 1180 | 201 / 1248 |
| oggetti disegnati (massimo) | 5868 | 5637 | 3948 | 4108 |
| memoria statica | 170 MB | 172 MB | 169 MB | 171 MB |
| memoria video | 199 MB | 207 MB | 209 MB | 216 MB |

**Simulazione** (non toccata dal disegno, ma misurata): 60 anni del test di stress 344,5 s (codice di prima:
355 s); quarant'anni di villaggio col pianificatore nuovo 151 s (prima 146 s: il villaggio cresce diverso).
**Un difetto trovato dal benchmark e corretto**: in una cittadina di trecento abitanti ogni giorno di gioco costava
**246 ms** (un fotogramma perso al giorno), perché la HUD si ricalcolava a ogni «insediamento cambiato» — uno per
edificio al lavoro. Ora la HUD prende nota e si aggiorna una volta per fotogramma: **11,6 ms** al giorno.

Dove sono andate le misure di questo passaggio: i campi di tutta la mappa in una sola mesh (erano migliaia di
comandi di disegno per i solchi), il terreno a terra (sentieri, strade, orti, campi, ombre) disegnato da un figlio
che si ridisegna solo quando cambiano gli edifici o il mese, i blocchi della media distanza senza trasformazioni,
i cespi del bosco che guardano solo gli edifici vicini (secchi da 128 m), un budget di 4 ms per costruire blocchi
di bosco in un fotogramma, i canneti con un indice dei fiumi costruito all'avvio.

## 10. Limiti ancora presenti

- **Ponti e guadi**: nel gioco nessuna strada può attraversare un fiume (il piazzamento lo vieta), quindi non c'è
  alcun attraversamento da disegnare. Arriveranno con la meccanica dei ponti.
- **Macchine d'assedio e picchieri**: non esistono come unità. Le quattro unità che esistono si distinguono già
  (Fase 18: blocchi per reggimento, pennoni diversi, micro-scarti).
- **Il pianificatore a zone** vale per il pilota e gli scenari; i villaggi del giocatore sono disposti dal
  giocatore. Il disegno (rotazioni, campi a strisce, sentieri, oggetti, terra battuta) vale per tutti.
- **Dentro un bosco fitto, da vicino** (0,4–1 m/px) resta un tappeto di chiome: le radure e i margini ci sono, ma un
  nucleo fitto è fitto. Non ho aggiunto un «tetto di chioma» a media distanza: l'albedo dipinto e le macchie
  del prato bastavano a non vedere più le palline verdi.
- **Movimento degli abitanti**: non toccato. Nella simulazione dettagliata ogni spostamento ha già una meta (casa,
  lavoro, deposito, cantiere, forno); i «passeggiatori» sono gli inattivi.
- **Terreno**: variazione di tinta e macchie, nessuna texture nuova (niente fotografico, come chiesto); nessuna
  normal map né Light2D: le ombre sono dipinte e condividono la luce da alto-sinistra.
- **Fotogramma peggiore ~95–110 ms**: resta quando si attraversano le bande di zoom (costruzione dei blocchi di
  bosco) e quando si guarda da vicino una cittadina grande (la simulazione ora per ora di 290 persone, 15 ms per
  tick). Da guardare in Fase 19.
- **Mondi di prova B–D rigenerati**: il pilota ora dispone gli edifici per zone, quindi le foto «dopo» di B, C, D
  sono villaggi cresciuti con lo stesso seme ma disposti diversamente (vedi nota in cima).

