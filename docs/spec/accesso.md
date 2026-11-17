# Accesso e primo avvio

Specifica delle schermate A1, A2, A3, A7–A11: accesso con Google, sblocco, primo accesso, creazione della casa, inviti, posizione e primo avvio di Finanze. Rotte in [`navigazione.md`](navigazione.md), stile e componenti in [`stile.md`](stile.md). Esempi inventati.

## 1. Flusso

All'avvio e a ogni cambio di stato il router controlla, in quest'ordine:

| # | Condizione | Schermata |
|---|---|---|
| 1 | Nessuna sessione | A2 Accesso |
| 2 | Informativa privacy non letta (o cambiata di versione) | A3 Primo accesso |
| 3 | Nessuna casa | A7 → A8 → A9; A10 se c'è un invito in sospeso |
| 4 | Posizione mai chiesta su questo dispositivo | A11 Posizione |
| 5 | Riapertura con una sessione salvata | A1 Sblocco |
| 6 | Altrimenti | Hub |

- Lo sblocco non si chiede subito dopo l'accesso con Google.
- **Secondo dispositivo dello stesso account:** A2 → A11 → hub; il dispositivo si registra sull'account.
- "Posizione già chiesta" si salva solo sul dispositivo, mai sul server.
- Nessuna presentazione iniziale a schede.
- **Schermi larghi:** layout del telefono centrato (vedi `navigazione.md`, sezione 5).
- Le schermate sono uguali con uno, due o più membri; cambiano solo l'elenco degli inviti (A9) e l'anteprima della casa (A10).

## 2. A1 — Sblocco

- Logo, nome dell'app, richiesta di sistema con biometria o credenziale del dispositivo (PIN, sequenza, password) tramite `local_auth`; tasto "Sblocca" per riprovare; "Esci dall'account" (con conferma, poi A2).
- **Quando:** sempre all'avvio a freddo con una sessione salvata; al ritorno dal background dopo **1 minuto** (predefinito; scelte nelle impostazioni: subito, 1 minuto, 5 minuti).
- **Dispositivo senza blocco schermo:** A1 non compare, l'app funziona e l'hub mostra un avviso fisso "Proteggi Home-made: attiva il blocco schermo", con il tasto che apre le impostazioni di sicurezza del sistema.
- Sblocco annullato: resta su A1. Sessione scaduta: A2 con il messaggio di sessione scaduta.

## 3. A2 — Accesso

- Logo, "Home-made", la frase "Conti, spese e conguagli di casa in un posto solo.", tasto "Continua con Google" e sotto il tasto "Accedi o registrati con il tuo account Google.". Unico metodo di accesso e registrazione.
- Durante l'accesso il tasto mostra un indicatore ed è disattivato.

| Caso | Messaggio |
|---|---|
| Accesso annullato dall'utente | nessuno |
| Senza rete | "Nessuna connessione. Controlla la rete e riprova." |
| Nessun account Google sul dispositivo | "Aggiungi un account Google nelle impostazioni di Android e riprova." |
| Qualunque altro errore (anche di configurazione, solo nel log) | "Accesso non riuscito. Riprova." |
| Arrivo per sessione scaduta | "La sessione è scaduta: accedi di nuovo." |

**Da verificare:** quale codice restituisce `google_sign_in` quando sul dispositivo non c'è un account Google.

## 4. A3 — Primo accesso

- Foto dell'account Google (nessun caricamento; se manca, le iniziali), **nome** preso da Google e modificabile (obbligatorio), casella **"Ho letto l'informativa privacy"** con il link all'informativa, tasto "Continua" (attivo con nome e casella).
- **"Esci dall'account"** nel menu della barra in alto, per chi ha scelto l'account Google sbagliato (con conferma, poi A2).
- Sul profilo si salvano nome visualizzato, versione dell'informativa e data di presa visione. Con una nuova versione dell'informativa A3 ricompare con la sola casella.
- La casella registra la presa visione dell'informativa, non un consenso.

## 5. A7 — Crea o entra in una casa

- Due scelte con una riga di spiegazione: "Crea una casa" → A8; "Ho un invito" → A10.
- Con un invito in sospeso A7 si salta.
- **"Esci dall'account"** nel menu della barra in alto, come in A3.

