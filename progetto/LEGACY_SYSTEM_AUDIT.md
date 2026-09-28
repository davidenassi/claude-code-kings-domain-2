# LEGACY SYSTEM AUDIT — da *Regno* a *King's Domain*

Fonte analizzata: `Regno old.zip` → `Regno.html` (identico a `Regno_9.html`), ~25.200 righe,
un unico file HTML/JS con ~90 moduli logici. Analisi eseguita il 16/09/2026.

Regno.html è trattato come **specifica funzionale**: da qui si estraggono sistemi, numeri e
interazioni. Nessuna riga di JS viene portata in Godot; l'architettura (una valle a griglia +
una "carta strategica" separata + una scena di battaglia separata) è esattamente ciò che
King's Domain deve superare.

Legenda esito:
- **TENERE** — il sistema passa in KD con la stessa logica (dati ribilanciabili).
- **TRASFORMARE** — lo scopo resta, la forma cambia per il mondo unico.
- **ELIMINARE** — concetto legacy da rimuovere.

---

## 1. Mappa dei moduli di Regno

| Riga | Modulo Regno | Contenuto | Esito |
|---|---|---|---|
| 2364 | CORE | Bus eventi, tick logico 10/s, RNG deterministico (mulberry32), hash2D, value noise, heap | TRASFORMARE (EventBus/Clock/RNG Godot) |
| 2481 | DATI | Risorse, terreni, stagioni, calendario, edifici, bilanciamento, salari | TENERE come dati JSON |
| 3170 | GOVERNO (dati) | Razioni, tasse, leva, leggi, decreti, festa, forma dello Stato, riforme | TENERE |
| 3399 | ESERCITO (dati) | 8 unità, contrasti, formazioni, ordini, terreni e meteo di battaglia | TENERE |
| 3564 | NEMICI | Banditi, goblin, troll, sciamani, non-morti, nani, elfi, teutonici | Banditi: TRASFORMARE in briganti/ribelli · resto: ELIMINARE |
| 3637 | ARMERIA | 4 slot × 3 livelli di equipaggiamento | TRASFORMARE (sblocchi non più da "vittorie in campagna") |
| 3669 | DIFFICOLTÀ | 6 leve (lavoro, resa, sventure, viandanti, colonizzate, nascita) | TENERE |
| 3724 | ICONE | Icone vettoriali canvas | ELIMINARE (sostituite da asset) |
| 3866 | ARALDICA | Stemmi procedurali da hash del nome casata | TENERE (generatore stemmi) |
| 4078 | MONDO (valle) | Griglia 128×128 locale, 9 zone da aprire | TRASFORMARE: le regole di terreno passano al mondo unico · zone: ELIMINARE |
| 4622 | SOCIETÀ | 6 classi sociali, miscela per insediamento, umori, rischio rivolta | TENERE |
| 4747 | MERCATO | Prezzi dinamici per scarsità | TENERE, esteso a mercati regionali |
| 4848 | POLITICA | 5 poteri, favore, scosse con rivalità, richieste/crisi/doni, vocazioni | TENERE (fazioni) + vocazioni → Spiriti Nazionali |
| 5341 | Memoria del regno | Reazioni politiche ai gesti via Bus | TENERE |
| 5446 | CETI | Clero/Soldati/Cittadini → Legittimità/Consenso | TRASFORMARE (fuso nelle fazioni) |
| 5634 | PERCORSI | A* 8-direzioni con costo strade | TENERE come concetto (navigazione Godot + grafo) |
| 5709 | CRONACA | Voci per anno e categoria, bilancio finale | TENERE |
| 5778 | MONDO (carta) | 256×174 celle, 240 province a onde, continente, laghi, fiumi | TRASFORMARE: mappa **fissa**, non più generata a seme in partita |
| 6421 | REGNI | 24 corone, indoli, scopi, economia astratta, misure della corona | TENERE (logica) / TRASFORMARE (dati fisici) |
| 7112 | DIPLOMAZIA | Opinioni, patti, guerre, tregue, azioni con probabilità | TENERE |
| 7457 | ESERCITI | Armate sulla carta, rifornimenti, marcia, assedi, battaglie astratte | TENERE + battaglie **sulla mappa** |
| 8023 | FRONTE | Tappe di una guerra verso la capitale | TRASFORMARE in obiettivi di guerra |
| 8150 | IA REGNI | Memoria (rancore/stima), scopi, testa del regno | TENERE, ristrutturata in planner |
| 8802 | TECNOLOGIA | 4 rami × 3 livelli lineari | TRASFORMARE (specializzazioni esclusive) |
| 8915 | CORTE | Tratti, consorte, eredi, educazione, successione | TENERE, estesa a dinastie |
| 9196 | SPEDIZIONI (valle) | Pagare oro per aprire zone della valle | **ELIMINARE** |
| 9383 | SPEDIZIONI terre di nessuno | Spedizioni sulla carta | **ELIMINARE** |
| 9568 | SIMULAZIONE | Il villaggio: edifici, depositi, abitanti, nascite, morti, felicità | TENERE (riscritto data-oriented) |
| 10530 | AMBIZIONI | Mete lunghe misurate sui rivali | TENERE → obiettivi di campagna |
| 10680 | LAVORO | Assegnazione posti, carrettieri, catene di trasporto | TRASFORMARE (flussi + agenti visivi) |
| 11241 | GOVERNO (logica) | Effetti composti, leggi, decreti, riforme, paghe, gettito | TENERE |
| 11561 | CANTASTORIE | Eventi pesati sullo stato con scelte | TENERE, reso data-driven |
| 12110 | CRISI | Epidemia, incendio, gelo, razzie, repressione | TENERE |
| 12383 | COLONI | Coloni da province conquistate | TRASFORMARE (migrazioni) |
| 12467 | OSPITI | Mercanti che arrivano fisicamente in valle | TENERE (carovane sulla mappa) |
| 12620 | SALVATAGGIO | JSON versionato v5 in localStorage | TRASFORMARE (file, save_version, migrazioni) |
| 12894 | SUONO | Sintesi WebAudio | ELIMINARE (placeholder audio in Fase 14) |
| 13504 | ESERCITO (valle) | Reclutamento da cittadini, scuole, leva automatica, riarmo, paghe | TENERE |
| 14070 | CAMPAGNA | Carta a nodi "oltre il fiume" contro banditi/goblin, sblocco unità | **ELIMINARE** (tenere le 4 unità) |
| 14339 | BATTAGLIA | Battaglia tattica a reggimenti in scena separata | TRASFORMARE: stesse regole, **sulla mappa** |
| 14869 | IA BATTAGLIA | Avanza, aggira, protegge tiratori | TENERE (IA tattica in mappa) |
| 14970–18745 | PRESENTAZIONE | Canvas della valle, ritratti, battaglia, carta, marching squares | ELIMINARE (nuovo rendering 2.5D) |
| 18746–24976 | UI | Cruscotto, pannelli governo/regno/esercito/corte/diplomazia/fronte, tutorial | TRASFORMARE (nuova UI Godot) |
| 24298 | ESPLORAZIONE (UI) | "I tre modi di allargarsi" | **ELIMINARE** |
| 24478 | FINE DI UNA STORIA | Schermata dopo 160 anni | TENERE (cronaca finale) |
| 24981 | OBIETTIVI | Missioni tutorial lineari | TRASFORMARE (obiettivi guida senza campagna) |

