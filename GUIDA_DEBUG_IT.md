# Guida al Debug di GuildRoll (Italiano)

## Cosa Cercare Quando Carichi l'Addon

Quando entri nel gioco con GuildRoll abilitato, dovresti vedere questi messaggi nella chat:

### Messaggi di Successo (Verde) - In Ordine

Se tutto funziona correttamente, vedrai questi 6 messaggi verdi:

1. **"[EPGP] epgp.lua loading..."** - Il file epgp.lua sta caricando
2. **"[EPGP] Libraries loaded successfully"** - Le librerie per epgp.lua sono caricate
3. **"[EPGP] get_ep_v3 function defined successfully"** - La funzione critica è stata definita
4. **"[EPGP] epgp.lua loaded completely!"** - epgp.lua è completamente caricato
5. **"[GuildRoll] standings.lua libraries loaded successfully"** - Le librerie per standings sono caricate
6. **"[GuildRoll] GuildRoll_standings module created successfully"** - Il modulo standings è stato creato

✅ **Se vedi tutti i 6 messaggi verdi, l'addon è caricato correttamente!**

### Quando Clicchi per Aprire Standings

Dovresti vedere:
1. **"[GuildRoll] OnClick: Attempting to toggle standings..."** - Il click è stato rilevato
2. **"[GuildRoll] GuildRoll_standings and Toggle exist, calling..."** - Il modulo esiste
3. **"[Standings] Toggle called, forceShow=..."** - Toggle è stato chiamato
4. **"[Standings] Currently attached/Not attached..."** - Stato corrente
5. L'azione intrapresa (attach/detach/refresh)

### Messaggi di Errore (Rosso)

I messaggi di errore in rosso ti diranno esattamente cosa è fallito.

## Scenari Diagnostici

### Scenario 1: NON vedi nessun messaggio [EPGP]
**Significato:** epgp.lua non viene caricato affatto
**Possibili cause:**
- File epgp.lua mancante o corrotto
- Errore nel file .toc
- Errore di sintassi che impedisce l'esecuzione

**Cosa fare:**
- Prendi uno screenshot di TUTTI i messaggi di errore
- Verifica che il file epgp.lua esista in Interface/AddOns/guildroll/

### Scenario 2: Vedi messaggi [EPGP] ma con errori rossi
**Significato:** epgp.lua ha iniziato a caricare ma ha trovato un errore
**Cosa fare:**
- Leggi il messaggio di errore - ti dice esattamente cosa è fallito
- Prendi uno screenshot dell'errore
- Controlla che tutte le librerie siano presenti nella cartella Libs/

### Scenario 3: Tutti i messaggi [EPGP] sono verdi, ma get_ep_v3 ancora nil
**Significato:** La funzione è definita ma non è accessibile
**Cosa fare:**
- Prendi uno screenshot di TUTTI i messaggi verdi
- Condividi il numero di linea esatto dell'errore get_ep_v3
- Questo è uno scenario insolito che richiede ulteriori indagini

### Scenario 4: Il modulo standings è creato ma non si apre
**Significato:** Il modulo è caricato ma Toggle non funziona
**Controlla:**
- Vedi il messaggio "[GuildRoll] OnClick: Attempting to toggle standings..." quando clicchi?
- Vedi il messaggio "[Standings] Toggle called..." ?
- Vedi errori in rosso tipo "[Standings] Error in Toggle: ..." ?

## Cosa Fare Ora

1. **Carica l'addon** - Guarda per i 6 messaggi verdi
2. **Prendi uno screenshot** di TUTTI i messaggi che appaiono
3. **Prova ad aprire Standings**:
   - Clicca sull'icona FuBar (click sinistro)
   - Guarda quali messaggi appaiono
   - Prendi screenshot di eventuali errori
4. **Prova i pulsanti EP** - Nota se c'è ancora l'errore get_ep_v3
5. **Condividi gli screenshot** con tutti i messaggi visibili

## Output di Successo Atteso

Se tutto funziona, dovresti vedere:

```
[EPGP] epgp.lua loading...
[EPGP] Libraries loaded successfully
[EPGP] get_ep_v3 function defined successfully
[EPGP] epgp.lua loaded completely!
[GuildRoll] standings.lua libraries loaded successfully
[GuildRoll] GuildRoll_standings module created successfully

(Quando clicchi sull'icona:)
[GuildRoll] OnClick: Attempting to toggle standings...
[GuildRoll] GuildRoll_standings and Toggle exist, calling...
[Standings] Toggle called, forceShow=nil
[Standings] Currently attached, detaching (showing)...
```

Dopo questi messaggi, la finestra standings dovrebbe apparire!

## Informazioni Importanti da Condividere

Se hai ancora problemi, per favore condividi:

1. **Screenshot** che mostrano:
   - Tutti i messaggi quando l'addon si carica
   - Tutti i messaggi quando clicchi per aprire standings
   - Il messaggio di errore esatto con il numero di linea

2. **Nota cosa NON vedi**:
   - Mancano messaggi [EPGP]?
   - Non vedi messaggi OnClick quando clicchi?
   - Toggle chiamato ma nessun messaggio successivo?

3. **Quali messaggi verdi vedi**:
   - Tutti i 6?
   - Solo alcuni? Quali?
   - Nessuno?

Queste informazioni ci aiuteranno a identificare esattamente il problema!
