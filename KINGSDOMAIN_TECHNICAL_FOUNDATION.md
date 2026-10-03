# KING'S DOMAIN — Fondamenta tecniche

Documento della **premessa tecnica obbligatoria**, scritto prima della Fase 1.
Serve a fissare le decisioni strutturali che sarebbe costoso cambiare dopo: scala, prospettiva,
coordinate, pipeline degli asset, prestazioni. Tutto il resto resta libero di evolvere.

Il nuovo King's Domain nasce **da zero**. I file del vecchio progetto (`1_documenti.txt` … `5_strumenti.txt`,
`LEGGIMI.md`) restano nella radice del repository intatti, solo come fonte concettuale (risorse, regno,
eserciti, diplomazia, indicatori). Nessuna riga di codice, nessuna scena e nessuna struttura della mappa
del vecchio progetto viene riusata.

---

## 1. Verifica dell'ambiente (eseguita il 03/10/2026)

| Strumento | Esito | Dettagli |
|---|---|---|
| **Godot 4.7.2** | ✅ verificato | Binario ufficiale scaricato da GitHub (`Godot_v4.7.2-stable_linux.x86_64`). `--version` → `4.7.2.stable.official.ed1daf0bf`. |
| Rendering Godot | ✅ verificato | Sotto Xvfb con Mesa **llvmpipe** (OpenGL 4.5 Core, LLVM 20). Renderer *Compatibility*. Cattura di uno screenshot reale riuscita. |
| Vulkan (Forward+/Mobile) | ❌ non disponibile nel container | Nessun driver Vulkan installato. Non blocca: il gioco è 2.5D e usa il renderer *Compatibility* (vedi §4). |
| **Blender** | ⚠️ verificato con limite | Il binario da `download.blender.org` è **bloccato dalla rete del container (HTTP 403)**. Installato invece **Blender 4.5.4 LTS come modulo Python `bpy`** da PyPI: stesso motore, stesso **Cycles**, stesso API. Verificati: render Cycles CPU, denoiser **OpenImageDenoise**, *shadow catcher*, film trasparente. Gli script girano identici anche con un Blender 4.5 installato normalmente (`blender -b -P script.py`). |
| **Python** | ✅ 3.11.15 | numpy 1.26.4, Pillow 12.3, scipy 1.17.1, **numba 0.68** (per erosione e rasterizzazione veloci). |
| Hardware del container | 4 core CPU, 15 GB RAM, **nessuna GPU** | Le misure di FPS fatte qui sono su CPU (llvmpipe) e **non** rappresentano una GPU reale: vedi §9. |

Riproducibilità: `pipeline/setup_env.sh` crea l'ambiente Python (`pipeline/requirements.txt`) e scarica Godot 4.7.2.

---

## 2. Struttura del repository

```
/                                   radice del repository
├─ KINGSDOMAIN_TECHNICAL_FOUNDATION.md   questo documento
├─ PHASE_1_GRAPHICS_REPORT.md            report della Fase 1
├─ screenshots/phase1/                    screenshot ufficiali della Fase 1
├─ game/                                  PROGETTO GODOT 4.7.2 (aprire questa cartella)
│  ├─ project.godot
│  ├─ core/            autoload: Proj (proiezione, conversioni, altezze del terreno)
│  ├─ valley/          la Valle (scala city builder)
│  │  ├─ terrain/      chunk del terreno pre-renderizzato + shader di dettaglio
│  │  ├─ water/        shader dell'acqua (fiumi, lago, cascate)
│  │  ├─ vegetation/   foreste e vegetazione (MultiMesh per chunk)
│  │  ├─ roads/        strade organiche (mesh a nastro)
│  │  ├─ fields/       campi (poligoni con shader delle colture)
│  │  ├─ buildings/    registro e nodi degli edifici
│  │  ├─ citizens/     cittadini animati
│  │  ├─ camera/       camera con zoom fluido e limiti
│  │  └─ demo/         insediamento dimostrativo (Fase 1)
│  ├─ gallery/         scene di prova (libreria edifici, cittadini)
│  ├─ tools/           cattura screenshot automatica, misure prestazioni
│  ├─ data/            JSON: proiezione, metadati terreno, layout, atlanti
│  └─ assets/          asset GENERATI dalla pipeline (non modificare a mano)
│     ├─ terrain/      chunk del terreno, mappe acqua/materiali, griglia altezze
│     ├─ textures/     texture di dettaglio ripetibili
│     └─ sprites/      edifici, alberi, oggetti, cittadini (atlanti + JSON)
├─ pipeline/           GENERATORI DEGLI ASSET (Python + Blender)
│  ├─ kd/const.py      unica fonte di verità per scala, proiezione e luce
│  ├─ terrain/         generatore della valle (altezze, erosione, acque, materiali, luce, proiezione)
│  ├─ blender/         modellazione procedurale + render Cycles di edifici, alberi, cittadini
│  ├─ textures/        texture di dettaglio procedurali
│  └─ setup_env.sh / requirements.txt
└─ 1_documenti.txt … 5_strumenti.txt, LEGGIMI.md   (vecchio progetto: solo riferimento concettuale)
```