---

## 2. Inventario dei sistemi da TENERE (con numeri chiave)

I numeri servono come **punto di partenza del bilanciamento**, non come vincolo.

### 2.1 Tempo e calendario
- Tick logico fisso (10/s) separato dalla grafica interpolata.
- Anno che inizia a Marzo, 4 stagioni, anno di partenza **1230**.
- Stagioni con moltiplicatore agricolo `1.0 / 1.25 / 0.85 / 0.0` e ricrescita bosco `1.4 / 1.0 / 0.6 / 0`.
- Regno comprimeva l'anno in 32 giorni e faceva invecchiare ~9,6 anni per anno di gioco:
  **in KD l'età avanza realisticamente** (le generazioni devono succedersi in modo credibile
  in una campagna lunga). Vedi TECHNICAL_ARCHITECTURE §6.
- Campagna di riferimento: 160 anni, poi "vuoi continuare?".

### 2.2 Risorse
`legno, pietra, ferro, grano, pane, armi, oro` (Regno v5 aveva già tolto farina/mulino).
KD aggiunge (fasi successive): `cavalli` (legati alle province d'allevamento, necessari per
cavalleria), e l'oro diventa esplicitamente *tesoro della corona*, non merce di magazzino.

### 2.3 Terreno locale (regole che passano al mondo unico)
| Terreno | Camminabile | Edificabile | Costo passo |
|---|---|---|---|
| Acqua | no | no | — |
| Riva | sì | sì | 1.2 |
| Erba | sì | sì | 1.0 |
| Terra fertile | sì | sì | 1.0 |
| Bosco | sì | **no** (va abbattuto) | 1.7 |
| Roccia | no | no (va scavata) | — |
| Vena di ferro | no | no | — |
| Collina | sì | sì | 1.35 |
| Pietraia (cava esaurita) | sì | sì | 1.25 |
- Strada: costo 0.55, velocità 2.7 contro 1.5; ponte 0.9.
- Ogni cella di bosco ha 3–5 "cariche" d'ascia; esaurita diventa erba con **ceppo** che
  ricresce dopo ~42 giorni ×(0.8–1.4) se non occupata.
