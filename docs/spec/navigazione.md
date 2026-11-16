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
- **Sessione:** all'avvio il router controlla la sessione: senza sessione porta ad Accesso (A2), con sessione all'hub. Sblocco (A1) e primo avvio (A3, A7–A10) si collegano al router con la specifica dell'accesso.
- **Finanze:** barra Riepilogo · Movimenti · Analisi · Conti, con etichette sempre visibili (badge su Movimenti in arrivo). Ogni scheda ricorda il proprio stato (filtri, scorrimento): una pila di navigazione per scheda (`StatefulShellRoute.indexedStack`).
- **Tasto "+":** specifico per sezione; in Finanze apre il menu F1, da cui si apre F2.
- **Tasto indietro di Android:** chiude il foglio → chiude il dettaglio → dalla seconda, terza o quarta scheda torna alla prima (Riepilogo) → dalla prima torna all'hub → dall'hub esce dall'app. Indietro predittivo attivo.
- **Impostazioni:** si aprono dall'avatar dell'hub; l'indietro torna all'hub.
- **Link diretti** (notifiche, inviti, ritorno dal collegamento bancario): da definire. Ogni link apre la schermata con sotto la sua sezione, così l'indietro funziona.
- **Tablet:** barra laterale e layout dedicati da definire; finché non sono decisi, la navigazione è quella del telefono.
- **Percorsi** in inglese (codice), titoli in italiano (interfaccia). I parametri (`:…Id`) sono identificativi, mai dati leggibili.

## 3. Rotte

### Livello 0

| Codice | Schermata | Percorso | Si apre da |
|---|---|---|---|
| A1 | Sblocco | `/unlock` | avvio con sessione (in arrivo) |
| A2 | Accesso | `/sign-in` | avvio senza sessione; Esci (I2) |
| A3 | Primo accesso | `/welcome` | A2, al primo accesso |
| A7 | Crea o entra in una casa | `/household` | A3 |
| A8 | Crea casa | `/household/create` | A7 |
| A9 | Invita | `/household/invite` | A8; I4 |
| A10 | Entra con invito | `/household/join` | A7; link di invito (in arrivo) |
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

Totale: 31 schermate e 7 fogli.

## 4. Indice delle schermate (sviluppo)

`/dev/screens`: elenco di tutte le schermate e i fogli con codice e nome, per aprirli durante lo sviluppo; si raggiunge da un link nell'hub. È temporaneo: si toglie quando tutte le schermate sono costruite.

## 5. Da definire

- Sblocco: quando si chiede (all'apertura, dopo quanto tempo in background) e cosa succede senza blocco schermo.
- Primo avvio: ordine di A3, permesso di posizione e A7–A10, e loro collegamento al router.
- Link diretti e App Link.
- Tablet: barra laterale e layout dedicati.
- Badge di Movimenti.
