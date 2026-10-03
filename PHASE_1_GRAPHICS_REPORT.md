# KING'S DOMAIN — Fase 1: grafica della Valle

Obiettivo della fase: dimostrare che King's Domain può essere **visivamente bello**, costruendo il luogo in cui il
giocatore passerà gran parte della partita. Nessun gameplay definitivo: valle, acqua, foreste, montagne, campi,
edifici, cittadini, strade, camera e un insediamento dimostrativo.

Tutto ciò che si vede è **generato da codice** (Python + Blender 4.5 + Godot 4.7.2) e quindi rigenerabile e
migliorabile. Nessun asset è stato disegnato a mano né preso da librerie esterne.

<!-- SCREENSHOTS -->

---

## 1. Cosa è stato realizzato

### 1.1 La Valle di Altavera (3,1 × 2,6 km giocabili + montagne di fondale)
Disegnata da me (non copiata dal riferimento), costruita attorno alla camera che guarda a nord:

| Elemento | Realizzazione |
|---|---|
| Montagne a nord (fondale) | 9 vette nominate e creste di collegamento, profilo concavo (ripide in alto, dolci al piede), modulazione *ridged multifractal* per creste frastagliate, **erosione stream-power** (valli dendritiche) + **erosione idraulica a gocce** a 4 m e 2 m + gradoni rocciosi e speroni. Neve sopra ~560 m e nei canaloni. |
| Catena ovest | 4 vette più basse, rocciose, con boschi di conifere al piede |
| Altopiano est | **mesa** con cornici di roccia a due salti, sezionata dall'erosione, coperta di bosco |
| Colline sud | basse e boscose (non devono nascondere il fondovalle alla camera) |
| Gole | il Fiume Argento entra da una gola a nord-est con **due cascate** ed esce da una gola a sud |
| Valle sospesa | a nord-ovest, con la **cascata del Torrente Bianco** (~37 m) rivolta verso la camera |
| Rocca | colle roccioso tra i due fiumi, spianato in cima per il castello |
| Lago Specchio | lago irregolare a sud-ovest, profondità fino a 11 m |
| Rio Ponente | ruscello dalla catena ovest al lago |