## 6. A8 — Crea casa

- **Nome della casa:** obbligatorio, senza valore predefinito.
- **Data di inizio:** predefinita il primo giorno del mese in corso, modificabile; ammessa da 90 giorni prima di oggi a 12 mesi dopo. Testo sotto il campo: "L'app considera solo i movimenti da questa data. Le banche di solito restituiscono circa tre mesi di movimenti: collegale subito dopo."
- **Quote predefinite:** non si chiedono (un solo membro).
- **Contanti:** se la data di inizio è il giorno stesso, campo facoltativo "Quanti contanti hai adesso?" (vedi sezione 10).
- **Crea:** nascono la casa (nome, data di inizio, creata da), il primo membro (data di inizio = quella della casa) e il suo conto Contanti → A9.

## 7. A9 — Invita

- Un invito per persona: **link monouso** (App Link), **QR** dello stesso link e **codice di 8 caratteri** senza caratteri ambigui, mostrato in due gruppi da 4 (es. "K7QM X2PA"); etichetta facoltativa "per chi".
- Scadenza **7 giorni**; revocabile dalle impostazioni della casa; può invitare qualunque membro. Il limite di membri conta anche gli inviti aperti.
- Azioni: condividi, copia link, copia codice, "Invita un'altra persona", "Continua". Arrivando da A8 il tasto dice "Più tardi" e diventa "Continua" dopo che un invito è stato condiviso o copiato.
- Il token del link si salva lato server solo come hash; i tentativi con il codice breve sono limitati lato server.

## 8. A10 — Entra con invito

- Dal link (codice compilato) o scrivendo il codice, accettato con o senza lo spazio tra i due gruppi; anteprima con nome della casa, chi invita e membri presenti → "Entra".
- **Senza app:** il link apre una pagina con le istruzioni e il codice. **Con l'app ma senza account:** A2 → A3 → A10.
- **Errori:**

| Caso | Messaggio |
|---|---|
| Codice sbagliato | "Codice non valido. Controlla e riprova." |
| Invito scaduto | "Questo invito è scaduto: chiedine uno nuovo a chi ti ha invitato." |
| Invito già usato | "Questo invito è già stato usato." |
| Invito revocato | "Questo invito è stato annullato." |
| Casa piena | "Questa casa ha già il numero massimo di membri." |
| Account già in una casa | "Fai già parte di una casa" (un account sta in una sola casa) |
- **Casa già avviata:** il nuovo membro parte con il saldo del conguaglio a zero e non vede le righe precedenti alla sua data di inizio. La sua **data di inizio** è la data di ingresso, modificabile qui all'indietro fino a quella della casa.
- **Casa non ancora iniziata** (data di inizio della casa nel futuro): la data di inizio del membro è quella della casa e non si modifica.
- **Contanti:** come in A8, se la data di inizio del membro è il giorno stesso.
- **Quote predefinite:** all'ingresso diventano uguali per tutti i membri, valide dalla **data di inizio del nuovo membro**; gli altri membri ricevono una notifica per modificarle.

Esempio: in una casa con data di inizio 1° marzo, Bruno entra il 10 aprile. La sua data di inizio è il 10 aprile e le quote passano da 1 a 1:1 per le spese dal 10 aprile; se Bruno sposta la sua data al 1° marzo, le quote 1:1 valgono dal 1° marzo. Se invece la casa inizia il 1° maggio e Bruno entra il 10 aprile, la sua data di inizio è il 1° maggio.

## 9. A11 — Posizione

- Ultimo passo del primo avvio, **una volta per dispositivo**.
- Testo: "Per mostrare il cielo e il meteo sopra la tua casa, Home-made usa la posizione approssimativa (circa 10 km). Resta su questo dispositivo: non viene salvata né mostrata agli altri membri." (vale anche su tablet)
- "Consenti" → richiesta di sistema per la sola posizione approssimativa (`ACCESS_COARSE_LOCATION`, mai in background). "Scegli una città" → ricerca in un elenco di città incluso nell'app (GeoNames, CC BY 4.0, attribuzione in Info › Licenze).
- Permesso negato → scelta della città, che si può saltare. Tutto si cambia dalle impostazioni.
- **Da verificare:** peso dell'elenco delle città e soglia di popolazione.

