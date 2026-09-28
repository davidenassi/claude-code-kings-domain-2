# WORLD ART AUDIT — come è disegnato il mondo, prima di cambiarlo

Scritto leggendo il codice e guardando le schermate standard `tests/output/wa0_*.png` (serie «prima»). La
simulazione resta com'è: qui si guarda **come viene mostrata**. Ogni voce dice dove sta, chi la genera, cosa non
va, cosa faccio e quanto costa.

## Come è fatto oggi il disegno del mondo (verificato)

| Livello (ordine di scena, `scenes/main.tscn`) | File | Cosa disegna | Zoom |
|---|---|---|---|
| `TerrainLayer` | `map/terrain/terrain_layer.gd`, `shaders/terrain.gdshader` | un quad sulla vista: colori di bioma sfumati, grana vicina, rilievo, roccia/neve, acqua; oltre 9–26 m/px l'albedo dipinto; tinta delle modalità mappa | tutti |
| `RiverLayer` | `map/water/river_layer.gd`, `shaders/river.gdshader` | 192 fiumi come nastri; da vicino la riva di ghiaia | tutti |
| `MountainLayer` | `map/terrain/mountain_layer.gd`, atlante 12 sprite | sagome dipinte in MultiMesh | sopra 5–8 m/px |
| `VegetationLayer` | `map/vegetation/vegetation_layer.gd`, `shaders/vegetation.gdshader`, `data/defs/vegetation.json` | tre bande a chunk MultiMesh: **vicina** (0–1,7 m/px) gli alberi veri di `LocalFeatures`; **media** (1,3–9,5) cespi di alberi; **carta** (7,5–40) cespi ingranditi come icone | a bande |
| `SettlementLayer` | `map/settlement/settlement_layer.gd`, atlante edifici | sentieri, strade, orti, terra battuta, ombre, sprite degli edifici, cantieri | sotto 2,7 m/px |
| `SettlementMarks` | `map/settlement/settlement_marks.gd` | ogni edificio come blocco leggibile | 2,2–40 m/px |
| `PeopleLayer` | `map/settlement/people_layer.gd`, atlante persone (83 sprite) | abitanti; punti colorati quando troppo piccoli | sotto 2,4 m/px |
| `ArmyLayer` | `map/military/army_layer.gd` | reggimenti in blocchi da vicino, vessillo col numero da lontano | sotto 45 m/px |
| `BorderLayer` | `map/borders/*` | confini di regno (alone, linea, banda) e di provincia (sottili) | tutti |
| `MapLabels` | `map/labels/map_labels.gd` | nomi di regni, province, segnaposto degli insediamenti | a bande |

- **Zoom/LOD**: ogni livello legge `WorldCamera.meters_per_pixel()` e sfuma per conto suo (costanti nei file e
  in `vegetation.json`); non c'è un punto unico, ma le bande sono coerenti fra loro.
- **Casualità esistente**: tutto è **deterministico** con `KDRng.hash01(a, b, salt)` (alberi, rocce, varianti
  delle case per id). Nessun `randf` nel disegno.
- **Asset davvero usati**: atlante edifici (22 sprite, di cui 3 case), vegetazione (40 sprite: 11 specie singole
  con 1–3 varianti, 5 tipi di cespo), montagne (12), persone (83), kit UI. Tutti prodotti da script Python
  (`tools/art/draw_*.py`, numpy) — non da scene 3D.
- **Import**: i quattro atlanti del mondo **non hanno mipmap** (`mipmaps/generate=false`) mentre il filtro di
  progetto è «lineare con mipmap»: da lontano gli sprite rimpiccioliti sfarfallano e sembrano granulosi.

## Da dove viene il «mondo matematico» (le cause, non i sintomi)

1. **Gli edifici del pianificatore stanno su anelli**: `SettlementPlanner.find_spot` prova 16 direzioni su cerchi
   distanti 12 m e prende il primo posto libero → case e campi su circonferenze concentriche e a distanze uguali.
2. **Tutti gli sprite sono dritti e uguali**: nessuno ruota o cambia misura; tre sole case; il campo è un unico
   sprite rettangolare 26×30 m con i solchi orizzontali, identico per ogni fattoria.
3. **Gli alberi vicini sono uno per cella di 12 m** (`LocalFeatures.cell_feature`), con probabilità che dipende
   solo dalla densità del bosco: dove il bosco è uniforme la distribuzione è un «campionamento a disco»
   regolarissimo, senza nuclei né radure.
4. **Le strade sono segmenti dritti** fra due punti, e i sentieri linee rette fra le porte.
5. **Il terreno vicino** è un verde di bioma con una grana fine: nessuna macchia ampia, niente terreno umido
   lungo i fiumi, nessuna differenza fra prato, pascolo e terra lavorata.
6. **Da lontano il bosco è fatto di migliaia di icone uguali** (banda «carta», 7,5–40 m/px).

---

## KEEP

| Elemento | File | Perché resta | Costo |
|---|---|---|---|
| Carta del continente, albedo dipinto, mare | `terrain.gdshader`, `tools/worldgen` | la banda migliore del gioco | — |
| Montagne dipinte | `mountain_layer.gd`, atlante | sagome grandi, ombra coerente, altezza suggerita | — |
| Confini (regno > provincia) e tinta politica | `border_layer.gd`, `map_modes.json` (forza 0,26) | la tinta è già semitrasparente e il rilievo resta leggibile | — |
| Stile degli sprite (luce da alto-sinistra, ombra in basso a destra) | `tools/art/draw_*.py` | coerente fra alberi, edifici, persone | — |
| Chunk MultiMesh della vegetazione | `vegetation_layer.gd` | già a chunk, ricostruiti solo quando cambia il terreno | — |
| Determinismo (`KDRng.hash01`) | ovunque | nessuna casa cambia dopo il caricamento | — |
| Blocchi da lontano, figure in scala, formazioni | `settlement_marks.gd`, `people_layer.gd`, `army_layer.gd` | fatti in Fase 18 | — |

