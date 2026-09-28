# KING'S DOMAIN — GAME DESIGN MAP

> *Non stiamo costruendo un gioco in cui controlli un regno.
> Stiamo costruendo un gioco in cui vedi un regno nascere.*

> **REBIRTH (28/09/2026).** Il pilastro 1 («un solo mondo continuo, nessun cambio di scena») e §4 («zoom continuo»)
> **non valgono più**: il gioco ha due scale distinte — la **mappa locale del dominio** (la valle della patria, dove si
> fonda e si costruisce) e la **mappa globale strategica** (il continente, dove si esplora e si espande) — con una sola
> simulazione. Il resto di questo documento resta il riferimento dei sistemi finché il Rebirth non lo aggiorna fase per
> fase. Vedi `KINGSDOMAIN_REBIRTH_AUDIT.md` e `KINGSDOMAIN_REBIRTH_REPORT.md`.

Documento vivo. Descrive **cosa** è il gioco e **come i sistemi si toccano**.
Il *come si costruisce* sta in `TECHNICAL_ARCHITECTURE.md`; l'eredità di Regno in `LEGACY_SYSTEM_AUDIT.md`.

---

## 1. Pilastri (in ordine di priorità)

1. **Un solo mondo continuo.** Nessun cambio di scena per villaggio, carta, battaglia o assedio.
2. **Geografia ↔ Regno ↔ Sovrano.** Il territorio crea possibilità e problemi, il sovrano sceglie,
   il regno trasforma il territorio, e il territorio trasformato apre nuove scelte.
3. **Sistemi reali e interconnessi.** Niente pulsanti che "fanno vincere": ogni esito è simulato.
4. **Dal re con sei abitanti al grande regno**, sulla stessa mappa, con continuità fisica.
5. **Mappa viva e trasformabile**, che conserva la storia della partita.
6. **Rigiocabilità:** mappa fissa, storia non fissa.
7. IA credibile · 8. guerra integrata nella mappa · 9. prestazioni · 10. grafica semplice e coerente · 11. rifinitura.

**Direzione artistica (17/09/2026):** *una grande mappa medievale illustrata che prende vita.*
Riferimento principale: il mockup `ChatGPT Image 14 set 2026, 00_02_00.png` (mappa + HUD), da interpretare in versione
ancora un po' più semplice. Grafica semi-realistica, illustrata, painterly, elegante e leggibile; prevalentemente 2D con
profondità 2.5D molto leggera. **Realismo nell'atmosfera, semplificazione nel rendering.**
- Montagne: catene riconoscibili fatte di sprite prerenderizzati con ombre incorporate, poche varianti riutilizzate.
- Foreste: masse da lontano, gruppi di alberi a zoom medio, qualche albero singolo da vicino.
- Fiumi e laghi evidenti; strade visibili ma discrete; città e castelli identificabili (sprite modulari, silhouette urbana);
  province leggibili con colori non troppo accesi.
- Abitanti e soldati molto più semplici di terreno ed edifici: pochi frame (idle, movimento, lavoro, combattimento),
  distinti per silhouette, colore, equipaggiamento, dimensione e formazione.
- UI in legno, pergamena e oro, ordinata; la mappa occupa la maggior parte dello schermo.
- Regole di scelta: leggibilità > realismo; sprite efficace > modello complesso; prestazioni > dettaglio;
  2D illustrato convincente > 2.5D pesante.

Domanda di controllo per ogni funzione:
*«Aiuta il giocatore a percepire la nascita, la crescita o la trasformazione fisica e politica del regno?»*

---

## 2. Il ciclo centrale

```
          ┌──────────────────────────────────────────────────────────┐
          │                                                          │
   GEOGRAFIA ──► possibilità e problemi ──► SOVRANO decide ──► REGNO agisce
 (terreno, fiumi,   (cibo, ferro, passi,     (carattere, fazioni,   (costruisce, disbosca,
  montagne, risorse, vicini, difendibilità)   spiriti, legittimità)   strade, guerre, leggi)
          ▲                                                          │
          └─────────────── il territorio è cambiato ◄────────────────┘
```

