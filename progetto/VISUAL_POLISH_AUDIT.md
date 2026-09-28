# FASE 18A — AUDIT VISIVO (prima di toccare qualcosa)

Diciassette schermate standard, sempre le stesse inquadrature e gli stessi scenari, così il confronto prima/dopo
(18H) è onesto: `tests/output/p18a_01_continente.png` … `p18a_17_evento.png` (1600×900, finestra di default;
le altre risoluzioni si provano in 18H). Script: `--kd-hide-debug --kd-no-events` più lo scenario.

| # | Inquadratura | Scenario |
|---|---|---|
| 01 | continente | partita nuova, `--kd-camera=player,110` |
| 02 | mappa politica | `--kd-mapmode=political --kd-camera=player,40` |
| 03 | zoom medio (3 m/px) | `community_ready` |
| 04 | villaggio (0,35 m/px) | `community_ready` |
| 05–06 | capitale dopo vent'anni (0,6 e 2,5 m/px) | `kingdom_grown` |
| 07–08 | esercito da vicino, guerra da lontano | `army`, `war` |
| 09–16 | schede Regno, Corte, Ceti, Governo, Economia, Diplomazia, Esercito, Cronaca | `kingdom`, `kingdom_grown`, `army` |
| 17 | carta evento | `kingdom --kd-event=fiera_di_primavera` |

## KEEP — regge, non si tocca

| Cosa | Dove si vede | Perché |
|---|---|---|
| Carta del continente dipinta, mare, rilievo | 01 | È la banda più riuscita del gioco: legge come una carta medievale. |
| Mappa politica, confini, nomi dei regni | 02 | Colori per dominio, linee nette, gerarchia dei nomi. |
| Fiume principale da vicino | 04 | Riva, larghezza che cresce a valle, colore. |
| Edifici dipinti con le varianti e le ombre | 04, 05 | Case diverse fra loro, ombra al piede, cantieri che crescono. |
| Kit dipinto (cornici, pulsanti, icone) | tutte | Una sola lingua visiva; da usare meglio, non da rifare. |
| Contenuto delle schede | 09–16 | I numeri ci sono e sono veri: il problema è come sono presentati. |

## IMPROVE — la cosa è giusta, la resa no

| Cosa | Dove | Problema visto | Sotto-fase |
|---|---|---|---|
| Bosco a zoom medio | 03, 06, 08 | Una carta da parati di cespi identici e chiari, senza radure né macchie di tono. | 18B |
| Strade | 04, 05 | Rettangoli marroni piatti, tutte uguali dal sentiero alla via maestra. | 18B |
| Villaggio a zoom medio | 03, 06 | A 3 m/px il villaggio è una macchia di pochi pixel coperta dai cespi. | 18C |
| Capitale dopo vent'anni | 05 | Una griglia di campi senza centro: nessun mastio, nessuna strada, nessun luogo. | 18C |
| Villaggio da vicino | 04 | Edifici a scacchiera: niente sentieri fra le porte, niente orti, niente recinti. | 18C |
| Segnaposto e nomi | 03, 06 | Il segnaposto sta sopra le case e le copre; provincia e insediamento con lo stesso nome hanno due segnaposto a pochi metri; la targa dipinta del nome non compare mai (cercata col nome sbagliato). | 18C |
| Abitanti | 04, 05 | Ingranditi fino a 26 px senza limite: nei campi sembrano alti quanto le case. | 18D |
| Esercito da vicino | 07 | Un mucchio unico di figure, stesso ingrandimento gigante, nessuna formazione. | 18D |
| Esercito da lontano | 08 | Il vessillo non dice quanti uomini porta (il commento nel codice lo prometteva). | 18D |
| Barra alta | tutte | I numeri non dicono da dove vengono: il tooltip del legname diceva «Legname». | 18E, 18G |
| Colonna costruzioni | tutte | Sempre aperta, tocca il riquadro dell'orologio, categorie solo a icone. | 18E |
| Minimappa | 06, 13 | Il rettangolo della camera esce dal riquadro. | 18E |
| Schede | 09–16 | Il nome sta in un secondo riquadro sopra la cornice, mentre la fascia dipinta della cornice resta vuota: sembrano due finestre. | 18F |
| Notifiche | 06, 09 | Fino a sei cartigli grandi con le volute: un quarto dello schermo, anche per «è nato un bambino». | 18G |
| Carta evento | 17 | Fascia vuota, nessuna immagine, conseguenze nascoste nel tooltip dei pulsanti. | 18G |

## REPLACE — va sostituita

