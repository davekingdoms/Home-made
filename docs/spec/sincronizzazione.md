# Sincronizzazione bancaria

Specifica della sincronizzazione con le banche tramite Enable Banking: collegamento, credenziali, importazione dal grezzo, deduplicazione, normalizzazione, giroconti automatici, conguagli PayPal, piani a rate, programmazione. Tabelle e vincoli di partenza in [`schema.md`](schema.md); qui le tabelle nuove e le regole delle funzioni lato server. Esempi inventati (Anna, Bruno, Carla, "Casa di prova", date del 2031, email `@example.com`).

Tutto avviene **lato server**: Edge Functions (Deno, TypeScript) con la service role e funzioni SQL `security definer` eseguibili solo dalla service role. L'app non legge mai il grezzo né le credenziali e non chiama mai Enable Banking.

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
| Pagina di ritorno | `infra/pages/` (Cloudflare Pages) | mostra l'esito del collegamento |
| Script di servizio | `supabase/scripts/eb-admin.ts` | uso da riga di comando per lo sviluppo, con la chiave service role dell'ambiente |

Configurazione delle Edge Functions (secrets di Supabase, mai nel repository):

| Nome | Contenuto |
|---|---|
| `EB_REDIRECT_URL` | URL di `eb-callback` dell'ambiente, registrato nell'applicazione Enable Banking |
| `APP_RETURN_URL` | URL della pagina di ritorno su Pages |
| `EB_GLOBAL_APP_ID`, `EB_GLOBAL_PRIVATE_KEY` | facoltativi: applicazione globale di ripiego, usata solo se la persona non ha credenziali proprie |

`SUPABASE_URL` e la chiave service role arrivano dall'ambiente delle Edge Functions. In `supabase/config.toml`: `verify_jwt = false` per `eb-callback` ed `eb-sync`, che fanno i propri controlli.

### Autenticazione delle Edge Functions
- **Utente** (app, più avanti): JWT di Supabase; il membro è `current_member_id()` dell'utente.
- **Servizio** (script di servizio, job): chiave service role nell'header `Authorization`; il membro o la connessione arrivano nel corpo della richiesta.
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
   - `POST /sessions` con il `code` → sessione, conti, `access.valid_until`;
   - crea o aggiorna `bank_connections` (`status = 'active'`, `session_id`, `valid_until`, `uses_global_app`);
   - crea o aggiorna i conti (sezione 6.4) e i saldi (sezione 6.5); per PayPal aggiunge l'email del conto a `paypal_emails` con `source = 'linked_account'` (se l'email è già di un'altra persona: niente riga, codice `paypal_email_taken` in `sync_runs`);
   - chiede la **prima sincronizzazione** con `request_bank_sync(connection_id, 'link')`, che parte subito, entro l'ora concessa dalle banche per lo storico lungo;
   - risponde `302` verso `APP_RETURN_URL?esito=ok` (oppure `esito=annullato|errore&codice=<codice>`). **Nell'URL di ritorno solo l'esito e il codice**: mai id, nomi o importi.
8. Un conto già noto (stesso proprietario, stesso tipo, stesso `identifier`) si aggiorna invece di crearne uno nuovo, così una nuova autorizzazione della stessa banca non duplica i conti.

Errori di Enable Banking, rete o database durante il ritorno: esito `errore`, codice `link_failed`, connessione con `status = 'error'` e `last_error`.

## 4. Sincronizzazione di una connessione

`eb-sync` riceve `connection_id` e `trigger` (`link`, `schedule`, `manual`, `admin`). Risponde subito `202` e lavora in `EdgeRuntime.waitUntil`, così la chiamata da `pg_net` non resta appesa.

1. **Un'esecuzione alla volta:** `begin_sync_run` apre la riga in `sync_runs`; se ce n'è già una `running` da meno di 15 minuti, niente (`already_running`).
2. **Consenso:** `GET /sessions/{session_id}`. Sessione scaduta o revocata → `status = 'expired'` o `'revoked'`, `last_error = 'consent_expired'` o `'consent_revoked'`, fine. Il consenso **non** si deduce mai dal testo di un errore sulle transazioni.
3. Per ogni conto della connessione non archiviato:
   - **saldi:** `GET /accounts/{uid}/balances` (sezione 6.5);
   - **transazioni:** `GET /accounts/{uid}/transactions` con `date_from` e `strategy` della tabella sotto, seguendo `continuation_key` fino all'ultima pagina;
   - **un conto si importa solo con tutte le pagine scaricate**: una pagina fallita lascia il conto com'era (`status = 'partial'` per la connessione).
