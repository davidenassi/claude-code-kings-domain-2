# VISUAL POLISH REPORT — Fase 18, prima e dopo

Le stesse inquadrature, gli stessi scenari, la stessa finestra (1600×900): **prima** = `tests/output/p18a_*.png`
(audit 18A, prima di toccare qualcosa), **dopo** = `tests/output/p18h_*.png`. Le foto intermedie di lavoro sono
`p18b_*` (HUD), `p18c_*` (zoom medio), `p18d_*` (insediamenti ed eserciti). L'elenco dei problemi e il giudizio
KEEP / IMPROVE / REPLACE / REMOVE sono in `VISUAL_POLISH_AUDIT.md` (sezione 18A).

La fase è divisa come chiesto: 18A audit · 18B mappa · 18C insediamenti · 18D abitanti ed eserciti · 18E layout
della HUD · 18F schede e tipografia · 18G tooltip, icone, eventi, notifiche · 18H coerenza e confronto.

---

## 18B — Mappa

| Prima | Dopo | Foto |
|---|---|---|
| A zoom medio il bosco è una carta da parati di cespi identici, chiari, fitti ovunque. | Radure e nuclei fitti (rumore a bassa frequenza, celle di 470 m), gruppi di chiome dello stesso tono, più escursione di tinta: il bosco ha macchie e respiro, e la carta dipinta sotto torna a vedersi. | 03, 08 |
| Strade: rettangoli marroni piatti, tutte uguali. | Tre stili per la grandezza del luogo (sentiero con l'erba in mezzo, sterrata con i solchi, via maestra in ghiaia), bordi irregolari, verge più scura, estremità arrotondate. | 04, 22 |
| Provincia e insediamento con lo stesso nome: due segnaposto a pochi metri. | La provincia che ha un insediamento non disegna il suo: un luogo, un nome. | 06, 08 |
| — | Confini, carta del continente, fiume principale: **tenuti** come erano (KEEP). | 01, 02 |

## 18C — Insediamenti

| Prima | Dopo | Foto |
|---|---|---|
| A 3 m/px il villaggio è qualche pixel sotto i cespi. | Nuovo livello `SettlementMarks`: fra 2,2 e 40 m/px ogni edificio vero è un blocco mai più piccolo di 3,2 px — tetti in quattro toni, campi del colore della stagione con i solchi, mastio in pietra con la torre — sopra la terra battuta; il bosco lascia una radura attorno alle case. Da lontano un borgo di duecento anime si distingue da un villaggio di trenta. | 03, 06, `p18d_03`, `p18d_08` |
| La capitale dopo vent'anni: una griglia di campi senza centro. | All'incoronazione le famiglie alzano il **mastio** accanto al fuoco comune (il sovrano ci va a vivere): la capitale ha un centro; le porte sono legate da **sentieri battuti** (mai oltre il fiume). | 05, `p18d_09` |
| Case a scacchiera, nessun segno di vita attorno. | **Orti recintati** accanto alle case (terra a solchi, qualche fila verde, pali e staccionata con il cancello), mai sopra un edificio, una strada, l'acqua o la riva. | 22 |
| Il segnaposto copre le case; la targa dipinta del nome non compariva mai. | Segnaposto sopra l'abitato, targa dipinta sotto (al raggio che contiene nove edifici su dieci); quando il luogo è abbastanza grande da leggersi da solo, il segnaposto si ritira. | 03, 06 |

## 18D — Abitanti ed eserciti

| Prima | Dopo | Foto |
|---|---|---|
| Abitanti ingranditi fino a 26 px senza limite: nei campi erano alti quanto le case. | Minimo 12 px ma mai più di 2,6 volte la misura vera; sotto i 7 px un abitante è un punto del colore del suo lavoro (contadino, boscaiolo, costruttore, cavatore, bambino). | 04, 22 |
| La schiera da vicino: un mucchio di 24 figure giganti. | Blocchi per reggimento (in colonna quando marcia, in linea a riposo), ogni blocco col suo pennone (fanti, arcieri, cavalieri), fino a 36 figure in scala. | 07 |
| Il vessillo lontano non diceva quanti uomini portava. | Una targa col numero di uomini sotto ogni vessillo, bordata del colore del regno. | 08, `p18d_06` |

## 18E — Layout della HUD

| Prima | Dopo | Foto |
|---|---|---|
| Sinistra: 5 voci (Il mio regno, Corte, Leggi e governo, Diplomazia, Abitanti); basso: Esercito, Ceti, Ricerca, Economia, Cronaca. | **Sinistra**: Regno, Corte, Governo, **Religione**, Esercito, Diplomazia, Economia, Ricerca, Mappa (prima della corona: Comunità, Famiglie, Consuetudini, Fede). **Basso**, una riga: Costruire, Abitanti, Ceti, Cronaca. Ogni scheda in un posto solo (verificato da un test sulle liste vere della HUD). | 09, 18 |
| Colonna costruzioni sempre aperta, attaccata all'orologio. | Si apre solo in modalità costruzione (Costruire o **B**; Esc lascia l'edificio in mano, poi chiude la lista); scostata dall'orologio; le notifiche stanno sul bordo destro e si spostano accanto quando la colonna è aperta. | 18 |
| Rettangolo della minimappa oltre il bordo. | Ritagliato al riquadro. | 06 |
| Pausa scritta col glifo `❙❙`. | Due barre disegnate. | tutte |

