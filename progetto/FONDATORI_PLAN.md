# FASE 15 — SEI FONDATORI

Il gioco non comincia più con un Regno. Comincia con sei persone. Il Regno è una conquista del giocatore.

```
6 FONDATORI → COMUNITÀ → FAMIGLIE → VILLAGGIO → SCELTA DELLA CASA REALE → PRIMO SOVRANO → REGNO → DINASTIA
```

Sostituisce definitivamente l'avvio «1 Re + 6 abitanti».

---

## 1. Com'è oggi (e perché non basta togliere il re)

| Dove | Cosa fa oggi | Problema con il nuovo inizio |
|---|---|---|
| `settlement/settlement_setup.gd` | crea il **mastio**, un riparo, **il re** e sei abitanti | c'è un castello e un re dal giorno zero |
| `kingdoms/systems/court_system.gd::found_courts` | dà a ogni regno senza sovrano un re, un consorte, dei figli, le leggi di default | gira **anche al caricamento** di ogni salvataggio: una comunità senza re verrebbe incoronata a caso |
| `CourtSystem._ensure_king_person` | alla successione crea la persona del re nel villaggio | presuppone che la dinastia esista già |
| `settlement/systems/population_system.gd::_newborn` | una donna partorisce da sola, senza padre | niente coppie, niente discendenza, niente cognomi |
| `data/defs/person_names.json` | solo nomi propri | «i cognomi arrivano con famiglie e dinastie» — mai arrivati |
| `ui/kingdom/court_panel.gd` | «Il trono è vacante: i grandi del regno si contendono la corona» se non c'è re | è il messaggio di una crisi, non di una comunità che non ha ancora un re |
| `ui/shell/top_bar.gd` | legittimità, ordine, prestigio sempre in vista | misure di una corona che non esiste |

## 2. Le scelte che prendo (dichiarate)

1. **I sei arrivano soli e si uniscono dopo.** Tre uomini e tre donne, ciascuno con il cognome della
   famiglia da cui viene. Nei primi mesi formano le coppie: è la «formazione delle prime famiglie» che la
   Cronaca deve registrare come evento a sé, dopo l'arrivo. Una coppia prende il cognome del marito (la
   famiglia d'origine della moglie resta registrata). Tutto in `data/defs/balance/families.json`.
2. **Si nasce da una coppia.** Un figlio ha madre, padre, cognome e famiglia: è la discendenza. Chi arriva da
   fuori arriva con il proprio cognome e può sposarsi nel villaggio.
3. **Le condizioni della monarchia** (brief delle Fasi 15-20, §15.5), tutte in dati:
   - popolazione sufficiente: il **Villaggio** (30 abitanti, la parola che il gioco usa già);
   - villaggio stabile: **Fiducia** (il consenso degli abitanti) ≥ 45 e nessuno che salta i pasti;
   - economia funzionante: cibo per almeno 60 giorni, **scorte che arrivano al prossimo raccolto** e la cassa
     comune non in debito (aggiunto in corso d'opera: è lo stesso criterio per cui la gente se ne va, vedi
     `PopulationSystem.harvest_outlook`);
   - famiglie consolidate: almeno due famiglie con tre membri vivi;
   - **Autorità** della comunità ≥ 50 e almeno 2 anni dall'arrivo.
   Il pulsante mostra ogni condizione con il suo stato, non solo la prima che manca.
4. **Il livello del territorio**: `Rank.SETTLEMENT` fino all'incoronazione, `Rank.KINGDOM` dopo. Borgo e Città
   restano i gradi dell'insediamento, come oggi.
5. **Gli altri regni del mondo non cambiano**: sono poteri già costituiti, con i loro re. Sperduto è il
   giocatore, non il continente.
6. **All'inizio non c'è il mastio.** Ci sono un fuoco comune che fa da primo deposito e un riparo: tutto il
   resto si costruisce. Il mastio resta un edificio del gioco, ma non è più il punto di partenza.

## 2b. Le misure della comunità (brief §15.4)

Prima della corona legittimità e prestigio non esistono. Al loro posto:

- **Fiducia** — il consenso degli abitanti, che il gioco calcola già da fatti reali (cibo, letti, lutti…).
- **Autorità** — la capacità della comunità di decidere insieme. Nasce dai fatti: la fiducia, le famiglie
  consolidate, la sicurezza del cibo, gli edifici in piedi, gli anni passati insieme. Si muove piano, ogni
  mese, verso il suo bersaglio (`KingdomState.authority`, formula in `families.json`). All'incoronazione
  l'autorità raggiunta diventa la legittimità iniziale della nuova casa: chi ha governato bene la
  comunità comincia il regno più saldo.

## 2c. Cosa si vede di ogni famiglia (brief §15.6)

