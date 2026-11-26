# Navigazione

Specifica tecnica della navigazione dell'app: livelli, regole, rotte e tasto indietro. Le schermate hanno il codice dell'inventario (A1–I10); i loro contenuti stanno nelle specifiche dei gruppi. Finché una schermata non è specificata e costruita, nell'app c'è un segnaposto con codice e nome.

## 1. Livelli

| Livello | Cosa | Barra in basso |
|---|---|---|
| 0 – globale | Sblocco, accesso, primo accesso, casa, hub, impostazioni | No |
| 1 – sezione | Le schede di una sezione (oggi solo Finanze), con in alto "‹ Finanze" che torna all'hub | Sì |
| 2 – dettaglio | Schermate a tutto schermo sopra la sezione, con la freccia indietro | Nascosta |
| 3 – foglio dal basso | Scelte rapide (categoria, ripartizione, filtri, menu del "+"): modali, non rotte | — |

## 2. Regole

- **Ingresso:** l'hub (B1) è sempre la schermata d'ingresso.
- **Avvio e primo avvio** (dettagli in [`accesso.md`](accesso.md)): un solo **stato dell'avvio** decide il primo passo mancante, in quest'ordine, all'avvio e a ogni cambio di stato (sessione o dati letti): nessuna sessione → Accesso (A2); informativa non letta nella versione attuale → Primo accesso (A3); nessuna casa → A7 (o A10 se c'è un invito in sospeso); posizione mai chiesta su questo dispositivo → Posizione (A11); altrimenti l'hub. Il router legge solo questo stato. Lo sblocco (A1) copre l'app dall'esterno del router, senza cambiare rotta.
  - **Passi attivi oggi:** sessione, informativa, casa e sblocco. Il passo della casa (dalla 4.6) apre A7, da cui A8; A9 e A10 restano segnaposto fino alla 4.7 (inviti). La posizione risulta sempre fatta finché non arriva la sua schermata (4.8): fino ad allora A11 resta un segnaposto raggiungibile.
  - **Attesa:** finché lo stato non è noto si vede la schermata d'avvio (`/start`, fuori dall'inventario) con il solo logo, senza testo: mai, nemmeno per un istante, una schermata sbagliata.
  - **Offline:** lo stato si legge da Supabase (proprio profilo, `user_settings`, membro attivo) e si salva sul dispositivo per account. Senza risposta (rete assente o nessuna risposta entro 8 secondi) o con un errore di Supabase si usa l'ultimo stato salvato. Senza stato salvato la schermata d'avvio mostra "Nessuna connessione. Controlla la rete e riprova." (o "Non è stato possibile caricare i dati. Riprova." se Supabase risponde con un errore) e il tasto "Riprova".
  - **Destinazione chiesta:** un link a una schermata interna resta valido dopo i passi: la schermata chiesta passa da un passo all'altro nel parametro `from` e si apre quando non manca più nulla, se è un percorso dell'app e non una schermata dei passi attivi (`/start`, A2, A3, e A7 con le sue sottorotte, `/household/…`); altrimenti l'hub. Le schermate dei passi non sono mai una destinazione: anche all'avvio a freddo un percorso `/household/…` passa dalla schermata d'avvio e diventa A7. Dopo "Esci" si dimentica: il nuovo accesso apre l'hub.
