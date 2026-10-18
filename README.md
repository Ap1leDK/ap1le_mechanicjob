# ap1le_mechanicjob

Mekanikerjob til ESX Legacy. Mekanikerne reparerer køretøjer, skifter performance-dele fra værkstedets lager,
tuner udseendet i et kamera-styret tuning-panel, bugserer biler på en flatbed, sender fakturaer og bestiller
dele, som ikke er på lager. Chefen har en fysisk computer på værkstedet til lager, bestillinger, personale og økonomi.

## Funktioner

- **Reparationer**: fuld motor- og karosserireparation og dækskift i et værksted. Motorreparation på stedet
  virker overalt med et reparationssæt, dog kun op til en konfigurerbar motorstatus.
- **Performance-skift**: motor, bremser, gearkasse, undervogn, panser og turbo, i niveauer. Hvert skift er to
  fysiske trin med animation: den gamle del tages ud, og den nye monteres. Dele tages fra og lægges tilbage i
  værkstedets lager (stash), ikke i mekanikerens egen taske.
- **Cosmetic tuning**: alle GTA-muligheder for køretøjet, grupperet i kategorier og underkategorier. Man kan
  bevæge kameraet rundt om bilen med musen (træk for at dreje, rul for at zoome) eller bruge kamerapresets.
  Lakering har alle GTA-farver, grupperet i metallic, matte, metal, chrome, perlemor, worn/util og chameleon.
- **Lager og bestilling**: hvert værksted har et lager. Dele, som ikke er på lager, kan bestilles fra tuning-menuen
  eller fra computeren. Virksomheden betaler, og leverancen kommer som en kasse ved leveringspunktet.
- **Chefens computer**: en fysisk computer på hvert værksted med et macOS-lignende UI (skrivebord, menulinje med
  ur, dock og programvinduer). Se afsnittet om computeren.
- **Bugsering**: læs et køretøj op på en flatbed og aflæs det på et afleveringssted.
- **Fakturaer**: en mekaniker sender en faktura med linjer til en spiller i nærheden, som accepterer eller afviser den.
  Beløbet deles mellem virksomhedens konto og den mekaniker, der sendte fakturaen.
- **Værksteder**: fuld reparation, performance-skift, tuning og bestillinger virker kun i et konfigureret værksted
  (undtagen motorreparation på stedet og computerens programmer, der også virker ved computeren).

## Afhængigheder

| Resource | Formål |
|---|---|
| `ap1le_core` | Notifikationer, menuer, dialoger, progress-bjælke og hjælpetekst (UI-laget i hele resourcen) |
| `es_extended` | ESX Legacy-kernen (job, spillere, konti) |
| `ox_lib` | Callbacks, locales og hjælpefunktioner |
| `oxmysql` | Databaseadgang |
| `ox_inventory` | Varer, lagre (stashes) og kasser |
| `ox_target` | Interaktion med køretøjer, lagre, kasser og computeren |
| `esx_addonaccount` | Virksomhedskonto (`society_mechanic`) |

## Installation

1. **Database.** Kør `sql/install.sql` én gang på serverens database. Scriptet opretter jobbet `mechanic` med
   fire grader (0 recruit, 1 mechanic, 2 experienced, 3 boss), virksomhedskontoen `society_mechanic` og disse
   tabeller:
   - `ap1le_mechanicjob_parts`: hvilke performance-dele scriptet har monteret (server-side).
   - `ap1le_mechanicjob_orders`: bestillinger og leverancer, pr. værksted.
   - `ap1le_mechanicjob_invoices`: betalte fakturaer.
   - `ap1le_mechanicjob_transactions`: indsættelser, hævninger, bestillinger og fakturaer til økonomien.
   - `ap1le_mechanicjob_prices`: prisliste for cosmetic-dele, som overskriver priserne i `config.lua`.

   Scriptet kan køres igen uden problemer: eksisterende grader (også nogen, du har omdøbt eller ændret løn på)
   bliver ikke rørt. Det ændrer ikke `owned_vehicles`.

   **Genstart serveren bagefter.** ESX læser jobs og grader, og esx_addonaccount læser virksomhedskonti, kun når
   de starter. Indtil genstarten virker ansættelse/forfremmelse og bestillinger ikke.