## 10. Primo avvio di Finanze

- Nessuna procedura guidata: il Riepilogo mostra la card **"Per iniziare"** con due voci saltabili, che spariscono quando sono fatte: "Collega la tua banca" (H4) e "Contanti nel portafoglio".
- Il **saldo iniziale dei contanti** si riferisce alla **data di inizio del membro**:

| Data di inizio del membro | Dove e come si chiede |
|---|---|
| Il giorno della creazione o dell'ingresso | Subito in A8 o A10: "Quanti contanti hai adesso?"; se saltato, nella card, con la data dal giorno dopo |
| Nel passato | Nella card, con la data: "Quanti contanti avevi il 1° marzo?" |
| Nel futuro | Nella card da quel giorno: "Quanti contanti hai oggi?", poi con la data |

- È il saldo iniziale del conto Contanti, non un'entrata, e resta fuori dal bilancio; si modifica dal dettaglio del conto. Se non viene mai indicato, la prima conta dei contanti diventa il saldo iniziale.
- **Saldo iniziale tra i membri:** con almeno due membri la card mostra a tutti la voce "Saldo iniziale tra i membri": quanto ogni membro deve o riceve alla data di inizio della casa (somma zero; con due membri "Bruno ti deve …"), solo per i membri con quella data di inizio. La inserisce qualunque membro, senza approvazione, oppure chiunque tocca **"Nessun saldo da riportare"**, che lo fissa a zero per tutti; in entrambi i casi la voce sparisce per tutti e gli altri ricevono una notifica (con la cifra, o con l'indicazione che non c'è nessun saldo). Si corregge dai Saldi, con la regola dei conflitti. I conguagli pagati dopo lo azzerano normalmente.

## 11. Dati

- **Profilo:** nome visualizzato, versione e data di presa visione dell'informativa.
- **Casa:** nome, data di inizio, creata da.
- **Membro:** casa, utente, data di ingresso, data di inizio propria (da cui valgono anche le sue quote predefinite).
- **Invito:** casa, hash del token, codice breve, creato da, etichetta, scadenza, usato da e quando, revocato.
- **Dispositivo:** utente, piattaforma (token per le notifiche quando arrivano).
- **Conto Contanti:** creato con il membro; saldo iniziale con la data a cui si riferisce.
- **Saldo iniziale tra i membri:** casa, membro, importo, data (= data di inizio della casa), inserito o modificato da; "Nessun saldo da riportare" salva importi a zero.

## 12. Criteri di accettazione

- Con una sessione e una casa, l'avvio a freddo apre A1 e, dopo lo sblocco, l'hub; subito dopo l'accesso con Google A1 non compare.
- Un secondo dispositivo con lo stesso account passa da A2 ad A11 all'hub, senza A3 né A7.
- In A8 la data predefinita è il primo del mese in corso; date fuori da −90 giorni / +12 mesi non si possono scegliere.
- Il campo dei contanti in A8 compare solo se la data di inizio è il giorno stesso.
- Un invito usato, scaduto o revocato non fa entrare nessuno; un account con una casa non può entrare in un'altra.
- Un membro entrato dopo non vede le righe precedenti alla sua data di inizio e parte con il saldo del conguaglio a zero.
- Un membro che entra in una casa non ancora iniziata ha la data di inizio della casa e non può cambiarla.
- Le quote predefinite uguali dopo un ingresso valgono dalla data di inizio del nuovo membro.
- Accesso annullato: nessun messaggio.
- Il codice d'invito si accetta con e senza lo spazio tra i due gruppi da 4.
- In A9, arrivando da A8, il tasto "Più tardi" diventa "Continua" dopo una condivisione o una copia.
- La voce "Saldo iniziale tra i membri" compare solo con almeno due membri e accetta solo cifre con somma zero.
- "Nessun saldo da riportare" fissa a zero il saldo iniziale di ogni membro e toglie la voce a tutti.
