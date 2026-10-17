# ap1le_mechanicjob: architecture contract v2

Binding for every file. v1 code exists and works; v2 changes it. Read the existing file(s) you own
before rewriting, keep what works (especially the security checks and the animations), and change
only what v2 requires. Do not rename anything defined here. Anything you add that other files need
must be reported under "contract additions".

Stack: ESX Legacy (`ESX` global), ox_lib, oxmysql, ox_inventory, ox_target, esx_addonaccount and
**ap1le_core** (`@ap1le_core/imports.lua`, global `Ap1le`). Source of ap1le_core:
`/home/user/ap1ledk/ap1le_core/ap1le_core` (read its README.md and the module you use; it is the
authority on its API). Lua 5.4. Plain HTML/CSS/JS NUI, no frameworks, no CDN.
`config.lua` (shared) is final and owned by the lead: read it, never edit it.
FiveM CEF is Chrome 103: no `:has()`, `color-mix()`, CSS nesting, `linear()` easing.

## 0. What changed in v2 (user requirements)

1. Use ap1le_core as much as possible: `Ap1le.Notify` for all notifications (client and server),
   `Ap1le.Progress` for every progress/timer bar (replaces the GTA timer bar), `Ap1le.RegisterMenu`/
   `ShowMenu` for menus, `Ap1le.InputDialog`/`Ap1le.Confirm` for dialogs, `Ap1le.ShowTextUI`/`HideTextUI`
   for help text. The tuning NUI and the laptop NUI use ap1le_core's design tokens and icons
   (`nui://ap1le_core/html/css/base.css` and Font Awesome, already linked in html/index.html).
   Danish is the main language (ap1le_core is Danish); English locale stays as second language.
2. The animations stay (the user likes them). Only their UI layer changes to Ap1le.Progress.
3. Tuning: the player can orbit/pan the camera around the car with the mouse (drag) and zoom (wheel),
   besides the presets. Remove unnecessary subtitles/eyebrows in the UI (no "VEHICLE TUNING", no
   "CAMERA" label, no item names under level names, no "WORK ORDER" caption). Every cosmetic option
   GTA offers is available and grouped in sub-categories (Config.Cosmetic.groups / sub, plus client-built
   subs such as wheel types and paint types). Paint offers every GTA colour, grouped by type
   (metallic, matte, metals, chrome, pearlescent, worn/util, chameleon if the game build supports it).
4. Parts storage per workshop (ox_inventory stash). Performance swaps take the new part from the
   stash of the workshop the mechanic is in, and put the old part back in that stash.
5. Parts not in stock can be ordered (from the tuning menu for that part, or from the computer).
   Society pays. The order arrives after `Config.Shop.deliveryMinutes` as a crate at the workshop's
   delivery point; a mechanic must go there and unpack it (Ap1le.Progress + animation) into the stash.
6. A physical computer (laptop prop) per workshop with a MacBook-style UI (macOS desktop, menu bar
   with clock, dock, app windows). Apps: Lager (stock), Bestil (order parts, cart), Ordrer (order
   status), and for the chef (grade >= Config.BossGrade): Personale (hire nearby, fire, promote/demote,
   online status), Økonomi (society balance, deposit, withdraw, history of invoices/orders/transfers),
   Prisliste (override cosmetic prices). Every mechanic can use Lager, Bestil, Ordrer.
7. Invoices: creation via `Ap1le.InputDialog`, customer answer via `Ap1le.Confirm`. The custom invoice
   NUI views are removed. Invoice prefill prices come from the price list (DB overrides of config).

## 1. Files and owners

| File | Owner |
|---|---|
| fxmanifest.lua, config.lua, docs/CONTRACT.md, html/index.html, html/js/common.js | lead (done) |
| server/main.lua, repair.lua, performance.lua, tuning.lua, billing.lua, stock.lua, computer.lua, sql/install.sql | server dev |
| client/ui.lua, client/anims.lua | animation dev |
| client/tuning.lua, shared/colours.lua | tuning client dev |
| client/main.lua, client/repair.lua, client/billing.lua, client/towing.lua, client/stock.lua, client/computer.lua | business client dev |
| html/css/tuning.css, html/js/tuning.js | tuning NUI dev |
| html/css/laptop.css, html/js/laptop.js | laptop NUI dev |
| locales/en.json, locales/da.json, install/items.lua, README.md | docs dev (runs after the others) |