2. **Items.** Åbn `install/items.lua` og indsæt alle elementerne i hovedtabellen i `ox_inventory/data/items.lua`.
   Læg et PNG-billede pr. vare i `ox_inventory/web/images/<navn>.png`, fx `engine_lvl1.png`. Genstart derefter
   `ox_inventory`. Filen indeholder alle reparationssæt, performance-dele på alle niveauer og turbo.
3. **Resource.** Kopiér mappen `ap1le_mechanicjob` til din `resources`-mappe.
4. **server.cfg.** Start resources i denne rækkefølge (ap1le_core skal være før dette script):

   ```
   ensure oxmysql
   ensure ox_lib
   ensure es_extended
   ensure ox_inventory
   ensure ox_target
   ensure esx_addonaccount
   ensure ap1le_core
   ensure ap1le_mechanicjob
   ```

5. **Giv jobbet.** Tildel jobbet `mechanic` til en spiller med ESX's jobværktøjer og vælg en grad. Alle grader
   kan bruge alle funktioner undtagen chefens programmer, som kræver grad 3 eller højere (se nedenfor).

## Konfiguration

Alt indstilles i `config.lua`. Vigtigste punkter:

- **Værksteder (`Config.Workshops`)**. Hvert værksted har en `id`, en `label`, `coords` og `radius` (sfæren hvor
  fuld reparation, skift og tuning virker), en blip og tre punkter:
  - `stash`: værkstedets lager. Lageret er et ox_inventory-stash med id `ap1le_mechanicjob_<id>`, og det oprettes
    automatisk ved start. `slots` og `weight` sætter størrelsen.
  - `computer`: computerens position og retning (`w`). `spawnProp = true` spawner en bærbar computer med
    `prop_laptop_01a` på pladsen.
  - `delivery`: hvor leverede kasser står, klar til afhentning.
- **`Config.BossGrade`**: den mindste jobgrad, der er "chef" (standard `3`). Chefen bruger personale, økonomi og
  prisliste på computeren. Serveren tjekker grad ved hvert kald.
- **`Config.Repair`**, **`Config.Performance`**: dele, tider og niveauer for reparationer og skift.
- **`Config.Shop`**: leveringstid (`deliveryMinutes`), oppakningstid (`unpackTime`), højeste antal pr. vare og
  pr. ordre (`maxPerLine`, `maxLines`), højeste antal åbne ordrer pr. værksted (`maxOpenOrders`), og prisen pr.
  vare i `items`.
- **`Config.Cosmetic`**: grupper, underkategorier, mods og ekstra valg, med standardpris og animation for hver.
  `maxPrice` er den højeste pris, chefen kan sætte i prislisten.
- **`Config.Invoice`**: virksomhedskonto, andel til virksomheden (`societyShare`), største antal linjer og samlet
  beløb, udløbstid, afstand og ventetid.
- **`Config.Computer`**: afstande til computeren, bankkonto til ind- og udbetalinger, højeste overførselsbeløb og
  antal historikrækker.
- **`Config.Towing`**: flatbed-model og forskydninger.

Ændr kun varenavne, hvis du også ændrer dem i `install/items.lua`.

## Lager og bestillinger

Hvert værksted har sit eget lager. Performance-skift tager den nye del fra lageret og lægger den gamle tilbage.
Hvis den nye del ikke er på lageret, kan du se det i tuning-menuen (knappen "Bestil" ved niveauer uden lager) og
bestille den der, eller bestille den fra computerens program "Bestil".

En bestilling fungerer sådan:

1. Mekanikeren vælger varer og antal. Serveren tjekker varerne mod `Config.Shop.items`, antal og linjer, og at
   værkstedet ikke har for mange åbne ordrer. Prisen tages fra konfigurationen, ikke fra spilleren.
   Mekanikere under chef-graden kan kun bestille små ordrer: 1 slags vare, højst 2 stk., højst $30.000 pr. ordre
   og højst 2 åbne ordrer ad gangen (konstanterne `STAFF_MAX_*` øverst i `server/stock.lua`). Chefen har de fulde
   grænser fra `Config.Shop`.
2. Virksomhedskontoen betaler summen. Hvis den ikke har penge nok, bliver bestillingen afvist.
3. Ordren står som "på vej" i `Config.Shop.deliveryMinutes`. I den tid ser alle mekanikere ordrerne i
   computerens "Ordrer"-program og i F6-menuen under "Åbne bestillinger".
