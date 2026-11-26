# Schema dati

Specifica dello schema del database (Supabase, Postgres 17) per la fase 1: casa da 1 a N membri, conti e sincronizzazione bancaria, transazioni divise in righe con quote per membro, giroconti, rate, conguagli, salvadanai, anticipi. Regole di comportamento in [`accesso.md`](accesso.md) e [`categorie.md`](categorie.md). Esempi inventati (Anna, Bruno, Carla, "Casa di prova").

Le migrazioni stanno in `supabase/migrations/`, i test pgTAP in `supabase/tests/database/`. Nessun seed contiene dati di una casa reale: solo l'elenco generico delle categorie.

## 1. Convenzioni

- **Nomi** di tabelle, colonne e funzioni in inglese, `snake_case`; tutto nello schema `public`, salvo Vault.
- **Identificativi:** `uuid`, con `default gen_random_uuid()`. Le righe create dall'app (movimenti manuali, righe, conguagli, dispositivi…) arrivano con l'id **generato sul dispositivo**: alla sincronizzazione della coda offline si sommano senza conflitti, e una seconda chiamata con lo stesso id non crea doppioni.
- **Importi** in centesimi, `bigint`. Le transazioni e le righe hanno il **segno**: negativo = uscita, positivo = entrata. Le quote hanno lo stesso segno della riga. Gli altri importi (conguagli, obiettivi, anticipi) sono positivi.
- **Valuta:** codice ISO 4217 in `char(3)`; `XXX` per un conto multivaluta.
- **Date:** `date` per le date dei movimenti e le date di inizio; `timestamptz` per tutto il resto.
- **Colonne comuni** su ogni tabella che si modifica: `version int not null default 1`, `created_at`, `updated_at`. Un trigger comune (`touch_row`) incrementa `version` e aggiorna `updated_at` a ogni `update`.
- **Conflitti** (regola dell'app): l'app aggiorna con il filtro `version = <versione letta>`. Se non cambia nessuna riga, la riga è stata modificata altrove: l'app rilegge, riapplica la propria modifica (vince l'ultima) e mostra "Modificata da un altro dispositivo" o "da un altro membro".
- **Eliminazione logica** (`deleted_at`) per movimenti manuali, righe, giroconti, conguagli, piani a rate e voci dei salvadanai. Le righe con `deleted_at` restano visibili a chi le vedeva, così la cache dei dispositivi le toglie; non contano in nessun calcolo.
- **RLS** attiva su ogni tabella; `anon` non ha nessun permesso. Le funzioni di supporto e quelle che toccano più righe sono `security definer` con `set search_path = ''` e nomi completi (`public.…`). Nelle policy `auth.uid()` si scrive `(select auth.uid())`.
- **Operazioni su più righe** passano da funzioni (RPC), perché ogni chiamata REST è una transazione a sé e i vincoli sulle somme verrebbero violati a metà.
- **Insert dall'app su `accounts`, `transactions`, `transaction_lines` e `piggy_banks`:** senza chiedere indietro la riga (niente `RETURNING`, cioè `return=minimal`) e senza `upsert`, perché la policy di select cerca la riga per id e una riga nuova non c'è ancora. L'id è già sul dispositivo; un secondo insert con lo stesso id dà `23505`, cioè la riga è già salvata.
- **Errori delle funzioni:** `raise exception` con codice `P0001` e un messaggio-chiave in inglese (`invite_expired`, `household_full`…), che l'app traduce nei testi delle schermate. **Eccezione:** `invite_preview` e `redeem_invite` non sollevano i propri errori ma restituiscono la chiave nella colonna `error` (null se è andata bene): un errore sollevato annullerebbe anche la riga di `invite_attempts`, e i tentativi falliti, quelli da limitare, non conterebbero mai.

## 2. Funzioni di supporto

| Funzione | Restituisce |
|---|---|
| `current_member_id()` | Il membro attivo (`left_at is null`) dell'utente collegato, o `null`. Un account sta in una sola casa. |
| `current_household_id()` | La casa di quel membro. |
| `is_household_member(household_id)` | Vero se l'utente è un membro attivo di quella casa. |
| `is_account_owner(account_id)` | Vero se il conto appartiene al membro attivo dell'utente. **Unico punto** in cui si decide la proprietà di un conto: un futuro conto cointestato cambierà solo questa funzione. |
| `can_see_transaction(transaction_id)` | Vero se l'utente è il proprietario del conto o, per un movimento manuale senza conto, chi l'ha inserito o chi l'ha pagato. |
| `can_see_line(line_id)` | Vero se: vede la transazione; oppure è chi ha pagato la riga o ha una quota; oppure la riga è un'entrata di un membro che mostra le proprie entrate, con data dalla data di inizio di chi guarda (sezione 7). |
| `max_household_members()` | `8`. Contano i membri attivi e gli inviti aperti. Per cambiarlo basta una migrazione di una riga. |
| `split_cents(amount, weights, payer)` | La ripartizione in centesimi (sezione 6). |

## 3. Account, casa e membri

### `profiles` — scheda pubblica dell'account nella casa
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | = `auth.users.id`, `on delete cascade` |
| `display_name` | text | 1–80 caratteri dopo `btrim` |
| `avatar_url` | text null | foto dell'account Google |
| `paypal_me` | text null | nome PayPal.Me, 1–20 caratteri alfanumerici (regole esatte da verificare con il link PayPal.Me) |
| `is_demo` | bool | predefinito `false`; account demo, solo sviluppo ([`accesso.md`](accesso.md), sezione 12) |
| comuni | | `version`, `created_at`, `updated_at` |