`html/legacy-script.js` and `html/legacy-style.css` are the v1 NUI (tuning + invoice). They are not
loaded. The tuning NUI dev may reuse code from them and deletes both files when done.
Load order: see fxmanifest.lua. Locale keys: use `locale('key', ...)`; name new keys clearly
(prefix per area, e.g. `stock_`, `order_`, `pc_`, `ui_` for NUI). The docs dev collects every key
used in the code afterwards, so list the keys you used (with %s/%d placeholders and a short English
meaning) in your report.

## 2. Core rules (unchanged from v1 unless noted)

- Only `Config.Job` players can use anything; the server re-checks every call. Chef = job grade
  >= `Config.BossGrade` (server-checked for chef apps).
- Workshop = inside a `Config.Workshops[i]` sphere. Full repairs, swaps, tuning: workshop only.
- Server never trusts client values for items, amounts, prices, levels, timing, workshop or computer.
- Performance swaps only on owned vehicles; current level from the DB; owner-present rule and the
  `ap1le_mechanicjob_parts` table from v1 stay.
- Plates compared trimmed. Level numbering: 0 = stock, 1..#levels = item index.

## 3. Server API

All `lib.callback.register`, return `ok, data` (data = locale key on failure). Existing v1 callbacks
keep their names and shapes unless listed here. Notifications from the server: `Ap1le.Notify(source,
msg, type)` (types `success|error|warning|info`); the v1 `ap1le_mechanicjob:notify` event is removed.

Stash (server/stock.lua):
- On start, register one stash per workshop: id `ap1le_mechanicjob_<workshop.id>`, label/slots/weight
  from config, `groups = { [Config.Job] = 0 }`, coords = stash.coords
  (`exports.ox_inventory:RegisterStash`). Helper `Mechanic.StashId(workshop)`.
- `ap1le_mechanicjob:stock:get` () -> mechanic in a workshop OR at a computer. Returns
  `true, { workshop = id, label, items = { { name, label, count } } }` (aggregated per item name).

Swaps (server/performance.lua, changed):
- `perf:begin` checks the new item in the stash of the mechanic's current workshop (not the player's
  inventory) and that the stash can take the old item (`CanCarryItem` on the stash id). Pending stores
  the stash id. `perf:finish` removes the new part from that stash and adds the old part to it.
- `tuning:canOpen` additionally returns `stock = { [item] = count }` for every Config.Performance
  item in that stash, `prices = { [id] = price }` (price list, see computer), and `workshop = id`.