## 18F — Schede e tipografia

| Prima | Dopo | Foto |
|---|---|---|
| Il nome della scheda in un secondo riquadro sopra la cornice, la fascia dipinta vuota: due finestre. | Nome e croce nella fascia della cornice: una finestra sola. | 09–16 |
| «DIPLOMAZIA», «ESERCITO», «CRONACA» scritti anche dentro la scheda. | Tolti: il nome è nella fascia. | 14–16 |
| La fede sparsa in tre schede. | Scheda **Religione**: fede della corona e suoi effetti, favore del clero e quanto pesa sulla legittimità, dono al clero, legge di fede, fedi delle terre con la conversione in corso e la tolleranza. | 21 |
| Scheda Esercito alta 560 px attorno a quattro righe, titoli di sezione in testo semplice. | Barre di sezione dipinte come nelle altre schede, pennone di ogni reparto, altezza misurata sul contenuto. | 15 |
| Governo: la legge in vigore si capiva solo dal colore del pulsante. | Scritta accanto al gruppo: «in vigore: …». | 12 |
| Obiettivi e condizioni con `✓` e `✗`. | Le caselle dipinte del kit. | 09, 10 |
| Economia: il deposito diceva solo quanto c'è. | Anche quanto è cambiato il mese scorso e perché. | 13 |

## 18G — Tooltip, icone, eventi, notifiche

| Prima | Dopo | Foto |
|---|---|---|
| Tooltip della barra alta: «Legname». | Per ogni merce: quanto c'è, quanto posto resta, **entrate e uscite del mese scorso per motivo** (lavoro, pasti, cantieri, mercanti, armi, eventi) e il saldo; l'oro col bilancio del tesoro e il soldo degli eserciti; abitanti, famiglie, letti, senza lavoro, partenze; per legittimità, ordine, prestigio, fiducia e autorità **le componenti che le spingono, il valore verso cui vanno e l'andamento**. Numeri verdi quando aiutano, rossi quando nuocciono. Dietro c'è un registro vero delle scorte, non una stima. | 19, 20, 23 |
| Sei cartigli grandi con le volute, un quarto dello schermo. | Al massimo quattro, più stretti, con l'icona dipinta del tipo; nascite, lavori finiti e viandanti su una riga sola che svanisce prima. | tutte |
| Carta evento: fascia vuota, conseguenze nel tooltip. | Categoria nella fascia, emblema della categoria in un medaglione, conseguenze scritte e colorate sotto ogni risposta. | 17 |
| Lista edifici: nome e costo in testo, categorie solo a icone. | Immagine dell'edificio dall'atlante, costo con le icone delle merci (in rosso ciò che manca), nome della categoria, tooltip con letti, lavoratori, deposito, dove può stare. | 18 |
| `✕` scritto a mano nell'ispettore della provincia, frecce `→` nei testi. | La croce dipinta; parole al posto delle frecce. | — |

## 18H — Coerenza

- **Risoluzioni.** Il progetto scala l'interfaccia per costruzione (`canvas_items`, base 1920×1080, `expand`):
  a 2560×1440 e a 3840×2160 il disegno è lo stesso della 1080p, 1,33 e 2 volte più grande e più nitido. **Non ho
  potuto aprire davvero una finestra 1440p o 4K**: il monitor di questa macchina è 1080p e Godot limita la
  finestra all'area dello schermo (le foto `p18h_24_1440p`, `p18h_25_4k` sono uscite a 1924×1061). Verificato
  invece: proporzioni diverse (`p18h_27_21-9`, `p18h_28_4-3`) e il test che misura le colonne fino a 2560 px.
- **Una lingua sola.** Tutti i riquadri usano i pezzi del kit (cornice con fascia per le schede e la carta evento,
  pannello scuro per barra, notifiche, liste), gli stessi colori per i segni (verde/rosso), le stesse barre di
  sezione, la stessa croce.
- **Prove.** `tests/unit/test_visual.gd` (orti, sentieri, bande di zoom dei segni, radure deterministiche,
  notifiche minori su una riga) e `tests/unit/test_ui.gd` (menu e barra bassa senza doppioni, scheda Religione,
  lista edifici solo in modalità costruzione, registro delle scorte e tooltip, salvataggio del registro).

## Resta aperto (dichiarato)

- **Tipografia**: i font sono ancora quelli di sistema (Palatino/Georgia di ripiego). Un font medievale incluso
  va scaricato: aspetto il tuo permesso.