4. Importazione con `ingest_bank_rows` (sezione 5), poi gli abbinamenti del membro (sezione 7).
5. Chiusura della riga di `sync_runs`; su `bank_connections` `last_sync_at`, e `last_success_at` se tutti i conti sono riusciti.

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
- Le sincronizzazioni senza l'utente presente sono limitate da molte banche a circa **4 al giorno** per conto. Una risposta di limite superato (`429` o il codice equivalente di Enable Banking) ferma la connessione fino al giro successivo, con `last_error = 'rate_limited'`.
- La prima sincronizzazione avviene con l'utente appena tornato dalla banca.
- Gli header facoltativi dell'utente presente (`Psu-Ip-Address`, `Psu-User-Agent`) arriveranno con l'aggiornamento manuale dall'app.

### Codici d'errore
Su `bank_connections.last_error` e `sync_runs.error_code` vanno **solo codici**, mai il testo della banca: `period_rejected`, `consent_expired`, `consent_revoked`, `rate_limited`, `no_credentials`, `invalid_credentials`, `bank_unavailable`, `bank_error`, `link_expired`, `link_cancelled`, `link_rejected`, `link_failed`, `already_running`, `paypal_email_taken`, `internal`. La tabella dagli errori di Enable Banking (campo `error` della risposta, stato HTTP) a questi codici sta nel client, con i test.

## 5. Grezzo e deduplicazione

Ogni transazione restituita dalla banca diventa una riga di `bank_raw_transactions` (tutte, anche `RJCT`, `CNCL`, `PDNG` e quelle prima della data di inizio). `ingest_bank_rows(account_id, rows)` riceve le righe già normalizzate (sezione 6) e fa tutto in **una transazione** con un `pg_advisory_xact_lock` sul conto:

1. **Con `entry_reference`:** insert con conflitto su (`account_id`, `entry_reference`) ignorato. **Eccezione:** se la riga salvata è `PDNG` e quella nuova è `BOOK`, la riga salvata si aggiorna (stato, date, importo, payload).
2. **Senza `entry_reference`:** si raggruppano le righe scaricate per `dedup_hash`. Per ogni gruppo, `n` = righe scaricate, `m` = righe già salvate con quell'hash sul conto: se `n > m` si inseriscono le righe con ordinali `m + 1 … n`; se `n ≤ m` non si fa niente (`n < m` si conta in `sync_runs.groups_shrunk`). **Una riga uguale a un'altra non si scarta mai.** I gruppi sono completi perché l'hash contiene le date e un conto si importa solo con tutte le pagine (sezione 4).
3. Per le righe nuove (o passate da `PDNG` a `BOOK`) che diventano movimenti (sezione 6.1) si crea la transazione; `bank_raw_transactions.transaction_id` la collega.
4. Restituisce i conteggi: righe ricevute, nuove, movimenti creati, saltate per data o stato.

**`dedup_hash`** = SHA-256 in esadecimale di
`booking_date|value_date|transaction_date|status|segno|importo_in_centesimi|descrizione`
con le date in ISO (vuote se mancano), segno `D` o `C`, descrizione normalizzata (sezione 6.3). Lo **stato** fa parte dell'hash: una riga `PDNG` che torna `BOOK` è un gruppo diverso, quindi la versione contabilizzata non viene scambiata per un doppione della provvisoria.

## 6. Dal grezzo al movimento

### 6.1 Quali righe diventano movimenti
- solo `status = 'BOOK'`;
- `movement_date` ≥ data di inizio del **membro proprietario del conto**: una spesa precedente contabilizzata dopo la data di inizio resta solo nel grezzo;
- non è l'acquisto di un piano a rate (sezione 7.3);
- `PDNG`, `RJCT`, `CNCL` restano solo nel grezzo. Una riga già diventata movimento che più avanti arriva `CNCL` non si tocca: si conta in `sync_runs.booked_then_cancelled`.

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
- **Importi:** testo con il punto decimale e un numero variabile di decimali (`4.4`, `1`, `12.50`): si converte in centesimi interi senza passare dai numeri a virgola mobile. Più di due decimali: si arrotonda al centesimo con metà verso l'alto e si conta in `sync_runs`.
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