## IMPROVE

| Elemento | File / sistema | Problema | Soluzione | Costo stimato |
|---|---|---|---|---|
| **Posizione visiva degli edifici** | `SettlementLayer._draw_sprite` | tutti dritti, allineati | trasformazione **solo visiva** e deterministica dall'id: spostamento ≤ 4% della misura, rotazione ±3°, scala ±5%; la posizione logica non cambia | nullo (una trasformazione per sprite) |
| **Scelta dei posti del pianificatore** | `SettlementPlanner.find_spot`, `lord_month` (usati da scenari e pilota, non dal giocatore) | anelli concentrici | spirale con angolo aureo e scarto deterministico; case vicine al centro, campi raccolti in un distretto agricolo, depositi e laboratori in mezzo | nullo |
| **Campi** | sprite `farm_*`, `SettlementLayer` | rettangolo unico, solchi sempre orizzontali | il campo disegnato a mano: 2–4 **strisce** (come i campi aperti medievali) con bordi irregolari, leggera rotazione, direzione dei solchi per striscia, prode erbose fra le strisce; cinque stati visivi (arato, seminato, in crescita, maturo, stoppie); la cascina resta sprite | basso (poligoni per campo, ridisegnati solo al cambio edifici/mese) |
| **Strade e sentieri** | `SettlementLayer._draw_road/_draw_track/footpaths` | segmenti dritti | curva leggera deterministica, larghezza che cambia, slarghi agli incroci e alle estremità, sentiero verso il fiume | basso |
| **Alberi vicini** | `LocalFeatures.cell_feature`, `vegetation.json` | distribuzione a disco uniforme | la probabilità di ogni cella modulata dallo stesso rumore delle radure della banda media, **a media invariata** (lo stesso numero di alberi in totale: la legna disponibile non cambia di media); boschetti fuori dal bosco a piccoli gruppi | nullo in resa; tocca quali celle hanno un albero (verificato con prove e campagna) |
| **Varietà degli alberi** | `vegetation_layer.gd` | alberi simili | scala per posizione nel bosco (nucleo più alti, margini più bassi), tinta per gruppo | nullo |
| **Terreno vicino e medio** | `terrain.gdshader` | verde uniforme | macchie ampie e morbide (prato scuro, prato secco, terreno fertile) con rumore deformato, nessuna griglia | basso (3 letture di rumore in più sotto 9 m/px) |
| **Rive** | `river.gdshader` | bordo uniforme identico | larghezza della riva che varia lungo il corso, fascia di erba umida esterna, sabbia/fango a tratti | nullo |
| **Integrazione edificio/terreno** | `SettlementLayer._draw_ground_patch` | cerchio di terra uguale per tutti | chiazza irregolare, più ampia davanti alla porta | nullo |
| **Varianti degli edifici** | `tools/art/draw_buildings.py` | 3 case, 1 variante per il resto | 5 case (annesso, camino, pietra, recinto), 2 cascine, varianti di magazzino, granaio, fucina, caserma | memoria: atlante da 1024×512 a 1024×1024 |
| **Filtraggio** | `.import` degli atlanti | niente mipmap | mipmap sugli atlanti che cambiano molto scala (vegetazione, edifici, montagne, persone) | +33% di memoria video degli atlanti (pochi MB) |
| **Bosco da lontano** | banda «carta» di `vegetation.json` | migliaia di palline | la banda si spegne prima e disegna meno cespi più grandi dove il bosco è fitto; sotto, l'ombra di chioma nello shader lega le masse | meno istanze di prima |

## REPLACE

| Elemento | File | Con cosa | Costo |
|---|---|---|---|
| Campo come sprite unico | `farm_bare/green/ripe` | cascina sprite + campo procedurale a strisce | basso |
| Case identiche su 3 modelli | atlante | 5 modelli e trasformazione visiva | basso |

## REMOVE

| Elemento | Perché |
|---|---|
| Cespi della banda «carta» sopra i 20 m/px | l'albedo dipinto disegna già le foreste: le icone sopra sono le «palline verdi» |

## NUOVO

| Elemento | Dove | Costo |
|---|---|---|
| **Oggetti di scena** (legna, ceppi, tronchi, casse, barili, sacchi, fieno, carro, carbone, attrezzi) | `tools/art/draw_props.py` → atlante; posati per contesto attorno agli edifici, solo da vicino, nessuna collisione | basso (disegnati solo sotto ~1,5 m/px) |
| **Canneti, sassi e fango lungo le rive** | nuovo livello decorativo a chunk | basso (solo vicino) |
| **Centro del villaggio** (slargo battuto attorno al pozzo/mastio) e mercato nei borghi | `SettlementLayer` | nullo |

## Fuori da questa fase (dichiarato)

- **Ponti e guadi**: oggi nessuna strada può attraversare un fiume (il piazzamento lo vieta: «servono ponti»),
  quindi non c'è nessun attraversamento da disegnare. Arriveranno con la meccanica.
- **Macchine d'assedio e picchieri**: non esistono come unità nel gioco (ci sono lancieri, alabardieri,
  balestrieri, cavalieri): non si disegna ciò che non esiste.
- **Luci dinamiche**: nessuna; luce e ombre restano dipinte (economico e coerente).

