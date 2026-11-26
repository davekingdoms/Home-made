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
| 5 | Altrimenti | Hub |

- Un solo stato dell'avvio decide il passo, e il router legge solo quello: attesa, stato offline e ritorno alla schermata chiesta in [`navigazione.md`](navigazione.md), sezione 2.
- **Passo della casa** (dalla 4.6): manca finché l'account non è membro attivo di una casa. A7 e le sue schermate (A8–A10) sono schermate del passo, come A2 e A3: mai una destinazione da riaprire; quando la casa c'è cedono il posto alla schermata chiesta o all'hub. Dopo "Crea" di A8 l'avvio passa al passo successivo; dalla 4.7 A8 porta ad A9 e un invito in sospeso apre A10.
- **Sblocco: un blocco sopra i passi, non un passo del router.** A1 copre l'app all'avvio a freddo con una sessione salvata, qualunque sia il passo, e al ritorno in primo piano dopo almeno 1 minuto con l'app nascosta, solo sull'hub; mai con l'accesso con Google, mai durante una richiesta di sblocco, mai su un dispositivo senza blocco schermo. Lo decide lo stesso stato dell'avvio, ma il router non lo legge: niente cambi di rotta. Regole nella sezione 2.
- **Secondo dispositivo dello stesso account:** A2 → A11 → hub; il dispositivo si registra sull'account.
- **Dispositivo:** alla prima entrata di un account su un'installazione l'app genera l'id del dispositivo (UUID), lo salva sul dispositivo insieme all'id dell'account e inserisce la riga in `devices` (piattaforma `android`, senza nome né token per le notifiche): un secondo inserimento con lo stesso id (`23505`) vuol dire già registrato. `last_seen_at` si aggiorna al più una volta al giorno, all'avvio e al ritorno in primo piano. Ogni dispositivo dello stesso account ha la sua riga. Nei log solo il passo e il codice, mai id né modelli.
- **Uscire dall'account** (I2, menu di A3 e A7, A1): sempre con la conferma "Uscire dall'account?", testo "Per rientrare ti servirà il tuo account Google.", tasti "Annulla" e "Esci" (testo nel colore `error`). "Esci" cancella la riga del dispositivo in `devices` (senza bloccare l'uscita se manca la rete), l'id locale del dispositivo e lo stato dell'avvio salvato per l'account, poi chiude la sessione: A2, senza il messaggio della sessione scaduta. I valori del dispositivo che non dipendono dall'account (la posizione chiesta) restano.
- **Sessione persa senza "Esci"** (scaduta o revocata, anche ad app chiusa): A2 con il messaggio della sessione scaduta. Lo riconosce l'id del dispositivo, che solo "Esci" cancella.
- "Posizione già chiesta" si salva solo sul dispositivo, mai sul server.
- Nessuna presentazione iniziale a schede.
- **Schermi larghi:** layout del telefono centrato (vedi `navigazione.md`, sezione 5).
- Le schermate sono uguali con uno, due o più membri; cambiano solo l'elenco degli inviti (A9) e l'anteprima della casa (A10).

## 2. A1 — Sblocco

- Logo, "Home-made", "Sblocca per continuare"; in basso il tasto "Sblocca" e il tasto "Esci dall'account". La richiesta di sistema chiede la biometria o la credenziale del dispositivo (PIN, sequenza, password) tramite `local_auth`.
- **Quando:**
  - all'avvio a freddo con una sessione salvata, qualunque sia il passo dopo (lettura dello stato in corso, A3, A7, A11, hub). Lo sblocco e la lettura dello stato da Supabase vanno in parallelo: dopo lo sblocco si vede il passo che lo stato dice;
  - al ritorno in primo piano dopo almeno **1 minuto** con l'app nascosta (un'altra app, la schermata home, lo schermo spento), solo se il passo è l'hub: durante A3 e A7–A11 no (per esempio chi legge l'informativa nel browser). L'app soltanto inattiva (tendina delle notifiche, schermo diviso senza fuoco) non conta. Il tempo si misura con un orologio monotono, mai con l'ora del sistema; la durata è una costante, senza scelta nelle impostazioni. Il minuto conta solo con il dispositivo sveglio: il tempo a schermo spento con il dispositivo in sospensione non conta (orologio monotono), quindi dopo uno schermo spento lo sblocco può arrivare più tardi o non arrivare; a schermo spento il dispositivo chiede già il suo sblocco;
  - mai con l'accesso con Google (dopo, la regola del minuto vale come per tutti), mai mentre una richiesta di sblocco è aperta (i cambi che la richiesta stessa causa, come la schermata del PIN, non contano), mai su un dispositivo senza blocco schermo.