- Roccia: 7–10 cariche; ferro: 14–20; esaurita → pietraia **permanente**.
- Mura con punti ferita (120), cancello (90), torri con danno a distanza.
- Controllo che un muro o un edificio **non tagli fuori** altri edifici dal centro.

### 2.4 Edifici (villaggio) — da Regno
| Edificio | Taglia | Costo | Posti | Funzione |
|---|---|---|---|---|
| Mastio | 3×3 | — | — | deposito 520, 8 letti |
| Casa | 2×2 | legno 14 | — | 4 letti |
| Pozzo | 1×1 | legno 6, pietra 8 | — | igiene r12 |
| Taglialegna | 2×2 | legno 16 | 2 | legno da bosco r14, ciclo 30, resa 4 |
| Cava | 2×2 | legno 24 | 2 | pietra da roccia r12, ciclo 46, resa 2 |
| Miniera | 2×2 | legno 26, pietra 16 | 2 | ferro da vena r10, ciclo 60, resa 1 |
| Fattoria | 3×3 | legno 20 | 3 | grano su terra fertile r9, stagionale |
| Forno | 2×2 | legno 20, pietra 14 | 1 | grano 4 → pane 6 |
| Magazzino | 3×3 | legno 26 | — | legno/pietra/ferro/armi 400 |
| Granaio | 3×3 | legno 22, pietra 6 | — | grano/pane 400 |
| Mercato | 2×2 | legno 28, pietra 8 | — | svago r16 |
| Fabbro | 2×2 | legno 26, pietra 22 | 1 | ferro 2 + legno 1 → armi 2 |
| Caserma | 3×3 | legno 44, pietra 34 | — | lancieri, fanti, alabardieri |
| Campo di tiro | 3×3 | legno 38, pietra 12 | — | arcieri, balestrieri |
| Stalle | 3×3 | legno 48, pietra 24 | — | cavalleria, cavalieri |
| Torre | 2×2 | legno 18, pietra 40 | — | sicurezza r14, danno 3 r9 |
| Mura / Cancello / Ponte / Strada | 1×1 | pietra / legno | — | infrastruttura |