RLS: **select** il proprietario e i membri attivi della stessa casa, solo se il profilo è di un membro attivo (chi è uscito compare come "Ex membro"); **insert** e **update** solo il proprietario; nessun delete (va con l'account).
Trigger (`check_profile_demo`, security definer perché legge l'interruttore): all'inserimento `is_demo = true` solo con l'interruttore degli account demo acceso (`demo_disabled`); poi `is_demo` non cambia mai, in nessun verso (`demo_immutable`).

### `user_settings` — impostazioni private dell'account
| Colonna | Tipo | Note |
|---|---|---|
| `user_id` | uuid PK | → `profiles.id`, `on delete cascade` |
| `privacy_notice_version`, `privacy_notice_read_at` | text, timestamptz | entrambe nulle o entrambe valorizzate |
| `show_income` | bool | predefinito `true`: le proprie entrate visibili agli altri membri |
| `preferences` | jsonb | predefinito `{}`; preferenze dell'account (chiavi decise con le impostazioni) |
| comuni | | |

RLS: tutto solo il proprietario. `show_income` lo legge `can_see_line` (security definer).

### `households`
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `name` | text | 1–80 caratteri |
| `start_date` | date | data di inizio della casa |
| `created_by` | uuid | → `profiles.id` (`on delete set null`); solo informazione, nessun permesso in più |
| comuni | | |

RLS: **select** i membri attivi; **update** del solo `name` i membri attivi (permesso sulla colonna); `start_date` cambia solo con una funzione futura (Impostazioni › Casa, con conferma). Insert solo con `create_household`.

### `members`
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `household_id` | uuid | → `households` |
| `user_id` | uuid null | → `profiles.id`, `on delete set null`: con l'account eliminato il membro resta come "Ex membro" |
| `joined_at` | timestamptz | |
| `start_date` | date | data di inizio del membro; ≥ `households.start_date` |
| `left_at` | timestamptz null | |
| comuni | | |

Vincoli: indice unico su `user_id` dove `left_at is null` (**un account in una sola casa**). Nella fase 1 ogni membro ha un account: lo garantiscono le funzioni di creazione, non lo schema (`user_id` resta nullable).
RLS: **select** i membri attivi della stessa casa (compresi i membri usciti, per mostrare "Ex membro"); nessuna scrittura diretta.

### `invites`
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `household_id` | uuid | |
| `created_by_member_id` | uuid | |
| `label` | text null | "per chi", facoltativa |
| `token_hash` | bytea unique | SHA-256 del token lungo del link; il token non si salva |
| `code` | text unique | 8 caratteri da un alfabeto senza caratteri ambigui (niente `0 O 1 I L`); mostrato in due gruppi da 4 |
| `expires_at` | timestamptz | creazione + 7 giorni |
| `used_by_member_id`, `used_at` | null | |
| `revoked_at` | timestamptz null | |
| `created_at` | timestamptz | |

RLS: **select** i membri attivi della casa (senza `token_hash`: permesso sulle colonne); **update** di `revoked_at` i membri attivi; insert e uso solo con le funzioni. `revoked_at` si imposta una volta sola: da null a una data, poi non cambia né torna null, nemmeno dal server (`invite_revoked`).

### `invite_attempts`
`user_id`, `attempted_at`. Nessun accesso dall'app. Lo usano `invite_preview` e `redeem_invite`: al massimo **10 tentativi all'ora** per account (`too_many_attempts`).

### `devices`
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | generato sul dispositivo alla prima apertura |
| `user_id` | uuid | |
| `platform` | text | `android` (in futuro `ios`) |
| `name` | text null | modello, per l'elenco dei dispositivi |
| `fcm_token` | text null | arriva con le notifiche push |
| `preferences` | jsonb | predefinito `{}`; **vince su quelle dell'account** per le stesse chiavi |
| `last_seen_at` | timestamptz | |
| comuni | | |

RLS: tutto solo il proprietario. La posizione per il meteo **non** si salva qui né altrove sul server.

### Funzioni di casa e inviti
| Funzione | Cosa fa | Errori |
|---|---|---|
| `create_household(id, name, start_date, cash_opening_cents)` | Crea la casa, il creatore come primo membro con la data di inizio della casa, poi (dai trigger) il conto Contanti, le quote predefinite e le categorie iniziali. Se `start_date` è oggi, `cash_opening_cents` (facoltativo) diventa il saldo iniziale dei contanti. | `no_profile`, `already_member`, `start_date_out_of_range` (da 90 giorni prima a 12 mesi dopo, con un giorno di tolleranza per i fusi orari) |
| `create_invite(label)` | Crea un invito; restituisce token e codice (unica volta in cui il token esiste in chiaro). | `not_member`, `household_full` |
| `invite_preview(code \| token)` | Prima di entrare: nome e data di inizio della casa (`household_start_date`), chi invita, nomi dei membri attivi. | nella colonna `error`: `invite_invalid`, `invite_expired`, `invite_used`, `invite_revoked`, `too_many_attempts` |
| `redeem_invite(code \| token, cash_opening_cents, start_date)` | Crea il membro con la data di inizio `start_date`, tra la data di inizio della casa e domani (un giorno di tolleranza per i fusi orari); senza, `max(data di inizio della casa, oggi)`. Con la casa non ancora iniziata la data è quella della casa e `start_date` si ignora. Il membro nasce con la sua data: le quote predefinite valgono da lì, senza `set_my_start_date`. Se la data è oggi, `cash_opening_cents` (facoltativo) diventa il saldo iniziale dei contanti. Segna l'invito come usato. Una seconda chiamata con lo stesso invito, dallo stesso account, restituisce lo stesso membro. Una casa è tutta demo o tutta vera: chi entra ha `is_demo` uguale a quello dei membri attivi della casa (controllo dopo l'invito, prima dei posti); la data si controlla per ultima. | nella colonna `error`: come sopra, più `no_profile`, `already_member`, `invite_demo_mismatch`, `household_full`, `start_date_out_of_range` |
| `set_my_start_date(date)` | Sposta la data di inizio del membro **all'indietro**, fino a quella della casa. Non è ammessa se la casa non è ancora iniziata (la data resta quella della casa). Sposta anche la versione delle quote predefinite nata con il suo ingresso. | `not_member`, `start_date_out_of_range`, `household_not_started` |

Il codice si accetta con o senza spazio e senza distinzione tra maiuscole e minuscole. `invite_preview` e `redeem_invite` ricevono il codice nel parametro `code` oppure il token del link nel parametro `token`; ogni chiamata conta come tentativo, tranne quelle rifiutate per `too_many_attempts`. **Lasciare la casa, rimuovere un membro ed eliminare l'account** arrivano con le impostazioni: lo schema ha già `left_at` e `user_id` nullable. Un membro uscito perde ogni accesso (`current_member_id()` è null). L'eliminazione degli account demo, solo per lo sviluppo, è qui sotto.

### Account demo (solo sviluppo)
Regole in [`accesso.md`](accesso.md), sezione 12.

- **Interruttore:** segreto `demo_accounts` in Vault, con valore `enabled`, inserito a mano su `dev`, mai su `prod`; nessun valore nel repository. In locale e in CI lo creano e lo tolgono i test pgTAP.

| Funzione | Cosa fa | Errori |
|---|---|---|
| `demo_accounts_enabled()` | Vero solo con il segreto `demo_accounts` uguale a `enabled`. Interna: security definer, `search_path` vuoto, nessun `execute` ad `anon` né ad `authenticated`. | — |
| `delete_my_demo_account()` | Senza parametri, solo su `auth.uid()`, in una transazione. In ogni casa di cui l'utente è membro attivo, con un lock sulla casa: se non restano altri membri attivi cancella la casa e **tutti** i suoi dati nell'ordine delle chiavi esterne (il grezzo lascia prima i movimenti; anticipi e rimborsi, tag delle righe, quote, righe, giroconti, conguagli, salvadanai, movimenti, piani a rate, grezzo, saldi, conti, connessioni con le loro esecuzioni, richieste di collegamento, contatti, saldi iniziali, quote predefinite, tag, categorie, inviti, membri, casa); altrimenti il membro diventa ex membro (`left_at` = adesso) e le sue righe restano, senza ricalcolare le quote predefinite. Poi cancella l'utente da `auth.users`: le cascate tolgono profilo, `user_settings`, `devices`, `paypal_emails`, `invite_attempts` ed `eb_credentials` con il segreto di Vault. Se l'utente non c'è più (seconda chiamata dopo una risposta persa) non fa niente. Security definer, `execute` solo ad `authenticated`. | `demo_disabled` (interruttore spento), `not_demo` (profilo non demo) |

Errori solo come chiavi, senza dati nei messaggi. Il test pgTAP controlla che le tabelle che puntano a una casa, direttamente o no, siano proprio quelle che la funzione svuota: una tabella nuova lo fa fallire finché non entra nella funzione.

## 4. Conti e dati delle banche

### `eb_credentials` — applicazione Enable Banking della persona
| Colonna | Tipo | Note |
|---|---|---|
| `user_id` | uuid PK | |
| `app_id` | text | ID dell'applicazione |
| `private_key_secret_id` | uuid | riferimento al segreto in **Supabase Vault**, che contiene la chiave privata (PEM) |
| comuni | | |

**Nessun accesso dall'app** (né lettura né scrittura): la scrive e la legge solo una Edge Function con la service role, che salva il PEM con `vault.create_secret` e lo legge da `vault.decrypted_secrets`. Senza una riga la persona usa l'applicazione globale (chiave nei secrets delle Edge Functions).

### `bank_connections` — un consenso PSD2 per banca
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `member_id` | uuid | |
| `aspsp_name`, `aspsp_country` | text | banca come la nomina Enable Banking |
| `session_id` | text unique null | sessione di Enable Banking |
| `uses_global_app` | bool | |
| `status` | text | `pending`, `active`, `expired`, `revoked`, `error` |
| `valid_until` | timestamptz null | scadenza del consenso |
| `last_sync_at`, `last_success_at` | timestamptz null | |
| `last_error` | text null | solo un codice (`period_rejected`, `consent_expired`…), mai testo della banca |
| comuni | | |

RLS: **select** il membro proprietario; scrittura solo lato server.

### `accounts`
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `household_id` | uuid | |
| `owner_member_id` | uuid | letta solo da `is_account_owner` |
| `kind` | text | `bank` (conto, deposito), `card` (carta di credito), `paypal`, `cash`, `manual` |
| `connection_id` | uuid null | → `bank_connections`; null per `cash` e `manual` |
| `provider_account_id` | text null | identificativo del conto presso Enable Banking; unico per connessione |
| `cash_account_type` | text null | `CACC`, `CARD`, `OTHR`… |
| `currency` | char(3) | `XXX` per PayPal |
| `display_name` | text | nome predefinito calcolato al collegamento ("Banca …1234", l'email per PayPal), rinominabile |
| `identifier` | text null | IBAN, carta mascherata o email del conto; solo il proprietario |
| `preferred_balance_type` | text null | saldo mostrato; null = regola predefinita (il disponibile) |
| `excluded_from_total` | bool | predefinito `false` |
| `opening_balance_cents` | bigint null | solo `cash` e `manual`: saldo iniziale alla **data di inizio del membro**, fuori dal bilancio |
| `archived_at` | timestamptz null | |
| comuni | | |

Vincoli: un solo conto `cash` per membro (indice unico parziale); `connection_id` obbligatorio per `bank`, `card`, `paypal` e assente per `cash`, `manual`; `opening_balance_cents` solo per `cash` e `manual`.
Trigger: alla creazione di un membro nasce il suo conto `cash` ("Contanti", EUR).
RLS: **select** e **update** solo `is_account_owner`; update consentito solo su `display_name`, `preferred_balance_type`, `excluded_from_total`, `opening_balance_cents`, `archived_at` (permessi sulle colonne); insert dall'app solo per `kind = 'manual'`; i conti delle banche li crea il server.

### `account_balances` — saldi letti dalle banche
| Colonna | Tipo | Note |
|---|---|---|
| `account_id` | uuid | |
| `currency` | char(3) | un saldo per valuta (PayPal) |
| `balance_type` | text | `CLBD`, `XPCD`, `ITAV`, `ITBD`, `OTHR`… |
| `amount_cents` | bigint | con segno (una carta di credito ha il debito negativo) |
| `reference_date` | date null | |
| `fetched_at` | timestamptz | |

PK (`account_id`, `currency`, `balance_type`): si tiene l'ultimo valore. Il saldo di un conto bancario **non si calcola mai dai movimenti**. Il totale di Conti somma solo gli EUR. RLS: **select** `is_account_owner`; scrittura solo lato server.

### `bank_raw_transactions` — grezzo delle banche
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `account_id` | uuid | |
| `entry_reference` | text null | |
| `dedup_hash` | text | hash dei campi della riga (data contabile, data valuta, data della transazione, stato, importo, segno, descrizione: [`sincronizzazione.md`](sincronizzazione.md), sezione 5) |
| `dedup_ordinal` | int | posizione della riga nel gruppo di righe identiche (1, 2, 3…) |
| `status` | text | `BOOK`, `PDNG`, `RJCT`, `CNCL` |
| `booking_date`, `value_date`, `transaction_date` | date null | |
| `movement_date` | date | data valuta, altrimenti della transazione, altrimenti contabile |
| `amount_cents` | bigint | con segno, da `credit_debit_indicator` |
| `currency` | char(3) | |
| `payload` | jsonb | risposta della banca per quella riga |
| `transaction_id` | uuid null | movimento creato da questa riga |
| `fetched_at` | timestamptz | |

**Deduplicazione** come vincolo: unico (`account_id`, `entry_reference`) dove `entry_reference` c'è; altrimenti unico (`account_id`, `dedup_hash`, `dedup_ordinal`). A ogni sincronizzazione, per ogni gruppo di righe identiche nella finestra scaricata, si inseriscono solo gli ordinali oltre quelli già salvati: **una riga uguale a un'altra non si scarta mai**.
**Diventano movimenti** solo le righe `BOOK` con `movement_date` ≥ data di inizio del membro proprietario del conto. Le righe precedenti, `PDNG`, `RJCT` e `CNCL` restano solo qui. Per PayPal il grezzo parte da circa 90 giorni prima della data di inizio, per trovare gli acquisti a rate precedenti.
**Nessun accesso dall'app**: solo il server.

## 5. Transazioni e righe

### `transactions`
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `household_id` | uuid | |
| `account_id` | uuid null | null solo per un movimento manuale inserito per un altro membro senza conto (uso deciso con l'inserimento manuale) |
| `source` | text | `bank` o `manual` |
| `raw_id` | uuid null unique | → `bank_raw_transactions` |
| `paid_by_member_id` | uuid | chi ha pagato (o ricevuto, per un'entrata); **uno solo** |
| `entered_by_member_id` | uuid null | chi l'ha inserita (null per le importate) |
| `movement_date` | date | data della spesa |
| `booking_date` | date null | |
| `booking_status` | text | `booked` o `pending` |
| `amount_cents` | bigint | con segno, ≠ 0 |
| `currency` | char(3) | |
| `original_amount_cents`, `original_currency`, `exchange_rate` | null | valuta originale e cambio, anche se oggi è sempre euro |
| `description` | text null | testo della banca |
| `counterparty` | text null | controparte normalizzata (campo dedicato o estratta dalla descrizione) |
| `counterparty_email` | text null | email PayPal della controparte, per il riconoscimento dei conguagli |
| `bank_code` | text null | `bank_transaction_code` |
| `installment_plan_id` | uuid null | per le rate |
| `deleted_at` | timestamptz null | solo per i movimenti manuali |
| comuni | | |

Vincoli e trigger:
- con un conto, `paid_by_member_id` = proprietario del conto;
- `movement_date` ≥ data di inizio di chi ha pagato: **nessun movimento prima della data di inizio**, anche cambiando la data (`movement_before_start_date`);
- per `source = 'bank'`, `amount_cents`, `currency`, `description`, `account_id` e `raw_id` non cambiano dall'app;
- alla creazione nasce **una riga** con tutto l'importo e una quota del 100% a chi ha pagato (movimento in inbox); una rata prende la categoria del suo piano;
- se cambiano `movement_date`, `counterparty` o `paid_by_member_id`, il trigger aggiorna le copie sulle righe;
- se cambia l'importo di una transazione con **una sola riga** non eliminata, la riga lo segue e le quote si ricalcolano con gli stessi pesi; con più righe la modifica è rifiutata (`lines_sum_mismatch`) finché arriva la funzione con l'inserimento manuale.

RLS: tutto con `can_see_transaction`. Chi è solo coinvolto in una riga **non legge mai la transazione**, quindi non vede mai il totale né l'email della controparte. Insert dall'app solo con `source = 'manual'`.

**Da classificare:** non c'è una colonna di stato. La definizione unica (transazioni con una riga senza `kind`, piani a rate senza categoria) è `unclassified_count()`, sezione 10.

### `transaction_lines`
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `transaction_id` | uuid | |
| `household_id` | uuid | |
| `position` | smallint | |
| `amount_cents` | bigint | stesso segno della transazione |
| `kind` | text null | tipo di movimento: `expense` Spesa, `income` Entrata, `saving` Risparmio, `transfer` Giroconto, `settlement` Conguaglio, `advance` Anticipo, `refund` Rimborso; null = da classificare |
| `category_id` | uuid null | |
| `excluded_from_budget` | bool | |
| `deductible_730` | bool | predefinito dalla categoria, modificabile |
| `movement_date`, `counterparty`, `paid_by_member_id` | | **copie** dalla transazione, così chi è coinvolto vede la riga senza leggere la transazione |
| `transfer_id`, `settlement_id`, `installment_plan_id` | uuid null | collegamenti |
| `deleted_at` | timestamptz null | |
| comuni | | |

Il **tipo di movimento sta sulla riga**: una transazione può essere in parte giroconto e in parte commissioni. Nel **bilancio** entrano solo le righe `expense` e `income` con `excluded_from_budget = false`.
Vincoli (trigger differiti a fine transazione):
- la somma delle righe non eliminate è uguale a `transactions.amount_cents` (`lines_sum_mismatch`); una transazione cancellata insieme alle sue righe non si controlla più (la chiave esterna non lascia righe senza transazione);
- una riga con una quota di un membro diverso da chi ha pagato ha una **categoria condivisa** e solo tag condivisi (`shared_line_personal_category`, `shared_line_personal_tag`);
- una categoria personale si usa solo dal suo proprietario, cioè sulle righe che ha pagato lui (`personal_category_not_owned`); lo stesso per i tag (`personal_tag_not_owned`).

Il flag 730: quando l'app cambia la categoria di una riga, la riga prende `deductible_730_default` della nuova categoria, salvo che la stessa modifica imposti il flag; `split_line` e `merge_categories` lasciano i flag come sono.

Collegamenti della riga, controllati anche per il server (`line_link_not_valid`): `settlement_id` è un conguaglio della stessa casa di cui chi ha pagato la riga è il pagatore o il ricevente; `transfer_id` è un giroconto della stessa casa e il conto della transazione è `from_account_id` o `to_account_id`; `installment_plan_id` è un piano della stessa casa con `account_id` uguale al conto della transazione.

RLS:
- **select** con `can_see_line`;
- **insert** ed eliminazione solo con `can_see_transaction` (dividere in righe richiede il totale);
- **update** da chi vede la transazione (tutto) o da chi è coinvolto (solo `kind`, `category_id`, `deductible_730`, `excluded_from_budget`: un trigger rifiuta il resto).

### `line_shares`
| Colonna | Tipo | Note |
|---|---|---|
| `line_id` | uuid | |
| `member_id` | uuid | |
| `household_id` | uuid | |
| `weight` | numeric(12,4) | > 0 |
| `amount_cents` | bigint | calcolato dal server |

PK (`line_id`, `member_id`). Ogni riga ha **almeno una quota**; la somma di `amount_cents` è uguale all'importo della riga (trigger differito, `line_shares_mismatch`). Un membro non ha quote su righe con data precedente alla sua data di inizio, anche cambiando la data della riga, né quote nuove se è uscito dalla casa (`member_not_eligible`).
**Mia, Condivisa, Per un altro membro non si salvano**: si ricavano dalle quote (Mia = una quota sola, di chi ha pagato; Per… = chi ha pagato non ha quota; altrimenti Condivisa).
RLS: **select** con `can_see_line`; nessuna scrittura diretta: solo `set_line_shares`.

## 6. Quote

### Calcolo dei centesimi (`split_cents`)
1. Per ogni membro: quota esatta = importo × peso / somma dei pesi; parte intera verso zero.
2. I centesimi che mancano si assegnano uno per volta ai **resti più grandi**.
3. A parità di resto: prima chi ha pagato, poi il membro con `joined_at` più vecchio, poi l'`id` più piccolo.

Esempio: 10,00 € tra Anna, Bruno e Carla a pesi 1:1:1 pagati da Bruno → Bruno 3,34, Anna 3,33, Carla 3,33. L'app usa lo stesso algoritmo solo per l'anteprima; i casi di test sono gli stessi in Dart e in SQL.

### Funzioni
| Funzione | Cosa fa |
|---|---|
| `set_line_shares(line_id, shares)` | `shares` = elenco di `{member_id, weight}`. Sostituisce le quote della riga e calcola i centesimi. Possono chiamarla chi vede la transazione e chi è coinvolto nella riga. Errori: `no_members`, `member_not_eligible` (uscito o con la data di inizio successiva alla riga). |
| `split_line(line_id, parts)` | `parts` = elenco di `{id, amount_cents}` con gli id generati sul dispositivo. Divide una riga in più righe: ogni parte è una **riga nuova che eredita** tipo, categoria, flag e pesi della riga da cui nasce, e la riga di partenza **tiene il resto** del suo importo (le parti hanno il segno della riga e non ne prendono tutto l'importo). Una seconda chiamata con gli stessi id non fa niente. Solo chi vede la transazione. Errore: `invalid_parts`. |
| `default_shares_at(date)` | Pesi predefiniti della casa validi a quella data (data della spesa), senza i membri usciti e quelli con la data di inizio successiva. |
| `set_default_shares(valid_from, weights)` | Nuova versione delle quote predefinite da quella data. Errori: `not_member`, `no_members`, `member_not_eligible`. |

Se cambia l'importo di una riga, i centesimi si ricalcolano con gli stessi pesi.

### `default_share_sets` e `default_share_weights`
- `default_share_sets`: `id`, `household_id`, `valid_from` (date), `reason` (`household_created`, `member_joined`, `manual`), `member_id` null (per `member_joined`), `created_by_member_id`, comuni. Unico (`household_id`, `valid_from`): una seconda modifica nello stesso giorno sostituisce la prima.
- `default_share_weights`: `set_id`, `member_id`, `weight` > 0.
- **Trigger:** alla creazione della casa una versione con il solo creatore; all'ingresso di un membro una versione con **pesi uguali per tutti i membri attivi, valida dalla data di inizio del nuovo membro**. Se il membro sposta la propria data di inizio, la versione si sposta con lei (e sostituisce una versione già in quella data); il membro entra con peso 1 anche nelle versioni successive create prima del suo ingresso, che non potevano comprenderlo.
- RLS: **select** i membri attivi; scrittura con le funzioni e i trigger.

## 7. Visibilità (riassunto delle regole RLS)

| Dato | Chi lo vede |
|---|---|
| Profilo (nome, foto, PayPal.Me) | il proprietario e i membri attivi della stessa casa |
| Impostazioni dell'account, dispositivi, email PayPal, credenziali | solo il proprietario (credenziali e grezzo: solo il server) |
| Conti, saldi, connessioni, transazioni | solo il proprietario del conto |
| Riga e quote | chi ha pagato e chi ha una quota; il proprietario della transazione |
| Riga di un'entrata | anche gli altri membri attivi, se chi la riceve ha `show_income = true` e la data della riga è dalla **data di inizio di chi guarda** |
| Conguaglio | i due membri coinvolti; gli altri ne vedono solo l'effetto sui saldi netti |
| Saldi netti di tutti i membri | tutti i membri attivi, **solo con `member_balances()`**: nessuna riga in più diventa visibile |
| Proprie spese per mese | chi chiama, **solo con `my_spending_by_month()`**: le sue quote e le altre quote delle stesse righe, nessuna riga in più diventa visibile |
| Categorie e tag condivisi | tutti i membri attivi; personali solo il proprietario |
| Salvadanaio e versamenti | i membri del salvadanaio; mai i saldi dei conti |
| Anticipi | come la riga da cui nascono |

Nessuna tabella espone il totale di una transazione a chi non ne è il proprietario.

## 8. Categorie e tag

### `categories`
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `household_id` | uuid | |
| `parent_id` | uuid null | null = macro |
| `name` | text | |
| `kind` | text | `expense` o `income` |
| `scope` | text | `shared` o `personal` |
| `owner_member_id` | uuid null | solo per `personal` |
| `system_key` | text null | `cash_difference` per la Differenza di cassa |
| `deductible_730_default` | bool | |
| `position` | smallint | |
| `archived_at` | timestamptz null | |
| `merged_into_id` | uuid null | |
| comuni | | |

Vincoli: una macro è sempre condivisa; una personale è sempre una sottocategoria (anche sotto una macro condivisa); nome unico tra le condivise non archiviate con lo stesso padre e lo stesso tipo (senza maiuscole e minuscole: spese ed entrate hanno entrambe una Varie); le categorie di sistema non si archiviano, non si uniscono e non diventano personali. Mai cancellate.
Seed: alla creazione della casa un trigger copia l'elenco iniziale di [`categorie.md`](categorie.md) (spese ed entrate, con il flag 730 e le due Differenza di cassa).
**Differenza di cassa:** due categorie di sistema condivise (spesa ed entrata, sotto Varie). Il contante è personale: una riga che le usa ha solo la quota di chi ha pagato (`shared_line_cash_difference`).
RLS: condivise → **select**, insert e update i membri attivi; personali → solo il proprietario. **Promozione** a condivisa: update di `scope` dal proprietario (con il controllo del nome); una condivisa non torna personale.
Funzione `merge_categories(from_id, into_id)`: sposta tutte le righe (anche quelle che chi chiama non vede) e i piani a rate, e archivia la categoria unita. Errori: `not_member`, `category_not_mergeable` (stessa categoria, tipi diversi, di sistema, archiviata, macro con sottocategorie, non visibile a chi chiama).

### `tags` e `line_tags`
- `tags`: `id`, `household_id`, `name`, `scope` (`shared`, `personal`), `owner_member_id` null, `archived_at`, comuni. Stesso modello delle categorie: condivisi o personali, mai cancellati, solo archiviati.
- `line_tags`: (`line_id`, `tag_id`) PK. Una riga condivisa ha solo tag condivisi. RLS: **select** se si vedono la riga e il tag; insert e delete da chi può modificare la riga.

## 9. Giroconti e rate

### `transfers`
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `household_id` | uuid | |
| `from_account_id`, `to_account_id` | uuid | diversi, dello stesso proprietario |
| `out_transaction_id`, `in_transaction_id` | uuid null | **entrambe facoltative**, almeno una presente (verso PayPal manca l'entrata) |
| `funded_transaction_id` | uuid null | pagamento PayPal finanziato dall'addebito |
| `origin` | text | `auto` (riconosciuto dal server) o `manual` |
| `deleted_at` | timestamptz null | annullare un giroconto riconosciuto in automatico |
| comuni | | |

Le righe delle transazioni collegate hanno `kind = 'transfer'` e `transfer_id`. Vale per ricariche, addebito della carta di credito, banca → PayPal, PayPal → banca (mai un'entrata), prelievi (conto → contanti).
RLS: tutto con `is_account_owner(from_account_id)`.

### `installment_plans`
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `household_id`, `account_id` | uuid | |
| `merchant` | text | |
| `total_cents` | bigint | positivo |
| `installments_count` | smallint | |
| `purchase_date` | date | anche precedente alla data di inizio |
| `purchase_raw_id` | uuid null | → `bank_raw_transactions`: l'acquisto da cui nasce il piano |
| `installments_before_start` | smallint | rate addebitate prima della data di inizio (fuori dal bilancio), per mostrare "2/3 pagate" |
| `next_due_date` | date null | |
| `category_id` | uuid null | categoria del piano, ereditata da ogni rata |
| `status` | text | `active`, `completed` |
| `deleted_at` | timestamptz null | |
| comuni | | |

`installment_plan_shares` (`plan_id`, `member_id`, `weight`): pesi del piano; ogni rata li copia con `set_line_shares`. L'acquisto non è un movimento e non entra nel bilancio; **contano le rate** con data dalla data di inizio del membro proprietario del conto. RLS: il proprietario del conto e i membri con un peso sul piano.

## 10. Conguagli e saldi

### `settlements`
| Colonna | Tipo | Note |
|---|---|---|
| `id` | uuid PK | |
| `household_id` | uuid | |
| `payer_member_id`, `payee_member_id` | uuid | diversi |
| `amount_cents` | bigint | > 0 |
| `currency` | char(3) | |
| `settled_on` | date | ≥ data di inizio di entrambi |
| `origin` | text | `paypal`, `manual` ("Segna come pagato"), `bank_transfer` |
| `payer_transaction_id`, `payee_transaction_id` | uuid null unique | **lati facoltativi** |
| `created_by_member_id` | uuid null | null se creato dal server |
| `deleted_at` | timestamptz null | |
| comuni | | |

Il primo lato che arriva crea il conguaglio; il secondo (stessa coppia, stesso importo e valuta, data entro ±3 giorni, lato libero) **si collega** a quello. L'abbinamento lo fa il server.
Pagatore, ricevente e chi lo crea sono membri attivi della casa, con la data di inizio non successiva a `settled_on`, anche dal server (`member_not_eligible`); ogni lato è un movimento del suo membro. Quando il server ha collegato almeno un lato, dall'app importo e data non cambiano più (`settlement_linked`); l'eliminazione resta possibile.
RLS: **select**, insert e update solo il pagatore e il ricevente. Dall'app solo conguagli `manual`, creati da uno dei due; cambiano solo importo, data ed eliminazione; i lati li collega il server.

### `initial_balances` — saldo iniziale tra i membri
`household_id`, `member_id`, `amount_cents` (con segno: positivo = credito), `set_by_member_id`, comuni; PK (`household_id`, `member_id`).
- Funzione `set_initial_balances(balances)`: riguarda solo i membri attivi con la data di inizio uguale a quella della casa (gli altri: `member_not_eligible`); `balances` è un elenco con ogni membro al massimo una volta (altrimenti `invalid_balances`); i mancanti valgono zero; **somma zero** obbligatoria (`initial_balance_not_zero_sum`); chi chiama è un membro attivo (`not_member`). Ogni chiamata riscrive le righe di tutti quei membri, così la versione di ciascuna sale di uno: l'app ci applica la regola dei conflitti.
- **"Nessun saldo da riportare"** = la stessa funzione con tutti gli importi a zero. La voce "Per iniziare" è fatta quando esistono le righe.
- La usano qualunque membro e le correzioni da Saldi (regola dei conflitti).
- RLS: **select** i membri attivi; scrittura solo con la funzione.

### `member_balances()` — saldo netto per membro
Restituisce `member_id`, `net_cents` per la casa di chi chiama (security definer). Per ogni membro:

```
net = Σ righe pagate da lui (−amount_cents)
    + Σ sue quote (amount_cents)
    + Σ conguagli versati − Σ conguagli ricevuti
    + saldo iniziale
```

- Solo righe e transazioni non eliminate, in EUR (le altre valute restano fuori finché sono rimandate), e conguagli non eliminati, in EUR.
- Restituisce tutti i membri della casa, anche quelli usciti, così la somma resta zero.
- Positivo = credito. Le righe "Mia" si annullano da sole, quindi inbox, giroconti e righe di tipo Conguaglio non spostano il saldo; anticipi e rimborsi seguono le loro quote.
- La somma dei saldi netti di una casa è sempre zero (test).
- Il **piano dei pagamenti** (chi deve di più paga chi deve ricevere di più) si calcola nell'app dai saldi.

### Funzioni di lettura (hub, Movimenti, Riepilogo)
I numeri dell'hub, con **una sola definizione** per l'hub, il badge di Movimenti e il Riepilogo. Tutte `stable`, con `search_path` vuoto, `execute` solo ad `authenticated`; agiscono solo sul membro attivo di chi chiama (`current_member_id()`), senza parametri con un id di membro; **senza casa** danno 0 o, per i mesi, righe a zero. Errori solo come chiavi.

| Funzione | Restituisce | Errori |
|---|---|---|
| `unclassified_count()` | **Da classificare**, numero esatto (il "99+" lo fa l'app). Somma di: le **transazioni** di chi chiama (`paid_by_member_id`; con un conto è il proprietario), non eliminate, con almeno una riga non eliminata senza `kind` che non è collegata (`transaction_lines.installment_plan_id`) a un piano non eliminato senza categoria; i **piani a rate** dei suoi conti, non eliminati, senza categoria, **qualunque sia lo stato** (anche `completed`, anche nati prima della data di inizio). Un piano conta **1** al posto delle sue rate; la rata senza tipo di un piano eliminato conta con la sua transazione. Security invoker: legge con le policy di chi chiama. | — |
| `my_spending_by_month(today, months)` | "Le tue spese": `month` (primo giorno del mese), `shared_cents`, `personal_cents` per ognuno degli ultimi `months` mesi (predefinito 6) **compreso quello di `today`**, dal più vecchio, anche a zero. `today` è la data locale del telefono (il server è in UTC). Contano le **proprie quote** delle righe `expense` non eliminate, con `excluded_from_budget = false`, con la data nel mese e dalla propria data di inizio, di transazioni non eliminate e in EUR (le altre valute restano rimandate). Spese in positivo, `-sum(amount_cents)` delle quote: un reso classificato come spesa riduce il totale. **Personali** = righe con la sola quota di chi chiama, pagate da lui (Mia); **Condivise** = tutte le altre righe con una sua quota (con altri membri, o pagate da un altro solo per lui); nessuna sovrapposizione. Le righe pagate per altri senza una propria quota non contano. Security definer, come `member_balances()`: legge solo le quote di chi chiama, le altre quote delle stesse righe (che vede, avendo una quota) e della transazione solo `deleted_at` e `currency`; con le policy, `can_see_line()` girerebbe su ogni quota di sempre. | `invalid_months` (fuori da 1–12 o null), `invalid_date` (`today` null) |
| `my_accounts_total()` — **provvisoria** | Totale in centesimi di EUR dei conti di chi chiama (`owner_member_id`), non archiviati e non esclusi dal totale. **Conti delle banche** (`bank`, `card`, `paypal`): il saldo in EUR di `account_balances` del tipo `preferred_balance_type`; se è null o il conto non ha un saldo in EUR di quel tipo, il primo presente tra `ITAV`, `CLAV`, `XPCD`, `ITBD`, `CLBD`, poi qualunque altro tipo in ordine alfabetico; senza un saldo in EUR, 0. Il saldo negativo di una carta resta negativo; PayPal solo in EUR. **Contanti e manuali** in EUR: `coalesce(opening_balance_cents, 0)` + `amount_cents` delle transazioni del conto non eliminate e in EUR; in un'altra valuta, 0. Security invoker. | — |

### `paypal_emails`
`id`, `user_id`, `email` (minuscolo, **unica**: una persona per email), `source` (`linked_account`, `manual`), comuni.
RLS: tutto solo il proprietario; il riconoscimento dei conguagli la legge solo lato server.

## 11. Salvadanai e anticipi

- **`piggy_banks`:** `id`, `household_id`, `name`, `target_cents` null, `created_by_member_id`, `archived_at`, comuni.
- **`piggy_bank_members`:** (`piggy_bank_id`, `member_id`).
- **`piggy_bank_entries`:** `id`, `piggy_bank_id`, `member_id`, `account_id` null, `kind` (`virtual` = quota accantonata sullo stesso conto; `real` = movimento di tipo Risparmio, con `transaction_id`), `amount_cents` (negativo = prelievo dal salvadanaio), `entry_date`, `deleted_at`, comuni.
- RLS: i membri del salvadanaio vedono salvadanaio, membri e versamenti (l'id del conto non dà accesso al conto). Un versamento lo crea solo il membro stesso, sui propri conti.
- Chi crea un salvadanaio ne diventa il primo membro; ogni membro del salvadanaio lo rinomina o lo archivia e aggiunge o toglie membri (nessun ruolo). Creatore, membri e autori dei versamenti sono membri attivi della casa, e un versamento è di un membro del salvadanaio, anche dal server (`member_not_eligible`).

**Persone esterne e anticipi:**
- **`contacts`:** `id`, `household_id`, `owner_member_id`, `name`, `archived_at`, comuni. Rubrica **personale**: solo il proprietario, membro attivo della casa (`member_not_eligible`).
- **`advances`:** `id`, `line_id` (unico: la riga rimborsabile da terzi), `contact_id`, `contact_name` (copiato, così lo vedono gli altri coinvolti), `expected_cents`, `written_off_at` (diventata spesa normale), comuni.
- **`advance_repayments`:** `advance_id`, `line_id` (riga del rimborso), `amount_cents`.
- Il rimborso eredita le quote della riga originale quando si collega all'anticipo; ogni membro di quelle quote è un membro attivo della casa (`member_not_eligible`). Aperto, parziale o chiuso si ricava dai rimborsi. RLS: come la riga dell'anticipo; collega anticipi e rimborsi chi può modificare le righe coinvolte, con un contatto della propria rubrica.

## 12. Fuori da questo schema

- **Notifiche:** tabella e funzioni con le notifiche push.
- **Sincronizzazione della cache:** come l'app scopre le righe che non può più vedere (per esempio un membro tolto da una spesa), con la coda offline.
- **Funzioni di sincronizzazione bancaria** (importazione, abbinamenti, giroconti automatici, conguagli PayPal, piani a rate): Edge Functions con la service role; qui solo le tabelle e i vincoli. Regole in [`sincronizzazione.md`](sincronizzazione.md).
- **Lasciare la casa, rimozione di un membro, eliminazione dell'account; modifica della data di inizio della casa:** funzioni con le impostazioni.
- **Valute estere:** le colonne ci sono, i calcoli escludono le valute diverse da EUR.

## 13. Test (pgTAP)

Utenti inventati: **Anna**, **Bruno**, **Carla**; "Casa di prova" con 1, 2 e 3 membri; una seconda casa (di Dario, che vive da solo) per i controlli tra case. Ogni gruppo di tabelle ha almeno questi casi.

**Casa, membri, inviti**
- `create_household` crea casa, membro, conto Contanti, quote predefinite e categorie; un account non entra in una seconda casa; data fuori intervallo rifiutata.
- Inviti: scaduto, usato, revocato, casa piena (contano gli inviti aperti), troppi tentativi; con o senza spazio nel codice.
- Ingresso: data di inizio = oggi, oppure quella della casa se non è iniziata (e non si sposta); spostamento all'indietro fino a quella della casa; nuova versione delle quote uguali dalla data di inizio del nuovo membro.
- Profili: nome, foto e PayPal.Me visibili ai membri della casa, non a Dario; `user_settings` e `devices` solo al proprietario.
- Un membro uscito non vede più niente e non è visibile nei profili.

**Account demo** (utenti demo Anna e Bruno in "Casa demo", Carla vera in "Casa di prova")
- Interruttore spento: profilo demo e eliminazione rifiutati (`demo_disabled`); acceso: profilo demo creato, `is_demo` immutabile nei due versi (`demo_immutable`).
- `redeem_invite`: demo → casa vera e vero → casa demo rifiutati (`invite_demo_mismatch`, invito non consumato); demo → casa demo ammesso.
- Eliminazione con un altro membro demo: casa intatta, membro ex, utente cancellato. Eliminazione dell'ultimo membro, con righe in **ogni** tabella che punta alla casa: nessuna riga rimasta della casa né dell'utente (anche il segreto di Vault), controlli differiti superati, altre case intatte.
- Account vero → `not_demo`; seconda chiamata dopo l'eliminazione senza errori; `execute` negato ad `anon`, interruttore non leggibile dall'app.

**Conti e transazioni**
- Conti, saldi, connessioni e transazioni visibili solo al proprietario; grezzo e credenziali invisibili all'app.
- Deduplicazione: due righe identiche senza riferimento si salvano entrambe; la stessa riga scaricata due volte no.
- Nessun movimento prima della data di inizio del membro (anche cambiando la data).
- Una transazione nuova ha una riga con il 100% a chi paga e compare tra quelle da classificare.

**Righe e quote**
- Bruno coinvolto in una riga di Anna la vede, con data, controparte, importo della riga e quote, ma **non vede la transazione** né le altre righe; Carla, non coinvolta, non vede niente.
- Bruno coinvolto cambia categoria e quote, non importo né divisione.
- Centesimi: 10,00 € a 1:1:1 (sezione 6), 0,01 € tra tre membri, "Per un altro membro" con il resto, somme sempre esatte.
- `split_line`: le righe nuove ereditano le quote; la somma resta il totale.
- Riga condivisa con categoria personale: rifiutata. Nessuna quota a un membro con data di inizio successiva alla riga.
- Entrate: visibili agli altri con `show_income = true`, invisibili con `false`, invisibili prima della data di inizio di chi guarda.
- Quote predefinite: la versione valida alla data della spesa.

**Conguagli e saldi**
- Conguaglio visibile solo ai due membri; Carla vede solo i saldi netti.
- `member_balances()` con tre membri su un caso calcolato a mano: spese condivise, una spesa "Per Carla", un'entrata condivisa, un anticipo con il rimborso, un conguaglio, il saldo iniziale; **somma zero**.
- Saldo iniziale: somma diversa da zero rifiutata; "Nessun saldo da riportare" salvato come zeri; escluso un membro entrato dopo la data di inizio della casa.
- Salvadanaio condiviso: i membri vedono i versamenti, non i conti; un non membro non vede il salvadanaio.

**Numeri dell'hub** (Anna e Bruno in "Casa di prova", Carla che entra dopo; Dario prima senza casa, poi da solo nella sua)
- Permessi: `execute` ad `authenticated`, negato ad `anon`; `unclassified_count()` e `my_accounts_total()` security invoker, `my_spending_by_month()` security definer.
- `unclassified_count()`: una riga senza tipo (1); due righe senza tipo (1); divisa con una riga classificata (1); tutte classificate (0); riga eliminata; movimento manuale eliminato; una transazione di Bruno, anche inserita da Anna, non conta per Anna; piano senza categoria con due rate senza tipo (1); piano con categoria e rata senza tipo (1, la rata); piano eliminato (contano le sue rate senza tipo); piano `completed` e piano nato prima della data di inizio (1); Dario senza casa (0).
- `my_spending_by_month()`: un membro (tutto in Personali); due membri con Mia, condivisa 50/50, pagata da Bruno per Anna sola (Condivise), pagata da Anna per Bruno solo (non conta); tre membri con quote diverse e il centesimo di chi paga; esclusa dal bilancio, tipi diversi da `expense`, riga eliminata, movimento eliminato o in USD (nemmeno per chi ha solo una quota), reso positivo; ultimo e primo giorno del mese; mesi a zero; `months` = 1, 12, 0, 13 e null, `today` null; righe della casa di Dario mai contate; Dario senza casa (righe a zero).
- `my_accounts_total()`: tipo preferito, ordine dei tipi con `preferred_balance_type` null, tipo preferito senza saldo in EUR, conto senza saldo, carta negativa, PayPal con EUR e USD, conto escluso dal totale, conto archiviato, contanti con saldo iniziale e transazioni (una eliminata), conto manuale con una transazione in USD, conto manuale in USD, conti di Bruno mai contati, Dario senza casa (0).