| Cosa | Dove | Con cosa | Sotto-fase |
|---|---|---|---|
| Menu: 5 voci a sinistra + 5 in basso, schede disperse | tutte | Sinistra: Regno, Corte, Governo, **Religione**, Esercito, Diplomazia, Economia, Ricerca, Mappa. Basso: Costruire, Abitanti, Ceti, Cronaca. Ogni scheda in un solo posto. | 18E |
| La fede sparsa in tre schede | 09, 11, 12 | Una scheda Religione: fede, clero, legge di fede, fedi delle terre. | 18F |
| Simboli di font `✓ ✗ ✕ ❙❙ →` | 09, 10, barra alta | Spunte e croce dipinte del kit, pausa disegnata, parole al posto delle frecce. | 18G |
| Tooltip di testo semplice | tutte | Tooltip a due colonne con motivi e numeri colorati per segno. | 18G |

## REMOVE — va tolto

| Cosa | Dove | Perché |
|---|---|---|
| Titoli «DIPLOMAZIA», «ESERCITO», «CRONACA» dentro le schede | 14, 15, 16 | Il nome va nella fascia della cornice: scritto due volte è rumore. |
| Etichetta della provincia dove c'è un insediamento con lo stesso nome | 06 | Due segnaposto per un luogo solo. |
| Colonna costruzioni fuori dalla modalità costruzione | tutte | Copre la mappa quando nessuno costruisce. |

## Fuori da questa fase (dichiarato)

- **Tipografia**: i font sono di sistema (Palatino/Georgia di ripiego). Un font medievale incluso richiede di
  scaricarlo: serve il permesso esplicito, non lo faccio da solo.
- **Ruscelli sottili** (04, in basso a destra): da vicino un ruscello di due metri resta una linea; il fiume
  principale è a posto. Non è un difetto di logica, è una scelta di resa che lascio com'è.
- **Audio**: Fase 20.

---

# AUDIT DEL POLISH GRAFICO — prima di chiudere la Fase 14

Verifica fatta guardando il codice, gli asset e quattro schermate a zoom diversi
(`tests/output/p14b_far.png`, `p14b_regional.png`, `p14b_local2.png`, `p14b_street.png`).
Conclusione: **il polish grafico non è completo**. La Fase 14 non si chiude qui: si apre la **Fase 14B**.

---

## 1. COMPLETATO

| Cosa | Dove | Stato |
|---|---|---|
| **Mappa generale a zoom lontano** | `shaders/terrain.gdshader` (albedo illustrato baked, `far_start=9`, `far_end=26`), `map/terrain/terrain_layer.gd`, `tools/worldgen/` | Legge davvero come una carta medievale dipinta: colori di bioma, rilievo accennato, mare con profondità. È la banda migliore del gioco. |
| **Confini e velatura politica** | `shaders/border.gdshader`, `map/borders/border_layer.gd`, `map/political/map_modes.gd` | Linee nette a larghezza costante sullo schermo, bande di colore per dominio, otto modalità mappa. |
| **Nomi sulla carta** | `map/labels/map_labels.gd`, `ui/theme/kd_fonts.gd` (capitali incise) | Gerarchia regno/signoria/provincia, dissolvenza per zoom, niente sovrapposizioni. |
| **Fiumi come geometria** | `shaders/river.gdshader`, `map/water/river_layer.gd` | 192 fiumi veri, larghezza che cresce a valle. |
| **Cornici, pulsanti e icone dell'HUD** | `assets/ui/kit.json` (18 pezzi + 36 icone), `ui/theme/kd_ui.gd`, `ui/theme/kd_theme.gd` | Nove sezioni dipinte, quattro stati dei pulsanti, icone al posto dei quadratini colorati. |
| **Struttura dell'interfaccia** | `ui/shell/*`, `ui/settlement/settlement_hud.gd` | Cinque blocchi ai bordi, centro libero, una scheda per volta (Fase 12.5). |
| **Notifiche e carta evento** | `ui/shell/notification_stack.gd`, `ui/events/event_card.gd` | Cartigli dipinti, colore per tipo, dissolvenza. |
| **Minimappa** | `ui/map/minimap.gd` | Continente, colori della modalità in uso, rettangolo della camera. |

## 2. PARZIALMENTE COMPLETATO

