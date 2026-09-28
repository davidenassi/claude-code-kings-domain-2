# HUD REFACTOR PLAN — Fase 12.5

Rifacimento della disposizione dell'interfaccia e adozione dei nuovi asset UI.
Non è un reskin: cambiano posizioni, gerarchia, contenitori e logica di apertura dei pannelli.

Riferimenti: i cinque fogli di asset (`art_source/ui/1..5`) e la bozza a mano (`art_source/ui/6`).

---

## 1. Com'è l'HUD oggi

Tutto vive in `ui/settlement/settlement_hud.gd` (CanvasLayer 11) più `ui/map/map_hud.gd` (CanvasLayer 10).

| Blocco | Dove sta | File |
|---|---|---|
| Barra depositi (nome, abitanti, 6 risorse, tesoro, consenso) | ancorata in alto a **sinistra** | `settlement_hud.gd::_make_bar` |
| 9 pulsanti (Abitanti, Regno, Corte, Governo, Economia, Sapere, Diplomazia, Esercito, Cronaca) | **dentro la stessa barra**, in fila | `settlement_hud.gd::_make_bar` |
| Barra modalità mappa (8 modi) | in alto al **centro**, seconda riga | `ui/map/map_mode_bar.gd` |
| Schede del regno (8 pagine + linguette) | al **centro-alto**, sopra la mappa | `ui/shell/panel_host.gd` |
| Menù costruzioni (6 categorie, 13 edifici) | barra larga in **basso**, sempre visibile | `settlement_hud.gd::_make_build_menu` |
| Pannello abitanti | riquadro a comparsa in basso a sinistra | `settlement_hud.gd::_make_people_panel` |
| Ispettore edificio | in basso al centro | `settlement_hud.gd::_make_inspector` |
| Ispettore provincia | in alto a **destra** | `ui/map/province_inspector.gd` |
| Notifiche | colonna in alto a **destra** | `ui/shell/notification_stack.gd` |
| Carta evento | in basso al **centro** | `ui/events/event_card.gd` |
| Orologio/data/velocità | solo nel riquadro di **debug** (F3) | `ui/debug/debug_overlay.gd` |

### Problemi veri di questa disposizione

1. **La data e la velocità del tempo non esistono nell'interfaccia di gioco**: stanno nel riquadro di debug. In un gioco dove il tempo scorre è il difetto più grave.
2. **Tutto è ammassato in alto**: barra depositi + 9 pulsanti + 8 modalità mappa + le linguette delle schede = quattro file sovrapposte nella stessa fascia.
3. **Il centro dello schermo è occupato** dalle schede quando sono aperte: la mappa, che è il gioco, viene coperta.
4. **Il menù costruzioni occupa tutta la base** anche quando non si costruisce, e mostra 13 edifici tutti insieme senza gerarchia.
5. **Nessuna separazione fra "governo il regno" e "costruisco"**: i pulsanti delle schede stanno accanto ai numeri dei depositi.
6. **Gli indicatori della corona (legittimità, ordine, prestigio) sono sepolti** dentro la scheda Corte: non si vedono mai mentre si gioca.
7. **Grafica provvisoria**: `KDTheme` disegna `StyleBoxFlat` a mano (colori piatti, bordo 2px). Gli asset nuovi sono dipinti e non vengono usati da nessuna parte.
8. Due ispettori diversi in due angoli diversi, senza una zona contestuale unica.

---