Edifici di provincia (astratti, a livelli) in Regno: fattorie, segheria, miniera, mercato,
pieve/chiesa, caserma, mura, strade, studio/università. **In KD diventano edifici fisici**
negli insediamenti delle province (vedi GAME_DESIGN_MAP §7).

### 2.5 Popolazione
- Abitanti con nome, età, sesso, mestiere, casa, lavoro, fame, umore, malattia.
- Mestieri: senza lavoro, boscaiolo, cavatore, minatore, contadino, fornaio, carrettiere, costruttore.
- Salari giornalieri per mestiere (0.02–0.18 oro), soldati 0.35 oro + 0.5 pane.
- Crescita: nascite come **tasso annuo** (0.20 × felicità × scorte × leggi × difficoltà),
  bloccate senza letto libero, felicità < 42 o cibo < 4 giorni/abitante.
- Viandanti: arrivano solo con letti liberi, ≥7 giorni di cibo, felicità ≥ 32 (a volte famiglie).
- Morti: fame, vecchiaia (>62), malattia, felicità < 20.
- Felicità (Consenso): cibo, alloggi, fame media, copertura servizi (pozzi/mercati), lutti,
  governo (razioni/tasse/leva/decreti/leggi/festa/corte/malcontento), malati, incendi, nemici, legittimità bassa.
- Quota costruttori regolabile (Pochi 15% / Giusti 34% / Molti 55% / Tutti 80%) con
  trade-off misurato (troppi costruttori bloccano i trasporti).
- Dispensa della corona: rete di sicurezza minima quando le scorte crollano.

### 2.6 Economia e mercato
- Prezzi base: legno 1.0, pietra 1.3, ferro 3.2, grano 0.9, pane 2.0, armi 6.5.
- Prezzo verso `base × clamp((riferimento·pop / scorta)^0.42, 0.55, 2.4)`, 12%/giorno;
  guerra alza armi/ferro, carestia alza cibo.
- Capacità di scambio = mercati × 40 × effetti; compra +10%, vendi −8%.
- Gettito: `pop × 0.55 × moltiplicatore tassa × tratti × vocazione × leggi` + 5 per mercato.
- Rendita province: `(pop/260)·(0.55 + sviluppo·0.18)` × vocazione del terreno × risorsa speciale,
  ridotta da occupazione (×0.15) e malcontento (>40), frenata dal **controllo amministrativo**
  `clamp(0.55 + tecnologie − 0.012·province, 0.3, 1)`.

### 2.7 Province (dati da mantenere, ampliati)
Campi Regno: nome, terreno (pianura/collina/bosco/montagna/palude/costa), celle, centro,
fiume, proprietario, insediamento (nessuno/villaggio/città/capitale), popolazione, sviluppo,
fortificazione, malcontento, occupata, assedio, cantiere, risorsa speciale, edifici, strade,
vicine, guadi.

Moltiplicatori per terreno (grano/legno/ferro/pietra, difesa, movimento):
pianura 1.35/.55/.25/.35 d1.0 m1.0 · collina .85/.75/.85/1.1 d1.25 m1.3 · bosco .6/1.75/.3/.25 d1.2 m1.4 ·
montagna .25/.35/1.7/1.55 d1.75 m1.9 · palude .45/.85/.2/.15 d1.35 m1.8 · costa .95/.55/.2/.45 d0.9 m1.0.

Risorse speciali: vene di ferro (×2.2), terra grassa (×1.9), cave (×2.0), foreste antiche (×1.9),
filone d'oro (×2.4), fiera annuale (×1.7).

Regole: difesa = terreno × (1 + fort·0.45) × (1 + insediamento·0.12); leva = pop·5%;
crescita verso tetto `260 + sviluppo·190 + fattorie·120`; malcontento ≥72 → secessione
(probabilità `(m−68)/620`, 45% verso un vicino); conquista +28 malcontento; capitale conquistata → città.