4. Når tiden er gået, står en kasse ved værkstedets leveringspunkt. Alle mekanikere får besked om det.
5. En mekaniker går hen til kassen og vælger "Pak kassen ud". Kassen åbnes med animation og bar, og varerne
   lægges i værkstedets lager. Hvis lageret er fuldt, bliver kassen stående, og der kommer en besked.

Ordrer gemmes i databasen, så de overlever en genstart af serveren.

## Computeren

Computeren er en fysisk bærbar på værkstedet. Man bruger den med target-menuen "Brug computeren". Den har et
macOS-lignende UI med skrivebord, menulinje (med ur og værkstedets navn), dock og vinduer, som kan flyttes,
minimeres og lukkes. Det røde trafiklys lukker et vindue. Esc eller "Luk computer" i menuen lukker computeren.

| Program | Hvem | Hvad |
|---|---|---|
| **Lager** | Alle mekanikere | Varer i værkstedets lager med antal og status (på lager, lav beholdning, ikke på lager). Søg og filtrér efter kategori. |
| **Bestil** | Alle mekanikere | Katalog med varer, kurv, antal og total. "Virksomheden betaler". "Bestil" sender ordren. |
| **Ordrer** | Alle mekanikere | Åbne og afhentede ordrer med en nedtælling til leveringen. |
| **Personale** | Chef | Ansatte med online-status og stilling. Ansæt nærliggende spillere, skift stilling eller fyr. |
| **Økonomi** | Chef | Virksomhedens saldo, indsæt og hæv på chefens konto, og historik over fakturaer, ordrer og overførsler. |
| **Prisliste** | Chef | Overskriv priser på cosmetic-dele. Ændringer gemmes først, når du trykker "Gem priser". |

Regler for chefen:

- Personale: man kan kun ansætte spillere, der står inden for `Config.Computer.hireDistance` fra computeren og
  ikke allerede er mekanikere. Spilleren får et jobtilbud på sin egen skærm og skal selv sige ja (tilbuddet lukker
  efter 30 sekunder); først derefter skifter jobbet. Man kan kun ændre og fyre ansatte med en lavere stilling end sin egen, og aldrig sig selv.
  Ansatte, der er offline, kan også ændres.
- Økonomi: indsættelse og hævning går mellem chefens bankkonto (`Config.Computer.account`) og virksomhedskontoen,
  og beløbet er et helt tal fra 1 til `maxTransfer`.
- Prisliste: hver pris skal være et helt tal fra 0 til `Config.Cosmetic.maxPrice`. Priserne gemmes i databasen
  og overskriver standardpriserne i `config.lua`.

Alle kald til computeren tjekker, at spilleren er inden for `Config.Computer.serverDistance` fra computeren på
serveren. Det er ikke nok, at klienten siger det.

## Fakturaer

- Mekanikeren åbner "Send faktura" fra F6-menuen. Dialogen viser de nærmeste spillere og en linje pr. prisregel,
  med standardprisen udfyldt. Der kan tilføjes én ekstra linje. Linjer med 0 udelades.
- Kunden får en bekræftelse med linjer, samlet beløb og en nedtælling. Svarer kunden ikke i tide, udløber fakturaen.
- Når kunden betaler, går `Config.Invoice.societyShare` (standard 70 %) til virksomhedskontoen. Resten går til
  mekanikerens bankkonto. Begge får besked. Betalte fakturaer gemmes i `ap1le_mechanicjob_invoices`.
- Serveren tjekker totalen, antal linjer, afstanden og ventetiden. Klienten kan ikke ændre beløbene.

## Sikkerhed

- Serveren tjekker job, grad, afstand, værksted, varer, penge og tid ved hvert kald. Klienten sender kun ID'er og valg.
- Varenavne, priser, antal og tider kommer fra `config.lua` på serveren, aldrig fra klienten.
- Kald der gentages, er begrænset i tid, og mistænkelige kald logges med præfikset `[ap1le_mechanicjob] suspicious:`.
- Chefens programmer tjekker grad på serveren. ox_target's `groups` er kun for bekvemmelighed.
- Lager- og værkstedskald tjekker serverside, at spilleren faktisk står i værkstedet eller ved computeren.
- Tuning kan kun gemmes på køretøjer i `owned_vehicles`, og kun når ejeren er til stede eller har den rigtige
  model. Skift af performance-dele er underlagt de samme regler.
