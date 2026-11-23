# Sincronizzazione bancaria

Specifica della sincronizzazione con le banche tramite Enable Banking: collegamento, credenziali, importazione dal grezzo, deduplicazione, normalizzazione, giroconti automatici, conguagli PayPal, piani a rate, programmazione. Tabelle e vincoli di partenza in [`schema.md`](schema.md); qui le tabelle nuove e le regole delle funzioni lato server. Esempi inventati (Anna, Bruno, Carla, "Casa di prova", date del 2031, email `@example.com`).

Tutto avviene **lato server**: Edge Functions (Deno, TypeScript) con una chiave segreta (ruolo `service_role` del database) e funzioni SQL `security definer` eseguibili solo dal ruolo `service_role`. L'app non legge mai il grezzo né le credenziali e non chiama mai Enable Banking.

## 1. Componenti

| Componente | Dove | Cosa fa |
|---|---|---|
| Client Enable Banking | `supabase/functions/_shared/eb/` | JWT, chiamate all'API, paginazione, errori in codici |
| Normalizzazione | `supabase/functions/_shared/normalize/` | funzioni pure: date, importi, controparte, tipo e nome del conto, hash |
| Abbinamenti | `supabase/functions/_shared/match/` | giroconti, conguagli PayPal, piani a rate |
| `eb-credentials` | Edge Function | salva o sostituisce ID dell'applicazione e chiave privata della persona (Vault) |
| `eb-link-start` | Edge Function | avvia il collegamento di una banca e restituisce l'URL di autorizzazione |
| `eb-callback` | Edge Function, **senza JWT** | ritorno da Enable Banking: crea la sessione, la connessione e i conti, chiede la prima sincronizzazione, rimanda alla pagina di ritorno |
| `eb-sync` | Edge Function, **senza JWT** (segreto proprio) | sincronizza una connessione e lancia gli abbinamenti |
| Funzioni SQL di servizio | migrazioni | Vault, richieste di collegamento, importazione atomica, richiesta di sincronizzazione |
| Job programmati | `pg_cron` + `pg_net` | sincronizzazioni automatiche, consensi scaduti, pulizia |
| Pagina di ritorno | `infra/pages/bank-link/` (Cloudflare Pages, percorso `/bank-link/`) | mostra l'esito del collegamento dai parametri `esito` e `codice` |
| Script di servizio | `supabase/scripts/eb-admin.ts` | uso da riga di comando per lo sviluppo, con una chiave segreta dell'ambiente letta da un file in `private/` |

Configurazione delle Edge Functions (secrets di Supabase, mai nel repository):

| Nome | Contenuto |
|---|---|
| `EB_REDIRECT_URL` | URL di `eb-callback` dell'ambiente, registrato nell'applicazione Enable Banking |
| `APP_RETURN_URL` | URL della pagina di ritorno su Pages, percorso `/bank-link/` con lo slash finale |
| `EB_GLOBAL_APP_ID`, `EB_GLOBAL_PRIVATE_KEY` | facoltativi: applicazione globale di ripiego, usata solo se la persona non ha credenziali proprie |

`SUPABASE_URL`, `SUPABASE_SECRET_KEYS` e `SUPABASE_PUBLISHABLE_KEYS` (oggetti JSON con una chiave per nome) arrivano dall'ambiente delle Edge Functions. In `supabase/config.toml`: `verify_jwt = false` per **tutte** le funzioni (`eb-credentials`, `eb-link-start`, `eb-callback`, `eb-sync`), che fanno i propri controlli: il controllo della piattaforma riconosce solo le chiavi vecchie.

### Autenticazione delle Edge Functions
- **Utente** (app, più avanti): JWT di Supabase nell'header `Authorization: Bearer …`, verificato nel codice: la funzione chiama `current_member_id()` su PostgREST con quel JWT (e la chiave publishable come `apikey`), che rifiuta un JWT non valido. Il membro è il risultato; `null` → `403` con codice `member_not_eligible`.
- **Servizio** (script di servizio, job): una **chiave segreta** di Supabase (`sb_secret_…`) nell'header **`apikey`**, confrontata nel codice in tempo costante con tutti i valori di `SUPABASE_SECRET_KEYS`; mai nell'header `Authorization`. Il membro o la connessione arrivano nel corpo della richiesta.
- `eb-sync` accetta anche l'header `x-sync-secret`, confrontato in SQL con il segreto in Vault (`sync_secret_matches`): è la strada dei job e della prima sincronizzazione.
- Ogni altra chiamata: `401` con codice `unauthorized`.

## 2. Credenziali

- Ogni persona ha la **propria applicazione Enable Banking**: ID dell'applicazione e chiave privata (PEM).
- `eb-credentials` (utente o servizio) riceve `app_id` e la chiave privata, **prova la chiave** firmando un JWT e chiamando `GET /aspsps`, poi chiama `eb_set_credentials`. Chiave non valida: `invalid_credentials`, niente salvato.
- La chiave sta **solo in Supabase Vault**, con nome `eb_private_key:<user_id>`; `eb_credentials` tiene `app_id` e `private_key_secret_id`. Una seconda chiamata sostituisce il segreto (stesso nome) e aggiorna la riga.
- Senza una riga in `eb_credentials` si usa l'applicazione globale, se configurata (`uses_global_app = true` sulla connessione); altrimenti `no_credentials`.
- La chiave non compare mai in una risposta, in un log o in un errore.
- **JWT:** RS256, `kid` = ID dell'applicazione, `iss` = `enablebanking.com`, `aud` = `api.enablebanking.com`, durata 1 ora (il massimo ammesso è 24), generato a ogni invocazione e mai salvato.

## 3. Collegamento di una banca

1. `eb-link-start` (utente o servizio) con `aspsp_name`, `aspsp_country` (e `psu_type`, predefinito `personal`).
2. Legge la banca da `GET /aspsps` e calcola `valid_until` = adesso + `maximum_consent_validity` − 10 minuti: **si chiede sempre la durata massima** della banca.
3. Crea una riga in `bank_link_requests` (sezione 9), il cui `id` è lo `state`, con scadenza a 30 minuti.
4. `POST /auth` con `access.valid_until`, `aspsp`, `state`, `redirect_url` = `EB_REDIRECT_URL`, `psu_type`. Restituisce l'`url` di autorizzazione.
5. La persona autorizza **nello stesso browser** in cui ha aperto l'URL (alcune banche chiedono due accessi di fila: il secondo sembra un ritorno all'inizio ma va completato).
6. Enable Banking rimanda a `eb-callback?code=…&state=…` (oppure `?error=…&state=…` se la persona annulla o la banca rifiuta).
7. `eb-callback`:
   - controlla lo `state` con `claim_link_request` (sezione 9): sconosciuto, scaduto o già usato → esito `errore`, codice `link_expired`;
   - `error` presente → esito `annullato` (codice `link_cancelled`) o `errore` (`link_rejected`), la richiesta resta usata;
   - `POST /sessions` con il `code` → sessione, conti, `access.valid_until`; poi `GET /accounts/{uid}/balances` per ogni conto (un saldo che non si legge non ferma il collegamento: quel conto resta senza saldi);
   - con `complete_bank_link` (sezione 9), **in una sola transazione**: crea o aggiorna `bank_connections` (`status = 'active'`, `session_id`, `valid_until`, `uses_global_app` della richiesta, `last_error` null), i conti (sezione 6.4) e i saldi (sezione 6.5); per PayPal aggiunge l'email del conto a `paypal_emails` con `source = 'linked_account'` (se l'email è già di un'altra persona: niente riga, codice `paypal_email_taken` in `sync_runs`); scrive `result = 'ok'` sulla richiesta. **Una connessione si riusa** se è dello stesso membro, della stessa banca e dello stesso paese (`aspsp_name`, `aspsp_country`): una nuova autorizzazione aggiorna quella invece di crearne un'altra;
   - chiede la **prima sincronizzazione** con `request_bank_sync(connection_id, 'link')`, che parte subito, entro l'ora concessa dalle banche per lo storico lungo. Se la richiesta fallisce, il collegamento resta riuscito (esito `ok`) e nel log resta solo il codice: la prima sincronizzazione arriva con quelle programmate o con lo script di servizio;
   - risponde `302` verso `APP_RETURN_URL?esito=ok` (oppure `esito=annullato|errore&codice=<codice>`). **Nell'URL di ritorno solo l'esito e il codice**: mai id, nomi o importi.