Membri con età e mestiere, **albero essenziale** (coppie e figli), **origine** che porterebbe alla corona
(contadini, artigiani, gente d'arme, la più stimata), **attività storica** (giorni nei campi, in bottega,
in armi, figli nati), **reputazione** (fondatrice, anni, membri, figli, lavoro), **rapporto con le fazioni**
(il favore che darebbe o toglierebbe) e i **vantaggi** moderati della sua origine. Il pulsante
«Scegli come Casa Reale» per ogni adulto eleggibile.

## 2d. Il momento storico (brief §15.7)

L'incoronazione apre una carta dedicata sopra la mappa — lo stemma nuovo della casa, il nome del primo
sovrano, «Nasce il Regno di …» — e l'interfaccia si trasforma: la colonna passa da «La mia comunità» e
«Famiglie» a «Il mio regno» e «Corte», le misure della corona compaiono nella fascia alta, Ceti e Leggi si
accendono.

## 3. Cosa si aggiunge

| Pezzo | File | Contenuto |
|---|---|---|
| **Famiglie** | `settlement/family_state.gd`, `WorldState.families` | id, cognome, giorno di fondazione, fondatori, registro di ciò che i membri hanno fatto (giorni nei campi, in bottega, in armi, figli nati) |
| **Legami nelle persone** | `settlement/person_state.gd` | `family`, `born_family`, `spouse`, `mother`, `father` |
| **Unioni** | `settlement/systems/family_system.gd` (nuovo sistema, mensile) | coppie tra adulti liberi, cronaca delle prime famiglie, registro dei mestieri |
| **Cognomi** | `data/defs/person_names.json` | una lista di cognomi per ogni cultura |
| **Stato pre-monarchico** | `KingdomState.monarchy_founded` | falso per la comunità del giocatore, vero per tutti gli altri regni e per i vecchi salvataggi |
| **La scelta** | `kingdoms/commands/found_monarchy_command.gd` | valida (livello, anni, adulto idoneo) e poi: dinastia, primo sovrano, consorte e figli come personaggi della corte, leggi e ceti, rango di Regno, cronaca |
| **Origine della casata** | `data/defs/house_origins.json`, nuova fonte in `KingdomModifiers` | contadini / artigiani / gente d'arme / famiglia più stimata: effetti moderati, e soprattutto un nome nella storia |
| **Cronaca prima della corona** | eventi nel sistema delle famiglie e nell'insediamento | arrivo dei sei, prima casa, prima unione, primo nato, primo raccolto, nascita del villaggio, scelta della casa, incoronazione, nascita del Regno |

## 4. Interfaccia prima e dopo

| Blocco | Prima della monarchia | Dopo |
|---|---|---|
| Fascia alta, misure | consenso e numero di famiglie; legittimità, ordine, prestigio nascosti | come oggi |
| Colonna sinistra | «La mia comunità», **«Famiglie»**, «Leggi e governo», «Diplomazia», «Abitanti» | «Il mio regno», **«Corte»**, … |
| Scheda Famiglie / Corte | **«NESSUN SOVRANO — La monarchia non è ancora stata fondata.»**, poi le famiglie con i membri, l'origine che avrebbero come casata e il pulsante **«Scegli come Casa Reale»** (spento con la ragione finché mancano le condizioni) | la Corte di oggi |
| Ceti | «Non ci sono ancora ceti: la comunità è fatta di famiglie.» | come oggi |
| Leggi | le leggi della corona si sbloccano con la corona | come oggi |
| Guida | un passo in più: «Una casa per il regno» | — |

## 5. Cosa non cambia

- Nessun sistema viene eliminato: corte, successione, eredi, legittimità, ceti, leggi restano identici e si
  **accendono** all'incoronazione.
- I regni dell'intelligenza artificiale, la guerra, la diplomazia, l'economia, la simulazione del villaggio.
- I vecchi salvataggi: il loro regno ha già un re, quindi vengono caricati come monarchie fondate
  (versione di salvataggio 4 → 5, con migrazione).

## 6. Ordine dei lavori e verifiche

1. Dati: cognomi, famiglie, origini delle casate, soglie.
2. Stato: famiglie, legami nelle persone, `monarchy_founded`, salvataggio e migrazione.
3. Nuovo avvio (sei fondatori, niente mastio), `found_courts` che salta la comunità.
4. Unioni, nascite da una coppia, registro dei mestieri.
5. Comando di fondazione della monarchia, origine della casata, cronaca.
6. Interfaccia: fascia alta, colonna, scheda Famiglie/Corte, Ceti, Leggi, guida.
7. Prove: il nuovo avvio (6, 3+3, nessun re, nessun castello); le coppie si formano e i figli hanno padre e
   cognome; la monarchia non si fonda prima della soglia e dice perché; la fondazione crea dinastia, sovrano,
   rango e cronaca; la successione funziona dopo; i vecchi salvataggi restano monarchie; nessuno viene
   incoronato al caricamento di una comunità. Più l'intera suite esistente, adattata dove presupponeva il re.