Orders and deliveries (server/stock.lua):
- `ap1le_mechanicjob:order:place` (lines) lines = `{ { item = string, count = int }, ... }`. Mechanic
  in a workshop or at a computer (that computer's workshop). Items must be keys of
  `Config.Shop.items`; 1..maxLines lines, count 1..maxPerLine, merge duplicates, price from config only,
  at most maxOpenOrders open orders per workshop. Society (esx_addonaccount, `Config.Invoice.society`)
  must cover the total: `account.removeMoney(total)` (check balance first and re-check result).
  Insert into `ap1le_mechanicjob_orders` with status `ordered`, `ready_at = now + deliveryMinutes`.
  Return `true, { id, total, eta = seconds }`. Rate limit 3 s.
- A server loop (every 15 s) moves due orders to status `arrived` and publishes all arrived crates in
  `GlobalState['ap1le_mechanicjob:crates'] = { { id, workshop, coords = {x,y,z,w} } }`. Crate positions:
  the workshop's `delivery` point, offset 1.2 m per crate along the heading so crates do not overlap.
  Rebuilt from the DB on resource start (orders survive restarts).
- `ap1le_mechanicjob:order:unpackBegin` (orderId) -> mechanic, order `arrived`, player within 3 m of its
  crate, no other pending. Pending `{ kind = 'unpack', orderId, minMs = Config.Shop.unpackTime * MinTimeFactor }`.
- `ap1le_mechanicjob:order:unpackFinish` () -> pending, elapsed, distance; the stash must fit all items
  (CanCarryItem per item on the stash); AddItem each; status `collected`, `collected_by`; republish crates.
  If the stash is full: fail with `stock_full`, keep the order arrived.
- `ap1le_mechanicjob:order:list` () -> last 25 orders of the player's workshop
  `{ id, items = { {item, label, count} }, total, status, eta (seconds, ordered only), ordered_by, created_at }`.

Computer (server/computer.lua). Every call: mechanic AND within `Config.Computer.serverDistance` of a
workshop's `computer.coords`; that workshop is the context. Chef calls also require grade >= BossGrade.
- `computer:open` () -> `true, { name, grade, gradeLabel, isBoss, workshop = { id, label } }`
- Shared apps reuse `stock:get`, `order:place`, `order:list` (they accept the computer position).
- `computer:catalog` () -> `{ { item, label, price, stock } }` for every `Config.Shop.items` key.
- Chef: `computer:staff` () -> `{ { identifier, name, grade, gradeLabel, online, serverId? } }` from `users`
  (job = Config.Job) plus online state; and `grades = { { grade, label } }` from `job_grades`.
- Chef: `computer:nearby` () -> players within `hireDistance` of the computer who are not mechanics
  `{ { serverId, name } }`.
- Chef: `computer:hire` (serverId) -> target online, near the computer, not already a mechanic:
  `xTarget.setJob(Config.Job, 0)`.
- Chef: `computer:setGrade` (identifier, grade) -> not self; target currently a mechanic; target's
  current grade < chef grade; new grade integer 0..(chefGrade - 1) and must exist in job_grades. Online:
  setJob; offline: `UPDATE users SET job_grade = ? WHERE identifier = ? AND job = ?`.
- Chef: `computer:fire` (identifier) -> same rank rules; online: `setJob('unemployed', 0)`; offline:
  `UPDATE users SET job = 'unemployed', job_grade = 0 WHERE identifier = ? AND job = ?`.
- Chef: `computer:economy` () -> `{ balance, history = { { type = 'invoice'|'order'|'deposit'|'withdraw', amount, by, detail, created_at } } }`
  (last `historyRows`, newest first, from the invoices/orders/transactions tables).
- Chef: `computer:deposit` (amount) / `computer:withdraw` (amount) -> integer 1..maxTransfer, moves
  money between the chef's `Config.Computer.account` and the society; logs a transaction row.
- Chef: `computer:prices` () -> `{ { id, label, group, default, price } }` for every Config.Cosmetic mod
  and extra. `computer:setPrices` (map id -> int) -> each id must exist, int 0..Config.Cosmetic.maxPrice;
  upsert `ap1le_mechanicjob_prices`; cache in memory. Helper `Mechanic.GetPrices()` -> `{ [id] = price }`.

Invoices (server/billing.lua): API unchanged; additionally insert every paid invoice into
`ap1le_mechanicjob_invoices` (id, mechanic identifier + name, customer identifier + name, total,
society_share, lines JSON, created_at). Notifications via Ap1le.Notify.

Tuning save (server/tuning.lua): allowed cosmetic keys = every `Config.Cosmetic.mods[i].id` plus
`wheels, modCustomTiresF, modCustomTiresR, modSmokeEnabled, tyreSmokeColor, wheelColor, color1, color2,
pearlescentColor, paintType1, paintType2, interiorColor, dashboardColor, modXenon, xenonColor,
neonEnabled, neonColor, windowTint, plateIndex, modLivery, livery`. Per-key type/range validation as in v1
(check ox_lib's lib.getVehicleProperties for the exact key names and value shapes and adjust the list to
the real names; report differences).

SQL (sql/install.sql, server dev): keep v1 statements; add `CREATE TABLE IF NOT EXISTS` for
`ap1le_mechanicjob_orders` (id PK auto, workshop, items JSON/LONGTEXT, total, status, ordered_by
identifier, ordered_by_name, created_at, ready_at, collected_by), `ap1le_mechanicjob_invoices`,
`ap1le_mechanicjob_transactions` (id, workshop?, type, amount, identifier, name, created_at),
`ap1le_mechanicjob_prices` (id VARCHAR PK, price INT). Use DATETIME/TIMESTAMP or unix INT
consistently and document which.

## 4. Client globals

client/ui.lua + client/anims.lua (animation dev):
- `Anim.*` API unchanged (Repair, Swap, Cosmetic, Winch, IsBusy, StopAll) plus `Anim.Unpack(crate, totalMs)`
  (open a crate with a crowbar and carry boxes, ends near the crate) and `Anim.Laptop(laptopEntity)` /
  `Anim.StopLaptop()` (stand at the laptop and type, looping until stopped).
- Every step of a sequence shows `Ap1le.Progress({ label = '<step text> (i/n)', duration = stepMs,
  icon = <fitting FA icon>, canCancel = true, disable = { move = true, car = true, combat = true } })`
  with NO anim/prop in the Progress call (Anim drives the ped). The step's work runs while the bar
  runs. Progress returning false (cancel key X from ap1le_core, death, ragdoll ...) cancels the
  sequence. Verify in ap1le_core/client/progress.lua how a Progress without `anim` stops (it must not
  ClearPedTasks our ped mid-sequence; if it does, work around it) and how back-to-back bars behave
  (CancelProgress, a stale bar resolving false must not cancel the next step).
- Remove the GTA timer bars, instructional buttons and v1 help text from sequences. ui.lua keeps
  thin wrappers for compatibility: `UI.Notify(msg, type)` -> `Ap1le.Notify(msg, type)` (map v1
  `inform` -> `info`), `UI.HelpText`/`UI.Shard` may be removed if unused by others (search the client
  files).

client/main.lua (business client dev): `Mechanic` global as v1 (IsMechanic, InWorkshop, GetTargetVehicle,
`Mechanic.RequestControl`, `Mechanic.IsBoss()` = grade >= BossGrade). ox_target registrations as v1, plus
stash targets (open the stash with `exports.ox_inventory:openInventory('stash', id)`), crate targets
and computer targets (see stock.lua / computer.lua). F6 job menu via `Ap1le.RegisterMenu`/`ShowMenu`
(send invoice, field repair, show open orders). `RegisterNUICallback('locale')` returns keys starting
with `ui_` and `pc_`.

client/tuning.lua (tuning client dev): `Tuning.Open(vehicle)` as v1 with the v2 payload (section 6),
orbit camera, order button, swaps from stash (the v1 swap flow, section 7 of v1, is unchanged on the
client except the stock check). shared/colours.lua: `Colours = { groups = { { id, label, colours = {
{ index, label, hex } } } } }` with every GTA vehicle colour (research a reliable list with hex values,
e.g. a decompiled data dump or a well-known resource; include chameleon 161-223 in its own group with a
note that it needs game build 2944+). Also used for pearlescent, wheel, interior and dashboard colours.

client/billing.lua: `Billing.OpenCreate(prefillLines?)` -> `Ap1le.InputDialog`: a `select` of nearby
players (server ids and names), one `number` field per prefill line (label = line label, default =
price, min 0), one optional extra line (input label + number), confirm label "Send faktura". Lines
with 0 are dropped. Calls `invoice:create`. Customer: on `ap1le_mechanicjob:invoice:show` show
`Ap1le.Confirm({ title, content = lines + total + "udløber om N sek.", confirmLabel = 'Betal' })` and
respond; on `invoice:hide` call `Ap1le.CloseDialog()` if that invoice is shown. Handle Confirm returning
false immediately because another dialog is open (retry after it closes, do not auto-decline).

client/stock.lua: stash targets per workshop, crate rendering from `GlobalState['ap1le_mechanicjob:crates']`
(AddStateBagChangeHandler on global; spawn local, non-networked crate props within 60 m only, delete
when out of range or collected; ox_target "Pak kassen ud" -> unpackBegin, `Anim.Unpack`, unpackFinish).

client/computer.lua: spawn the laptop prop (`prop_laptop_01a`, verify) on each workshop computer when
`spawnProp`, closed or open screen; ox_target "Brug computeren" (mechanics). Opening: `computer:open`,
`Anim.Laptop(prop)`, optional scripted camera looking at the screen, `SetNuiFocus(true, true)`,
`SendNUIMessage({ action = 'laptop:open', data = <computer:open data + Config.Shop info> })`.
NUI callback `laptop:request` `{ method, args }`: method must be in a whitelist (`stock:get`,
`order:place`, `order:list`, `computer:catalog`, `computer:staff`, `computer:nearby`, `computer:hire`,
`computer:setGrade`, `computer:fire`, `computer:economy`, `computer:deposit`, `computer:withdraw`,
`computer:prices`, `computer:setPrices`) -> `lib.callback.await('ap1le_mechanicjob:' .. method, false,
table.unpack(args or {}, 1, 4))` -> `cb({ ok = ok, data = data, error = not ok and locale(data or 'error') })`.
For mutating methods also `Ap1le.Notify` the result. `laptop:close` -> release focus, StopLaptop,
camera off, `cb({ ok = true })`. Close also on walking away / resource stop.

## 5. ox_target summary

Global vehicle options as v1. Stash per workshop (all mechanics). Laptop per workshop (all mechanics).
Crates (all mechanics). Flatbed model options as v1.

## 6. Tuning NUI protocol (v2)

Lua -> NUI `openTuning`:
```
{ vehicle = { label, plate, owned },
  groups = {                                   -- order of Config.Cosmetic.groups, first group = performance
    { id = 'performance', label = 'Ydelse', icon = 'gauge-high', items = {
        { type = 'performance', id = 'engine', label, current = level,
          options = { { level = 0, label = 'Standard' }, { level = 1, label = 'Niveau 1', item, stock = n, price = <shop price> } } } } },
    { id = 'bodywork', label, icon, items = <nodes> }, ... } }
node =
  { type = 'sub',    id, label, items = { <nodes> } }                                 -- sub-category
  { type = 'mod',    id, label, price, current, options = { { value, label } } }       -- value -1 = standard
  { type = 'colour', id, label, price, current = index, groups = Colours.groups }     -- id: color1|color2|pearlescent|wheelColor|interiorColor|dashboardColor
  { type = 'toggle', id, label, price, current = bool }                              -- e.g. xenon on/off, tyre smoke on/off, custom tires
  { type = 'rgb',    id, label, price, current = { r, g, b } }                        -- neon colour, tyre smoke colour
  { type = 'list',   id, label, price, current, options = { { value, label } } }       -- window tint, plate type, xenon colour, wheel type, neon layout
```
Wheels: `sub` per wheel type (Sport, Muscle, Lowrider, SUV, Offroad, Tuner, Bike, High End, Benny's
Original, Benny's Bespoke, Open Wheel, Street, Track where supported); selecting a rim in another type
also previews that wheel type. Only categories the vehicle supports are sent. Prices from
`tuning:canOpen` prices.

NUI -> Lua:
- `tuning:preview` `{ id, value }` -> Lua finds the node by id (and wheel type for rims, e.g. id
  `modFrontWheels:<wheelType>`), applies locally; cb `{ ok }`.
- `tuning:camera` `{ focus }` presets as v1. `tuning:orbit` `{ dx, dy }` (pixels moved while dragging
  on the free screen area, NUI throttles to <= 30/s) and `tuning:zoom` `{ delta }` (wheel). Lua keeps
  yaw/pitch/radius around the vehicle centre with sensible clamps (pitch -10..60 deg, radius from model
  dimensions); presets animate to their yaw/pitch/radius.
- `tuning:install` `{ changes = { { id, value, label, price } } }`, `tuning:swap` `{ category, level }`,
  `tuning:close` {} as v1.
- `tuning:order` `{ item }` -> Lua calls `order:place` with `{ { item, count = 1 } }`; cb `{ ok, error?, eta? }`;
  Ap1le.Notify the result. The NUI shows an "Bestil" button on levels whose stock is 0.

The tuning panel is on the right; the rest of the screen is the drag area for the camera. Layout:
header (vehicle name + plate + close), group list (icons) -> items -> options with breadcrumbs/back,
cart (lines + total) and Install. Keyboard: arrows, Enter, Backspace = back, Esc = close.

## 7. Laptop NUI protocol

Lua -> NUI: `laptop:open` data `{ name, grade, gradeLabel, isBoss, workshop = { id, label }, shop = {
deliveryMinutes } }`, `laptop:close` {}.
NUI -> Lua: `laptop:request` `{ method, args }` -> `{ ok, data, error }`; `laptop:close` {}.
macOS look: wallpaper, top menu bar (Apple-like logo replaced by a wrench icon, active app name, clock,
workshop name), dock with app icons (chef apps hidden for non-chefs), draggable windows with traffic
light buttons, Finder-like sidebar in apps where it fits. Built with ap1le_core tokens but in macOS
light/dark style (dark). Bestil: catalog grid with stock badge, quantity stepper, cart, total, society
pays, "Bestil" -> order:place; afterwards Ordrer shows ETA countdown. Personale: list with online dot,
grade select, fire (with confirm inside the NUI), "Ansæt" list from computer:nearby. Økonomi: balance,
deposit/withdraw inputs, history table. Prisliste: grouped table with editable prices and Save.
Esc or the red traffic light of the last window, or a "Luk computer" menu item, closes.

## 8. Locale

Danish first. Docs dev produces both files from the keys found in the code afterwards.
