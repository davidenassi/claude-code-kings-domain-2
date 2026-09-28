# KING'S DOMAIN — AUDIT DI CONSOLIDAMENTO DEI SISTEMI

Scopo (dal brief): **meno ridondanza, stessa profondità, più leggibilità**. Non si toglie profondità: si
tolgono i doppioni — due numeri che raccontano la stessa cosa, due schede che mostrano lo stesso dato, micro-effetti
che il giocatore non può percepire. Quando due sistemi si possono unire si preferisce **MERGE** a **REMOVE**.

Categorie: **KEEP** (resta com'è) · **MERGE** (si unisce a un altro) · **SIMPLIFY** (resta, ma più chiaro o più
sobrio) · **REMOVE** (esce, senza perdita di gioco) · **TRANSITIONAL** (esiste solo in una fase della partita).

Ogni voce riporta cosa c'è oggi nel codice e perché la si classifica così. I numeri vengono da misure fatte
sul progetto (script sui dati, due salvataggi di 40 anni, una campagna di 150 anni della Fase 19).

---

## 1. Indicatori politici e sociali

Oggi in cima allo schermo, dopo la corona: **Prestigio, Legittimità, Ordine, Fiducia**; prima della corona:
**Fiducia, Autorità, Famiglie** (conteggio). Nel codice e nei dati ci sono in più: `turbulence` (scosse che
abbassano l'Ordine), `happiness` dell'insediamento (è la Fiducia) e una chiave di modificatore `stability.base`
etichettata «Stabilità» che però **sposta la Fiducia della gente**, non l'Ordine.

| Voce | Oggi | Classe | Perché / cosa si fa |
|---|---|---|---|
| Prestigio | `k.prestige`, reputazione esterna: vittorie, eventi, diplomazia | **KEEP** | Unico, chiaro, attivo dopo la corona. |
| Legittimità | `k.legitimacy`, dinastia, successione, clero | **KEEP** | Attiva solo dopo la corona (già così). |
| Ordine + «Stabilità» | `k.order` mostrato «Ordine»; `order.base` = Ordine; `stability.base` = spinta alla Fiducia ma etichettata «Stabilità». Due nomi per due cose diverse, e lo stesso nome («stabilità») per una terza. Esempio reale: il coprifuoco dà «Ordine +10, Stabilità −5», dove quella «Stabilità» è la fiducia della gente. | **MERGE** | Un solo indicatore di tenuta interna: **STABILITÀ** (preferenza del brief). `order` → `stability`, `order.base` → `stability.base`; la vecchia `stability.base` diventa `trust.base` («Fiducia»). `turbulence` resta un fattore interno della Stabilità (visibile nel suo tooltip). |
| Fiducia / consenso / felicità | Un solo valore (`happiness` dell'insediamento), ma chiamato «Fiducia» in cima, «consenso» nella scheda Abitanti, in «Il mio regno», nelle parole degli effetti delle casate e negli eventi; «malcontento» in altri punti. | **MERGE (nomi)** | Un solo nome ovunque: **FIDUCIA** (già il nome in cima allo schermo). `happiness` → `trust` nel codice, nei dati e nei salvataggi. Non esiste una «felicità» separata: la voce «Felicità» del brief è già un fattore interno (le parti del tooltip: cibo, fame, alloggi, servizi, lutti, corona, assedio…). |
| Autorità | `k.authority`, solo prima della corona; all'incoronazione diventa il 60% della prima Legittimità; poi resta nel salvataggio ma non si vede. | **TRANSITIONAL** | Già transitoria. In più: all'incoronazione contribuisce anche alla prima **Stabilità** (una comunità che sa decidere insieme nasce più salda). Dopo la corona non compare in nessun pannello. |
| Famiglie (numero in cima prima della corona) | Conteggio delle famiglie con le radicate nel tooltip | **KEEP (dato)** | È una condizione della corona e non è un tasto; resta come dato di livello 1, il dettaglio va nei Ceti. |

## 2. Famiglie e Ceti

Oggi sono **due sistemi e due schede**:
- **Famiglie** (tasto a sinistra prima della corona, poi lo stesso tasto diventa «Corte»): condizioni del Regno, una
  scheda per ogni famiglia (albero, reputazione, lavoro, cosa porterebbe come casa reale, pulsanti «Scegli come
  Casa Reale»).
- **Ceti** (barra in basso): i cinque poteri del regno (Nobiltà, Popolo, Mercanti, Esercito, Clero) con favore,
  richieste, umore, doni ed effetto sulla corona — **ma prima della corona è una nota vuota**.
- In più: «Il mio regno» apre «Abitanti e famiglie»; la Corte ripete il favore dei cinque poteri
  («I POTERI DEL REGNO»); la scheda Religione ripete il favore del clero con un secondo misuratore.

Nel codice le famiglie hanno già un'**origine** calcolata dal lavoro fatto negli anni (`origin_jobs`):
contadini, artigiani, gente d'arme, «la famiglia più stimata». È lo stesso taglio dei ceti.

| Voce | Classe | Cosa si fa |
|---|---|---|
| Scheda Famiglie | **MERGE → Ceti** | Le famiglie vivono nei Ceti. Prima della corona la scheda Ceti mostra la comunità, i gruppi di lavoro e le famiglie (con la scelta della casa reale); dopo, ogni ceto mostra le sue **famiglie notabili**. |
| Tasto «Famiglie» a sinistra | **REMOVE** | Prima della corona a sinistra restano La mia comunità, Consuetudini, Costruzioni; «Corte» compare con la corona. |
| Condizioni del Regno | **MERGE → La mia comunità** | Sono lo stato della comunità: vanno nella sua scheda, con il rimando ai Ceti per scegliere la famiglia. |
| Ceti | **KEEP + SIMPLIFY** | Restano i cinque poteri con i loro pochi valori (favore = rapporto con la corona, peso = influenza, richieste, reazioni a leggi, tasse, guerre e doni). «Mercanti» diventa **«Mercanti e artigiani»** (le gilde erano già fra le loro richieste): è lì che vanno le famiglie di artigiani. Nessun sesto ceto: il brief chiede di adattare l'elenco alle meccaniche esistenti. |
| Famiglia → ceto | **nuovo, derivato** | Dall'origine: contadini → Popolo, artigiani → Mercanti e artigiani, gente d'arme → Esercito, famiglia stimata senza mestiere prevalente → Popolo. Dopo la corona: **Nobiltà** per le famiglie antiche e numerose (reputazione alta) e per quelle **imparentate con la casa reale**; la **Casa reale** ha uno stato a sé. Il Clero per ora non ha famiglie (non esiste un mestiere religioso da cui dedurle). Derivato ogni volta: una famiglia che cambia vita cambia ceto, e i salvataggi vecchi vengono smistati da soli. |
| Famiglie notabili | **SIMPLIFY (scala)** | Prima della corona tutte (sono poche); dopo, per ogni ceto le più influenti (poche) più «e altre N famiglie». Le famiglie in UI non esplodono più: nella campagna di 150 anni ce n'erano 1207 nel registro. |
| Casa reale | **KEEP** | Da «Il mio regno» (la casata, il sovrano, l'erede) e dai Ceti (stato speciale, rapporti coi ceti). |
| «I POTERI DEL REGNO» nella Corte | **REMOVE (doppione)** | Il favore dei ceti sta nei Ceti. La Corte è il sovrano, la sua casa, i suoi eredi. |
| Misuratore «Favore del clero» nella Religione | **MERGE → Ceti** | La Religione è la fede, le sue norme, la legge di fede e le fedi delle terre; il clero è un ceto: nella Religione resta una riga su quanto il clero pesa sulla legittimità e come reagisce, con il rimando ai Ceti. |
| «Abitanti e famiglie» | **SIMPLIFY** | Diventa «Abitanti» (chi fa cosa, nome per nome); le famiglie sono nei Ceti. |

## 3. Individui e scala

Oggi: solo gli insediamenti del giocatore hanno abitanti individuali (`PersonState`); le province, anche quelle
conquistate, hanno una popolazione aggregata (`ProvinceState.population`). La città del giocatore va da 6 a ~600
abitanti in 150 anni; la Fase 19 ha misurato città da 1000–2000 abitanti a costi accettabili. Le corti di tutti i
regni sono personaggi (`CharacterState`), limitati (~150–175 in 150 anni).

| Voce | Classe | Perché |
|---|---|---|
| Individui nel villaggio del giocatore | **KEEP** | È il cuore della piccola comunità; oltre una certa taglia la simulazione ora per ora vale solo sotto la telecamera, altrove la giornata si risolve per aggregato (già così). |
| Regno grande | **KEEP** | Popolazione aggregata per provincia: non si simulano 100.000 persone (non è mai successo). |
| Famiglie in UI | **SIMPLIFY** | Vedi «famiglie notabili». |

## 4. Spiriti nazionali

32 spiriti, con origine (geografia, registri delle azioni) ed evoluzione (`evolves`). Un regno ne tiene **fino a 6**
insieme (4 iniziali): nei due salvataggi di 40 anni il giocatore ne aveva 6. Effetti: 57 modificatori, 5 sotto la
soglia percepibile (+3% difesa fanteria, +0,03 controllo, +2 legittimità…).

| Voce | Classe | Cosa si fa |
|---|---|---|
| Sistema degli spiriti | **KEEP** | Origine geografica + storia + decisioni, evoluzione: è l'identità di King's Domain. |
| Numero contemporaneo | **SIMPLIFY** | Da 6 a **4** al massimo (3 iniziali): pochi, importanti. |
| Effetti minuscoli | **SIMPLIFY** | Ogni spirito tiene pochi effetti percepibili: i secondi effetti sotto il 5% escono o diventano percepibili. |

## 5. Modificatori

184 modificatori nei dati, **16 minuscoli** (<5% o <3 punti): origini delle casate (3), leggi (2), spiriti (5),
tratti (6). Più i due piccoli continui del sovrano (governo e diplomazia). «Il mio regno» mostra per intero
«La formula del regno»: 22 voci con tutte le fonti.

| Voce | Classe | Cosa si fa |
|---|---|---|
| Modificatori minuscoli | **SIMPLIFY** | Via dove l'oggetto ha già un effetto principale; portati a un valore percepibile dove sono l'unico effetto. |
| La formula del regno | **SIMPLIFY (livello 3)** | Resta, ma chiusa: si apre a richiesta. |

## 6. Cronaca

Nei due salvataggi di 40 anni la cronaca è al tetto di **600 righe**, e solo **47** (e 29) riguardano il giocatore.
Il resto: 129/154 eserciti che «varcano il confine», 119/69 patti fra regni dell'IA, 116/129 assedi, 88/86
occupazioni, 41/22 rivendicazioni. La storia del giocatore viene spinta fuori dai movimenti degli altri.

| Voce | Classe | Cosa si fa |
|---|---|---|
| Cronaca | **KEEP** | Fondazione, famiglie storiche, incoronazioni, guerre, grandi costruzioni, crisi, rivolte, trattati, cambi dinastici. |
| Micro-fatti (marce, assedi posti, occupazioni, rivendicazioni, patti fra altri) | **REMOVE dalla cronaca** | Restano solo se toccano il giocatore; le occupazioni si vedono sulla mappa, i patti nella Diplomazia, le paci e le conquiste restano. |

## 7. Modalità mappa

8 modalità (Politica, Terreno, Culture, Religioni, Risorse, Sviluppo, Popolazione, Diplomazia), già raccolte sotto
un solo pulsante «Mappa: …», ma tutte allo stesso livello.

| Voce | Classe | Cosa si fa |
|---|---|---|
| Politica, Terreno, Risorse, Popolazione | **KEEP (principali)** | Sempre in vista nel menu. |
| Culture, Religioni, Diplomazia, Sviluppo | **SIMPLIFY (secondarie)** | In una sotto-lista «Altre mappe»; tasti F invariati. |

## 8. Eventi

57 eventi, due scelte ciascuno, condizioni su stagione, geografia, corona, famiglie, tratti del sovrano, ceti.
Uno solo muove soltanto numeri piccoli («Lite tra famiglie»: autorità ±3–4, fiducia ±2–3); qualche seconda scelta
vale ±1.

| Voce | Classe | Cosa si fa |
|---|---|---|
| Eventi | **KEEP** | Sono decisioni con conseguenze, legate a ceti, famiglie, sovrano, geografia. |
| «Lite tra famiglie» e le scelte da ±1 | **SIMPLIFY** | Conseguenze percepibili. |

## 9. Ricerca

8 tecnologie in 4 rami (una strada per ramo), effetti dall'8% al 60%: nessuna esiste per un +1%.

| Voce | Classe | Cosa si fa |
|---|---|---|
| Ricerca | **KEEP** | Effetti già percepibili. |
| «Crisi in corso» nella scheda Ricerca | **MERGE → Il mio regno** | Le crisi sono lo stato del regno, non il suo sapere. |

## 10. Religione

La scheda Religione: la fede, il clero (misuratore del favore — doppione dei Ceti), la legge di fede, le fedi delle
terre. → vedi sezione 2: **MERGE** del misuratore nei Ceti, **KEEP** del resto.

## 11. Economia

Tesoro (entrate e uscite del mese), depositi (con il flusso del mese), lavoro (mestieri), prezzi. Manca la risposta
diretta a «dove sto perdendo, cosa devo costruire», che oggi va ricostruita leggendo i numeri.

| Voce | Classe | Cosa si fa |
|---|---|---|
| Tesoro, depositi | **KEEP** | Cosa produco, cosa consumo. |
| «Cosa manca» | **nuovo (sintesi)** | In cima: depositi pieni, cibo per pochi giorni, letti finiti, saldo negativo, con cosa costruire. Solo dati che esistono già. |
| Lavoro | **MERGE** | Il dettaglio dei gruppi di lavoro va nei Ceti (gruppi professionali); in Economia resta una riga. |
| Prezzi | **SIMPLIFY (livello 3)** | Chiusi, si aprono a richiesta. |

## 12. Complessità progressiva e interfaccia

Già oggi: prima della corona niente sovrano, legittimità, corte, leggi (consuetudini), patti; la barra in alto
mostra le misure della comunità. Da sistemare: il tasto «Famiglie» (vedi sopra), i Ceti vuoti prima della corona
(ora mostreranno la comunità).

| Voce | Classe |
|---|---|
| Struttura dell'HUD approvata (sinistra: comunità/regno, corte dopo la corona, governo, costruzioni; basso: esercito, ceti, ricerca, economia, diplomazia, religione) | **KEEP** |
| Tooltip «perché questo valore è così» (Legittimità, Stabilità, Prestigio, Fiducia, Autorità: parti con segno) | **KEEP** (rinominati) |

## 13. Salvataggi

Ogni rinomina passa da una migrazione **v5 → v6** (mai un salvataggio rifiutato): `order` → `stability`,
`happiness` → `trust`, chiavi dei modificatori nelle crisi salvate, sezioni di bilanciamento lette dal codice.
Le famiglie non cambiano formato: il ceto si deduce, quindi nomi, membri, storia, dinastia e legami restano.

---

## Piano (in quest'ordine, ognuno verificato prima del successivo)

1. **Indicatori**: Stabilità (ex Ordine), Fiducia (ex happiness/consenso/felicità), chiavi dei modificatori,
   Autorità che fonda anche la prima Stabilità, migrazione v6 con test.
2. **Ceti ⊃ Famiglie**: ceto di ogni famiglia, notabili, scheda Ceti prima e dopo la corona (con la scelta della
   casa reale), condizioni in «La mia comunità», Corte solo dopo la corona e senza il doppione dei poteri,
   Religione senza il doppio misuratore, Abitanti, guida aggiornata.
3. **Spiriti** (massimo 4) e **modificatori** minuscoli.
4. **Cronaca** senza micro-fatti.
5. **Mappa** principali/secondarie; **Economia** «cosa manca»; crisi in «Il mio regno»; formula e prezzi chiusi.
6. **Eventi** deboli.
7. Test (nuova partita, monarchia, regno medio, grande regno, salvataggi vecchi e nuovi, eventi, cronaca, UI, IA),
   `SYSTEM_CONSOLIDATION_REPORT.md`, documenti, commit.

