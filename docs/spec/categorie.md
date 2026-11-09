# Categorie

Specifica tecnica delle categorie finanziarie e delle regole di gestione. Esempi con membri e dati inventati.

## 1. Modello

- **Tipo di movimento**, separato dalla categoria: Spesa, Entrata, Risparmio, Giroconto, Conguaglio, Anticipo, Rimborso. Solo Spesa ed Entrata contano nel bilancio.
- **Categorie su due livelli:** macro e sottocategoria. L'elenco della sezione 7 è quello iniziale; nell'app le categorie si modificano.
- **Ogni transazione ha una o più righe** (somma degli importi = totale), ognuna con categoria e **quote per membro**. Mia, Condivisa e Per un altro membro sono il risultato delle quote, non un campo salvato.
- **Tag liberi trasversali** (es. "Viaggio estate"). Niente budget previsionale.

## 2. Gestione delle categorie

**Categorie condivise**
- Create da un membro, visibili e utilizzabili da tutti i membri della casa.
- Mai cancellate, solo **archiviate**: spariscono dalle scelte ma restano sulle transazioni passate.
- Qualsiasi membro può archiviarle, rinominarle o unirle, con notifica a tutti i membri e senza approvazione (nella casa non ci sono ruoli).
- Nell'unione le transazioni passano alla categoria che resta.

**Categorie personali**
- Visibili solo a chi le crea; si usano solo sulle righe personali. Una riga condivisa ha sempre una categoria condivisa.
- Possono stare sotto una macro condivisa; non esistono macro interamente personali.
- Si possono promuovere a condivise. Se esiste già una condivisa con lo stesso nome, l'app propone di unirle o di rinominare quella promossa; conferma chi fa l'azione, gli altri membri ricevono la notifica. Nessuno stato "in attesa".
- Se una riga con categoria personale diventa condivisa, l'app chiede una categoria condivisa oppure propone di promuovere quella personale.

## 3. Classificazione

- **Manuale:** nessuna regola automatica e nessun suggerimento di classificazione. Da rivalutare in futuro.
- **Logica di base, senza configurazione:** riconoscimento dei giroconti tra i propri conti (es. ricarica di un conto prepagato, addebito mensile di una carta di credito), abbinamento tra pagamenti PayPal e addebiti su conto o carta, rate degli acquisti a rate, conguagli tra membri, abbinamento dei rimborsi da terzi, Differenza di cassa (sezione 9), flag 730 (sezione 5).
- Nessuna previsione sulle spese da dividere.

## 4. Spese divise in righe

- Una transazione importata arriva come **una riga**; si divide in più righe, ognuna con categoria e quote proprie. Esempio: supermercato 50,00 € = 35,00 € Cibo › Spesa condivisa tra Anna e Bruno + 15,00 € Persona › Cosmetici di Anna.
- **Spesa tutta condivisa:** la ripartizione si sceglie sulla riga unica prima di dividerla; ogni riga nata da una divisione **eredita le quote** della riga da cui nasce. Se una parte è personale si cambia solo quella riga.
- **Visibilità:** ogni membro vede solo le righe in cui è coinvolto (chi ha pagato e chi ha una quota), con data, controparte, importo della riga e quote dei coinvolti. Mai il totale della transazione né quante altre righe ci sono.
- **Quote predefinite e "Con tutti":** valgono le quote predefinite della casa alla **data della spesa** (data reale dell'acquisto, presa dai dati della banca), non alla data di importazione o di classificazione.
- La divisione in righe è manuale fino alla fase degli scontrini.

## 5. Flag "detraibile 730"

- Automatico su **Salute**, **Animali › Veterinario** e **Formazione › Tasse universitarie**.
- Modificabile su ogni riga.

## 6. Viaggi

- La macro Viaggi contiene solo **Trasporto** e **Alloggio**.
- Le altre spese di un viaggio vanno nella loro categoria con il tag del viaggio; il costo totale si legge dal report per tag.

## 7. Elenco iniziale delle spese

| Macro | Sottocategorie | Note |
|---|---|---|
| Casa | Mutuo · Assicurazioni casa e mutuo · Luce · Gas · Acqua · Condominio · Internet · Manutenzione e riparazioni · Arredo ed elettrodomestici · Pulizia e detersivi · Tasse casa · Giardinaggio | Mutuo: tutta la rata, anche la quota capitale. Tasse casa: TARI, IMU |
| Cibo | Spesa · Ristoranti · Delivery | Ristoranti comprende il bar |
| Trasporti | Rata auto · Carburante · Assicurazione e bollo · Manutenzione auto · Pedaggi e parcheggi · Mezzi pubblici · Bici e altro · Multe | |
| Salute (730) | Farmaci · Visite ed esami · Ottico | Visite ed esami comprende il dentista |
| Persona | Abbigliamento · Parrucchiere · Estetista · Cosmetici · Cellulare · Tecnologia | |
| Animali | Alimentazione · Veterinario (730) · Accessori e giochi · Toelettatura | |
| Tempo libero | Abbonamenti · Libri e media · Cinema, concerti, musei · Sport · Hobby | |
| Viaggi | Trasporto · Alloggio | Sezione 6 |
| Regali e donazioni | Regali · Donazioni | Regali con il tag dell'occasione |
| Formazione | Corsi · Materiale · Tasse universitarie (730) | |
| Finanza | Commissioni bancarie · Bolli e tasse · Altre assicurazioni · Tasse personali | Commissioni dei prelievi all'estero registrate a parte |
| Varie | Varie · Differenza di cassa (di sistema) | Una sola "Varie" al posto di un "Altro" in ogni macro |

## 8. Elenco iniziale delle entrate

| Categoria | Note |
|---|---|
| Stipendio | Comprende extra e bonus |
| Rendimenti | Interessi, cedole |
| Vendite usato | |
| Regali ricevuti | |
| Varie | Cashback, rimborsi assicurativi e simili; comprende Differenza di cassa (di sistema) |

Il rimborso del 730 arriva nello stipendio e non è un'entrata a sé. Il rimborso da terzi è un tipo di movimento (Rimborso), non un'entrata.

## 9. Differenza di cassa (categoria di sistema)

- Nasce dalla riconciliazione dei contanti: si conta il contante vero e la differenza con il saldo dell'app diventa un movimento.
- Sotto Varie: spesa se il contante vero è meno del saldo, entrata se è di più.
- Sempre personale, conta nel bilancio, non si archivia e non si unisce.

## 10. Contanti: saldo iniziale [proposta]

- Al primo avvio di Finanze ogni membro può indicare i contanti che ha: è il **saldo iniziale** del conto Contanti, non un'entrata, e resta fuori dal bilancio. Si può saltare e modificare dopo.
- Se viene saltato, la prima conta diventa il saldo iniziale e non una Differenza di cassa.

## 11. Salvadanai

- Due modi: **quota virtuale** accantonata su un proprio conto (senza movimenti bancari) oppure **movimento reale** di tipo Risparmio verso un altro conto o un investimento, collegato al salvadanaio.
- Personali o condivisi con membri scelti. Ognuno accantona dai propri conti; i membri del salvadanaio vedono quanto ha messo ciascuno, mai i saldi dei conti.
- Schema dati: entità salvadanaio con i membri e gli accantonamenti virtuali.
- Interfaccia: card nel Riepilogo di Finanze e schermata Salvadanai.