- **Sopra l'app:** A1 non è una rotta. Copre tutta l'app dall'esterno del router, senza cambiare rotta: sotto resta tutto com'era (scheda, dettagli, fogli aperti, testo scritto) e dopo lo sblocco si ritrova. Con A1 visibile sotto non arrivano tocchi, il lettore di schermo non trova niente e la tastiera si chiude; l'indietro di Android fa quello che fa dall'hub (l'app esce) e non agisce sotto, salvo chiudere la conferma di "Esci" se è aperta. A1 compare senza animazione e sparisce con una dissolvenza. Il percorso `/unlock` mostra A1 solo come anteprima, dall'indice delle schermate.
- **Richiesta di sistema:** parte da sola quando A1 compare e a ogni ritorno in primo piano con A1 visibile. Dopo un annullamento non riparte da sola fino al ritorno successivo: si riprova con "Sblocca", disattivato mentre la richiesta è aperta; se invece il sistema la ferma perché l'app è uscita dallo schermo, riparte al ritorno. Prima la biometria, poi PIN, sequenza o password; nessuna conferma dopo il riconoscimento del volto; la richiesta non continua dopo l'uscita dall'app. Testi in italiano: titolo "Home-made", descrizione "Sblocca per continuare", nessun sottotitolo, tasto "Annulla" (con la credenziale del dispositivo ammessa Android mostra i suoi tasti).
- **Esiti:** riuscito → A1 sparisce. Annullato, tempo scaduto, fermato dal sistema, troppi tentativi (temporaneo o permanente), qualunque altro errore → resta A1, senza messaggi (li mostra il sistema); nel log solo il codice. Blocco schermo tolto mentre l'app era in background → A1 sparisce, come su un dispositivo senza blocco schermo.
- **Esci dall'account:** con la conferma della sezione 1, poi A2 senza messaggio. Sessione persa con A1 visibile: A2 con il messaggio della sessione scaduta.
- **Disposizione:** fondo `surface`; colonna centrata larga al massimo 640 dp, anche sugli schermi larghi, con margini laterali di 16 dp e 24 dp sopra la barra dei gesti.
  - In alto, centrati, con 16 dp tra l'uno e l'altro: il logo provvisorio (biscotto di 88 dp in `primary` con la casa in `onPrimary`), "Home-made" (headlineMedium) e "Sblocca per continuare" (bodyMedium in `onSurfaceVariant`). Sopra il logo uno spazio pari a 200/844 dell'altezza dello schermo (circa un quarto: 200 dp su un telefono alto 844), mai meno di 48 dp sotto la barra di stato.
  - In basso, centrati, con 8 dp tra l'uno e l'altro: "Sblocca", tasto pieno largo quanto la colonna, alto 56 dp, con l'icona dell'impronta; "Esci dall'account", tasto contornato largo quanto il suo contenuto, alto 44 dp, con testo e icona di uscita in `error`.
  - Con il testo fino al 200% niente si taglia: la colonna scorre se serve e i tasti restano in fondo finché ci stanno.
- **Blocco schermo del dispositivo:** si controlla con `isDeviceSupported()` di `local_auth` (su Android: blocco sicuro, oppure biometria registrata, che richiede un blocco sicuro), ogni volta che serve, mai salvato; se il controllo fallisce vale come un dispositivo senza blocco schermo. Lo stesso controllo serve all'avviso dell'hub.
- **Dispositivo senza blocco schermo:** A1 non compare, l'app funziona e l'hub mostra un avviso fisso "Proteggi Home-made: attiva il blocco schermo", con il tasto che apre le impostazioni di sicurezza del sistema.

## 3. A2 — Accesso

- Logo, "Home-made", la frase "Conti, spese e conguagli di casa in un posto solo.", tasto "Continua con Google" e sotto il tasto "Accedi o registrati con il tuo account Google.". Unico metodo di accesso e registrazione. Finché non c'è il logo, al suo posto una casa sul biscotto.
- Durante l'accesso il tasto mostra un indicatore ed è disattivato.
- Solo su `dev`: la casella "Modalità demo" (sezione 12).
- I messaggi degli errori sono snackbar; quello della sessione scaduta è un avviso fisso sopra il tasto, finché non si accede di nuovo.
- **Disposizione:** fondo `surface`; colonna centrata larga al massimo 640 dp, anche sugli schermi larghi, con margini di 16 dp ai lati e in alto e 24 dp sopra la barra dei gesti.
  - In alto la card in evidenza (`primaryContainer` con le bande diagonali, raggio 32 dp, padding 24 dp), non toccabile e letta come una voce sola dal lettore di schermo. Nella card, in basso a sinistra: il logo provvisorio di 72 dp (biscotto in `tertiary` con la casa in `onTertiary`, che si distingue dalla card in entrambi i temi); 20 dp sotto, "Home-made" (displaySmall in `onPrimaryContainer`); 4 dp sotto, la frase (bodyLarge in `suPrimarioTenue`).
  - **Altezza della card:** 460/844 dell'altezza sotto la barra di stato (460 dp su un telefono alto 844), mai meno di 280 dp né del suo contenuto. Se in basso manca spazio si accorcia fino a quel minimo, lasciando almeno 12 dp tra la card e l'avviso o il tasto; poi la colonna scorre.
  - In basso, in fondo alla colonna, con 12 dp tra l'uno e l'altro: "Continua con Google", tasto pieno largo quanto la colonna, alto 56 dp; la riga "Accedi o registrati con il tuo account Google." (bodySmall in `testoTerziario`, centrata). Solo su `dev`, 8 dp sotto la riga, la casella "Modalità demo", centrata.
  - **Avviso della sessione scaduta:** riquadro fisso con l'aspetto di uno snackbar (fondo `inverseSurface`, testo `onInverseSurface` nello stile del contenuto degli snackbar, raggio 8 dp, alto almeno 48 dp), largo quanto la colonna, 12 dp sopra il tasto; regione che il lettore di schermo annuncia (regione live), ma senza il ruolo di stato, che Flutter in quel punto vieta con un'asserzione; senza azione né chiusura.
  - Con il testo fino al 200% niente si taglia: la colonna scorre e la card tiene la sua altezza minima.

| Caso | Messaggio |
|---|---|
| Accesso annullato dall'utente | nessuno |
| Senza rete | "Nessuna connessione. Controlla la rete e riprova." |
| Nessun account Google sul dispositivo | "Aggiungi un account Google nelle impostazioni di Android e riprova.", solo quando `google_sign_in` lo distinguerà con un codice proprio; oggi "Accesso non riuscito. Riprova." |
| Qualunque altro errore (anche di configurazione, solo nel log) | "Accesso non riuscito. Riprova." |
| Arrivo per sessione persa senza "Esci" | "La sessione è scaduta: accedi di nuovo." |
| Arrivo dopo "Esci" | nessuno |

**Nessun account Google:** `google_sign_in` (7.2, Android) non ha un codice per questo caso: lo segnala come `unknownError`, distinguibile solo dalla descrizione, che non è un dato sicuro. Il caso riceve il messaggio generico e nel log va solo il codice.

## 4. A3 — Primo accesso

- In alto **"Il tuo profilo"** e sotto "Gli altri membri della casa ti vedranno con questo nome e questa foto.". Poi la foto dell'account Google (nessun caricamento; se manca o non si carica, l'iniziale del nome sul biscotto) e il **nome** preso da Google e modificabile (obbligatorio: spazi alle estremità tolti, da 1 a 80 caratteri come il vincolo di `profiles`), con il testo d'aiuto "Preso da Google: puoi cambiarlo.".
- **Card della casella:** **"Ho letto l'informativa privacy"**, che si spunta toccando tutta la riga; sotto il tasto di testo "Leggi l'informativa" (con l'icona di apertura esterna), che apre l'informativa; poi la riga "Home-made registra quale versione hai letto e quando.".
- In fondo il tasto "Continua" (attivo con nome e casella), largo quanto la colonna. Layout del telefono, centrato: il contenuto parte sotto la barra in alto, con 24 dp tra i blocchi; con il testo fino al 200% o con la tastiera aperta la colonna scorre e "Continua" resta raggiungibile, in fondo finché ci sta, altrimenti dopo il contenuto.
- **"Esci dall'account"** nel menu della barra in alto, per chi ha scelto l'account Google sbagliato (con conferma, poi A2).
- **Informativa:** versione **`p1`** (provvisoria 1), costante nel codice. È la pagina `/privacy/` del sito su Cloudflare Pages (indirizzo nella configurazione `PAGES_BASE_URL`), che "Leggi l'informativa" apre nel browser: un'informativa provvisoria per le prove tra i membri della casa; quella definitiva arriverà prima che l'app sia usata da persone esterne alla casa.
- A3 compare se `user_settings` manca o ha un'altra versione dell'informativa. Se il profilo c'è già (cambia solo la versione), A3 mostra **"Informativa aggiornata"** e sotto "L'informativa privacy è cambiata. Leggila e conferma per continuare.", poi la card della casella senza la riga sulla versione e "Continua" in fondo: niente foto né nome.
- "Continua" crea o aggiorna il proprio profilo (nome e foto) e poi `user_settings` (versione e data di presa visione); con la sola casella salva solo `user_settings`. Durante il salvataggio il tasto mostra un indicatore. Errori (snackbar): "Nessuna connessione. Controlla la rete e riprova." oppure "Non è stato possibile salvare. Riprova.". Poi lo stato dell'avvio passa al passo successivo, o alla schermata chiesta.
- La casella registra la presa visione dell'informativa, non un consenso.
- Per un account demo, la riga della sezione 12 sotto il testo d'aiuto del nome.

## 5. A7 — Crea o entra in una casa

- **Saluto:** "Ciao, {nome}" (headlineLarge), con {nome} = la prima parola del nome visualizzato del profilo; senza nome (stato salvato prima che l'app lo leggesse), "Ciao". Sotto, a 8 dp, "Per iniziare crea la tua casa, oppure entra in quella di chi ti ha invitato." (bodyMedium in `onSurfaceVariant`). Il nome visualizzato arriva con lo stato dell'avvio, che lo legge dal profilo e lo salva sul dispositivo.
- **"Crea una casa"** → A8: card in evidenza (`primaryContainer` con la banda diagonale, raggio 28 dp, padding 20 dp); in alto il biscotto di 56 dp in `tertiary` con la casa da aggiungere (28 dp, `onTertiary`); 32 dp sotto, il titolo (titleLarge) e "Scegli il nome e da quando tenere i conti. Gli inviti puoi mandarli anche dopo." (bodyMedium in `suPrimarioTenue`), con la freccia in basso a destra.
- **"Ho un invito"** → A10: card `surfaceContainerLow` con le stesse misure; cerchio di 56 dp in `surfaceContainerHighest` con il link (28 dp, `primary`); "Scrivi il codice che hai ricevuto, oppure apri il link su questo dispositivo." in `onSurfaceVariant`, freccia in `onSurfaceVariant`.
- Ogni card si tocca tutta ed è letta come una voce sola, con il ruolo di tasto.
- In fondo, centrata, "Una casa con un solo membro funziona già: gli altri si aggiungono quando vuoi." (bodySmall in `testoTerziario`), 24 dp sopra il bordo inferiore.
- **Disposizione:** in alto la barra con il solo menu, senza titolo né indietro; il contenuto parte sotto la barra, con 24 dp tra i blocchi, nella colonna centrata larga al massimo 640 dp; con il testo fino al 200% la colonna scorre. L'indietro di Android fa come in A3 (l'app esce).
- **Menu della barra:** "Esci dall'account", come in A3; per un account demo anche "Elimina account demo", con il dialogo, gli errori e l'esito di I2 (sezione 12). Durante l'eliminazione al posto del menu c'è un indicatore.
- Con un invito in sospeso A7 si salta (dalla 4.7).

## 6. A8 — Crea casa

- **Disposizione:** barra alta 64 dp con l'indietro (→ A7) e il titolo "Crea casa"; campi con 16 dp ai lati e in alto e 24 dp tra l'uno e l'altro; in fondo "Crea", tasto pieno alto 56 dp, 24 dp sopra il bordo. Con la tastiera aperta o il testo grande la colonna scorre e "Crea" resta raggiungibile.
- **Nome della casa:** campo contornato, vuoto all'apertura, con la maiuscola iniziale; obbligatorio: spazi alle estremità tolti, da 1 a 80 caratteri (vincolo di `households`).
- **Data di inizio:** campo contornato non scrivibile con il calendario a destra; il tocco apre il selettore di data di Material in italiano. Predefinita il primo giorno del mese in corso; ammessa da 90 giorni prima di oggi a 12 mesi dopo (date locali del dispositivo; con i 12 mesi, lo stesso giorno del mese, o l'ultimo di un mese più corto). Si scrive "1° novembre 2026" (il simbolo ° solo per il giorno 1) e, se è oggi, "17 novembre 2026 · oggi". Il lettore di schermo legge "Data di inizio: 1° novembre 2026. Tocca per cambiarla" (oggi: "Data di inizio: oggi, 17 novembre 2026. Tocca per cambiarla"). Testo sotto il campo: "L'app considera solo i movimenti da questa data. Le banche di solito restituiscono circa tre mesi di movimenti: collegale subito dopo."
- **Quote predefinite:** non si chiedono (un solo membro).
- **Contanti:** solo se la data di inizio è oggi, campo facoltativo "Quanti contanti hai adesso?" (vedi sezione 10): contornato, con "€" in fondo, segnaposto "0,00", cifre tabulari, tastiera numerica con il decimale. Si scrivono solo cifre e un separatore decimale, la virgola (il punto diventa virgola), al più 2 decimali, niente segno, al più 999.999,99; vuoto = nessun saldo. Testo sotto: "Facoltativo. È il saldo iniziale del tuo conto Contanti, non un'entrata: puoi indicarlo anche dopo." Se la data cambia il campo sparisce, ma il valore scritto resta; si manda solo se al tocco di "Crea" la data è oggi.
- **Crea:** attivo con un nome valido; durante il salvataggio mostra un indicatore ed è disattivato. Chiama `create_household(id, name, start_date, cash_opening_cents)` con un id generato all'apertura di A8, uguale a ogni nuovo tentativo: la funzione non crea doppioni. Nascono la casa (nome, data di inizio, creata da), il primo membro (data di inizio = quella della casa) e il suo conto Contanti; poi lo stato dell'avvio dice che la casa c'è e l'avvio va al passo successivo (dalla 4.7 A9).

| Caso | Messaggio |
|---|---|
| Senza rete | "Nessuna connessione. Controlla la rete e riprova." |
| `start_date_out_of_range` | "La data di inizio non è più valida: scegline un'altra." |
| `already_member` (casa creata o invito usato da un altro dispositivo) | nessuno: si rilegge lo stato e si va avanti |
| Qualunque altro errore (anche `no_profile`; nel log solo il codice) | "Non è stato possibile creare la casa. Riprova." |

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

- **Profilo:** nome visualizzato e foto; nelle impostazioni dell'account (`user_settings`) versione e data di presa visione dell'informativa.
- **Casa:** nome, data di inizio, creata da.
- **Membro:** casa, utente, data di ingresso, data di inizio propria (da cui valgono anche le sue quote predefinite).
- **Invito:** casa, hash del token, codice breve, creato da, etichetta, scadenza, usato da e quando, revocato.
- **Dispositivo:** id generato sul dispositivo, utente, piattaforma, ultimo accesso (token per le notifiche quando arrivano).
- **Sul dispositivo** (mai sul server): id del dispositivo con l'account, stato dell'avvio per account, scelta della modalità demo (solo `dev`, sezione 12); poi posizione chiesta, città e invito in sospeso. Mai dati delle finanze.
- **Conto Contanti:** creato con il membro; saldo iniziale con la data a cui si riferisce.
- **Saldo iniziale tra i membri:** casa, membro, importo, data (= data di inizio della casa), inserito o modificato da; "Nessun saldo da riportare" salva importi a zero.

## 12. Account demo (solo sviluppo)

Strumento di sviluppo: su `dev` un account Google creato come demo si elimina dall'app con tutto ciò che gli appartiene, così il primo avvio si rifà da capo. Su `prod` non esiste: né la casella né l'eliminazione. **Non è** l'eliminazione dell'account delle Impostazioni, che resta da decidere. Colonne, funzioni ed errori in [`schema.md`](schema.md), sezione 3.

- **Interruttore lato server:** gli account demo sono attivi in un ambiente solo se in Vault c'è il segreto `demo_accounts` con valore `enabled`, inserito a mano su `dev`, mai su `prod`; nessun valore nel repository (come `project_url`). In locale e in CI lo creano e lo tolgono i test.
- **Flag sul profilo** (`profiles.is_demo`): deciso alla creazione del profilo e poi mai cambiato. Con l'interruttore spento un profilo demo non si crea (`demo_disabled`); un account vero non diventa demo e un demo non diventa vero (`demo_immutable`).
- **Case di soli demo:** una casa è tutta demo o tutta vera. `redeem_invite` rifiuta con `invite_demo_mismatch` chi ha il flag diverso da quello dei membri attivi della casa, dopo i controlli dell'invito e prima di quello dei posti; gli altri errori restano com'erano. Il testo per A10 arriva con gli inviti.
- **A2:** solo se `APP_ENV` è esattamente `dev` (assente o diverso: niente casella), sotto il tasto "Continua con Google" e la sua riga, la casella **"Modalità demo"**, che si spunta anche toccando il testo. La scelta si salva sul dispositivo come valore in sospeso e vale solo per un account **nuovo**: in A3 "Continua", quando crea il profilo, lo crea demo; poi il valore si cancella. Se il profilo c'è già (A3 con la sola casella, oppure un account che salta A3) il valore si cancella senza effetto. "Esci" non lo cancella: dopo un'uscita da A3 la casella mostra ancora la scelta.
- **Interruttore spento con la casella spuntata** (in locale, o su `dev` prima del segreto): "Continua" di A3 dà l'errore generico "Non è stato possibile salvare. Riprova."; si esce con "Esci dall'account" dal menu di A3 e si toglie la spunta in A2.
- **A3:** per un account demo, sotto il testo d'aiuto del nome, la riga "Account demo: si potrà eliminare da Impostazioni › Account."
- **I2 Account:** per un account demo (letto dal profilo), sotto "Esci", il tasto **"Elimina account demo"** (colore `error`) con il dialogo **"Eliminare l'account demo?"**, testo **"Si cancellano l'account, le case rimaste senza altri membri e tutti i loro dati. Non si può annullare."**, tasti **"Annulla"** e **"Elimina"** (testo nel colore `error`). Durante l'eliminazione il tasto mostra un indicatore. Errori (snackbar): "Nessuna connessione. Controlla la rete e riprova." oppure "Non è stato possibile eliminare l'account. Riprova.". Per un account vero il tasto non c'è.
- **A7:** per un account demo il menu della barra ha anche la voce "Elimina account demo", con lo stesso dialogo, gli stessi errori e lo stesso esito di I2; durante l'eliminazione al posto del menu c'è un indicatore. Per un account vero la voce non c'è.
- **Eliminazione** (`delete_my_demo_account()`, in una transazione): in ogni casa di cui l'account è membro attivo, se non restano altri membri attivi la casa si cancella con **tutti** i suoi dati; se restano altri membri (demo) il membro diventa ex membro e le sue righe restano, come per ogni ex membro (le quote predefinite non si ricalcolano: rischio accettato, solo `dev`). Poi si cancella l'account, con profilo, impostazioni, dispositivi, email PayPal e credenziali di Enable Banking (con il segreto di Vault). Una seconda chiamata, dopo una risposta persa, non fa niente.
- **Dopo l'eliminazione, sul dispositivo:** come "Esci" (id del dispositivo, stato dell'avvio salvato, uscita da Google e da Supabase), più **tutti i valori del dispositivo** (posizione chiesta, città, invito in sospeso, scelta della modalità demo), così il primo avvio si rifà intero. La riga di `devices` va con l'account: niente cancellazione separata. A2 senza il messaggio della sessione scaduta.
- **Stato dell'avvio:** legge anche `is_demo` dal profilo e lo salva con lo stato dell'account; nessun passo nuovo.
- **Banca:** nessun codice. Gli account demo si collegano solo alla Mock ASPSP con lo script di servizio, dopo che esiste una casa. All'eliminazione nessuna revoca della sessione su Enable Banking: la Mock non ha consensi reali.

## 13. Criteri di accettazione

- Con una sessione e una casa, l'avvio a freddo apre A1 e, dopo lo sblocco, l'hub; subito dopo l'accesso con Google A1 non compare.
- Un secondo dispositivo con lo stesso account passa da A2 ad A11 all'hub, senza A3 né A7.
- Senza casa l'avvio apre A7; con la casa, l'hub. Dopo "Crea" di A8 l'avvio va al passo successivo (oggi l'hub; dalla 4.7 A9).
- In A8 la data predefinita è il primo del mese in corso; date fuori da −90 giorni / +12 mesi non si possono scegliere.
- Il campo dei contanti in A8 compare solo se la data di inizio è il giorno stesso, e il saldo iniziale si manda solo se al tocco di "Crea" la data è oggi.
- "Crea" ripetuto dopo un errore non crea una seconda casa (stesso id); `already_member` non mostra messaggi e porta avanti.
- Un invito usato, scaduto o revocato non fa entrare nessuno; un account con una casa non può entrare in un'altra.
- Un membro entrato dopo non vede le righe precedenti alla sua data di inizio e parte con il saldo del conguaglio a zero.
- Un membro che entra in una casa non ancora iniziata ha la data di inizio della casa e non può cambiarla.
- Le quote predefinite uguali dopo un ingresso valgono dalla data di inizio del nuovo membro.
- Accesso annullato: nessun messaggio.
- Sessione persa senza "Esci": A2 con "La sessione è scaduta: accedi di nuovo."; dopo "Esci" A2 senza messaggi.
- "Esci" chiede conferma; "Annulla" non esce; "Esci" cancella la riga del dispositivo e l'id locale ed esce anche se la cancellazione fallisce.
- Il dispositivo si registra una volta per account e installazione: il secondo avvio non inserisce una nuova riga.
- Dopo A3 l'informativa non si chiede più finché la versione non cambia; con il profilo già salvato si chiede la sola casella.
- Offline con uno stato salvato l'app si apre; senza stato salvato compare "Riprova".
- Il codice d'invito si accetta con e senza lo spazio tra i due gruppi da 4.
- In A9, arrivando da A8, il tasto "Più tardi" diventa "Continua" dopo una condivisione o una copia.
- La voce "Saldo iniziale tra i membri" compare solo con almeno due membri e accetta solo cifre con somma zero.
- "Nessun saldo da riportare" fissa a zero il saldo iniziale di ogni membro e toglie la voce a tutti.
- Gli account demo esistono solo con il segreto `demo_accounts` in Vault: su `prod` né la casella di A2 né l'eliminazione, e il server rifiuta sia il flag sia l'eliminazione.
- Un account demo non entra in una casa vera, né un account vero in una casa demo.
- "Elimina account demo" (da I2 o dal menu di A7) chiede conferma ("Annulla" non elimina), cancella l'account e le case rimaste senza membri con tutti i loro dati, e il dispositivo riparte dal primo avvio, con A2 senza messaggi.