8. Un conto già noto (stesso proprietario, stesso tipo, stesso `identifier`) si aggiorna invece di crearne uno nuovo, così una nuova autorizzazione della stessa banca non duplica i conti.

Errori di Enable Banking, rete o database durante il ritorno: esito `errore`, codice `link_failed`; nessuna scrittura parziale: una connessione già esistente resta com'era; la richiesta prende il codice in `result` (`finish_link_request`, sezione 9).

### Risposte delle funzioni
- `eb-credentials` ed `eb-link-start` (`POST`): JSON con `Cache-Control: no-store`, `{"ok": true, …}` oppure `{"error": "<codice>"}`. `eb-credentials` risponde `{"ok": true}`; `eb-link-start` `{"ok": true, "url": "…"}`. Codici: `401 unauthorized`, `403 member_not_eligible`, `400 invalid_request` (corpo sbagliato, `psu_type` non ammesso dalla banca), `400 invalid_credentials` (chiave rifiutata, niente salvato), `404 bank_not_found`, `409 no_credentials`, `502` con il codice di Enable Banking (sezione 4), `500 internal` (anche per una variabile d'ambiente mancante, senza il suo nome). Altri metodi: `405`.
- `eb-callback` (`GET`, pubblica; altri metodi `405`) risponde **sempre** `302` verso `APP_RETURN_URL` con `Cache-Control: no-store` e `Referrer-Policy: no-referrer`:

| Caso | `esito` | `codice` |
|---|---|---|
| `state` assente, non uuid, sconosciuto, scaduto o già usato | `errore` | `link_expired` |
| `error=access_denied` (la persona ha annullato) | `annullato` | `link_cancelled` |
| ogni altro `error` | `errore` | `link_rejected` |
| nessun `code`; errore di Enable Banking, rete o database | `errore` | `link_failed` |
| collegamento completato | `ok` | — |

## 4. Sincronizzazione di una connessione

`eb-sync` riceve `connection_id` e `trigger` (`link`, `schedule`, `manual`, `admin`); un altro corpo è `400 invalid_request`. Apre l'esecuzione (punto 1) e risponde subito `202` con `{"ok": true, "run_id": …, "status": "running"}` (oppure `"skipped"` se una sincronizzazione della connessione è già in corso; connessione sconosciuta: `404 connection_not_found`), poi lavora in `EdgeRuntime.waitUntil`, così la chiamata da `pg_net` non resta appesa.

1. **Un'esecuzione alla volta:** `begin_sync_run` apre la riga in `sync_runs`; se ce n'è già una `running` da meno di 15 minuti, niente (`already_running`).
2. **Consenso:** `GET /sessions/{session_id}`. Sessione scaduta o revocata → `status = 'expired'` o `'revoked'`, `last_error = 'consent_expired'` o `'consent_revoked'`, fine. Il consenso **non** si deduce mai dal testo di un errore sulle transazioni.
3. Per ogni conto della connessione non archiviato:
   - **saldi:** `GET /accounts/{uid}/balances` (sezione 6.5); un saldo che non si legge non ferma il conto: restano i saldi precedenti e nel log resta il codice (salvo il limite della banca, sotto);
   - **transazioni:** `GET /accounts/{uid}/transactions` con `date_from` e `strategy` della tabella sotto, seguendo `continuation_key` fino all'ultima pagina;
   - **un conto si importa solo con tutte le pagine scaricate**: una pagina fallita lascia il conto com'era (`status = 'partial'` per la connessione);
   - **normalizzazione** di ogni riga (sezione 6): una riga che non si normalizza (`invalid_row`: importo, valuta, data, segno o stato non validi) resta fuori dal grezzo e si conta in `sync_runs.rows_invalid`; le altre righe del conto si importano.
4. Importazione di ogni conto con `ingest_bank_rows` (sezione 5); dopo tutti i conti, una volta per esecuzione e se almeno un conto è stato importato, gli abbinamenti del membro (sezione 7) in quest'ordine: **piani a rate** (7.3), **conguagli PayPal** (7.2), **giroconti** (7.1). Un errore in un abbinamento lascia l'esito dei conti com'è e salta quelli che seguono: un errore nei piani salta conguagli e giroconti, un errore nei conguagli salta i giroconti.
5. Chiusura della riga di `sync_runs`: `ok` se tutti i conti sono importati; `partial` con il codice del primo conto non importato; `error` se la connessione stessa non si sincronizza (consenso, credenziali, sessione). Per `error` e `partial` sempre un codice. Su `bank_connections` `last_sync_at`, e `last_success_at` se tutti i conti sono riusciti.

Lo script di servizio `eb-admin.ts sync <connection_id>` chiama `eb-sync` con la chiave segreta (`trigger = 'admin'`), aspetta la fine dell'esecuzione e stampa da `sync_runs` solo stato, codici, strategia, date richieste e ottenute e conteggi di ogni conto ("account 1", "account 2"…): nessun importo, nome o id.

### Finestra scaricata

| Caso | `strategy` | `date_from` |
|---|---|---|
| Prima sincronizzazione di un conto (nessuna riga in `bank_raw_transactions`) | `longest` | data di inizio del membro proprietario del conto |
| Prima sincronizzazione di un conto PayPal | `longest` | data di inizio del membro **meno 90 giorni** (il grezzo serve a trovare gli acquisti a rate precedenti) |
| Sincronizzazioni successive | predefinita | data dell'ultima sincronizzazione riuscita del conto meno **15 giorni** (finestra sovrapposta), mai prima della data di inizio del membro |

Senza `date_to` (fino a oggi).

### Periodo rifiutato
Una risposta `422` con errore `WRONG_TRANSACTIONS_PERIOD` vuol dire **periodo troppo lungo**, anche quando il messaggio della banca parla di consenso scaduto. Si riprova con `date_from` = il più recente tra la data richiesta e oggi − 89, poi − 60, poi − 30 giorni. Se si scarica meno di quanto richiesto, la riga di `sync_runs` registra `history_from` (la data ottenuta) e `history_incomplete = true`: non si ritenta più indietro.

### Limiti delle banche
- Le sincronizzazioni senza l'utente presente sono limitate da molte banche a circa **4 al giorno** per conto. Una risposta di limite superato (`429` o il codice equivalente di Enable Banking) ferma la connessione fino al giro successivo, con `last_error = 'rate_limited'`: i conti rimasti si saltano (`skipped`).
- La prima sincronizzazione avviene con l'utente appena tornato dalla banca.
- Gli header facoltativi dell'utente presente (`Psu-Ip-Address`, `Psu-User-Agent`) arriveranno con l'aggiornamento manuale dall'app.

### Codici d'errore
Su `bank_connections.last_error` e `sync_runs.error_code` vanno **solo codici**, mai il testo della banca: `period_rejected`, `consent_expired`, `consent_revoked`, `rate_limited`, `no_credentials`, `invalid_credentials`, `bank_unavailable`, `bank_error`, `link_expired`, `link_cancelled`, `link_rejected`, `link_failed`, `already_running`, `paypal_email_taken`, `internal`. La tabella dagli errori di Enable Banking (campo `error` della risposta, stato HTTP) a questi codici sta nel client, con i test.

## 5. Grezzo e deduplicazione

Ogni transazione restituita dalla banca diventa una riga di `bank_raw_transactions` (tutte, anche `RJCT`, `CNCL`, `PDNG` e quelle prima della data di inizio). `ingest_bank_rows(account_id, rows)` riceve le righe già normalizzate (sezione 6) e fa tutto in **una transazione** con un `pg_advisory_xact_lock` sul conto:

1. **Con `entry_reference`:** insert con conflitto su (`account_id`, `entry_reference`) ignorato. **Eccezione:** se la riga salvata è `PDNG` e quella nuova è `BOOK`, la riga salvata si aggiorna (stato, date, importo, `dedup_hash`, payload).
2. **Senza `entry_reference`:** si raggruppano le righe scaricate per `dedup_hash`. Per ogni gruppo, `n` = righe scaricate, `m` = righe già salvate con quell'hash sul conto: se `n > m` si inseriscono le righe con ordinali `m + 1 … n`; se `n ≤ m` non si fa niente (`n < m` si conta in `sync_runs.groups_shrunk`). **Una riga uguale a un'altra non si scarta mai.** I gruppi sono completi perché l'hash contiene le date e un conto si importa solo con tutte le pagine (sezione 4).
3. Per le righe nuove (o passate da `PDNG` a `BOOK`) che diventano movimenti (sezione 6.1) si crea la transazione; `bank_raw_transactions.transaction_id` la collega.
4. Restituisce i conteggi: righe ricevute, nuove, movimenti creati, saltate per data o stato.

**`dedup_hash`** = SHA-256 in esadecimale minuscolo di
`booking_date|value_date|transaction_date|status|segno|importo_in_centesimi|descrizione`
con le date in ISO (vuote se mancano), segno `D` o `C`, importo in centesimi **senza segno** (il segno è il campo prima), descrizione normalizzata (sezione 6.3), vuota se manca. Lo **stato** fa parte dell'hash: una riga `PDNG` che torna `BOOK` è un gruppo diverso, quindi la versione contabilizzata non viene scambiata per un doppione della provvisoria.

## 6. Dal grezzo al movimento

### 6.1 Quali righe diventano movimenti
- solo `status = 'BOOK'`;
- `movement_date` ≥ data di inizio del **membro proprietario del conto**: una spesa precedente contabilizzata dopo la data di inizio resta solo nel grezzo;
- importo diverso da zero: una riga `BOOK` da zero resta solo nel grezzo e si conta in `sync_runs.skipped_status`;
- non è l'acquisto di un piano a rate (sezione 7.3);
- `PDNG`, `RJCT`, `CNCL` restano solo nel grezzo. Una riga già diventata movimento che più avanti arriva `CNCL` (con lo stesso `entry_reference`) non si tocca: si conta in `sync_runs.booked_then_cancelled`.

### 6.2 Campi della transazione

| Colonna di `transactions` | Da |
|---|---|
| `household_id`, `account_id` | conto |
| `source` | `bank` |
| `raw_id` | riga del grezzo |
| `paid_by_member_id` | proprietario del conto (`entered_by_member_id` null) |
| `movement_date` | data valuta, altrimenti data della transazione, altrimenti data contabile |
| `booking_date` | data contabile |
| `booking_status` | `booked` |
| `amount_cents`, `currency` | `transaction_amount`, con il segno da `credit_debit_indicator` (`DBIT` negativo, `CRDT` positivo) |
| `original_amount_cents`, `original_currency`, `exchange_rate` | dal blocco del cambio, se presente; altrimenti null |
| `description` | descrizione normalizzata (6.3) |
| `counterparty` | controparte normalizzata (6.3) |
| `counterparty_email` | solo PayPal: email della controparte (creditore sulle uscite, debitore sulle entrate), in minuscolo |
| `bank_code` | `bank_transaction_code` come `code/sub_code` (es. `PAYMENT/PAYMENT`), o il solo codice |

Alla creazione il trigger dello schema crea la riga al 100% di chi paga, senza tipo: il movimento è **da classificare**.

### 6.3 Normalizzazione
- **Importi:** testo con il punto decimale e un numero variabile di decimali (`4.4`, `1`, `12.50`): si converte in centesimi interi senza passare dai numeri a virgola mobile. Più di due decimali: si arrotonda al centesimo con metà verso l'alto e la normalizzazione segnala la riga, che si conta in `sync_runs.amounts_rounded`.
- **Descrizione:** `remittance_information` unite da uno spazio, spazi ripetuti ridotti a uno, `trim`; vuota → null.
- **Controparte:** campo dedicato se presente (nome del creditore sulle uscite, del debitore sulle entrate); altrimenti estratta dalla descrizione con il formato della banca (sezione 8); se nessun formato riconosce la descrizione, null. La controparte serve a suggerimenti e regole, non decide niente da sola.
- **Date:** ISO `YYYY-MM-DD`; una data mancante resta null.

### 6.4 Conti
| Colonna di `accounts` | Regola |
|---|---|
| `kind` | `paypal` se la banca è PayPal; `card` se `cash_account_type = 'CARD'`; altrimenti `bank` |
| `provider_account_id` | `uid` del conto in Enable Banking (aggiornato a ogni nuova sessione) |
| `cash_account_type`, `currency` | dal dettaglio del conto (`XXX` per un conto multivaluta) |
| `identifier` | IBAN, numero di carta mascherato o email del conto |
| `display_name` | **nome predefinito**: nome della banca + " …" + ultime 4 cifre dell'IBAN; per una carta il prodotto (o "Carta") + " …" + ultime 4 cifre; per PayPal l'email del conto. Il nome mandato dalla banca, ripulito degli spazi in coda, non si usa come nome predefinito (spesso è l'intestatario) |

### 6.5 Saldi
Ogni saldo di `GET /accounts/{uid}/balances` va in `account_balances` (`account_id`, `currency`, `balance_type`) con il segno, `reference_date` e `fetched_at`: si tiene l'ultimo valore. Una carta di credito ha il debito negativo. Un conto multivaluta ha un saldo per valuta. **Il saldo non si calcola mai dai movimenti.**

## 7. Abbinamenti dopo la sincronizzazione

Dopo ogni sincronizzazione, per il **membro proprietario** della connessione, sui suoi movimenti degli ultimi **45 giorni** (i piani a rate cercano acquisti e rate su tutto il grezzo, 7.3), in quest'ordine: piani a rate, conguagli PayPal, giroconti. Regole comuni:
- **idempotenti:** rilanciati non cambiano niente;
- toccano solo transazioni con **una sola riga**, senza tipo e non collegate;
- non ricreano mai un collegamento **annullato**: una transazione che compare in un giroconto, un conguaglio o un piano con `deleted_at` non si abbina più in automatico;
- con **più candidati alla pari** non si abbina niente: il movimento resta da classificare (meglio una classificazione a mano che un abbinamento sbagliato).

### 7.1 Giroconti (`transfers.origin = 'auto'`)
Le righe collegate prendono `kind = 'transfer'` e `transfer_id`; categoria e quote della riga restano come sono (senza categoria, 100% di chi paga) e la transazione non cambia: `version` resta quella di prima (`version = 1` è la regola dell'acquisto a rate, 7.3).

**Quando:** una volta per esecuzione di `eb-sync`, dopo tutti i conti e **dopo i piani a rate e i conguagli PayPal** (7.3, 7.2), se almeno un conto è stato importato (anche con esito `partial`). Il numero dei giroconti creati va in `matched_transfers` della riga della connessione. Un errore negli abbinamenti lascia l'esito dei conti com'è: nel log solo il codice, `matched_transfers` = 0; il giro successivo riprova (la finestra di 45 giorni lo copre). Un errore nei piani o nei conguagli salta anche i giroconti dello stesso giro (7.3, 7.2).

**Quali movimenti:** solo quelli importati dalle banche (`source = 'bank'`) sui conti del membro con una connessione e **non archiviati**, con `movement_date` negli ultimi 45 giorni. Movimenti manuali, conti `cash` e `manual` e conti archiviati non entrano mai, nemmeno come "carta nella stessa connessione" o "conto PayPal collegato". Un movimento è **libero** se ha una sola riga non eliminata, senza tipo e senza collegamenti (giroconto, conguaglio, piano), non è una rata (`installment_plan_id` sulla transazione), non compare in un giroconto non eliminato e non è un lato di un conguaglio non eliminato. È **annullato** se compare in un giroconto eliminato, è un lato di un conguaglio eliminato o è collegato a un **piano eliminato** (sulla transazione o su una riga): non si abbina più (regole comuni), così un conguaglio o un piano annullati dall'utente non diventano un giroconto al giro dopo. Importi sempre nella stessa valuta.

**Ordine:** prima l'addebito mensile della carta, poi banca o carta → PayPal, poi tra due conti (i primi due hanno un segnale nella descrizione o nella controparte, più sicuro del solo importo). Un movimento usato da una regola non entra nelle successive.

| Caso | Riconoscimento | Giroconto |
|---|---|---|
| Addebito mensile della carta di credito | uscita sul conto con la descrizione dell'addebito della carta (sezione 8), di un membro che ha **una** carta nella stessa connessione; senza carte nella connessione la regola non si applica e l'uscita passa alle successive | da: conto; a: carta; lato in entrata = l'accredito sulla carta con lo stesso importo a distanza ≤ 5 giorni (prima o dopo l'addebito), se c'è |
| Banca o carta → PayPal | uscita di un conto `bank` o `card` la cui controparte contiene "PAYPAL" (addebito diretto o pagamento con carta verso PayPal), **solo se il membro ha un conto PayPal collegato**; senza, resta da classificare | da: conto o carta; a: conto PayPal; `in_transaction_id` vuoto; `funded_transaction_id` = l'uscita PayPal con lo stesso importo e data tra 7 giorni prima e il giorno dell'addebito, non già finanziata, se c'è. **L'abbinamento con il pagamento non decide il tipo**: l'addebito è un giroconto anche senza pagamento corrispondente |
| Tra due conti dello stesso membro (es. ricarica di un conto prepagato) | stesso importo, segno opposto, conti diversi, date a distanza ≤ 3 giorni; se uno dei due conti è PayPal, la controparte del lato bancario contiene "PAYPAL" (due conti PayPal: mai) | da: conto dell'uscita; a: conto dell'entrata; entrambi i lati |
| PayPal → banca (trasferimento del saldo) | caso precedente | da: PayPal; a: banca. **Mai un'entrata** |

Il pagamento PayPal finanziato non si tocca (resta con il suo tipo, anche già classificato): basta che non compaia in un giroconto, annullato o no, e non sia annullato. Un pagamento collegato a un conguaglio non eliminato resta finanziabile, e così una rata di un piano non eliminato (7.3); una rata di un piano eliminato è annullata e non si finanzia. Per trovarlo `eb-sync` legge anche i movimenti dei 7 giorni prima della finestra di 45 giorni, che servono solo a questo.

**Candidati alla pari**, caso per caso:
- addebito della carta: più carte nella stessa connessione → niente, l'uscita resta da classificare (e non passa alle regole successive); più accrediti possibili sulla carta, o un accredito possibile per più addebiti → giroconto senza lato in entrata;
- banca o carta → PayPal: più conti PayPal collegati → niente, l'uscita resta da classificare; più uscite PayPal possibili da finanziare, o un'uscita possibile per più addebiti → giroconto senza `funded_transaction_id`;
- tra due conti: un'uscita con più entrate possibili, o un'entrata con più uscite possibili → niente.

**Decisione e scrittura:** le regole sono funzioni pure in `_shared/match/transfers.ts`. `eb-sync` legge i candidati con `transfer_candidates` e scrive i giroconti con `apply_transfers` (sezione 9), che lavora in una transazione con un lock sul membro e ricontrolla ogni condizione: i job delle sincronizzazioni partono per tutte le connessioni insieme, e due connessioni dello stesso membro farebbero gli abbinamenti in parallelo.

### 7.2 Conguagli PayPal (`settlements.origin = 'paypal'`)
**Quali movimenti:** per il membro proprietario della connessione, i movimenti importati (`source = 'bank'`) dei suoi **conti PayPal** con una connessione e non archiviati, con `movement_date` negli ultimi 45 giorni, in **EUR**, liberi per i conguagli e non annullati. Per i conguagli un movimento è libero se ha una sola riga non eliminata, senza tipo e senza collegamenti, non è una rata, non è l'uscita o l'entrata di un giroconto non eliminato e non è un lato di un conguaglio non eliminato; a differenza dei giroconti, un pagamento **finanziato** da un giroconto resta libero (il finanziamento non lo classifica, 7.1). Annullato: come in 7.1 (giroconto, conguaglio o piano eliminati).

- **Lato di chi paga:** uscita su un conto PayPal di Anna con `counterparty_email` uguale (in minuscolo) a un'email di `paypal_emails` di Bruno, **membro attivo della stessa casa**, diverso da Anna.
- **Lato di chi riceve:** entrata su un conto PayPal di Bruno con un'email di Anna come controparte: stessa regola, a parti invertite.
- **Collegamento:** il movimento si collega a un conguaglio con la stessa coppia nello stesso verso (pagatore, ricevente), stesso importo, EUR, `settled_on` a distanza ≤ 3 giorni dalla data del movimento, non eliminato, con il **lato di quel membro ancora vuoto**. Vale per ogni `origin`, anche `manual` ("Segna come pagato"); collegare un lato non cambia importo, data né `origin` del conguaglio.
- **Altrimenti nasce un conguaglio**, solo se per quel movimento **non c'è nessun conguaglio candidato**: `origin = 'paypal'`, `settled_on` = data del movimento, importo = valore assoluto del movimento, EUR, `created_by_member_id` null, il lato del movimento collegato.
- **ID della transazione PayPal:** se il riferimento della banca (`entry_reference` del grezzo) del movimento è uguale a quello del lato già collegato di un conguaglio candidato, quella coppia vince prima della sola regola su importo e data e scioglie la parità. Nei dati di prova del caso 5 gli ID dei due lati sono diversi e basta la regola su importo e data (da verificare sui dati veri).
- **Candidati alla pari:** un movimento con più conguagli candidati, o un conguaglio candidato per più movimenti → niente, **e nemmeno un conguaglio nuovo** (sarebbe un doppione di quello esistente); il movimento resta da classificare. Un conguaglio preso con l'ID uguale non è più candidato per gli altri movimenti, che possono crearne uno proprio. Due movimenti dello stesso membro che creano ciascuno un conguaglio (es. due pagamenti uguali a Bruno nello stesso giorno, nessun conguaglio esistente) non sono alla pari: nascono due conguagli.
- Valgono i vincoli dello schema: date di inizio dei due membri non successive a `settled_on`, membri attivi. Se un vincolo non vale, il movimento resta da classificare, senza un errore che fermi gli altri.
- In un'altra valuta, verso un'email che non è di nessun membro attivo della casa, verso un ex membro o verso un'email del membro stesso: niente, il movimento resta da classificare.
- La riga prende `kind = 'settlement'` e `settlement_id`; categoria e quote restano come sono e la transazione non cambia (`version` invariata, come per i giroconti). Un pagamento collegato a un conguaglio resta finanziabile da un addebito della banca (7.1).

**Quando:** una volta per esecuzione di `eb-sync`, come i giroconti, **dopo i piani a rate** (7.3) e **prima** dei giroconti. `matched_settlements` della riga della connessione = numero dei **movimenti collegati** (lati), sia creando sia collegando un conguaglio. Un errore nei conguagli lascia l'esito dei conti com'è e **salta i giroconti dello stesso giro** (così un movimento destinato a un conguaglio non finisce in un giroconto): nel log solo il codice, `matched_settlements` e `matched_transfers` = 0; il giro successivo riprova (finestra di 45 giorni). Un errore nei piani salta anche i conguagli (7.3).

**Decisione e scrittura:** come per i giroconti, le regole sono funzioni pure in `_shared/match/settlements.ts`; `eb-sync` legge i candidati con `settlement_candidates` e scrive con `apply_settlements` (sezione 9). **Le email si confrontano solo in SQL:** i candidati portano, per ogni movimento, il membro attivo della stessa casa a cui appartiene l'email della controparte, mai l'email. I due lati di un conguaglio arrivano dalle sincronizzazioni di **due membri diversi**, che partono insieme: `apply_settlements` prende il lock del proprietario e di ogni altro membro delle proposte, in ordine di id e con la stessa chiave dei giroconti, prima di rileggere, e ricontrolla ogni condizione, compreso "nessun conguaglio candidato" per una creazione. I collegamenti si scrivono prima delle creazioni.

### 7.3 Piani a rate (PayPal "Paga in 3 rate")
**Quali righe:** per il membro proprietario della connessione, le righe del grezzo `BOOK`, in **EUR**, in uscita, dei suoi **conti PayPal** con una connessione e non archiviati. Acquisti e rate si cercano su **tutto il grezzo** di quei conti (che parte dalla data di inizio meno 90 giorni, sezione 4), non solo negli ultimi 45 giorni: un piano dura mesi e alla prima sincronizzazione acquisto e prime rate possono essere più vecchi della finestra. Si collegano come movimenti solo le rate con `movement_date` negli ultimi **45 giorni**. Codice e sottocodice si leggono da `bank_transaction_code` del payload. Un acquisto in un'altra valuta resta com'è.

- **Acquisto:** uscita `PAYMENT/PAYMENT` di importo `P` con, **lo stesso giorno** e sullo stesso conto, un'uscita `PAYMENT/LOAN` (la prima rata) di importo `L` tale che `n = round(P / L)` è tra 2 e 12 e `|P − n·L| ≤ n` centesimi.
- **Piano:** `merchant` = controparte dell'acquisto (il nome del creditore, normalizzato come per i movimenti, 6.3; senza nome la descrizione normalizzata, altrimenti `PayPal`; **mai l'email**), `total_cents` = `P`, `installments_count` = `n`, `purchase_date`, `purchase_raw_id`, `account_id` = conto PayPal, `status = 'active'`, `category_id` null, nessun peso. **Un piano per acquisto:** indice unico su `installment_plans.purchase_raw_id`, anche per i piani eliminati, così un piano annullato dall'utente non si ricrea.
- **Rate:** in ordine di data, le uscite `PAYMENT/LOAN` dello stesso conto con importo `L` (±1 centesimo; l'ultima rata, la `n`-esima, fino a `n` centesimi di differenza), dalla data dell'acquisto, a distanza **≥ 20 giorni** dalla rata precedente del piano; la prima rata è quella dello stesso giorno dell'acquisto. Una rata va al **piano attivo più vecchio** (per data dell'acquisto) con quell'importo e meno di `n` rate; qui non c'è parità. Una rata già collegata a un piano resta sua. Un piano eliminato continua a prendere le sue rate, che non si toccano più (non passano a un altro piano).
- `installments_before_start` = rate con data precedente alla data di inizio del membro proprietario (solo nel grezzo, fuori dal bilancio). `next_due_date` = data dell'ultima rata + 30 giorni finché il piano è attivo; alla rata `n` `status = 'completed'` e `next_due_date` null.
- **Rata diventata movimento:** si collega se è libera (come per i conguagli, 7.2: una sola riga non eliminata, senza tipo e senza collegamenti, non l'uscita o l'entrata di un giroconto né un lato di un conguaglio, non eliminati; un pagamento finanziato resta libero) e non annullata. Prende `installment_plan_id` sulla transazione e sulla riga: la `version` della transazione sale come per ogni modifica (l'app deve vedere il cambiamento; `version = 1` è la regola dell'acquisto, sotto). Se il piano ha categoria e pesi e la riga può prenderli, la riga prende `kind = 'expense'`, la categoria (con il suo flag 730 predefinito) e le quote dei pesi, calcolate come `set_line_shares`; altrimenti resta da classificare, ma non è più libera per conguagli e giroconti. La riga **può prenderli** se la categoria è di spesa e della casa; i membri con un peso sono attivi, della casa e con la data di inizio non successiva alla rata; con un peso di un membro diverso da chi paga, la categoria è condivisa e non è "Differenza di cassa" e la riga non ha tag personali; una categoria personale è di chi paga. Una rata prima della finestra, non libera o annullata conta nel piano (rate pagate, data dell'ultima) ma non si collega.
- **L'acquisto non è mai un movimento.** Se è già diventato una transazione (variante del caso 4: acquisto in una sincronizzazione, rate nella successiva), quando nasce il piano il server la **elimina davvero** (le transazioni importate non hanno `deleted_at`): quote, riga e transazione, e `transaction_id` del grezzo a null. Solo se è ancora com'era alla creazione: `transactions.version = 1`; **una sola riga**, non eliminata, con `version = 1`, senza tipo, categoria, tag né collegamenti, con la sola quota del 100% di chi paga, senza anticipi né salvadanai; la transazione **non compare in nessun giroconto** (nemmeno come pagamento finanziato) **né conguaglio**, eliminati o no. Altrimenti resta com'è e conta **1** in `sync_runs.purchase_already_classified`, **una sola volta**, quando nasce il piano. Il piano nasce comunque. `ingest_bank_rows` non ricrea il movimento di un acquisto eliminato: la riga del grezzo resta salvata (`BOOK`), e una riga già salvata non torna movimento, nemmeno arrivando di nuovo `BOOK` o `PDNG` (sezione 5: solo una riga salvata `PDNG` che arriva `BOOK` diventa movimento, e un piano nasce solo da un acquisto `BOOK`).
- **Alla pari niente:** un acquisto con più prime rate possibili lo stesso giorno, o una prima rata possibile per più acquisti → nessun piano. Nessun piano da un acquisto che compare in un giroconto, un conguaglio o un piano eliminati (annullato); nessuna rata annullata si collega.
- I pagamenti della banca o della carta verso PayPal che finanziano le rate sono giroconti (7.1): una rata collegata a un piano non eliminato resta finanziabile.

**Quando:** una volta per esecuzione di `eb-sync`, **prima** dei conguagli e dei giroconti (sezione 4). `matched_installments` della riga della connessione = numero dei **movimenti collegati** a un piano (rate), non dei piani creati; `purchase_already_classified` della stessa riga = acquisti lasciati (sezione 9). Un errore nei piani lascia l'esito dei conti com'è e **salta conguagli e giroconti dello stesso giro** (così una rata non finisce in un conguaglio o in un giroconto): nel log solo il codice, `matched_installments`, `matched_settlements` e `matched_transfers` = 0; il giro successivo riprova.

**Decisione e scrittura:** come per giroconti e conguagli, le regole sono funzioni pure in `_shared/match/installments.ts`; `eb-sync` legge i candidati con `installment_candidates` e scrive con `apply_installments` (sezione 9). `apply_installments` prende il `pg_advisory_xact_lock` del **solo proprietario** (un piano è di un conto solo), con la chiave condivisa dagli abbinamenti della sezione 7, prima di rileggere; blocca con `for update` la riga del grezzo dell'acquisto, il suo movimento, i piani da aggiornare e le righe dei movimenti, e **ricontrolla** ogni condizione: quello che non vale più si salta e non si conta. Un piano già salvato si aggiorna solo se cambia qualcosa: rilanciati, gli abbinamenti non creano piani né collegamenti in più.

## 8. Formati supportati

Il collegamento funziona con qualunque banca di Enable Banking; questi formati migliorano controparte e abbinamenti. Esempi inventati.

**Credito Emiliano, conto (`CACC`)**: controparte sempre nella descrizione; `entry_reference` sempre presente (formato `…-AAAAMMGG-NNNNNNN-NNN`); un bollettino e la sua commissione hanno lo stesso riferimento con suffisso `-001` e `-002`.

| Descrizione (esempio inventato) | Controparte |
|---|---|
| `BANCOMAT 03/02/31,ORE 12:34,TESS.00000000 BAR ESEMPIO` | `BAR ESEMPIO` (data e ora reali dell'acquisto nella descrizione; la data valuta coincide) |
| `SEPA DD CORE DA ESEMPIO ENERGIA SPA MANDATO XX000000` | `ESEMPIO ENERGIA SPA` |
| `SEPA DD CORE DA PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A. MANDATO XX000001` | `PAYPAL (EUROPE)…` → caso "verso PayPal" |
| `EMOLUMENTI DITTA ESEMPIO SRL STIPENDIO MARZO` | `DITTA ESEMPIO SRL` |
| `PAGAMENTO CBILL ESEMPIO SERVIZI` / `COMM. PAG. CBILL` | `ESEMPIO SERVIZI` / null |
| `BON. ISTANTANEO A DEBITO ANNA ESEMPIO … RICARICA` | `ANNA ESEMPIO` (il nome finisce alla prima parola con una cifra, es. l'IBAN) |
| `ADDEBITO MESE CARTA EGO` | null → addebito mensile della carta (7.1) |

Il conto bancario arriva con un secondo conto `CARD` nella stessa sessione. Il campo `debtor_account` sulle uscite è il conto stesso: non è una controparte.

**Credito Emiliano, carta (`CARD`)**: solo `transaction_date`; nessun `entry_reference` né codice (deduplicazione solo per gruppi); descrizione `ESERCENTE CITTÀ PAESE` → si toglie il codice paese di 2 lettere in fondo, poi l'ultima parola (la città): `FERRAMENTA PROVA CITTAPROVA IT` → `FERRAMENTA PROVA`. Importi con decimali variabili. Saldi `CLBD` (debito, negativo) e `OTHR` (disponibilità residua).

**HYPE**: nome del conto vuoto; `entry_reference` solo sulle entrate; codici `pos` (pagamento con carta) e `boi` (entrata, es. ricarica); descrizione dei pagamenti `pos` `NOME CITTÀ PROV` → si toglie la sigla di 2 lettere in fondo e l'ultima parola: `CAFFE ESEMPIO CITTAPROVA ZZ` → `CAFFE ESEMPIO`; sulle altre righe la controparte viene solo dal campo dedicato. Saldi `ITBD` e `ITAV`.

**PayPal**: conto `OTHR`, identificato dall'email, valuta `XXX`, saldi `XPCD` per valuta; solo `transaction_date`; `entry_reference` sempre presente; controparte con nome ed email nel creditore (uscite) o nel debitore (entrate); `PAYMENT/PAYMENT` = pagamento o invio di denaro, `PAYMENT/LOAN` = rata; compaiono righe `RJCT`. I finanziamenti dalla banca non compaiono su PayPal.

## 9. Tabelle e funzioni nuove

### `bank_link_requests` — collegamenti in corso
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | è lo `state` mandato a Enable Banking |
| `member_id` | uuid | → `members` |
| `aspsp_name`, `aspsp_country` | text | |
| `psu_type` | text | `personal` o `business` |
| `uses_global_app` | bool | |
| `expires_at` | timestamptz | creazione + 30 minuti |
| `used_at` | timestamptz null | |
| `result` | text null | codice dell'esito |
| `created_at` | timestamptz | |

Nessun accesso dall'app. Pulizia delle righe più vecchie di 7 giorni con un job.

### `sync_runs` — esito di ogni sincronizzazione
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `connection_id` | uuid | → `bank_connections` |
| `account_id` | uuid null | null = riga della connessione; una riga per conto con i suoi conteggi |
| `run_id` | uuid null | → `sync_runs`; null sulla riga della connessione, l'id di quella riga sulle righe dei conti |
| `trigger` | text | `link`, `schedule`, `manual`, `admin` |
| `status` | text | `running`, `ok`, `partial`, `error`, `skipped` |
| `error_code` | text null | solo codici (sezione 4) |
| `strategy` | text null | `longest` o `default` |
| `date_from` | date null | richiesta |
| `history_from` | date null | ottenuta |
| `history_incomplete` | bool | predefinito `false` |
| `rows_received`, `raw_inserted`, `transactions_created`, `skipped_before_start`, `skipped_status`, `groups_shrunk`, `booked_then_cancelled` | int | predefinito 0 |
| `purchase_already_classified` | int | predefinito 0; sulla riga della connessione: movimenti di acquisti lasciati dai piani dell'esecuzione perché non più com'erano alla creazione (7.3); 0 sulle righe dei conti |
| `matched_transfers`, `matched_settlements`, `matched_installments` | int | predefinito 0; sulla riga della connessione: giroconti, conguagli e rate abbinati dall'esecuzione (sezione 7) |
| `amounts_rounded`, `rows_invalid` | int | predefinito 0: righe con l'importo arrotondato (6.3) e righe lasciate fuori dalla normalizzazione (`invalid_row`, sezione 4) |
| `started_at`, `finished_at` | timestamptz | |

RLS: **select** il membro proprietario della connessione (servirà agli avvisi nell'app); scrittura solo lato server. Solo codici e conteggi: nessun importo, descrizione o nome.

### Funzioni (tutte `security definer` tranne `check_bank_link`, che non legge tabelle; `set search_path = ''`, `execute` solo a `service_role`)
| Funzione | Cosa fa |
|---|---|
| `eb_set_credentials(user_id, app_id, private_key)` | crea o sostituisce il segreto `eb_private_key:<user_id>` in Vault e la riga di `eb_credentials` |
| `eb_get_credentials(user_id)` | `app_id` e chiave privata, da `vault.decrypted_secrets` |
| `create_link_request(member_id, aspsp_name, aspsp_country, psu_type, uses_global_app)` | nuova riga di `bank_link_requests`; restituisce l'`id` |
| `claim_link_request(id)` | segna la richiesta come usata se non scaduta né usata, in un'unica istruzione; restituisce la riga o niente |
| `eb_service_member(member_id)` | `member_id`, `user_id`, `household_id` e `start_date` di un membro attivo (`left_at` null) con un account (`user_id` non null); altrimenti `member_not_eligible` |
| `check_bank_link(link jsonb)` | controlla forma e tipi del collegamento per `complete_bank_link`; se sono sbagliati, `invalid_link` senza i valori nel messaggio |
| `complete_bank_link(request_id, link jsonb)` | completa il collegamento (sezione 3) in **una transazione**, con un lock sul membro: richiesta già reclamata e senza `result` (altrimenti `link_not_claimable`); connessione, conti, saldi ed email PayPal; `result = 'ok'`. Restituisce `connection_id` e il numero dei conti. Forma o tipi sbagliati: `invalid_link`, senza i valori nel messaggio |
| `finish_link_request(request_id, result)` | scrive l'esito `link_cancelled`, `link_rejected` o `link_failed` su una richiesta reclamata senza `result` (altrimenti `link_not_claimable`); nient'altro |
| `begin_sync_run(connection_id, trigger)` / `finish_sync_run(...)` | apertura e chiusura di `sync_runs`, con il controllo di un'esecuzione già in corso. `finish_sync_run` riceve in cima al `result`, con `strategy`, i tre `matched_*` e i conti, anche `purchase_already_classified` (7.3), che sulla riga della connessione si somma ai conteggi dei conti |
| `ingest_bank_rows(account_id, rows jsonb)` | importazione atomica (sezione 5), con un lock sul conto; restituisce i conteggi della riga del conto di `sync_runs`. Forma o tipi sbagliati: `invalid_rows`, senza i valori nel messaggio |
| `transfer_candidates(member_id, since)` | conti del membro con una connessione e non archiviati (`id`, `kind`, `connection_id`, `aspsp_name`, `cash_account_type`) e i loro movimenti importati con `movement_date` da `since` (`transaction_id`, `account_id`, importo con segno, valuta, data, controparte, descrizione e lo stato: `free` libero, `in_transfer` in un giroconto, `cancelled` in un giroconto, un conguaglio o un piano annullato), in un oggetto JSON. Membro non attivo: `member_not_eligible`; senza data: `invalid_since` |
| `apply_transfers(member_id, transfers jsonb)` | scrive i giroconti automatici proposti da `eb-sync` (7.1) in **una transazione**, con un `pg_advisory_xact_lock` sul membro, condiviso dagli abbinamenti della sezione 7, e **ricontrolla** ogni condizione: due conti diversi del membro, con una connessione e non archiviati; uscita e entrata sui loro conti, con segni, importo e valuta coerenti, ancora libere e non annullate; pagamento finanziato su un conto PayPal, in nessun giroconto e non annullato. Quello che non vale più si salta e non si conta. Righe con `kind = 'transfer'` e `transfer_id`, transazioni invariate. Restituisce il numero dei giroconti creati. Forma o tipi sbagliati: `invalid_transfers`, senza i valori nel messaggio; membro non attivo: `member_not_eligible` |
| `settlement_candidates(member_id, since)` | movimenti importati dei conti PayPal del membro con una connessione e non archiviati, con `movement_date` da `since` (`transaction_id`, `account_id`, importo con segno, valuta, data, `entry_reference` del grezzo, `counterpart_member_id`: il membro attivo della stessa casa, diverso dal membro, a cui appartiene l'email della controparte, oppure null, **mai l'email**; lo stato: `free` libero per i conguagli, `cancelled` in un giroconto, un conguaglio o un piano annullato) e i conguagli non eliminati del membro, come pagatore o ricevente, con `settled_on` da `since` − 3 giorni (id, pagatore, ricevente, importo, valuta, data, lati collegati e il riferimento della banca di ciascun lato), in un oggetto JSON. Membro non attivo: `member_not_eligible`; senza data: `invalid_since` |
| `apply_settlements(member_id, settlements jsonb)` | scrive i conguagli PayPal proposti da `eb-sync` (7.2), ognuno `{transaction_id, counterpart_member_id, settlement_id}` (`settlement_id` null = conguaglio nuovo), in **una transazione**: prende i `pg_advisory_xact_lock` del membro e di ogni controparte, in ordine di id, con la chiave condivisa dagli abbinamenti della sezione 7, poi blocca con `for update` le righe dei movimenti e i conguagli da collegare e **ricontrolla** ogni condizione: movimento del membro su un suo conto PayPal con connessione e non archiviato, EUR, ancora libero e non annullato; email della controparte ancora di quel membro, attivo e della stessa casa; per un collegamento, conguaglio non eliminato, stessa coppia e verso, stesso importo e valuta, ≤ 3 giorni, lato del membro vuoto; per una creazione, nessun conguaglio candidato; membri attivi con data di inizio ≤ `settled_on`. I collegamenti prima delle creazioni. Quello che non vale più si salta e non si conta. Righe con `kind = 'settlement'` e `settlement_id`, transazioni invariate. Restituisce il numero dei movimenti collegati. Forma o tipi sbagliati: `invalid_settlements`, senza i valori nel messaggio (mai un'email); membro non attivo: `member_not_eligible` |
| `installment_candidates(member_id, since)` | la data di inizio del membro; le righe del grezzo dei conti PayPal del membro con una connessione e non archiviati, `BOOK`, in EUR, in uscita, che sono una rata (`PAYMENT/LOAN`) o un acquisto (`PAYMENT/PAYMENT`) con una rata lo stesso giorno sullo stesso conto, su **tutto il grezzo** (`raw_id`, `account_id`, stato, data, importo con segno, valuta, codice e sottocodice; per gli acquisti il nome del creditore e `remittance_information`, **mai l'email**; il movimento collegato: `transaction_id`, `installment_plan_id` e lo stato, `free` libero come per i conguagli, `cancelled` in un giroconto, un conguaglio o un piano annullato); i piani dei conti PayPal del membro con una connessione e non archiviati, **anche eliminati** (`deleted`), con id, conto, acquisto, data, totale, numero di rate, rate prima dell'inizio, prossima scadenza e stato, in un oggetto JSON. `since` si controlla come per gli altri abbinamenti: le righe si leggono tutte, `eb-sync` collega solo le rate da `since`. Membro non attivo: `member_not_eligible`; senza data: `invalid_since` |
| `apply_installments(member_id, installments jsonb)` | scrive i piani proposti da `eb-sync` (7.3), ognuno `{plan_id, purchase_raw_id, first_raw_id, merchant, installments_before_start, installments_paid, last_installment_date, transaction_ids}`: `plan_id` null = piano nuovo, con acquisto, prima rata e `merchant`; altrimenti l'aggiornamento di un piano, senza; le rate pagate (nel grezzo), quelle prima dell'inizio, la data dell'ultima e i movimenti da collegare. In **una transazione**, con il `pg_advisory_xact_lock` del solo proprietario (chiave condivisa dagli abbinamenti della sezione 7) prima di rileggere e `for update` su grezzo e movimento dell'acquisto, piani e righe; **ricontrolla** ogni condizione: per una creazione acquisto e prima rata sui conti PayPal del membro con una connessione e non archiviati, `BOOK`, EUR, uscite `PAYMENT/PAYMENT` e `PAYMENT/LOAN` dello stesso giorno con `n` tra 2 e 12 e `|P − n·L| ≤ n`, nessun'altra prima rata per l'acquisto né altro acquisto per la rata, nessun piano per l'acquisto (anche eliminato), acquisto non annullato; per un aggiornamento un piano non eliminato di quei conti; `0 ≤ rate prima dell'inizio ≤ rate pagate ≤ n`, ultima rata non prima dell'acquisto; per un collegamento un movimento importato del conto del piano, `BOOK`, `PAYMENT/LOAN`, uscita in EUR dalla data dell'acquisto, con un importo vicino alle rate del piano, libero, non annullato e con posto nel piano. Stato e `next_due_date` dalle rate pagate e dall'ultima; un piano si aggiorna solo se cambia. Il movimento dell'acquisto si elimina o si conta come in 7.3. Quello che non vale più si salta e non si conta. Restituisce `{plans_created, matched_installments, purchase_already_classified}`. Forma o tipi sbagliati: `invalid_installments`, senza i valori nel messaggio; membro non attivo: `member_not_eligible` |
| `request_bank_sync(connection_id, trigger)` | `net.http_post` verso `eb-sync` con l'header `x-sync-secret`; URL del progetto e segreto letti da Vault. Senza l'URL o senza il segreto: errore con codice (`project_url_missing`, `sync_secret_missing`), nessuna chiamata |
| `sync_secret_matches(secret)` | confronto con il segreto in Vault; non lo restituisce mai |
| `schedule_bank_syncs()` | job `bank-sync` (sezione 10): `request_bank_sync(id, 'schedule')` per ogni connessione scelta, in ordine di id, ognuna in un blocco con la propria `exception`; l'errore di una connessione diventa un `warning` con il solo codice e non ferma le altre; mai un errore alla fine. Restituisce il numero delle richieste messe in coda |
| `expire_bank_consents()` | job `bank-consents` (sezione 10): connessioni `active` con `valid_until` passata → `status = 'expired'`, `last_error = 'consent_expired'`. Restituisce quante |
| `cleanup_bank_sync()` | job `bank-cleanup` (sezione 10): richieste di collegamento oltre 7 giorni, esecuzioni oltre 180 giorni tranne quella con l'ultima riga `ok` di ogni conto, esecuzioni dei job oltre 30 giorni. Restituisce i conteggi `{link_requests, connection_runs, account_runs, job_runs}` |

Alla cancellazione di una riga di `eb_credentials` (anche con l'account) un trigger cancella il suo segreto da Vault: la chiave privata non resta senza proprietario.

Vault contiene anche:
- `sync_cron_secret`: **generato dalla migrazione** con byte casuali se non esiste; nessuno lo vede né lo copia;
- `project_url`: URL del progetto, inserito a mano in ogni ambiente (non è un segreto, ma resta fuori dal repository).

## 10. Programmazione (`pg_cron`)

I job li crea la migrazione con `cron.schedule(nome, orario, comando)`, **per nome**: rilanciata, la migrazione aggiorna i job invece di duplicarli. Il comando è una sola `select` della funzione del job (sezione 9); i job girano come `postgres`, proprietario delle funzioni. Orari fissi in **UTC** (d'estate, in Italia, un'ora più tardi). Stessi job su `dev` e su `prod`.

| Job | Quando (UTC) | Funzione | Cosa fa |
|---|---|---|---|
| `bank-consents` | `0 6 * * *` (ogni giorno, prima del primo giro) | `expire_bank_consents()` | consensi scaduti |
| `bank-sync` | `10 6,12,19 * * *` (3 volte al giorno) | `schedule_bank_syncs()` | `request_bank_sync(id, 'schedule')` per ogni connessione scelta |
| `bank-cleanup` | `30 3 * * 0` (ogni domenica) | `cleanup_bank_sync()` | pulizia |

**Sincronizzazioni programmate** (`bank-sync`):
- **Connessioni scelte:** `status = 'active'`, membro proprietario attivo (`left_at` null) e **nessuna esecuzione** della connessione (riga della connessione in `sync_runs`, stato diverso da `skipped`) **iniziata nelle ultime 2 ore**: dopo un collegamento o una sincronizzazione a mano il giro programmato si salta, così tre sincronizzazioni più un collegamento restano nel limite di circa 4 accessi al giorno (sezione 4, "Limiti delle banche"). Una riga `skipped` non conta. Ordine fisso (id). Il resto (credenziali mancanti, consenso scaduto davanti alla banca) lo gestisce `eb-sync` con i suoi codici in `sync_runs`.
- Ogni richiesta sta in un blocco con la propria `exception` (sottotransazione): l'errore di una connessione **non ferma le altre** e diventa un `warning` con **solo il codice** (il messaggio se è una chiave `^[a-z_]{1,40}$`, altrimenti `internal`; mai valori). La funzione **non solleva mai un errore alla fine**: annullerebbe la transazione e con lei le richieste già messe in coda da `pg_net`, che partono solo al commit. Restituisce il numero delle richieste messe in coda. Senza `project_url` in Vault (come in CI) ogni richiesta finisce in un `warning` `project_url_missing` e non parte niente.
- Ogni chiamata lavora su **una connessione**, per stare nei limiti di CPU e durata delle Edge Functions; `eb-sync` ne apre una alla volta per connessione (sezione 4, punto 1). Tre sincronizzazioni lasciano margine sotto il limite delle banche per un nuovo tentativo con un periodo più corto (sezione 4, "Periodo rifiutato").

**Consensi scaduti** (`bank-consents`): le connessioni `active` con `valid_until` passata diventano `status = 'expired'` con `last_error = 'consent_expired'`; nessun'altra colonna cambia (il trigger dello schema aggiorna `version` e `updated_at`, come per ogni modifica). Una connessione senza `valid_until` resta com'è. Restituisce quante; rilanciato non cambia niente.

**Pulizia** (`bank-cleanup`):
- `bank_link_requests` con `created_at` più vecchia di 7 giorni;
- righe della connessione di `sync_runs` iniziate più di 180 giorni fa, con le righe dei loro conti (`run_id` in cascata), **tranne l'esecuzione che contiene l'ultima riga `ok` di ogni conto**: la finestra delle sincronizzazioni successive parte da lì (sezione 4, "Finestra scaricata"); senza, un conto rimasto in errore per sei mesi ripartirebbe dalla data di inizio;
- `cron.job_run_details` più vecchie di 30 giorni (per la fine dell'esecuzione; per l'inizio se non c'è la fine).

Restituisce i conteggi in un oggetto JSON: `link_requests`, `connection_runs` (righe della connessione), `account_runs` (righe dei conti), `job_runs`.

**Nessun keep-alive:** Supabase mette in pausa i progetti Free con poca attività in 7 giorni e non è chiaro se i job interni contino. Resta da verificare su `dev` e `prod` che la sincronizzazione tenga attivo il progetto; per ora nessun workflow né chiamata esterna.

## 11. Sicurezza e log

- Nei log delle funzioni e della CI solo passaggi, codici e conteggi: mai importi, descrizioni, controparti, email, IBAN, numeri di carta, `session_id`, `code`, `state`, JWT o chiavi. `eb-sync` registra anche la durata di ogni passo in millisecondi (passo `<nome>_ms`), per i limiti delle Edge Functions.
- `eb-callback` è pubblica: lo `state` è un uuid casuale, vale una volta e per 30 minuti; senza uno `state` valido il `code` non serve a niente.
- Le risposte delle funzioni all'app non contengono mai il grezzo.
- Nessun dato reale nei test: solo i dati sintetici della sezione 12.

## 12. Test

**Deno** (`deno test` nel job `functions` della CI, senza secrets né rete): client con risposte finte, normalizzazione, hash, abbinamenti come funzioni pure. **pgTAP**: funzioni SQL, permessi (app e `anon` non vedono grezzo, credenziali né richieste), `ingest_bank_rows`.

**Job** (pgTAP, sezione 10): i tre job in `cron.job` con nome, orario e comando, e `cron.schedule` rilanciato non li duplica; `schedule_bank_syncs()` senza `project_url` in Vault (come in CI): nessun errore, nessuna richiesta, ogni connessione scelta provata comunque; con l'URL e il segreto inseriti nel test: una richiesta in `net.http_request_queue` per ogni connessione scelta, verso `…/functions/v1/eb-sync`, con `connection_id` e `trigger = 'schedule'` nel corpo e l'header del segreto (mai confrontato né stampato); connessioni escluse (`expired`, `revoked`, `pending`, membro uscito, esecuzione iniziata un'ora fa) e incluse (esecuzione iniziata 3 ore fa, riga `skipped` recente); la richiesta fallita di una connessione non ferma le successive; `expire_bank_consents()` solo sulle `active` con `valid_until` passata, idempotente; `cleanup_bank_sync()`: richieste e righe vecchie cancellate (con le righe dei conti), recenti tenute, l'ultima `ok` di ogni conto tenuta anche se vecchia, conteggi; app e `anon` non eseguono le tre funzioni (`42501`), `service_role` sì.

**Dati sintetici** in `supabase/functions/_shared/testdata/eb/` (una sottocartella per formato della sezione 8; il `README.md` della cartella collega ogni caso ai suoi file): stessa struttura delle risposte di Enable Banking (sessione, conti, dettaglio, saldi, pagine di transazioni, errori), valori inventati; IBAN di esempio pubblici, carte palesemente finte, email `@example.com`; date intorno a una data di inizio inventata (1° marzo 2031). Casi obbligatori:
1. due righe identiche senza riferimento lo stesso giorno: si salvano entrambe; scaricate di nuovo, nessuna riga in più; una terza uguale il giorno dopo nella finestra sovrapposta: si aggiunge solo quella;
2. bollettino e commissione con riferimenti `-001` e `-002`;
3. spesa con data valuta prima della data di inizio e data contabile dopo: solo grezzo;
4. "Paga in 3 rate" a cavallo della data di inizio: acquisto e prima rata prima, seconda e terza dopo; piano con `installments_before_start = 1`, rate dopo l'inizio come movimenti, acquisto mai movimento; variante con la rata arrivata in una sincronizzazione successiva all'acquisto;
5. conguaglio PayPal visto dai due lati (Anna paga Bruno, date a un giorno di distanza): un solo conguaglio con i due lati;
6. trasferimento del saldo PayPal alla banca: giroconto, nessuna entrata;
7. addebito diretto verso PayPal che finanzia un pagamento di due giorni prima; un secondo addebito senza pagamento corrispondente (giroconto senza `funded_transaction_id`); lo stesso senza un conto PayPal collegato (resta da classificare);
8. ricarica di un conto prepagato dalla banca: giroconto con i due lati;
9. addebito mensile della carta: giroconto conto → carta;
10. righe `RJCT` e `CNCL`: solo grezzo;
11. importi `4.4`, `1`, `12.50`;
12. nome del conto con spazi in coda; conto senza nome;
13. `422 WRONG_TRANSACTIONS_PERIOD` con un messaggio che parla di consenso scaduto: nuovo tentativo con un periodo più corto, `history_incomplete`, connessione ancora `active`;
14. risposta su più pagine con `continuation_key`; una pagina fallita: conto non importato;
15. saldi: conto con `CLBD`, `XPCD`, `OTHR`; carta con debito negativo; PayPal con EUR e USD;
16. riga `PDNG` che torna `BOOK`, con e senza riferimento: un solo movimento;
17. stipendio (entrata) con controparte;
18. giroconto automatico annullato (`deleted_at`): rilanciando gli abbinamenti non si ricrea;
19. due candidati alla pari per lo stesso giroconto: nessun abbinamento.

**Forma delle risposte vere:** `supabase/scripts/eb-shape.ts`, lanciato a mano dal PC con il solo permesso di lettura delle due cartelle, legge una cartella di risposte vere (fuori dal repository) e stampa per classe (pagina di transazioni, saldi, sessione, dettaglio del conto, errore, altro) i percorsi delle chiavi, i tipi, i conteggi e i segnali di formato: mai un valore né il nome di un file. Con `--compare <dati sintetici>` elenca le chiavi e i tipi che mancano nei dati sintetici e dove stanno le stringhe simili a un'email nelle transazioni; i dati sintetici si completano finché non manca niente.

Le prove con la banca finta di Enable Banking (Sandbox, Mock ASPSP) si fanno a mano dal PC, mai in CI.

## 13. Rilascio

- **Rilascio** (`release.yml`, environment `prod`): su un tag `v*` o avviato a mano da `main`, mai da un altro branch; CLI di Supabase alla versione fissata nel workflow. `supabase link`, poi `supabase db push --dry-run --remote`, che elenca le migrazioni da applicare e fallisce se `prod` ne ha una che il repository non ha. Avviato a mano ha l'opzione **prova** (predefinita sì), che si ferma qui. Altrimenti `supabase db push --remote` **senza seed**, `supabase migration list --remote` (le migrazioni di `prod` devono essere quelle del repository) e deploy di tutte le Edge Functions con la loro configurazione di `config.toml`. Nel log solo l'elenco delle migrazioni (nomi dei file del repository), il confronto locale/remoto e i nomi delle funzioni; ref del progetto, URL e password mascherati; nessun artifact. Su `dev` migrazioni e funzioni si portano dal PC con la CLI, sempre con `--remote`, dalla radice del repository.
- **Backup:** per ora non è previsto alcun backup del database.
- I segreti di Vault non si possono decifrare fuori dal progetto: dopo un ripristino su un progetto nuovo le chiavi private si salvano di nuovo con `eb-credentials`.

## 14. Fuori da questa specifica

- Schermate di collegamento, rinnovo del consenso, aggiornamento manuale con l'utente presente e avvisi nell'app (Conti e Impostazioni).
- App Link verso l'app dalla pagina di ritorno (con gli inviti).
- Valute estere oltre alle colonne; transazioni provvisorie dalle notifiche delle app bancarie.
- Regole di categoria per controparte.