Regola: **gli asset in `game/assets/` sono prodotti dalla pipeline**. Si rigenerano, non si ritoccano a mano.
Così ogni miglioramento grafico si ottiene cambiando il generatore e rilanciandolo.

---

## 3. Risoluzione e scala

| Valore | Scelta | Motivo |
|---|---|---|
| Risoluzione di riferimento | **1920×1080**, stretch `canvas_items`, aspect `expand` | target richiesto; l'interfaccia (Fase 2) sarà progettata a 1080p e scalata. |
| Unità di gioco | **metro** (x est, y sud, z alto) | la simulazione ragiona in metri; edifici, persone e alberi hanno misure credibili. |
| Pixel per metro a zoom 1.0 | **32 px/m** | zoom 1.0 è lo zoom più vicino: una persona è alta ~40 px, una casa ~200–260 px di larghezza. |
| Risoluzione nativa degli sprite | **32 px/m**, renderizzati a 64 px/m e ridotti (2× supersampling) | a zoom massimo gli sprite non vengono mai ingranditi → nitidi. |
| Dimensione della Valle | **3072 × 2560 m** (+640 m di montagne a nord, solo scenografia) | contiene una capitale murata, villaggi, campi, foreste, miniere e lascia spazio di crescita. |
| Terreno pre-renderizzato | **2 texel/m** proiettati, chunk da 1024² | sufficiente da lontano; da vicino il dettaglio arriva dallo shader (§6.2). |
| Zoom | da **1.0** (vicino) a **~0.02** (valle intera), continuo | lontano: tutta la valle; medio: villaggi; vicino: edifici e cittadini. |

Misure di riferimento: persona 1,75 m · casa semplice 6–8 m · casa ricca 9–11 m · conifera 9–16 m ·
castello iniziale ~45 m · mura alte 7–9 m.

---

## 4. Rendering

- **Renderer: Compatibility (OpenGL 3.3 / GLES3).** Il gioco è 2.5D: terreno, edifici, alberi e cittadini sono
  immagini pre-renderizzate disegnate dal motore 2D. Il renderer Compatibility copre completamente il 2D
  (shader canvas, MultiMesh2D, mipmap), gira sull'hardware più vecchio e integrato, ed è l'unico verificabile
  in questo ambiente. Passare a Forward+ in futuro non richiede di cambiare scene o shader 2D.
- **Nessun 3D in tempo reale.** Il 3D vive in Blender: si modella, si illumina con Cycles, si salva come sprite.
  In gioco costa quanto un'immagine.

---

## 5. Prospettiva della camera e sistema di coordinate

### 5.1 La camera
- **Ortografica obliqua, top-down inclinata.** Nessuna prospettiva conica: la scala non cambia con la distanza,
  quindi lo stesso sprite vale ovunque nella valle.
- **Elevazione 50°** sopra l'orizzonte. Compromesso fra leggibilità della pianta (campi, strade, quartieri) e
  lettura delle facciate (edifici riconoscibili), come nell'immagine di riferimento.
- **Yaw 0°: si guarda verso nord.** Il nord è in alto sullo schermo. Le montagne alte stanno a nord e fanno da
  fondale; a sud la valle è chiusa da colline basse, che non nascondono il fondovalle.