| Cosa | Dove | Cosa manca davvero |
|---|---|---|
| **Vegetazione** | `assets/environment/vegetation/vegetation_atlas.json` (12 specie, 24 sprite), `map/vegetation/vegetation_layer.gd`, `shaders/vegetation.gdshader` | Le specie ci sono, ma a zoom medio (2–6 m/px) il bosco è una **punteggiatura verde uniforme**: nessuna variazione di tinta o dimensione per gruppo, nessuna chioma d'insieme, nessuna ombra. Vedi `p14b_local2.png`. |
| **Montagne** | `assets/environment/mountains/mountain_atlas.png` (12 sprite, 175×134 px), `map/terrain/mountain_layer.gd` | A zoom regionale gli sprite sono **stirati e impastati**: 175 px su ~400 px di schermo. Vedi `p14b_regional.png`. Servono render più grandi. |
| **Edifici** | `assets/buildings/building_atlas.json` (19 sprite), `map/settlement/settlement_layer.gd` | Ogni casa è **identica a ogni altra casa**: nessuna variante, nessuna rotazione, nessuna usura. Si appoggiano al terreno senza ombra propria né terra battuta attorno: sembrano incollati. |
| **Unità ed eserciti** | `map/military/army_layer.gd`, `assets/people/people_atlas.json` (84 sprite) | I soldati vicini ci sono; lo stendardo lontano è **una sprite di persona tinta**, non un gonfalone dipinto. Nessun cerchio di selezione, nessun segno di battaglia o assedio sulla carta. |
| **Stemmi** | `kingdoms/coat_of_arms.gd`, `ui/map/arms_view.gd` | Sono **poligoni vettoriali piatti** generati a codice: leggibili e coerenti fra loro, ma di un'altra lingua visiva rispetto all'interfaccia dipinta. Il foglio 5 ha 13 scudi dipinti e dodici cariche, non usati. |
| **Asset UI nuovi** | `assets/ui/kit.json` vs `art_source/ui/cut/` (319 pezzi ritagliati) | Usati **18 pezzi su 319**. Interi fogli non entrano in gioco: **foglio 3** (cornici a tre misure, finestra con lista, finestra con tabella, tooltip, intestazioni di sezione, barra di scorrimento, dialogo di conferma) e **foglio 5** (araldica, stendardi, spilli di mappa, indicatori di battaglia e assedio, targhe). Di quelli scelti, `panel_gold`, `slot`, `pill`, `check_on/off` sono definiti e mai usati. |

## 3. NON ANCORA FATTO

| Cosa | Dove sarebbe | Perché conta |
|---|---|---|
| **Tipografia vera** | `ui/theme/kd_fonts.gd` — sono **font di sistema** (`SystemFont` con ripieghi Palatino/Georgia) | Il commento nel file dice «un font medievale incluso arriva con la Fase 12»: non è mai arrivato. Su un'altra macchina il gioco cambia faccia. |
| **Tema di progetto** | nessun `.tres`, `project.godot` non ha `gui/theme/custom` | Tutto ciò che non è vestito a mano dal codice resta **grigio Godot**: tooltip, barre di scorrimento, caselle, `ProgressBar` di sistema, contorni di fuoco. |
| **Tooltip dipinti** | foglio 3 ha tooltip grande e piccolo; nessun `make_custom_tooltip` nel progetto | I tooltip sono il testo che il giocatore legge di più: oggi sono riquadri grigi di serie. |
| **Spilli e targhe degli insediamenti** | foglio 5 (villaggio, borgo, città, capitale); oggi `map_labels.gd` disegna solo testo + stemma | La carta lontana è bella ma gli insediamenti sono solo nomi. |
| **Terreno locale** | `shaders/terrain.gdshader` sotto i 2 m/px | A livello di strada il suolo è **un verde piatto con un filo di rumore**: niente erba, niente terra battuta, niente campi arati oltre alla fattoria. Vedi `p14b_street.png`. |
| **Rive e acque locali** | `shaders/river.gdshader` | Il fiume da vicino è **una fascia azzurra con un bordo netto**: niente rive, niente ghiaia, niente canne, nessun riflesso. |
| **Ombre** | nessuna | Né edifici né alberi né persone proiettano nulla: è la ragione principale per cui la scena locale sembra «ritagliata e incollata». |
| **Suoni e musica** | — | Dichiarato apertamente non fatto: non posso ascoltare quel che produco. |

## 4. DA RIFINIRE