Dopo ogni sincronizzazione, per il **membro proprietario** della connessione, sui suoi movimenti degli ultimi **45 giorni**, in quest'ordine: piani a rate, conguagli PayPal, giroconti. Regole comuni:
- **idempotenti:** rilanciati non cambiano niente;
- toccano solo transazioni con **una sola riga**, senza tipo e non collegate;
- non ricreano mai un collegamento **annullato**: una transazione che compare in un giroconto, un conguaglio o un piano con `deleted_at` non si abbina più in automatico;
- con **più candidati alla pari** non si abbina niente: il movimento resta da classificare (meglio una classificazione a mano che un abbinamento sbagliato).

### 7.1 Giroconti (`transfers.origin = 'auto'`)
Le righe collegate prendono `kind = 'transfer'` e `transfer_id`.

| Caso | Riconoscimento | Giroconto |
|---|---|---|
| Tra due conti dello stesso membro (es. ricarica di un conto prepagato) | stesso importo, segno opposto, conti diversi, date a distanza ≤ 3 giorni; se uno dei due conti è PayPal, la controparte del lato bancario contiene "PAYPAL" | da: conto dell'uscita; a: conto dell'entrata; entrambi i lati |
| Addebito mensile della carta di credito | uscita sul conto con la descrizione dell'addebito della carta (sezione 8), di un membro che ha una carta nella stessa connessione | da: conto; a: carta; lato in entrata = l'accredito sulla carta con lo stesso importo entro 5 giorni, se c'è |
| Banca o carta → PayPal | uscita la cui controparte è PayPal (addebito diretto o pagamento con carta verso PayPal), **solo se il membro ha un conto PayPal collegato**; senza, resta da classificare | da: conto o carta; a: conto PayPal; `in_transaction_id` vuoto; `funded_transaction_id` = l'uscita PayPal con lo stesso importo e data tra 7 giorni prima e il giorno dell'addebito, non già finanziata, se c'è. **L'abbinamento con il pagamento non decide il tipo**: l'addebito è un giroconto anche senza pagamento corrispondente |
| PayPal → banca (trasferimento del saldo) | primo caso della tabella | da: PayPal; a: banca. **Mai un'entrata** |

### 7.2 Conguagli PayPal (`settlements.origin = 'paypal'`)
- **Lato di chi paga:** uscita su un conto PayPal di Anna, in EUR, con `counterparty_email` uguale a un'email di `paypal_emails` di Bruno, **membro attivo della stessa casa**. Se c'è un conguaglio con pagatore Anna, ricevente Bruno, stesso importo, EUR, `settled_on` a distanza ≤ 3 giorni, lato del pagatore libero e non eliminato, il movimento si collega a quello; altrimenti nasce un conguaglio con `settled_on` = data del movimento e `created_by_member_id` null.
- **Lato di chi riceve:** entrata su un conto PayPal di Bruno con l'email di Anna come controparte: stessa regola, sul lato del ricevente.
- Se l'ID della transazione PayPal risulta uguale sui due lati, l'abbinamento usa quello prima della regola su importo e data.
- La riga prende `kind = 'settlement'` e `settlement_id`. Valgono i vincoli dello schema: date di inizio dei due membri non successive a `settled_on`, membri attivi.
- In un'altra valuta: niente conguaglio automatico, il movimento resta da classificare.