### 2.8 Le misure della Corona
- **Prestigio**: strutturale (terre, fortezze, risorse) + guadagno di corte lento; mostrato come
  **fama estera** relativa (0–10) = reputazione + terre vs media rivali ×2 + (vittorie−sconfitte)×3 + alleanze×5.
- **Legittimità** (init 65): bersaglio = 50 ±erede (+15/−12), età sovrano (<16 −20, >65 −6),
  tratto guerriero +8, corte completa +6, −10 per ogni potere chiave (esercito, popolo, clero) ostile;
  inseguito al 12%/giorno. <35 malus consenso, <30 congiure, <15 emergenza dinastica.
- **Ordine** (ex Stabilità): `100 − scontento poteri·0.5 − pressione fiscale − turbolenza + guarnigione`;
  la turbolenza sale per fatti precisi (razzia +6, tiranno +20, guerra impopolare +18) e scende 1.5/giorno.
- **Consenso/Fiducia**: la felicità del popolo.

### 2.9 Politica interna — i cinque poteri (→ Fazioni KD)
| Potere | Peso | Rivali | Vuole |
|---|---|---|---|
| Nobiltà | 3.2 | Popolo | terre, guerre vinte, corona che ascolta |
| Popolo | 1.0 | Nobiltà, Esercito | pane, tasse leggere, figli a casa |
| Clero | 2.4 | Mercanti | chiese, rispetto, niente indulgenze |
| Mercanti | 2.2 | Clero, Esercito | strade sicure, trattati, niente guerre |
| Esercito | 1.8 | Mercanti, Popolo | paga, armi nuove, un nemico |

- Potere = quota di classi × peso; Favore 0–100 insegue l'umore reale (7%/giorno, il malumore non rallenta).
- **Scossa**: ogni gesto dà un vettore di favore; i rivali di chi guadagna perdono il 42%; massimo 16.
- Soglie: <38 **richiesta** concreta (accetta / compromesso a metà prezzo / rifiuta), dopo 2 rifiuti
  e favore <26 **crisi** (congiura, tumulto, interdetto, serrata dei banchi −45% commercio per 14 giorni,
  ammutinamento); >74 **dono** (oro, entusiasmo, benedizione, prestito, fedeltà).
- Eventi che scuotono i poteri: decreti, leggi, feste, guerra/pace, conquiste/perdite, costruzioni
  (chiesa, mercato, caserma, mura), tecnologie, battaglie, commercio, tassazione stagionale.

### 2.10 Vocazioni (proto-Spiriti Nazionali, dinamici)
Registri `armi / commercio / fede / ordine` accumulati dalle azioni reali (legge +26, decreto +8,
guerra +14, conquista +10, mercato +10, chiesa +12, caserma +10, tecnologia +9, battaglia vinta +8…),
con oblio 1.5%/giorno. Una vocazione si afferma se il registro primo ≥55, supera il secondo ×1.3
per 10 giorni: *militare, mercantile, religioso, autoritario*, ciascuno con pro e contro e con
riequilibrio del peso dei poteri. **In KD questo meccanismo è la base degli Spiriti Nazionali dinamici.**

### 2.11 Governo, leggi, editti
- Leve quotidiane: razioni (scarse/normali/doppie), tasse (5 livelli, +18 → −30 umore),
  leva automatica (0% → 5% al giorno), priorità del fabbro (reclute/armeria), festa (60 oro, 25 pane, +22 per 6 giorni).
- **Leggi** permanenti, esclusive per gruppo (fisco: catasto/franchigia; fede: decima/tolleranza;
  armi: leva perpetua/congedo invernale; famiglia: culle piene/doti tardive) + annona, corte di giustizia,
  libertà delle gilde, strade maestre. Ognuna: costo, mantenimento, effetti, **vincitori e perdenti politici**.
- **Editti** revocabili: catena dell'acqua (emergenza, 3 giorni), turni lunghi, giorno di riposo,
  coprifuoco, indulgenze, gilda dei mastri, medico di corte, arruolamento obbligatorio, granai aperti.