### 1.2 Terreno
Materiali con transizioni morbide: erba (tre tonalità + macchie di trifoglio e fiori), prato alpino, terreno
fertile vicino all'acqua, terra, fango sulle rive, sabbia/ghiaia ai bordi dei fiumi, ghiaione, roccia (calda/fredda,
stratificata), neve, sottobosco sotto le chiome. Luce: sole da ovest-sud-ovest con **ombre portate calcolate**
(anche le ombre delle montagne sul fondovalle), occlusione ambientale multi-scala, accentuazione di creste e
cavità, **normali di dettaglio per pixel** sulla roccia. Da vicino lo shader aggiunge texture di dettaglio
(fili d'erba, aghi, sassi, crepe) che spariscono da lontano senza cambiare il colore.

### 1.3 Acqua
Shader animato su dati cotti (profondità, direzione e velocità del flusso, schiuma):
colore per profondità (riva trasparente → blu profondo), increspature trasportate dalla corrente
(*flow mapping* a due fasi), increspature lente del vento sul lago, **creste di onda pittoriche**, riflessi,
schiuma di riva che "respira", rapide, **cascate con strisce che scendono e spruzzi alla base**, ombre delle
montagne sull'acqua, massi nei tratti bassi dei fiumi, alberi ripariali lungo le rive.

### 1.4 Foreste
~150.000 alberi in 26 sprite (abeti ×4, pecci ×2, pini ×2, querce ×3, faggi ×2, betulle ×2, pioppi ×2, alberi da
frutto ×3, cespugli ×4, albero secco) + 6 rocce. Ogni chioma è fatta di **migliaia di ciuffi di foglie/aghi
istanziati** in Blender, con ombra portata separata. Distribuzione: boschi di conifere sui versanti fino al limite
del bosco, boschi misti e boschetti sul fondovalle (con radure), filari lungo i corsi d'acqua, alberi isolati e
siepi nei prati. Disegno con **MultiMesh2D a strisce di 32 m** (101 draw call per l'intera valle).

### 1.5 Edifici (libreria Blender, 17 tipi richiesti + varianti)
Kit architettonico procedurale: muri intonacati con **vera intelaiatura a graticcio**, zoccoli in pietra,
tetti a capanna/padiglione/cono con materiali **coppi sovrapposti / ardesia / scandole / paglia**, finestre con
imposte, porte con gradino, camini, abbaini, merlature.

| Tipo richiesto | Sprite |
|---|---|
| casa semplice | 5 varianti (paglia, coppi, legno con tettoia, pietra, intonaco) × 3 orientamenti |
| casa più ricca | 3 varianti (2–3 piani, sporto, abbaini) × 3 orientamenti |
| fattoria | casa + fienile + covone + carro + recinto |
| granaio | su pilastrini in pietra, rampa di carico, sacchi |
| segheria | tettoia aperta, banco con tronco, cataste di tronchi e tavole |
| cava | parete rocciosa a gradoni, blocchi squadrati, gru a ruota |
| miniera | ammasso roccioso, ingresso armato, binari, carrello, cumulo di minerale, capanno, lanterna |
| mulino | mulino a torre con **pale animate (8 fotogrammi)** |
| mercato | 5 bancarelle con tende a strisce e merci + pozzo |
| fabbro | casa in pietra + forgia aperta con **brace incandescente**, incudine, abbeveratoio |
| caserma | edificio a due piani, cortile d'addestramento con fantocci, rastrelliera, stendardi |
| stalla | stalle con mezze porte, fienile, recinto, abbeveratoio, balle |
| torre | torre di guardia rotonda con tetto conico |
| mura | segmenti in 4 orientamenti, torri, porte fortificate (2 orientamenti) |
| ponte | ponte in pietra a 4 arcate (Fiume Argento) e ponte in legno (Torrente Bianco), su misura del guado |
| edificio amministrativo | palazzo comunale con portico, due piani a graticcio, campanile con orologio |
| castello iniziale | mastio con torrette angolari, cinta muraria pentagonale con 5 torri, porta, sala |
| oggetti | botti, casse, sacchi, cataste, covoni, balle, carri, spaventapasseri, recinzioni in 8 orientamenti |

### 1.6 Cittadini
7 ruoli (contadino, boscaiolo, minatore, costruttore, mercante, soldato, cittadino) riconoscibili da abiti,
copricapo e attrezzo; animazioni **idle (4), walk (8), carry (8), work (8)** in 5 direzioni renderizzate + 3
specchiate = 8 direzioni. Nella demo ~250 cittadini camminano sulle strade, trasportano merci, lavorano nei
campi, alla cava, alla miniera, alla segheria, si muovono in piazza, fanno la guardia alle porte.

### 1.7 Strade, campi, insediamento dimostrativo
- Strade: nastri lisci (Catmull-Rom) che seguono il terreno, larghezza variabile, solchi delle ruote, sassi, bordi
  erbosi irregolari; tre classi (strada maestra, vicolo, sentiero); acciottolato solo in piazza.
- Campi: patchwork irregolare (nessun rettangolo identico) in 5 zone agricole + orti dietro le case; colture
  grano, orzo, terra arata, ortaggi a file, fieno a strisce, lino in fiore; capezzagne, recinti, siepi,
  covoni, spaventapasseri, carri.
- **Altavera**: borgo murato compatto a nord della Rocca, case a schiera lungo vie curve, piazza del mercato
  con palazzo comunale, tre porte, castello sulla Rocca, due ponti, caserma, fabbro, granaio, stalla, mulino,
  segheria, cava, miniera, cinque fattorie con frazioni, fumo dai camini, ombre delle nuvole.

### 1.8 Camera
Zoom esponenziale fluido verso il cursore (rotellina), pan con WASD/frecce e trascinamento, limiti sul terreno.
Zoom da **1.0** (32 px/m: cittadini ed edifici) a **~0.02** (tutta la valle). F3 mostra FPS e draw call.

---

## 2. Pipeline (rigenerabile)

```
pipeline/setup_env.sh                       # ambiente (Python + bpy 4.5 + Godot 4.7.2)
python -m terrain.build_terrain             # valle: altezze, erosione, acque, materiali, luce, proiezione
python textures/make_detail.py              # texture di dettaglio e dell'acqua
python blender/vegetation.py                # alberi, cespugli, rocce (Cycles)
python blender/buildings.py                 # edifici, ponti, oggetti, recinzioni (Cycles)
python blender/citizens.py                  # cittadini e animazioni (Cycles)
python layout/demo_town.py                  # insediamento dimostrativo
python -m terrain.plan_vegetation           # atlante + distribuzione della vegetazione
python godot_import.py                      # impostazioni di import (dati esatti, VRAM compressa)
pipeline/capture.sh res://data/capture/phase1_views.json <cartella>   # screenshot + misure
```

<!-- REST -->