| Cosa | Dove | Nota |
|---|---|---|
| **Coerenza fra le bande di zoom** | `terrain.gdshader` (`far_start`/`far_end`), `mountain_layer.gd`, `vegetation_layer.gd` | Il passaggio 9→26 m/px è il punto debole: la carta dipinta sfuma dentro mentre montagne e alberi restano sprite. È lì che il gioco «cambia stile». |
| **Densità del bosco** | `vegetation_layer.gd` | A 2 m/px gli alberi sono troppi e tutti uguali; a 0.5 m/px sono troppo radi per fare un sottobosco. |
| **Villaggio come luogo** | `map/settlement/settlement_layer.gd`, `settlement/settlement_planner.gd` | Gli edifici stanno a distanza regolare: manca l'aia, il recinto, il mucchio di legna, il sentiero battuto che li lega. |
| **Leggibilità dei numeri** | `ui/shell/top_bar.gd` | Le pastiglie in alto sono corrette ma piccole; oro e grano si distinguono per icona, non per peso tipografico. |
| **Pannelli lunghi** | `ui/shell/kd_sheet.gd` | Le schede molto lunghe (Cronaca, Economia) scorrono con la barra grigia di sistema. |
| **Spazio vuoto in basso a destra** | `ui/settlement/settlement_hud.gd` | Con la colonna costruzioni chiusa resta un angolo morto. |

---

## Conclusione

Il **sistema** è finito; l'**aspetto** no, e non in modo uniforme: la carta lontana sembra un gioco pubblicato,
la banda media e quella locale sembrano un prototipo pulito. L'interfaccia è dipinta ma appoggia ancora su un
tema di sistema per tutto ciò che non è stato vestito a mano, e due fogli di asset su cinque non sono mai
entrati in gioco.

Si apre la **FASE 14B — VISUAL POLISH FINALE**, senza rifare nulla di ciò che funziona.

---

# FASE 14B — VISUAL POLISH FINALE: quel che è stato fatto

## Fatto

| Intervento | File / asset | Perché |
|---|---|---|
| **Tema di progetto** | `ui/theme/kd_theme.gd` (`project_theme()`, `dress()`), chiamato da `ui/menu/main_menu.gd` e `ui/settlement/settlement_hud.gd` | Tooltip, barre di scorrimento, caselle, popup, barre di avanzamento e separatori non sono più grigio Godot: il tooltip usa la cornice dipinta, le barre l'oro della corona. Era la cosa che più faceva «due giochi incollati». |
| **Ombre e terra battuta** | `map/settlement/settlement_layer.gd` (`_draw_shadow`, `_draw_ground_patch`, `_stands_up`), `map/settlement/people_layer.gd`, `map/military/army_layer.gd` | Edifici, abitanti e soldati proiettano un'ombra verso sud-est (la stessa direzione del sole del rilievo) e attorno a ciò che è vissuto la terra è battuta. Un campo arato non proietta ombra: è già terreno. |
| **Il bosco sembra un bosco** | `map/vegetation/vegetation_layer.gd` (variazione per istanza), `data/defs/vegetation.json` (bande ritarate) | Ogni albero ha ora una sua misura (0.78–1.24) e metà sono specchiati; la banda dei singoli si ferma a 1.7 m/px e i grappoli prendono la fascia media. A 2 m/px non è più una punteggiatura regolare di puntini identici. |
| **Montagne nitide** | `tools/art/draw_mountains.py` (PX 200 → 384, atlante 2048×1024), `assets/environment/mountains/*` | A zoom regionale le vette erano impastate: gli sprite erano stirati del 250%. |
| **Roccia con grana e luce** | `shaders/terrain.gdshader` | L'alta quota era una velatura pallida uniforme: ora la roccia ha una grana propria e prende il doppio della luce del sole. |
| **Spilli e targhe sulla carta** | `assets/ui/kit.json` (+12 pezzi dal foglio 5), `tools/art/build_ui_kit.py`, `map/labels/map_labels.gd` | Ogni provincia porta lo spillo dipinto della sua taglia (villaggio, borgo, città, capitale) con il punto del colore di chi la tiene; gli insediamenti veri hanno spillo e targa con il nome. |
| **Gonfaloni, battaglie e assedi** | `map/military/army_layer.gd`, kit (`gonfalon_foot/horse/bow`, `mark_battle`, `mark_siege`) | Un esercito lontano era la figura di un uomo tinta di colore: ora è il pennone dipinto dell'arma che pesa di più, con il disco del regno. Battaglie e assedi hanno il loro segno dipinto. |
| **Schermate pulite per il controllo** | `scenes/main.gd`, `core/boot/boot_args.gd` (`--kd-no-events`, `--kd-menu`, `--kd-pause`) | Per fotografare il gioco senza una carta evento davanti all'obiettivo. |

## Resta aperto (dichiarato, non nascosto)