Esempio canonico — un regno montano ricco di ferro:
- sovrano **militarista** → miniere → fabbri → fanteria pesante → fortezze sui passi;
- sovrano **mercantile** → miniere → strade → mercati → esportazione del ferro ai vicini di pianura;
- sovrano **prudente** → passi fortificati → riserve di grano → difesa e alleanze.

Lo stesso luogo produce storie diverse; e quando il sovrano muore, la direzione può ribaltarsi.

---

## 3. Il mondo

### 3.1 Struttura concettuale
```
World (mappa ufficiale, fissa)
 ├ Terrain        altitudine, biomi, fiumi, laghi, coste, foreste, rocce, depositi (+ modifiche salvate)
 ├ Provinces      ~400 forme irregolari, dati regionali
 ├ Kingdoms       proprietari politici delle province
 ├ Settlements    insediamenti fisici dentro le province
 ├ Buildings      edifici fisici con posizione e impronta
 ├ Population     individui simulati che abitano e lavorano negli insediamenti
 ├ Resources      scorte, depositi naturali, rese
 ├ Roads          strade e ponti fisici
 ├ Armies         eserciti fisici che marciano
 ├ Characters     sovrani, eredi, consorti, generali, dinastie
 ├ Battles/Sieges combattimenti che avvengono sul posto
 ├ Diplomacy      relazioni, patti, guerre
 └ Environment    stagioni, ricrescita, devastazione
```

### 3.2 Il continente
- **Una sola massa terrestre**, nessuna isola giocabile, ogni regione raggiungibile via terra.
- Coste articolate (golfi, penisole, fiordi a nord), grandi fiumi navigabili solo come ostacolo/confine,
  laghi, catene montuose con **passi**, altopiani, colline, valli fertili, paludi, steppe e zone aride a sud-est,
  foreste di conifere a nord, foreste miste al centro, macchia mediterranea a sud.
- Geografia **originale**, non l'Europa, ma con una logica climatica credibile (latitudine, venti, ombra pluviometrica).
- Riferimento di stile: mockup "Regno" del 14/09/2026 (mappa illustrata con foreste dense, montagne
  in rilievo, fiumi ben visibili, colori politici velati sopra la geografia).

### 3.3 Regioni culturali (proposta iniziale della mappa ufficiale)
| Macro-area | Cultura prevalente | Religione prevalente | Carattere geografico |
|---|---|---|---|
| Nord-ovest e centro | Germanica | Cattolica | foreste miste, colline, grandi fiumi |
| Sud-ovest | Latina | Cattolica | pianure fertili, coste, colline mediterranee |
| Nord-est | Slava | Ortodossa | pianure, foreste di conifere, paludi |
| Sud-est (penisole, isole di costa non giocabili escluse) | Ellenica | Ortodossa | coste frastagliate, montagne, uliveti |
| Sud | Araba | Musulmana | altopiani aridi, oasi fluviali, steppe |
| Estremo est | Asiatica | Induista | grandi valli fluviali, catena montuosa di confine |

Le frontiere culturali e religiose **non coincidono** sempre: esistono province latine ortodosse,
province slave cattoliche, minoranze arabe in terre elleniche, ecc.