- La camera **non ruota**. Le varietà di orientamento degli edifici si ottengono con render a più angoli.

### 5.2 Le formule (identiche in Python, Blender e Godot)
```
mondo (metri):  x → est,  y → sud,  z → alto
Godot (px):     X = x · 32
                Y = (y · sin50° − z · cos50°) · 32  =  (0,766·y − 0,643·z) · 32
Blender:        x → est,  y → NORD (y_blender = −y_mondo),  z → alto
                camera ORTHO, rotazione X = 40°, ortho_scale = larghezza_px / 32
```
Le costanti stanno in `pipeline/kd/const.py` e sono esportate in `game/data/projection.json`, letto
dall'autoload `Proj` di Godot. Nessuna costante di proiezione è scritta a mano altrove.

### 5.3 Ordinamento (chi sta davanti)
- Ogni oggetto ha la **posizione del nodo** alla sua base sul piano: `(x·32, y·sin50·32)`, **senza** la quota.
- La quota del terreno entra come **offset dello sprite** (`−z·cos50·32`).
- Così l'ordinamento Y di Godot (`y_sort_enabled`) confronta la profondità reale (y del mondo) anche su
  pendii e colline.

### 5.4 Strati di disegno (dal basso)
1. terreno pre-renderizzato (chunk) + shader di dettaglio
2. acqua (shader animato sulle zone d'acqua del terreno)
3. decalcomanie del suolo: campi, strade, piazze, terra battuta
4. **ombre** di edifici e alberi (strato unico, sotto a tutti gli oggetti → nessuna ombra disegnata sopra un tetto)
5. oggetti ordinati per profondità: alberi, edifici, cittadini, oggetti di scena
6. effetti (fumo, uccelli, nuvole) — più avanti
7. interfaccia (CanvasLayer) — Fase 2

### 5.5 Luce
Un solo sole per tutto il gioco: **da ovest-sud-ovest, 42° di altezza**, luce calda; cielo azzurro come luce
ambiente. Illumina le facciate rivolte verso la camera e i fianchi ovest; le ombre cadono verso est-nord-est.
Terreno (Python) e sprite (Blender/Cycles) usano lo stesso vettore e gli stessi colori → nessuno sprite
"incollato" con una luce diversa.

---

## 6. Pipeline degli asset

### 6.1 Terreno della Valle (Python + numpy + numba)
```
layout della valle (fiumi, lago, colle del castello, zone abitate)
 → altezze: rumore frattale + maschere + profilo della valle
 → erosione idraulica a particelle + erosione termica (numba)
 → idrografia: alvei scavati lungo curve, livelli dell'acqua, cascate, lago, flusso
 → materiali: erba, prato, terreno fertile, terra, fango, ghiaia, roccia, neve, sottobosco
 → luce: normali, ombre portate del sole, occlusione ambientale, cavità/creste
 → proiezione obliqua (rasterizzazione della superficie a colonne, esatta per camera ortografica)
 → chunk 1024² (colore) + mappe dati (acqua: profondità/flusso/schiuma; materiali) + griglia altezze
```
Uscita in `game/assets/terrain/` + `game/data/valley/terrain.json`.
Tutto ciò che è **naturale** viene cotto nel terreno. Tutto ciò che è **costruito** (strade, campi, edifici)
è disegnato in gioco sopra al terreno, perché nella Fase 2 il giocatore lo potrà cambiare.

### 6.2 Dettaglio del terreno da vicino
Il terreno cotto ha 2 texel/m: perfetto da lontano, morbido da vicino. Lo shader del terreno moltiplica il
colore cotto per **texture di dettaglio ripetibili** (erba, sottobosco, terra, roccia, ghiaia, neve) scelte dalla
mappa dei materiali, con media 1,0 → da lontano scompaiono (mipmap), da vicino aggiungono fili d'erba,
sassi e crepe senza cambiare il colore generale.

### 6.3 Sprite (Blender 4.5 + Cycles)
```
modello procedurale in Python (bpy) — kit: muri, tetti, travature, finestre, torri, merli…
 → materiali procedurali (intonaco, legno, pietra, coppi, ardesia, paglia)
 → camera ortografica di progetto (50°), sole e cielo di progetto
 → render 1: CORPO (RGBA, senza suolo)
 → render 2: OMBRA (shadow catcher, oggetto invisibile alla camera) → alfa = ombra
 → Pillow: riduzione 2×→1×, ritaglio, ancoraggio al punto a terra, gradazione colore
 → atlanti PNG + JSON (ancora, ingombro, varianti, fotogrammi)
```
Animazioni (mulino, cittadini) = fotogrammi renderizzati. Direzioni dei cittadini: 5 renderizzate
(S, SE, E, NE, N) + 3 specchiate.

### 6.4 Import in Godot
- Chunk del terreno: compressione VRAM, mipmap.
- Mappe dati (acqua, materiali): lossless, senza mipmap dove servono valori esatti.
- Atlanti sprite: lossless con mipmap (lo zoom va da 1.0 a 0.02).

---

## 7. Tecniche di prestazione previste (usate quando servono davvero)

| Problema | Tecnica |
|---|---|
| Valle grande (≈ 6000×5000 texel di terreno) | chunk 1024² → si disegnano solo quelli visibili (culling del CanvasItem) |
| Decine di migliaia di alberi | **MultiMesh2D a strisce orizzontali di 32 m** (101 strisce per la valle), istanze ordinate per profondità; anche recinzioni e piccoli oggetti usano lo stesso atlante |
| Ombre | strato ombre separato, anch'esso MultiMesh |
| Molti edifici | atlanti condivisi → batching 2D di Godot |
| Cittadini | nascosti / semplificati sotto una soglia di zoom; animazione a passo ridotto quando lontani |
| Zoom molto lontano | mipmap; in Fase 4, se necessario, impostori di foresta cotti nel terreno |

---

## 8. Target prestazionali

| Metrica | Target |
|---|---|
| Risoluzione | 1920×1080 |
| FPS | **60** su GPU di fascia media (es. GTX 1060 / RX 580); ≥ 30 su grafica integrata recente |
| Draw call 2D | < 1.500 nella vista peggiore |
| VRAM | < 1,5 GB in Fase 1 |
| RAM | < 2 GB in Fase 1 |
| Avvio della valle | < 5 s |
| Cittadini animati visibili | ≥ 300 senza cali (Fase 2: rappresentazione per popolazioni grandi) |

La grafica deve poter scalare: le opzioni di qualità previste sono densità della vegetazione, risoluzione
del terreno (mipmap di partenza), numero di cittadini disegnati e animazioni dell'acqua.

---

## 9. Limiti dichiarati (principio 7)

| Problema | Causa | Limite | Soluzioni | Scelta |
|---|---|---|---|---|
| Niente GPU nel container | ambiente cloud senza scheda video | FPS misurati qui sono su CPU e molto più bassi di un PC reale | (a) misurare draw call, nodi, memoria qui e FPS sul PC dell'utente; (b) stimare | (a): misure oggettive qui + script di benchmark incluso da lanciare su GPU reale |
| Blender standalone non scaricabile | rete del container: `download.blender.org` → 403 | nessuna interfaccia grafica di Blender | `bpy` da PyPI (stesso Cycles) | `bpy` 4.5.4 LTS; script compatibili con Blender 4.5 standalone |
| Nessun artista umano / nessun asset esterno | asset solo generati proceduralmente | qualità dipendente dai generatori | Blender + Cycles per volumi e luce reali, post-processo pittorico | pipeline procedurale interamente rigenerabile; gli asset temporanei saranno dichiarati nel report |
| Audio | nessuno strumento di generazione audio professionale | — | — | si affronta in Fase 4 come richiesto: sistema + elenco asset mancanti |

---

## 10. Cosa riprendiamo concettualmente dal vecchio King's Domain

Solo idee, non codice: le risorse (oro, cibo, legno, pietra, ferro, popolazione, uomini in armi), il regno con
corte e legittimità, eserciti, diplomazia e pochi indicatori chiari. Tutto verrà riprogettato nelle Fasi 2–4
attorno alla nuova identità (Valle = casa, Mondo = conquista).