## 2. Il nuovo layout (dalla bozza)

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│           [ oro | abitanti | legno | pietra | grano | ferro | sapere ]   ← A1        │
│                                                  [ A2 corona ] [ A3 data/velocità ]  │
├────────────────┬────────────────────────────────────────────────┬────────────────────┤
│ B  IL REGNO    │                                                │  C  COSTRUZIONI    │
│   Regno        │                                                │   [categorie]      │
│   Corte        │                 M A P P A                      │   Casa   Pozzo     │
│   Governo      │              (centro libero)                   │   Fattoria …       │
│   Diplomazia   │                                                │                    │
│   Abitanti     │         schede e finestre si aprono qui,       │   ── contestuale ──│
│                │         ancorate a sinistra                    │   ispettore prov./ │
│ [ Mappe ▾ ]    │                                                │   edificio         │
├────────────────┴────────────────────────────────────────────────┴────────────────────┤
│        [ Esercito ]   [ Ceti ]   [ Ricerca ]   [ Economia ]   [ Cronaca ]   ← D      │
└──────────────────────────────────────────────────────────────────────────────────────┘
        E: notifiche sotto A2/A3 a destra · carta evento al centro, sopra tutto
```

**A — fascia superiore (globale)**
- **A1 barra risorse** centrata in alto: oro, abitanti, legno, pietra, grano, ferro, punti di sapere. Icone dal foglio 2, contenitori dal foglio 1 (riga 1).
- **A2 indicatori della corona** in alto a destra: legittimità, ordine, prestigio, consenso — come pastiglie con icona (corona, scudo, stella, volto).
- **A3 data e velocità** nell'angolo: anno/mese/giorno, stagione, pulsanti di velocità (pausa 1-5). Esce dal riquadro di debug ed entra nel gioco.

**B — colonna sinistra: il regno**
Accesso rapido a ciò che si *governa*: Regno, Corte, Governo (leggi ed editti), Diplomazia, Abitanti.
In fondo alla colonna il selettore **Mappe** (le 8 modalità, raccolte in un menù a scomparsa invece di una barra sempre aperta).

**C — colonna destra: si costruisce**
Il menù costruzioni lascia la base e diventa una colonna: categorie in alto (Popolazione, Materie prime, Trasformazione, Depositi, Infrastrutture, Milizia) e sotto gli edifici della categoria scelta, con costo e motivo se non si può.
Sotto, la **zona contestuale**: quando si seleziona una provincia o un edificio, l'ispettore appare **qui**, non in un angolo diverso.

**D — barra inferiore: le sezioni principali**
Esercito (e statistiche militari), Ceti (i cinque poteri del regno), Ricerca (il Sapere), Economia, Cronaca. Pulsanti grandi, con l'icona.

**E — feedback**
Notifiche a destra sotto gli indicatori (max 6, sbiadiscono). Carta evento al centro, sopra tutto, con la cornice "Evento" del foglio 1.

**Centro**: mai occupato da barre fisse. Le schede si aprono **ancorate alla colonna sinistra** (finestra alta, larga ~560) così la metà destra della mappa resta sempre visibile.

---

## 3. Mappa delle funzioni: dove va ciascuna

| Funzione attuale | Dove sta oggi | Dove va | Nota |
|---|---|---|---|
| Nome insediamento, abitanti, letti | barra in alto a sinistra | **A1** (parte sinistra della barra) | |
| 6 risorse (legno, pietra, ferro, grano, pane, armi) | barra in alto a sinistra | **A1** | 7 pastiglie: oro, abitanti, legno, pietra, grano, ferro, sapere; pane e armi nella scheda Economia |
| Tesoro (oro) | barra in alto a sinistra | **A1** prima pastiglia | |
| Consenso | barra in alto a sinistra | **A2** | con legittimità, ordine, prestigio |
| Legittimità / Ordine / Prestigio | dentro scheda Corte | **A2** (sempre visibili) + dettaglio in Corte | |
| Data, stagione, velocità | riquadro di debug (F3) | **A3** | nuova funzione visibile |
| Pulsante **Regno** | barra alta | **B** colonna sinistra | |
| Pulsante **Corte** | barra alta | **B** | |
| Pulsante **Governo** (leggi, editti) | barra alta | **B** | |
| Pulsante **Diplomazia** | barra alta | **B** | |
| Pulsante **Abitanti** | barra alta | **B** | apre la lista abitanti come scheda |
| Pulsante **Esercito** | barra alta | **D** barra inferiore | rinominato "Esercito" con icona spade |
| Pulsante **Sapere** | barra alta | **D** come **Ricerca** | |
| Pulsante **Economia** | barra alta | **D** | |
| Pulsante **Cronaca** | barra alta | **D** | |
| *(nuovo)* **Ceti** | non esiste | **D** | i cinque poteri del regno, oggi dentro Corte: diventano una scheda propria |
| Barra modalità mappa (8) | seconda riga in alto | **B**, menù "Mappe" in fondo alla colonna | |
| Menù costruzioni (6 categorie) | barra larga in basso | **C** colonna destra | categorie + lista |
| Ispettore edificio | in basso al centro | **C** zona contestuale | |
| Ispettore provincia | in alto a destra | **C** zona contestuale | un solo posto per entrambi |
| Notifiche | alto a destra | **E** (resta a destra, sotto A2/A3) | cornici nuove con icona per tipo |
| Carta evento | in basso al centro | **E** centro schermo | cornice "Evento" nuova |
| Schede (host a linguette) | centro-alto | ancorate a **sinistra**, sotto la colonna B | il centro-destra della mappa resta libero |

---

## 4. Asset nuovi e come vengono usati

| Foglio | Contenuto | Uso |
|---|---|---|
| **1** | barre superiori con slot, fila di linguette grandi, fila di linguette piccole, pastiglie risorsa, finestra "Titolo della Finestra", popup "Evento", cartigli notifica, pulsanti colorati (Costruisci/Arruola/Ricerca/Nomina), angoli e separatori decorativi, barra inferiore a sezioni | A1 (barra risorse), B e D (linguette), C (barra inferiore → colonna categorie), cornice finestra di tutte le schede, popup evento, cartigli notifica |
| **2** | 60+ icone (oro, popolazione, legno, pietra, ferro, grano, pane, spade, libro, pergamena, giglio, lira, freccia, volto, letto, martello, scudo, corona, bilancia, borsa, stemma, mitra, miniera, villaggio, forno, incudine, magazzino, strada, tenda, banditi, fuoco, neonato…) ognuna in due misure | icone delle risorse in A1, icone dei pulsanti in B e D, icone delle notifiche per tipo, icone degli edifici in C |
| **3** | cornici finestra in tre misure, finestra con lista (Cronaca), finestra con barre (Sovrano), finestra con tabella (Economia), pannello notifiche, tooltip grande e piccolo, barra informativa, intestazioni di sezione e sottosezione, popup Evento e Conferma, pulsanti chiusura/frecce, barra di scorrimento, angoli e divisori | cornici di tutte le schede, intestazioni di sezione dentro le schede, tooltip, dialogo di conferma, barre di scorrimento |
| **4** | ogni pulsante nei **quattro stati** (normale, sopra, premuto, disabilitato) per Abitanti/Regno/Corte/Governo/Economia/Sapere/Diplomazia/Esercito/Cronaca e per i modi mappa, pulsanti colorati (Costruisci, Arruola, Ricerca, Nomina, Muovi, Sciogli, Accetta, Annulla, Conferma), pastiglie risorsa con numero, caselle, spunte, barra inferiore a sezioni | **base degli stati** di tutti i pulsanti del gioco: da qui escono gli StyleBox di `KDTheme` |
| **5** | scudi araldici (13 tinte), stendardi, corone, spilli di mappa (villaggio, borgo, città, capitale), indicatori di battaglia e assedio, gonfaloni per tipo di unità, cerchi di selezione, cariche araldiche (giglio, leone, aquila, cavallo, quercia, covone, croce, rosa, lira, luna, sole, stella), targhe e cartigli | spilli e nomi sulla mappa, stendardi degli eserciti, cerchi di selezione, targhe dei nomi di provincia e regno |
| **6** | bozza a mano del layout | struttura di questa fase |

### Pipeline degli asset

I fogli sono immagini uniche su fondo bianco. Servono ritagliati.
`tools/ui_slicer.gd` (già scritto) gira in Godot headless: toglie il fondo bianco (riempimento dai bordi, così il bianco *dentro* una cornice resta), trova le isole, e scrive in `assets/ui/<foglio>/NN.png` più un `manifest.json` con i rettangoli. Da lì si scelgono i pezzi e si costruiscono:
- `StyleBoxTexture` a **nove sezioni** per cornici, barre e pulsanti (margini di stiramento presi dalla decorazione degli angoli);
- `AtlasTexture` per le icone;
- un `Theme` di Godot (`assets/ui/kd_theme.tres`) con i quattro stati dei pulsanti, così l'intera UI cambia pelle da un punto solo.

---

## 5. Ordine dei lavori

1. **Asset**: ritaglio dei sei fogli, scelta dei pezzi, nomi definitivi (`panel_window`, `panel_event`, `bar_top`, `tab_normal/hover/pressed/disabled`, `button_green/red/blue`, `note_card`, `icon_*`).
2. **Tema**: `KDTheme` passa da `StyleBoxFlat` disegnati a `StyleBoxTexture` a nove sezioni + `Theme` di progetto. Le API pubbliche (`wood_panel()`, `parchment_panel()`, `button_styles()`) restano, così nessuna scheda va riscritta.
3. **Struttura**: nuovo `ui/shell/hud_root.gd` con i cinque blocchi (A/B/C/D/E) in `MarginContainer` ancorati ai bordi; `settlement_hud.gd` si svuota e diventa il montatore dei blocchi.
4. **Blocchi**: `top_bar.gd` (A1+A2+A3), `realm_column.gd` (B), `build_column.gd` (C, con la zona contestuale), `main_bar.gd` (D). Le schede restano quelle di Fase 12, spostate a sinistra.
5. **Ceti**: nuova scheda che prende i cinque poteri (oggi in Corte) e li mette con le loro richieste.
6. **Verifiche**: i test di `test_ui.gd` estesi (ogni funzione della tabella §3 raggiungibile, niente pannelli fuori schermo a 1080p/1440p), screenshot alle due risoluzioni.

## 6. Cosa non cambia

- Nessun sistema di gioco viene toccato: comandi, simulazione, salvataggi restano identici.
- Le schede di Fase 12 (Regno, Corte, Governo, Economia, Sapere, Diplomazia, Esercito, Cronaca) restano con i loro contenuti: cambiano cornice e posizione, non sostanza.
- `KDSheet.command_button()` continua a chiedere al comando il suo `validate()`: l'interfaccia non decide mai da sola cosa è permesso.

---

# RESOCONTO DOPO L'IMPLEMENTAZIONE

Scritto a lavoro finito: cosa si è davvero spostato, quali asset sono entrati, quali scene e file sono
cambiati, e dove la realizzazione si è staccata dal piano (e perché).

## A. Cosa si è spostato

| Funzione | Prima | Adesso | File |
|---|---|---|---|
| Oro, abitanti, legno, pietra, grano, ferro, sapere | barra in alto a sinistra, testo su colore piatto | **A1**: sette pastiglie dipinte con icona | `ui/shell/top_bar.gd` |
| Legittimità, ordine, prestigio | sepolti nella scheda Corte | **A2**: sempre in alto a destra, con il consenso | `ui/shell/top_bar.gd` |
| Data, stagione, velocità del tempo | solo nel riquadro di debug (F3) | **A3**: angolo in alto a destra, pausa e 1–5 | `ui/shell/top_bar.gd` |
| Regno, Corte, Governo, Diplomazia, Abitanti | nove pulsanti in fila nella barra dei depositi | **B**: colonna di sinistra, con icona | `ui/shell/nav_block.gd` |
| Modalità mappa (8) | barra sempre aperta al centro in alto | **B**: menù a scomparsa in fondo alla colonna | `ui/map/map_mode_menu.gd` |
| Menù costruzioni (6 categorie, 13 edifici) | barra larga su tutta la base | **C**: colonna a destra, categorie + lista con costo e motivo | `ui/shell/build_column.gd` |
| Ispettore edificio | in alto a destra, riquadro suo | **C**: zona contestuale | `ui/settlement/settlement_hud.gd` |
| Ispettore provincia | in alto a destra, altro riquadro | **C**: stessa zona contestuale | `ui/map/province_inspector.gd` |
| Esercito, Ricerca (Sapere), Economia, Cronaca | barra in alto | **D**: barra inferiore, pulsanti grandi con icona | `ui/shell/nav_block.gd` |
| **Ceti** (i cinque poteri) | tre righe in fondo alla scheda Corte | **D**: scheda propria, con umori, richieste e costo del malcontento | `ui/kingdom/estates_panel.gd` |
| **Abitanti** | riquadro a comparsa appeso alla barra | **B**: scheda come le altre | `ui/settlement/people_panel.gd` |
| Notifiche | alto a destra | **E**: a destra, accanto alla colonna C | `ui/shell/notification_stack.gd` |
| Carta evento | in basso al centro | **E**: al centro dello schermo | `ui/events/event_card.gd` |
| Schede del regno | al centro-alto, sopra la mappa | ancorate alla colonna sinistra, con una sola riga di intestazione | `ui/shell/panel_host.gd` |

Nessuna funzione è andata persa: ogni voce della tabella del §3 ha la sua casa nuova, e il test
`test_the_columns_reach_every_sheet_of_the_realm` verifica che i dieci pulsanti aprano le dieci schede.

## B. Asset adottati

Dai cinque fogli sono stati ritagliati 319 pezzi; ne sono entrati nel gioco **18 cornici e pulsanti** più
**36 icone**, elencati in `assets/ui/kit.json`:

- **cornici**: `window` (con la fascia del titolo: schede, carta evento), `panel` (la stessa senza fascia:
  cartigli delle notifiche, ispettori, riga di intestazione), `panel_dark` (pastiglie, colonne, barre);
- **pulsanti**: `button` nei quattro stati (normale, sopra, premuto, disabilitato) più le varianti
  `button_green/red/blue`, `close` nei tre stati, `slot`, `pill`, `check_on/off`;
- **icone** (foglio 2): oro, abitanti, legno, pietra, ferro, grano, pane, guerra, libro, legge, giglio,
  cultura, crescita, consenso, letti, martello, scudo, corona, giustizia, tesoro, casata, clero, miniera,
  villaggio, forno, fucina, magazzino, strada, campo, sviluppo, allarme, cronaca, diplomazia, commercio,
  intrigo, fuoco.

Due pulizie sono state necessarie perché gli asset erano dipinti con un contenuto finto: la fascia del titolo
portava le parole "Titolo della Finestra" e una croce di chiusura (cancellate ripetendo una colonna pulita
della fascia), e l'interno della cornice era una pergamena dipinta che rendeva illeggibile il testo chiaro
(sostituita con il legno della fascia più una grana leggera). Il ritaglio è ripetibile: i tre script stanno
in `tools/art/` e si rilanciano sui fogli originali in `art_source/ui/`.

## C. File e scene toccati

**Nuovi**: `ui/shell/top_bar.gd`, `ui/shell/nav_block.gd`, `ui/shell/build_column.gd`,
`ui/kingdom/estates_panel.gd`, `ui/settlement/people_panel.gd`, `ui/map/map_mode_menu.gd`,
`ui/theme/kd_ui.gd`, `tools/art/slice_ui.py`, `tools/art/ui_contact_sheet.py`, `tools/art/build_ui_kit.py`,
`assets/ui/kit/*`, `assets/ui/icons/*`, `assets/ui/kit.json`.

**Riscritti**: `ui/settlement/settlement_hud.gd` (da disegnatore a montatore dei cinque blocchi),
`ui/theme/kd_theme.gd` (dai riquadri disegnati a mano alle nove sezioni dipinte, con `card_panel()` nuovo),
`ui/map/map_hud.gd` (non porta più barre: solo i nomi e gli stemmi sulla mappa).

**Modificati**: `ui/shell/panel_host.gd` (intestazione compatta con nome e croce), `ui/shell/kd_sheet.gd`
(la cornice segue l'altezza del contenuto), `ui/kingdom/court_panel.gd` (i poteri diventano una riga di
riepilogo che rimanda ai Ceti), `ui/map/province_inspector.gd` (misure adatte alla colonna),
`ui/shell/notification_stack.gd` (cornice nuova), `scenes/main.tscn` (l'HUD riceve il controller delle
mappe), `tests/unit/test_ui.gd` (+5 prove).

**Non toccato**: nessun sistema di gioco, nessun comando, nessun salvataggio. La simulazione è quella di
prima, riga per riga.

## D. Dove ci siamo staccati dal piano

1. **Le notifiche non stanno sotto A2/A3 ma accanto alla colonna C** (400 px dal bordo destro): a destra ora
   vivono due blocchi e sovrapporli sarebbe stato peggio che spostarli.
2. **La barra delle risorse resta ancorata a sinistra**, non centrata: centrata, su uno schermo 16:10 stretto
   andrebbe a toccare le misure della corona.
3. **La barra delle linguette non è sparita ma si è ridotta**: una riga con il nome della scheda aperta e la
   croce. Serviva un modo visibile di chiudere che non fosse solo ESC.
4. **`hud_root.gd` non esiste**: i cinque blocchi sono montati da `settlement_hud.gd`, che è già il
   `CanvasLayer` dell'interfaccia. Un nodo in più sarebbe stato un guscio vuoto.
5. **L'ispettore dell'edificio è rimasto dentro `settlement_hud.gd`** invece di diventare una classe a sé:
   legge lo stato del cantiere e i comandi dei lavoratori, e spostarlo avrebbe mescolato un refactor di
   struttura con uno di responsabilità. È pronto per la Fase 14.

## E. Verifiche

- **139 test, 0 fallimenti** (`tools/check.ps1`), di cui 11 in `test_ui`: cinque nuovi scritti per questa fase.
- Benchmark di volo: **124,8 fps medi** (129,8 in Fase 12).
- Screenshot in `tests/output/`: `p125_layout.png` (villaggio, HUD completo), `p125_sheet.png` (Corte),
  `p125_economy.png`, `p125_ultrawide.png` (Governo), `p125_1440p.png` (Esercito), `p125_province.png`
  (provincia selezionata nella zona contestuale), `p125_building.png` (edificio selezionato).
- Il viewport logico del progetto è 1920×1080 con `canvas_items`/`expand`: i blocchi sono ancorati ai bordi,
  quindi il disegno scala con la finestra e i test verificano che due colonne più una scheda aperta stiano
  dentro 1280, 1920 e 2560 px di larghezza logica.

## F. Pulizia

- `ui/map/map_mode_bar.gd` è stato cancellato: la barra delle modalità non esiste più, il menù della colonna
  ne ha preso il posto con gli stessi tasti. Resta nella storia di git.
- `tools/ui_slicer.gd` (il ritaglio in Godot headless previsto al §4) è stato cancellato: il ritaglio vero lo
  fa la pipeline Python, che legge l'alfa invece del fondo bianco e taglia a X/Y ricorsivo.
- I pezzi ritagliati **non stanno in `assets/`**: sono intermedi, il gioco non ne carica nemmeno uno, e
  farli importare da Godot voleva dire 373 texture inutili. Vivono in `art_source/ui/cut/` e si rifanno con
  `slice_ui.py`; in `assets/ui/` restano solo il kit e le icone che il gioco usa davvero (2,2 MB).