- **Categoria «Speciali»** della lista edifici: nel gioco non esiste ancora un edificio speciale costruibile
  (chiesa, mura, monumenti). Non ho aggiunto una scheda vuota; arriverà con gli edifici.
- **Ruscelli sottili**: da vicino restano una linea.
- **Tooltip fissati per le foto** (`--kd-tip`): servono solo alle prove; in gioco il tooltip è il riquadro
  dipinto del tema.

---

## Revisione della HUD sul disegno di riferimento (seconda passata)

Il giocatore ha dato un disegno di riferimento per **posizioni, ingombri e gerarchia** (non per contenuti o
numeri). Foto: `tests/output/hud_*.png` (stessa finestra 1600×900; `hud_08_21-9`, `hud_09_4-3` per le
proporzioni).

**Spostato**
- Le risorse e le misure: da pastiglie separate agli angoli a **una fascia continua** da bordo a bordo, stemma
  del regno in apertura, icone da 22 a 32 px, numeri a 19 px, sotto ogni merce la variazione del mese chiuso
  (nascosta quando è zero), le misure con il loro nome scritto.
- Data e velocità: in un **orologio compatto** sotto l'estremità destra della fascia, con i pulsanti mappa e menu.
- Le notizie: dalla colonna di destra libera a un riquadro **Notizie** impilato sotto l'orologio, con «quanto
  tempo fa» (in giorni di gioco: restano finché sono recenti, anche a gioco fermo), clic per andare sul posto o
  aprire la cronaca, «Vedi tutto», ripiegabile.
- Le costruzioni: si aprono da **Costruzioni** nella colonna sinistra; il pannello sta a destra sotto le notizie,
  con il menu «Tutte le categorie» e schede grandi (immagine, descrizione, costo a icone, ore di lavoro, martello
  acceso o spento).
- Il menu delle mappe: dal fondo della colonna sinistra alla **Mappa del mondo**, in basso a sinistra.
- Le schede: al centro-sinistra, accanto alla colonna; il primo rigo sta sotto la linea interna della cornice.

**Unificato**
- Colonna sinistra: da otto voci a **quattro piastre grandi** con icona e freccia, «Il mio regno» più evidente.
- Barra inferiore: da quattro voci miste a **sei grandi sezioni** (Esercito, Ceti, Ricerca, Economia,
  Diplomazia, Religione) su una fascia da bordo a bordo.
- Grano e pane: una sola voce **Cibo** in alto, con il tooltip che li separa.

**Riassorbito (nulla è stato tolto)**
- Abitanti e famiglie: pulsante nella scheda **Il mio regno** (e tasto P).
- Cronaca: «Vedi tutto» nelle Notizie (e tasto C).
- Punti di sapere: nel tooltip di **Ricerca** e nella scheda.
- Uomini in armi: nuova voce della fascia (reparti in campo e in addestramento).

**Leggibilità**
- Testo mai sotto i 13 px (prima scendeva a 12, che a 1600×900 diventa 10), righe delle schede a 15, notizie
  a 14, tooltip a 15; hinting leggero dei font; barre di scorrimento più larghe e bordate d'oro.

**Da rifinire**
- Il testo resta un font di sistema: il salto vero di qualità è un font incluso nel gioco (serve il permesso di
  scaricarlo).
- Le icone della fascia sono ritagli dei fogli dipinti a 32 px: più grandi di così perdono nitidezza; un nuovo
  foglio di icone più grande le renderebbe più ricche.
- 1440p e 4K restano verificate solo per costruzione (monitor 1080p).

### Terza passata (osservazioni del giocatore sulla revisione)

Foto: `tests/output/hud2_*.png`.
- **Caratteri**: minimo portato a 14 px ovunque; valori della fascia a 23 px e variazioni a 15 px con ombra
  scura e colori più accesi; notizie a 14–15; guida a 15; etichette della mappa del mondo a 15–16.
- **Fascia alta**: icone da 32 a 44 px, più pesanti dei numeri; il valore accanto, la variazione piccola sotto.
- **Colonna sinistra**: la prima voce (La mia comunità → Il mio regno, stesso posto) è la targa dipinta con i
  due gigli, più alta (74 px), icona da 46 px; le altre tre restano compatte con la freccia.
- **Guida**: ripiegata in una barretta «Una casa per il Regno ›»; un clic apre il testo e il pulsante per
  chiuderla; la mappa del mondo resta sempre.
- **Notizie**: una riga sola — icona, titolo breve, tempo. Il testo completo al passaggio del mouse, sotto il
  titolo con un clic (con «Vai sul posto» quando ha un luogo), e nella Cronaca.
- **Barra bassa**: icone da 46 px, i sei pulsanti riempiono la fascia (niente più marrone vuoto ai lati).
- Nessun pulsante principale aggiunto: la struttura resta quella approvata.