| Cosa | Perché non è stato fatto |
|---|---|
| **Tipografia** | Serve un file di font medievale ridistribuibile. Non posso scaricarlo da qui, e non voglio spacciare per scelta tipografica un ripiego di sistema. `ui/theme/kd_fonts.gd` resta a font di sistema con ripieghi dichiarati. |
| **Suoni e musica** | Non posso ascoltare quel che produco: un rumore sintetizzato alla cieca sarebbe peggio del silenzio. |
| **Terreno locale** (erba, terra battuta fuori dai villaggi, campi arati diffusi) e **rive dei fiumi** | Lavoro di shader ancora da fare: sotto i 2 m/px il suolo resta un verde con poca grana. |
| **Varianti degli edifici** | Ogni casa è ancora identica a ogni altra: servono 2–3 varianti per tipo in `tools/art/draw_buildings.py`. |
| **Stemmi dipinti** | I 13 scudi del foglio 5 potrebbero fare da fondo agli stemmi generati: va verificato che le cariche vettoriali ci stiano sopra senza sporcare. |
| **Fogli 3** (cornici a tre misure, finestra con lista, con tabella, intestazioni di sezione) | Il tema di progetto ne usa una parte (tooltip); il resto resta da adottare nelle schede. |

## Secondo passaggio

| Intervento | File / asset | Perché |
|---|---|---|
| **Rive dei fiumi** | `shaders/river.gdshader` | Da vicino il nastro è più largo dell'acqua: la parte esterna è la riva (limo bagnato al bordo, ghiaia asciutta fuori), l'acqua ha un'increspatura lenta e un filo di luce sul lato nord-ovest. Dalla carta alta torna la linea blu. |
| **Grana del terreno vicino** | `shaders/terrain.gdshader` | Sotto i 3,5 m/px il prato ha una grana sua e la terra affiora dove l'erba si dirada. Tutte le scale di rumore dividono 1024 m, come chiede il commento dello shader: niente cuciture quando il riquadro si sposta (quella da 48 m introdotta nel primo passaggio è stata corretta a 64). |
| **Case diverse** | `tools/art/draw_buildings.py` (`house_1`, `house_2`), `map/settlement/settlement_layer.gd` (`_variant`) | Tre case sulla stessa impronta 8×8: paglia chiara a frontone, scandole rosse a frontone laterale, paglia bruna su legno scuro. Ogni edificio sceglie la sua per sempre dal proprio id, quindi un salvataggio ricaricato mostra la stessa strada. Vale per ogni edificio che nell'atlante abbia `nome_1`, `nome_2`… |
| **Un difetto delle ombre** | `settlement_layer.gd`, `people_layer.gd`, `army_layer.gd` | Le ellissi di mezzo metro costruite a coordinate mondiali di 34 km perdevano i punti per la precisione dei float e la triangolazione falliva: centinaia di errori nel log a ogni fotografia. Ora sono cerchi scalati attorno a un'origine locale: zero errori, e costano meno. |

Resta aperto dopo il secondo passaggio: **tipografia**, **suoni**, **stemmi dipinti**, il resto del **foglio 3**
nelle schede, e le **varianti degli altri edifici** (per ora solo le case ne hanno).

## Foglio 3: com'è davvero

Nel primo audit avevo scritto che il foglio 3 offriva «cornici a tre misure, finestra con lista, finestra con
tabella». Guardato a piena risoluzione non è così: le sette finestre grandi hanno **titolo e contenuto dipinti
dentro** («Regno», «Economia», le righe della Cronaca, la griglia della tabella) — sono bozze di schermata, non
parti. Le parti vere sono nell'ottavo pezzo, una striscia che il ritaglio automatico non poteva separare
perché le ombre morbide la tengono insieme: sono state ritagliate a mano in `build_ui_kit.py` (voce `crop`).

| Pezzo | Uso |
|---|---|
| `section_bar` (con la parola «Sezione» cancellata) | ogni titolo di sezione delle schede (`KDSheet.section`) |
| `subsection_bar` (con «Sottosezione» cancellata) | pronto, non ancora usato |
| `rule_ornate` | sotto il titolo del menù e del menù di pausa (`KDTheme.ornate_rule`) |

## Un difetto che non era grafico

Lo screenshot del menù mostrava sparite le voci «Continua» e «Carica partita». Il motivo: le prove di
`test_menu` svuotavano l'intera `user://saves` prima e dopo ogni prova — **la stessa cartella dei salvataggi
veri**. Chi lanciava la suite perdeva le proprie campagne. Ora `SaveSystem.save_dir` è configurabile e le
prove usano `user://tests/saves`, con un `assert` che impedisce di svuotare altro. Nella stessa occasione una
prova instabile ha mostrato che due salvataggi nello stesso millisecondo non avevano un ordine: `saved_unix`
è ora strettamente crescente dentro il processo (`SaveSystem.next_stamp()`).