- **Forma dello Stato**: asse assoluta ↔ rappresentativa (5 gradi), Corona (4), Assemblea (4),
  Amministrazione (3); si muovono solo con **riforme** a un passo, con requisiti di Legittimità/Ordine,
  costo e scossa ai poteri. Nessuna forma è "quella giusta".
- Malcontento fiscale: sale con pressione < −12 (moltiplicato dalla forma dello Stato), scende con pressione ≥ 0.

### 2.12 Corte e successione
- Tratti: giusto, generoso, avaro, guerriero, pio, crudele, saggio, severo, gaudente, malaticcio, robusto, amato.
- Consorte da proposte (dote 60–320), figli, erede designato, educazione (armi→guerriero,
  lettere→saggio, fede→pio, governo→giusto), torneo.
- Morte per età (rischio crescente oltre 58/70 × vita), attentati.
- Successione: erede adulto (liscia), minorenne (crisi +12 malcontento), nessun erede (cugino lontano, crisi +20);
  la crisi si chiude con sovrano ≥16 e consenso > 52.

### 2.13 Regni e IA
- **Indoli** (moltiplicatori guerra/tradimento/commercio/sviluppo/alleanze): conquistatore,
  prudente, mercante, devoto, opportunista, costruttore.
- **Scopi** (moltiplicano l'indole, durano 40–300 giorni): espansione (provincia), vendetta (regno),
  egemonia, ricchezza, consolidamento, sopravvivenza.
- **Memoria**: rancore (provincia strappata 34, guerra 16, tradimento 42, rifiuto 3; oblio 0.22/giorno;
  ≥52 giura vendetta) e stima (al fianco in guerra 22, dono 8). Opinione diplomatica che torna a zero in mesi
  ≠ rancore che dura anni.
- Ciclo di pensiero (1/3 dei regni al giorno): ricerca, costruzione dove serve allo scopo, arruolamento
  proporzionato a minaccia e indole, diplomazia con interlocutori scelti dallo scopo, pace per stanchezza,
  guerra su bersagli votati (terra libera, debolezza relativa, prestigio, opinione, rancore, scopo).
- Contro il giocatore: **3 anni di grazia** iniziali e **preavviso** di 8 giorni ("sguardi dal confine").

### 2.14 Diplomazia
Opinione −100…100 (decade), stato pace/guerra, tregua 60 giorni, patti (non aggressione a scadenza,
commercio, alleanza, matrimonio), reputazione (tradire −30). Azioni: ambasciatore, doni, non aggressione,
trattato commerciale, alleanza, matrimonio dinastico, chiedere denaro, imporre tributo, vassallaggio,
ultimatum, guerra, pace — ognuna con formula di accettazione leggibile. Gli alleati del difensore entrano in guerra.

### 2.15 Eserciti, assedi, battaglie
- Armata: uomini, feriti, veterani, morale, rifornimenti (max 30), generale (attacco/difesa/assedio/marcia 1–5),
  esperienza, stato ferma/marcia/assedio.
- Rifornimenti: +4 in terra amica, +1.2 con linea, −1 altrimenti; a zero logoramento 1.2%/giorno.
- Assedio: punti/giorno ∝ uomini, generale, tecnologia; viveri del difensore; assalto con perdite 22%;
  guarnigione `clamp(pop·0.055 + fort·55, 70, 900)`.
- Battaglia astratta: potenza = uomini × tecnologia × generale × morale × veterani × terreno;
  vincitore −12%/q, sconfitto −34%·q·0.6, ritirata verso casa, stanchezza di guerra.
- **Battaglia tattica** (la parte più preziosa): reggimenti con ancora e slot di formazione, soldati in
  array compatti, contrasti leggibili (lancia ferma cavallo ×3.1, cavallo travolge arciere ×2.6,
  alabarda apre armature), fianco/schiena ×1.55, carica annullata contro lance frontali (×0.42),
  formazioni con bonus reali (linea, profonda, cuneo, quadrato, muro di scudi, sparsa, colonna, mezzaluna),
  terreno (piano/collina/bosco/fango/guado) e meteo (sereno/pioggia/nebbia/neve),
  **morale come vero sistema di vittoria** (rotta ≤15, raccolta ≥46, panico contagioso, capitano +0.55,
  caduta del capitano −16 a tutti), stanchezza, IA tattica.
- Unità: lancieri, fanti, **alabardieri**, arcieri, **balestrieri**, cavalleria leggera, **cavalieri**, **capitano**.
- Reclutamento dai cittadini veri (15–48 anni) in scuole con code e tetti, leva automatica con
  soldati "a pugni" se mancano armi, riarmo progressivo, diserzioni se non pagati/sfamati.

### 2.16 Eventi e crisi
Eventi pesati dallo stato (non casuali): febbre (igiene), incendio (estate, edifici in legno),
rivolta (felicità, malcontento, tratto crudele), banditi (oro, guarnigione), assalto, carestia in provincia,
alleato che chiede aiuto, complotto a corte, scoperta mineraria, mercanti, ambasciata, raccolto, gelo, lupi,
miracolo. Ogni evento propone 2–4 scelte con costi reali; nessun evento due volte di fila; frequenza
più alta con Ordine basso e regno in difficoltà. Crisi con conseguenze fisiche (incendi che si propagano,
epidemie con letalità, razzie che rubano dai depositi).

### 2.17 Cronaca, ambizioni, salvataggi
- Cronaca per anno con categorie (regno, guerra, diplomazia, corte, popolo, economia, scoperta) e bilancio finale.
- Ambizioni (egemonia territoriale, tesoro, forza, prestigio, sapienza, dinastia) sostenute per un anno.
- Salvataggio JSON versionato (v5) con rifiuto delle versioni diverse → **in KD: migrazioni, non rifiuto**.

---

## 3. Sistemi da ELIMINARE

| Concetto legacy | Perché | Cosa lo sostituisce |
|---|---|---|
| Valle locale 128×128 come mondo a sé | Viola il mondo unico | La valle è un luogo della mappa continentale |
| Carta strategica come "seconda scena" | Viola il mondo unico | Zoom continuo sulla stessa mappa |
| Scena di battaglia separata | Viola il mondo unico | Battaglie sulla mappa con LOD visivo |
| Zone della valle da aprire con spedizioni (`Sped`, `ZONE`, `BAL_SPED`) | Esplorazione legacy | Nessun blocco artificiale: si costruisce dove si controlla il territorio |
| Spedizioni nelle terre di nessuno (`SpedTerre`, `BAL_SPEDT`) | Esplorazione legacy | Espansione fisica: coloni, insediamenti, eserciti |
| Pannello Esplorazione "i tre modi di allargarsi" | UI legacy | Nessun tasto "Esplora" |
| Campagna "Oltre il fiume" (`NODI`, `Campagna`, fazioni goblin/non-morti/nani/elfi/troll/teutonici) | Livello II fantasy | Guerre reali tra regni; briganti e ribelli come minacce interne |
| Sblocco unità tramite vittorie in campagna | Legato alla campagna | Requisiti data-driven (edifici, tecnologie, risorse, istituzioni, prestigio) |
| Requisito "vittorie in campagna" dell'armeria | Legato alla campagna | Requisiti di esperienza militare del regno e tecnologia |
| Seme visibile / nuova valle con seme / mappe alternative | Mappa fissa | Una mappa ufficiale; il caso agisce solo sulla storia |
| Obiettivi tutorial legati a spedizioni e goblin | Contenuto legacy | Obiettivi guida sul mondo unico |
| Sintesi audio WebAudio, icone canvas, ritratti a strati canvas | Tecnologia web | Asset Godot/Blender |

### Unità esplicitamente conservate
**Alabardieri, Balestrieri, Cavalieri, Capitano** restano nel gioco con le loro statistiche e ruoli.
Cambia solo lo sblocco (nuovi requisiti in `data/defs/units.json`):

| Unità | Sblocco Regno | Sblocco King's Domain (proposta iniziale, data-driven) |
|---|---|---|
| Alabardieri | vincere il Capobanda | Caserma + Fabbro + tecnologia *Armi in asta* |
| Balestrieri | vincere la Palude di Marcio | Campo di tiro + tecnologia *Balestre* + ferro disponibile |
| Cavalieri | vincere la Forra | Stalle + cavalli + tecnologia *Cavalleria pesante* + prestigio minimo + nobiltà non ostile |
| Capitano | vincere il Troll | Esperienza militare del regno (battaglie combattute) + personaggio generale disponibile |

---

## 4. Cosa NON era presente in Regno (nuovo in KD)
- Culture (Germanica, Ellenica, Asiatica, Latina, Slava, Araba) con statistiche fisse.
- Religioni (Cattolica, Ortodossa, Musulmana, Induista) con statistiche fisse, separate dalle culture.
- Spiriti Nazionali dinamici legati alla geografia (evoluzione delle *vocazioni* di Regno).
- Dinastie estese a tutti i regni (in Regno la corte esisteva solo per il giocatore; gli altri avevano `sovrano{nome, eta}`).
- Carattere del sovrano che guida le decisioni IA (in Regno l'IA leggeva l'*indole del regno*, non la persona).
- Fog of war militare.
- Logistica con strade fisiche, ponti e passi.
- Devastazione e trasformazione fisica permanente del territorio a scala continentale.
- Assedi e battaglie visibili sulla mappa.
- Crisi di lungo periodo (coalizioni, guerre civili, collassi).
- Specializzazioni tecnologiche esclusive.

---

## 5. Dipendenze fra sistemi (estratte dal comportamento di Regno)

```
Terreno ──► Estrazione ──► Depositi ──► Lavorazione ──► Cibo/Armi
   │             │              │                           │
   ▼             ▼              ▼                           ▼
Costruzione ◄── Materiali   Mercato (prezzi) ◄──────── Consumo/Leva
   │                                                        │
   ▼                                                        ▼
Popolazione (letti, cibo, servizi) ──► Felicità/Consenso ──► Nascite/Viandanti
   │                                         │
   ▼                                         ▼
Classi sociali ──► Poteri (favore/potere) ──► Legittimità / Ordine ──► Eventi/Crisi
   │                     │                         ▲
   ▼                     ▼                         │
Gettito/Salari      Vocazione ◄── registri delle azioni (leggi, guerre, costruzioni)
   │
   ▼
Esercito (reclutamento dai cittadini) ──► Armate ──► Guerre ──► Province ──► Rendite/Prestigio
                                                       ▲             │
Diplomazia ◄── Memoria IA (rancore/stima) ◄────────────┘             ▼
                                                              Cronaca / Ambizioni
Corte (tratti, eredi) ──► Legittimità, effetti economici, morale ──► Successione ──► Crisi
```

In Regno la geografia influenzava la produzione delle province e i costi di marcia, ma **non** la
personalità dei regni né le decisioni della corte: questo è il principale anello mancante che KD aggiunge.

---

## 6. Il tentativo precedente `Desktop/kings_domain`
Cartella esterna al progetto ufficiale (non modificata). È un progetto Godot 4.7 in **3D**
(Forward+, terreno a mesh, camera 3D, kit Blender di modelli .glb) scritto senza poter eseguire Godot.
- Architettura: **non riutilizzabile** (3D, 16 autoload monolitici, mappa generata a seme a runtime).
- Asset: nessun asset esportato presente.
- Informazioni utili recuperate: percorsi degli strumenti sul PC
  (Godot `C:\Users\ciabe\Downloads\Godot_v4.7.2-stable_win64.exe\`, Blender `C:\Program Files\Blender Foundation\Blender 5.2\`).