### 3.4 Province
- Forme irregolari, nessuna griglia visibile. Numero previsto ~400 (l'architettura non ha limiti fissi).
- Confini: a volte seguono fiumi, creste, laghi, valli; spesso sono **politici** e attraversano pianure.
- Dati: proprietario, controllo (occupazione), cultura, religione, popolazione, fertilità, sviluppo,
  risorse (depositi e rese), bioma dominante, terreno, infrastrutture, strade, fortificazioni,
  insediamenti, ordine locale, fedeltà, devastazione, importanza economica, importanza strategica
  (passi, guadi, ponti, coste, incroci).
- Le province non sono equivalenti: la geografia decide fertilità, legname, pietra, ferro, cavalli,
  costi infrastrutturali, vie naturali e valore strategico.

---

## 4. Zoom continuo e livelli di dettaglio

Livelli **visivi** della stessa mappa (non modalità di gioco). Le soglie sono dati tarabili.

| Livello | Cosa si vede | Cosa si fa |
|---|---|---|
| **Continente** | regni colorati, confini di regno, capitali, grandi eserciti come stendardi, nomi dei regni | leggere il mondo, diplomazia, guerre |
| **Regno / Strategico** | province, confini di provincia, strade principali, castelli/villaggi/città come simboli, fiumi, foreste e montagne illustrate, eserciti con numero | muovere eserciti, map mode, gestire province |
| **Provincia** | insediamenti come gruppi di edifici, campi, strade, ponti, boschi, cave | pianificare insediamenti, strade, fortificazioni |
| **Locale (città/villaggio)** | case, fattorie, miniere, segherie, mura, torri, alberi singoli, rocce, abitanti | costruire, assegnare lavori, trasformare il terreno |
| **Ravvicinato** | abitanti e lavoratori distinguibili, soldati, cavalli, formazioni, macchine d'assedio | osservare, seguire battaglie e assedi |

Transizioni morbide (dissolvenze) tra rappresentazioni; mai "popping" di una scena intera.

---

## 5. Inizio della partita

### 5.1 Stato iniziale del giocatore
- **1 Re** (personaggio con età, tratti, dinastia nascente) + **6 abitanti** con nome ed età.
- Un **mastio di legno** (torre/palizzata: casa del re e primo deposito), un riparo per gli abitanti,
  un piccolo orto.
- Scorte iniziali (da bilanciare, base Regno): legno 150, pietra 90, grano 50, pane 90, oro 200.
- Un piccolo territorio: **una provincia di frontiera non rivendicata**, con bosco, rocce, un fiume o
  torrente, terra fertile e un guado.
- Ambiente circostante in gran parte **naturale**.

### 5.2 Il mondo attorno (decisione D1, vedi §17)
- Alcuni **regni già formati** (4–6, da 5 a 15 province), diverse **signorie minori** (8–12, 1–4 province),
  molte province **libere** abitate da villaggi senza corona.
- Il giocatore parte in una **valle di frontiera** relativamente riparata, con **periodo di grazia**
  (3 anni base) prima che i vicini lo considerino un bersaglio, e con preavviso delle minacce.

### 5.3 Progressione emergente (nessun pulsante "sali di livello")
```
insediamento (7) → villaggio (~30) → borgo (~120) → signoria (più insediamenti/province)
→ regno (titolo e istituzioni) → grande regno / nazione
```
I nomi sono **etichette derivate** da popolazione, insediamenti, province e istituzioni.
Le prime case non spariscono: vengono ampliate, sostituite dal giocatore o inglobate nella città.
Il titolo di "Regno" è un traguardo politico (legittimità, prestigio, province, corte) che sblocca istituzioni.

---

## 6. Territorio: costruzione e trasformazione

### 6.1 Costruzione fisica
1. Il giocatore sceglie un edificio (menu per categorie: popolazione, materie prime, trasformazione,
   depositi e mercato, armi e difesa, strade/ponti/mura).
2. Sceglie posizione e orientamento sulla mappa.
3. Il gioco verifica terreno, pendenza, ostacoli (alberi, rocce), accesso, controllo territoriale, materiali.
4. Nasce un **cantiere**: i materiali vengono portati, i costruttori lavorano, l'edificio cresce a vista.
5. Gli abitanti iniziano a usarlo.

### 6.2 Trasformare invece di esplorare
- Alberi → abbattuti dai boscaioli → legname → terreno libero (ceppi che ricrescono se non si costruisce).
- Rocce e affioramenti → cavatori → pietra → spazio edificabile / pietraia.
- Vene di ferro → miniere → ferro → si esauriscono; i depositi profondi durano molto di più.
- Paludi → bonifica (fase avanzata) → terra fertile.
- Campi arati, prati, strade battute, ponti, mura: tutto modifica il terreno ed è **salvato**.
- Nessun pulsante "Esplora".

### 6.3 Crescita organica degli insediamenti
- Il giocatore piazza gli edifici chiave nella propria capitale e dove vuole.
- Per regni grandi, ogni insediamento può avere una **politica di sviluppo** (crescita libera,
  agricola, mineraria, commerciale, militare) che il `ConstructionPlanner` applica automaticamente,
  piazzando edifici fisici coerenti con le stesse regole del giocatore.
- L'IA dei regni usa lo stesso sistema: le città degli altri crescono fisicamente allo stesso modo.

---

## 7. Edifici

Categorie e tipi iniziali (dati in `data/defs/buildings.json`):

| Categoria | Edifici |
|---|---|
| Popolazione | mastio/residenza, casa (capanna → casa → casa in pietra), pozzo, chiesa/pieve, taverna |
| Materie prime | taglialegna, cava, miniera, fattoria (campi), pascolo/allevamento, pesca |
| Trasformazione | forno, mulino (fase avanzata), fabbro, segheria, conceria (fase avanzata) |
| Depositi e mercato | magazzino, granaio, mercato |
| Armi e difesa | caserma, campo di tiro, stalle, torre di guardia, mura, cancello, castello |
| Infrastrutture | strada (sterrata → lastricata), ponte (legno → pietra), molo fluviale |
| Istituzioni | corte/palazzo, cancelleria, studio/università, cattedrale (sbloccano leggi e tecnologie) |

Ogni edificio: impronta, costo, tempo, posti di lavoro, input/output, raggio di servizio, requisiti
(terreno, vicinanza a risorse, tecnologia, istituzioni), livelli di miglioramento, danneggiabilità,
effetti politici (una chiesa piace al clero, una caserma all'esercito, un mercato ai mercanti).

---

## 8. Popolazione

- Gli abitanti sono **individui** (nome, età, sesso, famiglia, casa, mestiere, salute, fame, umore, classe, cultura, religione).
- Il giocatore **non** comanda individui: decide edifici, priorità, numero di lavoratori, quota di costruttori,
  razioni, tasse, leva.
- La popolazione esegue: assegnazione automatica ai posti vicini a casa, trasporti, costruzione, pasti, riposo.
- Visibilità: vicino alla camera gli abitanti escono di casa, camminano sulle strade, lavorano e tornano;
  lontano la stessa economia è calcolata in forma aggregata.
- Crescita: nascite (tasso), viandanti, migrazioni interne (verso insediamenti prosperi), coloni da province conquistate.
- Classi sociali (contadini, artigiani, mercanti, nobili, clero, soldati) derivate dai mestieri reali e dagli insediamenti.
- Morti: fame, vecchiaia, malattia, guerra, incendi.

---

## 9. Economia regionale

- Catene: estrazione → depositi → lavorazione → consumo/leva/commercio.
- Scorte **locali per insediamento**: il ferro di una miniera lontana deve viaggiare lungo le strade per arrivare al fabbro della capitale.
- Trasporto a **flussi** lungo la rete stradale: più strada/ponte = più capacità e meno tempo; carovane visibili a zoom medio.
- Mercati regionali con prezzi da scarsità; commercio fra regni con trattati, dazi, rotte.
- Tesoro della corona: tasse (per classe e provincia), dazi, rendite, tributi; spese: salari, soldati, mantenimento di editti/leggi/edifici, debiti.
- **Controllo amministrativo**: più province = più dispersione, compensata da strade, cancelleria, istituzioni.
- La guerra non è sempre conveniente: costi, devastazione, campi abbandonati, debiti.

---

## 10. Identità del regno

```
STATO DEL REGNO = cultura (fissa) + religione (fissa) + geografia + spiriti nazionali (dinamici)
                + sovrano (persona) + governo + leggi/editti + economia + eventi temporanei
```
Nel codice ogni termine è una **fonte di modificatori** separata e ispezionabile (vedi TECHNICAL_ARCHITECTURE §8).

### 10.1 Culture (statistiche fisse, archetipi ludici, nessuna superiore)
| Cultura | Archetipo | Bonus (bozza) | Malus (bozza) |
|---|---|---|---|
| Germanica | foreste, fanteria, consuetudine | legname +10%, difesa fanteria +5% | commercio −5% |
| Ellenica | città, mare, sapere | ricerca +10%, prestigio da edifici +10% | leva −5% |
| Asiatica | amministrazione, grandi valli | controllo amministrativo +5%, resa agricola irrigua +8% | costo leggi +10% |
| Latina | diritto, città, strade | costo strade −15%, gettito +5% | morale in guerre lunghe −5% |
| Slava | resistenza, pianure, cavalli | logoramento invernale −25%, resa pascoli +10% | sviluppo urbano −5% |
| Araba | commercio, irrigazione, cavalleria leggera | commercio +10%, resa terre aride +15% | costo fortificazioni +10% |

### 10.2 Religioni (statistiche fisse, separate dalla cultura)
| Religione | Bonus (bozza) | Malus (bozza) |
|---|---|---|
| Cattolica | legittimità da clero +, costo chiese −10% | tolleranza −, decima più cara politicamente |
| Ortodossa | stabilità +5, legame corona-chiesa | riforme amministrative +10% costo |
| Musulmana | commercio +5%, tolleranza di base + | leggi sul credito limitate |
| Induista | ordine sociale +, crescita pop +5% | mobilità sociale −, costo leva +5% |

Tutti i valori sono **bozze** da bilanciare in dati; evitare stereotipi caricaturali.

### 10.3 Spiriti Nazionali (dinamici)
- Ogni regno ne ha 2–4 fin dall'inizio, derivati da geografia, cultura, religione, risorse, storia iniziale.
- Evolvono da **registri di azioni** (eredità diretta delle *vocazioni* di Regno) e da condizioni sul mondo:
  guerre combattute, leggi promulgate, strade costruite, fortezze, commercio, crisi, istituzioni, trasformazioni geografiche.
- Possono migliorare, peggiorare, ramificarsi, essere sostituiti, scomparire.
- Esempi di catene:
  - *Popolo di Frontiera* → **Marche Fortificate** (torri e mura sul confine, guerre difensive vinte) oppure **Frontiera Pacificata** (patti, commercio, nessuna guerra per 20 anni).
  - *Montanari del Ferro* → **Fucine del Regno** (fabbri, armi) / **Via del Ferro** (strade, esportazione).
  - *Granaio della Pianura* → **Terra dei Mercati** / **Carestia Ricordata** (dopo una carestia grave: scorte obbligatorie).
  - *Signori dei Guadi* → **Città dei Ponti** (ponti in pietra, pedaggi).

---

## 11. Sovrani, dinastie, successione

- Ogni regno ha un **sovrano-persona**: nome, età, salute, dinastia, 2–4 tratti, competenze (governo, guerra, diplomazia, intrigo), ambizione personale.
- Tratti (unione Regno + prompt): ambizioso, prudente, bellicoso, diplomatico, mercantile, austero, generoso,
  autoritario, riformatore, tradizionalista, pragmatico, sospettoso, popolare, arrogante, giusto, pio, crudele,
  saggio, severo, gaudente, malaticcio, robusto, avaro, guerriero.
- I tratti hanno **due facce**: effetti numerici modesti **e pesi decisionali** per l'IA (utility weights) e
  reazioni delle fazioni (un sovrano pio piace al clero, uno arrogante irrita la nobiltà).
- Famiglia: consorte, figli, fratelli, cugini; matrimoni dinastici; educazione degli eredi.
- Successione: regole di legge (primogenitura, elettiva, ecc. — fase avanzata); crisi quando l'erede è minorenne,
  assente o contestato; **pretendenti** sostenuti da fazioni; guerre di successione.
- Il cambio di sovrano può cambiare radicalmente la direzione del regno.

---

## 12. Fazioni interne

Nobiltà, Popolo, Mercanti, Esercito, Clero (base: i cinque poteri di Regno).
- Influenza (dal peso sociale e istituzionale), soddisfazione (favore), richieste, interessi, rapporto col sovrano,
  rapporto con leggi e politiche, rivalità.
- Comportamenti: sostegno, doni, richieste concrete (accetta/compromesso/rifiuta), proteste, crisi
  (congiure, tumulti, interdetti, serrate, ammutinamenti), appoggio a pretendenti, rivolte.

---

## 13. Governo, corte, leggi, editti

- Misure della corona: **Prestigio, Legittimità, Ordine (Stabilità), Fiducia (Consenso)**.
- Forma dello Stato (asse assolutismo ↔ rappresentanza, Corona, Assemblea, Amministrazione) con riforme a passi.
- Corte e **consiglieri** (cancelliere, maresciallo, tesoriere, cappellano, ciambellano): personaggi con competenze che
  potenziano ambiti e hanno lealtà e fazione.
- **Leggi** permanenti a gruppi esclusivi; **editti** revocabili; ogni scelta ha vincitori e perdenti politici.
- Istituzioni fisiche (palazzo, cancelleria, università, cattedrale) sbloccano leggi e riforme.

---

## 14. Militare

### 14.1 Unità
Fanti, arcieri, lancieri, picchieri, **alabardieri**, **balestrieri**, cavalleria leggera, **cavalieri**, **capitano**,
macchine d'assedio (ariete, torre d'assedio, trabucco). Requisiti data-driven (edifici, tecnologie, risorse, cavalli,
istituzioni, prestigio, esperienza).

### 14.2 Eserciti sulla mappa
- Reclutati da **persone reali** degli insediamenti (chi prende la lancia non semina).
- Marciano fisicamente lungo strade e terreno; velocità da strade, terreno, stagione, dimensione, generale.
- Rifornimenti: depositi, territorio amico, foraggiamento (devasta), linee di rifornimento semplici.
- LOD: lontano stendardo con numero; medio blocchi di formazione; vicino soldati distinguibili.

### 14.3 Battaglie sulla mappa
- Quando due eserciti ostili si incontrano **combattono dove sono**.
- Regole tattiche di Regno (reggimenti, formazioni, contrasti, fianchi, cariche, morale, rotta) applicate al terreno reale:
  fiumi e guadi, ponti, colline, boschi, paludi, passi, fortificazioni.
- Lontano si vede l'esito; zoomando si vedono formazioni, tiri, cariche, rotte.
- Il giocatore può dare ordini di alto livello ai reggimenti (opzionale) senza fermare il mondo.

### 14.4 Assedi e conquista
- Assedi visibili: mura, porte, torri, accampamento, macchine, difensori.
- Blocco (fame) o assalto (perdite). Mura danneggiate restano danneggiate finché non riparate.
- Conquista: la provincia cambia proprietario **senza reset** (edifici, strade, popolazione, cultura, religione restano;
  devastazione registrata).

### 14.5 Conseguenze
Morti, feriti, veterani, devastazione, campi abbandonati, edifici e mura danneggiati, debiti e tasse, malcontento,
migrazioni, crisi politiche, stanchezza di guerra. Vincere può indebolire.

### 14.6 Fog of war
Geografia e posizione dei regni noti. Eserciti nemici visibili solo entro raggio di visione di province proprie,
eserciti, torri/castelli, alleati e diplomazia (ambasciatori). Informazione vecchia mostrata come "ultima posizione nota".

---

## 15. IA dei regni

Decisioni da: regno + geografia + cultura + religione + spiriti + **carattere del sovrano** + fazioni + economia +
situazione militare + diplomazia + storia recente (memoria di rancore/stima di Regno).

Struttura: `StrategicEvaluator` (valutazione) → planner specializzati (`EconomicPlanner`, `ConstructionPlanner`,
`MilitaryPlanner`, `DiplomaticPlanner`, `PoliticalPlanner`) → azioni con **utility scoring** contestuale →
esecuzione tramite gli stessi comandi del giocatore. Scopi a medio termine (espansione, vendetta, egemonia,
ricchezza, consolidamento, sopravvivenza) ereditati da Regno, ora scelti anche in base alla persona che regna.

---

## 16. Eventi, crisi, tecnologia, cronaca, obiettivi

- **Eventi sistemici** data-driven: condizioni sullo stato, peso, cooldown, opzioni, effetti, catene.
  Catene tipiche: poco grano → prezzi → malcontento → migrazione → rivolte; ricchezza urbana → mercanti potenti → richieste;
  generale vittorioso → prestigio → influenza militare; guerra lunga → debito → tasse → opposizione.
- **Crisi di lungo periodo** condizionali: guerra dinastica, successione, carestia, epidemia, grande rivolta, coalizione,
  invasione, collasso di un regno, guerra civile, crisi economica, tensione religiosa, disgregazione.
- **Tecnologia e specializzazione**: rami con **scelte esclusive** (esercito professionale vs grandi leve; cavalleria vs fanteria
  pesante; agricoltura vs commercio; centralizzazione vs autonomia; fortificazioni vs mobilità).
- **Cronaca**: fondazioni, incoronazioni, morti, guerre, battaglie, conquiste, rivolte, crisi, alleanze, carestie, riforme, cambi dinastici;
  consultabile in partita e come racconto finale.
- **Obiettivi di campagna** liberi: espansione, unificazione regionale, grande economia, potenza commerciale, dinastia prestigiosa,
  capitale monumentale, predominio militare, sopravvivenza, stabilità, sviluppo territoriale (eredi delle *Ambizioni* di Regno).

---

## 17. Decisioni di design (confermate il 17/09/2026)

Proposte come default e confermate dall'autore. Restano dati/configurazione, modificabili senza toccare il codice:

| # | Decisione | Default scelto | Alternativa |
|---|---|---|---|
| D1 | Stato iniziale degli altri regni | Mondo misto: alcuni regni formati, signorie minori, molte terre libere | Tutti partono da un singolo insediamento come il giocatore |
| D2 | Luogo di partenza | Una valle di frontiera designata (latina/cattolica) | Scelta fra più valli di partenza con culture diverse |
| D3 | Scala del tempo | 1 giorno ≈ 4 s a velocità 1 ("Lenta"; fino a 0,05 s alla massima), anno di 360 giorni, età realistica | Anno compresso come in Regno |
| D4 | Lingua | Interfaccia in italiano, chiavi pronte per localizzazione | — |
| D5 | Comando in battaglia | Il giocatore può dare ordini ai reggimenti sulla mappa senza pausa forzata | Solo ordini strategici |
| D6 | Anno di inizio | 1230 (come Regno) | Datazione di fantasia |

---

## 18. Matrice delle interazioni (chi legge chi)

| ↓ influenza → | Terreno | Prov. | Econ. | Pop. | Fazioni | Legitt./Ordine | Spiriti | Militare | Diplom. | IA |
|---|---|---|---|---|---|---|---|---|---|---|
| **Geografia/Terreno** | — | fertilità, risorse, forma | rese, costi | dove vivere | — | — | spiriti iniziali | difesa, marcia | vicini | valutazione |
| **Province** | — | — | rendite, controllo | popolazione | nobiltà (terre) | prestigio | registri | leva, fortezze | rivendicazioni | bersagli |
| **Economia** | disbosco, campi | sviluppo | — | cibo, lavoro | mercanti | ordine (fame) | registri commercio | armi, paga | trattati | piani |
| **Popolazione** | uso del suolo | crescita | forza lavoro | — | popolo/classi | consenso | — | reclute | — | forza |
| **Sovrano/Corte** | — | — | tratti | umore | favore | legittimità | registri | morale | opinione | **pesi decisionali** |
| **Leggi/Editti** | — | calma | gettito, costi | nascite | scosse | ordine | registri | costo leva | — | piani politici |
| **Fazioni** | — | secessioni | serrate | tumulti | — | legittimità, ordine | — | ammutinamenti | pretendenti | vincoli |
| **Spiriti** | — | — | modificatori | — | pesi | — | — | modificatori | — | pesi |
| **Guerra** | devastazione | conquista | costi, debito | morti | scosse | turbolenza | registri armi | — | rancore | scopi |
| **Eventi/Crisi** | incendi, carestie | rivolte | shock | epidemie | richieste | shock | trasformazioni | razzie | coalizioni | reazioni |