- Cosmetic-værdier kontrolleres for type og område, før de gemmes. Ved gem skrives kun de cosmetic-nøgler, så
  performance-niveauer ikke kan ændres via tuning-menuen.

## Test-tjekliste

Test med en mekaniker og en kunde, begge med jobbet `mechanic`, på en server med afhængighederne installeret.

- [ ] Serveren starter uden fejl, og sprogfilerne `da` og `en` indlæses.
- [ ] En spiller uden jobbet ser ingen mekanikermuligheder og kan ikke starte en handling.
- [ ] Værkstederne vises som blips på kortet.
- [ ] Motorreparation i et værksted bruger sættet og reparerer motoren. Uden for værkstedet afvises den.
      Reparation på stedet virker overalt med et reparationssæt.
- [ ] Skift af en performance-del tager den nye del fra værkstedets lager, og den gamle del lægges i lageret.
- [ ] Afbrydelse midt i et skift (X) stopper animationen og efterlader varerne uændrede.
- [ ] Hvert niveau og hver kategori virker, og niveauet på et ejet køretøj er det samme efter genstart.
- [ ] Et skift eller en gemning på et andet spillers bil afvises, når ejeren er offline eller mere end 30 m væk.
- [ ] Tuning-panelet: træk for at dreje, rul for at zoome, kamerapresets, kurv og "Monter". Ikke-ejede køretøjer får
      en besked om, at intet gemmes.
- [ ] Bestilling af en vare uden lager fra tuning-menuen: virksomheden betales, og ordren vises under "Åbne bestillinger".
- [ ] Efter leveringstiden står kassen ved leveringspunktet. Den kan pakkes ud, og varerne ligger i lageret.
      Pakkes den ud, når lageret er fuldt, bliver den stående.
- [ ] Computeren åbnes med animation, og alle programmer virker for en mekaniker. Chefens programmer er skjult for
      almindelige mekanikere, og serveren afviser deres kald, selv hvis de sendes direkte.
- [ ] Chefen kan ansætte en nærliggende spiller, ændre stilling og fyre. Stillinger over egen grad kan ikke ændres.
- [ ] Chefen kan indsætte og hæve. Historikken viser fakturaer, ordrer og overførsler.
- [ ] Prislisten gemmer ændringer, og en ugyldig pris afvises.
- [ ] Bugsering: læs et køretøj op på flatbed'en, kør af sted og aflæs det på leveringspunktet.
- [ ] Send en faktura til en spiller i nærheden. Accepter: kunden betales, virksomheden får 70 % og mekanikeren
      30 %. Begge får en besked med beløbet.
- [ ] Afvis en faktura, og lad en anden udløbe. Begge sider får besked.
- [ ] En faktura for langt væk, med for mange linjer eller over det højeste beløb afvises.
- [ ] Genstart resourcen: ingen spøgelsesprops, kameraer, computere eller NUI-fokus bliver tilbage.

## Skærmbilleder

Taget med demodata i Chromium (bilen er en placeholder, ikke spillet).

**Tuning**

| Ydelse (lager og bestil) | Underkategorier |
|---|---|
| ![](docs/screenshots/tuning-1080-01-performance.png) | ![](docs/screenshots/tuning-1080-04-sub.png) |
| **Fælge pr. fælgtype** | **Alle farver, sorteret efter type** |
| ![](docs/screenshots/tuning-1080-06-wheels.png) | ![](docs/screenshots/tuning-1080-08-colour-metallic.png) |
| **Kurv** | |
| ![](docs/screenshots/tuning-1080-14-cart.png) | |

**Chefens computer**

| Skrivebord | Bestil |
|---|---|
| ![](docs/screenshots/laptop-1080-01-desktop.png) | ![](docs/screenshots/laptop-1080-03-order.png) |
| **Ordrer** | **Personale** |
| ![](docs/screenshots/laptop-1080-04-orders.png) | ![](docs/screenshots/laptop-1080-05-staff.png) |
| **Økonomi** | **Prisliste** |
| ![](docs/screenshots/laptop-1080-06-eco.png) | ![](docs/screenshots/laptop-1080-07-prices.png) |