- **Finanze:** barra Riepilogo · Movimenti · Analisi · Conti, con etichette sempre visibili (badge su Movimenti in arrivo). Ogni scheda ricorda il proprio stato (filtri, scorrimento): una pila di navigazione per scheda (`StatefulShellRoute.indexedStack`).
- **Tasto "+":** specifico per sezione; in Finanze apre il menu F1, da cui si apre F2.
- **Tasto indietro di Android:** chiude il foglio → chiude il dettaglio → dalla seconda, terza o quarta scheda torna alla prima (Riepilogo) → dalla prima torna all'hub → dall'hub esce dall'app. Indietro predittivo attivo.
- **Impostazioni:** si aprono dall'avatar dell'hub; l'indietro torna all'hub.
- **Link diretti** (notifiche, inviti, ritorno dal collegamento bancario): App Link su Cloudflare Pages; il link di invito apre A10 con il codice compilato (anche dopo A2 e A3, se manca l'account). Gli altri link da definire. Ogni link apre la schermata con sotto la sua sezione, così l'indietro funziona.
- **Schermi larghi:** regole nella sezione 5.
- **Percorsi** in inglese (codice), titoli in italiano (interfaccia). I parametri (`:…Id`) sono identificativi, mai dati leggibili.

## 3. Rotte

### Livello 0

| Codice | Schermata | Percorso | Si apre da |
|---|---|---|---|
| A1 | Sblocco | `/unlock` | copre l'app all'avvio con sessione e al ritorno dopo 1 minuto; il percorso è solo l'anteprima dell'indice |
| A2 | Accesso | `/sign-in` | avvio senza sessione; Esci (I2) |
| A3 | Primo accesso | `/welcome` | A2, al primo accesso |
| A7 | Crea o entra in una casa | `/household` | A3 |
| A8 | Crea casa | `/household/create` | A7 |
| A9 | Invita | `/household/invite` | A8; I4 |
| A10 | Entra con invito | `/household/join` | A7; link di invito |
| A11 | Posizione | `/location` | ultimo passo del primo avvio, una volta per dispositivo |
| B1 | Hub | `/` | avvio |
| I1 | Impostazioni | `/settings` | avatar dell'hub |
| I2 | Account | `/settings/account` | I1 |
| I3 | Aspetto | `/settings/appearance` | I1 |
| I4 | Casa | `/settings/household` | I1 |
| I5 | Impostazioni Finanze | `/settings/finance` | I1 |
| I6 | Categorie | `/settings/finance/categories` | I5 |
| I7 | Tag | `/settings/finance/tags` | I5 |
| I8 | Rubrica persone esterne | `/settings/finance/people` | I5 |
| I9 | Sicurezza, notifiche, info | `/settings/security` | I1 |
| I10 | Hub | `/settings/hub` | I1 |

### Livello 1 — schede di Finanze

| Codice | Schermata | Percorso | Si apre da |
|---|---|---|---|
| C1 | Riepilogo | `/finance/summary` | card Finanze dell'hub; barra |
| D1 | Movimenti | `/finance/transactions` | barra |
| G1 | Analisi | `/finance/analytics` | barra |
| H1 | I tuoi conti | `/finance/accounts` | barra; saldo del Riepilogo |

### Livello 2 — dettagli

| Codice | Schermata | Percorso | Si apre da |
|---|---|---|---|
| C2 | Saldi | `/finance/summary/balances` | C1 (card del conguaglio) |
| C3 | Dettaglio persona | `/finance/summary/balances/people/:personId` | C2 |
| C4 | Salvadanai | `/finance/summary/savings` | C1 (card dei salvadanai) |
| E1 | Dettaglio transazione | `/finance/transactions/:transactionId` | D1 |
| F2 | Nuovo movimento | `/finance/new/:kind` (`cash-expense`, `income`, `transfer`) | F1 |
| G2 | Report | `/finance/analytics/reports` | G1 |
| H2 | Dettaglio conto | `/finance/accounts/:accountId` | H1 |
| H4 | Collega banca | `/finance/accounts/link` | H1 |
| H5 | Conto manuale | `/finance/accounts/new` | H1 |

`/finance/accounts/link` e `/finance/accounts/new` si dichiarano prima di `/finance/accounts/:accountId`.

### Livello 3 — fogli dal basso

| Codice | Foglio | Si apre da |
|---|---|---|
| D2 | Filtri | D1 |
| E2 | Scelta categoria | E1; F2 |
| E3 | Ripartizione | E1; F2 |
| E4 | Rimborsabile da terzi | E1 |
| E5 | Tipo di movimento | E1 |
| F1 | Menu "+" | tasto "+" di C1 e D1 |
| H3 | Riconciliazione contanti | H2 |

Totale: 32 schermate e 7 fogli.

## 4. Indice delle schermate e catalogo dei componenti (sviluppo)

`/dev/screens`: elenco di tutte le schermate e i fogli con codice e nome, per aprirli durante lo sviluppo; si raggiunge da un link nell'hub. È temporaneo: si toglie quando tutte le schermate sono costruite.

`/dev/components`: catalogo dei componenti della specifica dello stile (sezione 8), con dati inventati; si apre dall'indice delle schermate e l'indietro torna lì. In alto ha la scelta della palette e del tema, che cambiano tutta l'app, e il testo al 100%, 130% e 200%. Sta fuori dall'inventario delle schermate (codice `DEV`) ed è temporaneo come l'indice.

## 5. Schermi larghi (tablet)

Una sola app adattiva, regolata dalla **larghezza della finestra**, non dal dispositivo: da Android 16 (SDK 36), sui dispositivi con lato corto ≥ 600 dp, i blocchi di orientamento e ridimensionamento sono ignorati, quindi un tablet può mostrare l'app in una finestra stretta (schermo diviso, finestra mobile).

1. **Classi di larghezza** Material 3: compatta < 600 dp (layout del telefono), media 600–839 dp, estesa ≥ 840 dp. Si calcolano dalla larghezza della finestra, mai dal dispositivo né dal display, in un solo punto del codice.
2. **Barra laterale:** da 600 dp la barra in basso di Finanze diventa un `NavigationRail` con le stesse quattro schede ed etichette sempre visibili; il "+" sta in cima (nel `leading`), solo su Riepilogo e Movimenti come in basso: nelle altre schede il suo spazio resta vuoto. Il badge su Movimenti arriva con l'iterazione 5, sulle due barre. "‹ Finanze" resta in alto. Stessa `StatefulShellRoute` e stesso tasto indietro: cambia solo il guscio della sezione. Al cambio di classe (finestra ridimensionata, rotazione, schermo diviso) la scheda scelta e la sua pila non si perdono.
3. **Tutte le altre schermate:** layout del telefono centrato, larghezza massima circa 640 dp.
4. **Layout dedicati** solo per l'hub (B1) e per Movimenti + dettaglio dalla classe estesa (elenco a sinistra, E1 a destra). Nel doppio pannello `/finance/transactions/:transactionId` si apre nel pannello destro con la barra laterale visibile: la rotta di E1 passa dentro la scheda Movimenti e, nella classe compatta, la barra si nasconde sui dettagli. Un altro layout dedicato solo con una motivazione nella specifica del gruppo.
5. **Fogli dal basso:** restano fogli, larghezza massima 640 dp, scritta nel tema.
6. **Orientamento:** telefono solo in verticale; tablet in entrambi gli orientamenti; lo stato si conserva quando la finestra cambia. È un telefono il dispositivo con il lato corto del **display** (non della finestra) sotto i 600 dp: lo decide l'app all'avvio e a ogni cambio del display (pieghevole aperto o chiuso). Nessun blocco nel manifest, che fermerebbe anche i tablet fino ad Android 15.
7. **Golden test** in formato tablet solo per la barra laterale, l'hub e Movimenti + dettaglio.

## 6. Da definire

- Badge di Movimenti.