### 7.3 Piani a rate (PayPal "Paga in 3 rate")
- **Acquisto:** uscita `PAYMENT/PAYMENT` di importo `P` su un conto PayPal, con lo stesso giorno un'uscita `PAYMENT/LOAN` (creditore PayPal) di importo `L` tale che `n = round(P / L)` è tra 2 e 12 e `|P − n·L| ≤ n` centesimi. La ricerca si fa **sul grezzo**, compresi i 90 giorni prima della data di inizio.
- **Piano:** `merchant` = controparte dell'acquisto, `total_cents` = `P`, `installments_count` = `n`, `purchase_date`, `purchase_raw_id`, `account_id` = conto PayPal, `status = 'active'`.
- **Rate:** le uscite `PAYMENT/LOAN` dello stesso conto con importo `L` (±1 centesimo; l'ultima rata può differire di qualche centesimo), dalla data dell'acquisto, a distanza ≥ 20 giorni dalla rata precedente, si collegano al piano attivo più vecchio con quell'importo e meno di `n` rate. Una rata diventata movimento prende `installment_plan_id`; se il piano ha già categoria e pesi, la rata li prende (tipo `expense`), altrimenti resta da classificare.
- `installments_before_start` = rate con data precedente alla data di inizio del membro (nel grezzo, fuori dal bilancio). `next_due_date` = ultima rata + 30 giorni finché il piano è attivo; `status = 'completed'` alla rata `n`.
- **L'acquisto non è mai un movimento.** Se è già diventato una transazione (la rata è arrivata dopo), il server la elimina e azzera `transaction_id` sul grezzo, ma solo se è ancora com'era alla creazione (`version = 1`, una riga senza tipo); altrimenti la lascia e lo conta in `sync_runs.purchase_already_classified`.
- I pagamenti della banca o della carta verso PayPal che finanziano le rate sono giroconti (7.1).

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
| `BON. ISTANTANEO A DEBITO ANNA ESEMPIO … RICARICA` | `ANNA ESEMPIO` |
| `ADDEBITO MESE CARTA EGO` | null → addebito mensile della carta (7.1) |

Il conto bancario arriva con un secondo conto `CARD` nella stessa sessione. Il campo `debtor_account` sulle uscite è il conto stesso: non è una controparte.

**Credito Emiliano, carta (`CARD`)**: solo `transaction_date`; nessun `entry_reference` né codice (deduplicazione solo per gruppi); descrizione `ESERCENTE CITTÀ PAESE` → si toglie il codice paese di 2 lettere in fondo, poi l'ultima parola (la città): `FERRAMENTA PROVA CITTAPROVA IT` → `FERRAMENTA PROVA`. Importi con decimali variabili. Saldi `CLBD` (debito, negativo) e `OTHR` (disponibilità residua).

**HYPE**: nome del conto vuoto; `entry_reference` solo sulle entrate; codici `pos` (pagamento con carta) e `boi` (entrata, es. ricarica); descrizione `NOME CITTÀ PROV` → si toglie la sigla di 2 lettere in fondo e l'ultima parola: `CAFFE ESEMPIO CITTAPROVA ZZ` → `CAFFE ESEMPIO`. Saldi `ITBD` e `ITAV`.

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
| `trigger` | text | `link`, `schedule`, `manual`, `admin` |
| `status` | text | `running`, `ok`, `partial`, `error`, `skipped` |
| `error_code` | text null | solo codici (sezione 4) |
| `strategy` | text null | `longest` o `default` |
| `date_from` | date null | richiesta |
| `history_from` | date null | ottenuta |
| `history_incomplete` | bool | predefinito `false` |
| `rows_received`, `raw_inserted`, `transactions_created`, `skipped_before_start`, `skipped_status`, `groups_shrunk`, `booked_then_cancelled`, `purchase_already_classified` | int | predefinito 0 |
| `matched_transfers`, `matched_settlements`, `matched_installments` | int | predefinito 0 |
| `started_at`, `finished_at` | timestamptz | |

RLS: **select** il membro proprietario della connessione (servirà agli avvisi nell'app); scrittura solo lato server. Solo codici e conteggi: nessun importo, descrizione o nome.

### Funzioni (tutte `security definer`, `set search_path = ''`, `execute` solo a `service_role`)
| Funzione | Cosa fa |
|---|---|
| `eb_set_credentials(user_id, app_id, private_key)` | crea o sostituisce il segreto `eb_private_key:<user_id>` in Vault e la riga di `eb_credentials` |
| `eb_get_credentials(user_id)` | `app_id` e chiave privata, da `vault.decrypted_secrets` |
| `create_link_request(member_id, aspsp_name, aspsp_country, psu_type, uses_global_app)` | nuova riga di `bank_link_requests`; restituisce l'`id` |
| `claim_link_request(id)` | segna la richiesta come usata se non scaduta né usata, in un'unica istruzione; restituisce la riga o niente |
| `begin_sync_run(connection_id, trigger)` / `finish_sync_run(...)` | apertura e chiusura di `sync_runs`, con il controllo di un'esecuzione già in corso |
| `ingest_bank_rows(account_id, rows jsonb)` | importazione atomica (sezione 5) |
| `request_bank_sync(connection_id, trigger)` | `net.http_post` verso `eb-sync` con l'header `x-sync-secret`; URL del progetto e segreto letti da Vault |
| `sync_secret_matches(secret)` | confronto con il segreto in Vault; non lo restituisce mai |

Vault contiene anche:
- `sync_cron_secret`: **generato dalla migrazione** con byte casuali se non esiste; nessuno lo vede né lo copia;
- `project_url`: URL del progetto, inserito a mano in ogni ambiente (non è un segreto, ma resta fuori dal repository).

## 10. Programmazione (`pg_cron`)

| Job | Quando (UTC) | Cosa fa |
|---|---|---|
| `bank-sync` | `10 6,12,19 * * *` (3 volte al giorno) | `request_bank_sync(id, 'schedule')` per ogni connessione `active` |
| `bank-consents` | ogni giorno | connessioni con `valid_until` passata → `status = 'expired'`, `last_error = 'consent_expired'` |
| `bank-cleanup` | ogni settimana | `bank_link_requests` più vecchie di 7 giorni; `sync_runs` più vecchie di 180 giorni |

Tre sincronizzazioni lasciano margine sotto il limite di circa 4 accessi al giorno per un nuovo tentativo con un periodo più corto. Ogni chiamata lavora su **una connessione**, per stare nei limiti di CPU e durata delle Edge Functions.

## 11. Sicurezza e log

- Nei log delle funzioni e della CI solo passaggi, codici e conteggi: mai importi, descrizioni, controparti, email, IBAN, numeri di carta, `session_id`, `code`, `state`, JWT o chiavi.
- `eb-callback` è pubblica: lo `state` è un uuid casuale, vale una volta e per 30 minuti; senza uno `state` valido il `code` non serve a niente.
- Le risposte delle funzioni all'app non contengono mai il grezzo.
- Nessun dato reale nei test: solo i dati sintetici della sezione 12.

## 12. Test

**Deno** (`deno test` nel job `functions` della CI, senza secrets né rete): client con risposte finte, normalizzazione, hash, abbinamenti come funzioni pure. **pgTAP**: funzioni SQL, permessi (app e `anon` non vedono grezzo, credenziali né richieste), `ingest_bank_rows`.

**Dati sintetici** in `supabase/functions/_shared/testdata/`: stessa struttura delle risposte di Enable Banking (sessione, conti, dettaglio, saldi, pagine di transazioni, errori), valori inventati; IBAN di esempio pubblici, carte palesemente finte, email `@example.com`; date intorno a una data di inizio inventata (1° marzo 2031). Casi obbligatori:
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

Le prove con la banca finta di Enable Banking (Sandbox, Mock ASPSP) si fanno a mano dal PC, mai in CI.

## 13. Rilascio e backup

- **Rilascio** (`release.yml`): su un tag `v*` o avviato a mano da `main`, environment `prod`: `supabase link`, `supabase db push` **senza seed**, deploy di tutte le Edge Functions. Il ref del progetto è mascherato nel log. Su `dev` migrazioni e funzioni si portano dal PC con la CLI.
- **Backup** (`backup.yml`, ogni notte, environment `prod`): `pg_dump` dal pooler in modalità sessione, cifrato con `age`, caricato su un bucket R2 con giurisdizione EU in `daily/` (e il primo del mese anche in `monthly/`); la conservazione la fanno le regole del bucket (30 giorni per `daily/`, 365 per `monthly/`). **Prova di ripristino** (`restore-check.yml`, ogni mese e a mano): scarica l'ultimo dump, lo decifra, lo ripristina in un Postgres temporaneo e controlla che sia più recente di 36 ore e che le tabelle principali abbiano gli stessi conteggi del database, con la tolleranza delle righe nate dopo il dump. Nei log solo gli esiti; nessun dump come artifact.
- I segreti di Vault non si possono decifrare fuori dal progetto: dopo un ripristino su un progetto nuovo le chiavi private si salvano di nuovo con `eb-credentials`.

## 14. Fuori da questa specifica

- Schermate di collegamento, rinnovo del consenso, aggiornamento manuale con l'utente presente e avvisi nell'app (Conti e Impostazioni).
- App Link verso l'app dalla pagina di ritorno (con gli inviti).
- Valute estere oltre alle colonne; transazioni provvisorie dalle notifiche delle app bancarie.
- Regole di categoria per controparte.
