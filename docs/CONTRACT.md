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

---

# v3: user feedback after in-game testing (binding, overrides v2 where it conflicts)

The user tested v2 in game. Everything below is a reported bug or a requested feature. Keep all
other v2 behaviour. Owners as in v2 section 1, plus the new files listed here.

## A. Bugs (each must be root-caused, not papered over)

| # | Bug as reported | Owner |
|---|---|---|
| A1 | Depositing money to the society from the laptop shows an error. Use standard ESX instead of our own society code: **esx_society** for laptop deposit/withdraw/balance (`esx_society:depositMoney` / `esx_society:withdrawMoney` server events triggered by the chef's client, balance via the `esx_society:getSocietyMoney` server callback; read the real esx_society source to get exact names/args and its boss check, which uses `grade_name == 'boss'`). On start, register the society with esx_society (`esx_society:registerSociety` for Config.Job / Config.Invoice.society) if that is the standard way. For server-side society moves (orders, invoice share) use the standard `esx_addonaccount:getSharedAccount` pattern without the extra after-the-fact balance comparison that can falsely fail (check `account.money >= x` before removeMoney; that is it). Also log transactions as before. Note in README: after running the SQL, restart esx_addonaccount/esx_society (or the server), otherwise the new shared account is not loaded. | server + laptop NUI + business client |
| A2 | Tuning UI is not centred; some parts look relatively positioned (layout shifts). | tuning NUI |
| A3 | Ordering an item from the tuning prompt fails; the user then sees "Try again in a moment" (= server `too_fast` rate limit), so the order is sent twice or right after another order:* call. Fix the double call and make the first error visible correctly. | tuning NUI + tuning client + server |
| A4 | The "Level X" row becomes very tall, but only when the "Try again in a moment" error text is shown in it. | tuning NUI |
| A5 | Engine swap gets cancelled when the mechanic fetches the hoist. Find out why (Ap1le.Progress interrupt rules, our distance check vs. where the hoist is fetched, a stale progress token, disable.move vs. tasks ...) and fix it for every sequence step that walks. | anims |
| A6 | Props are not rotated correctly (hoist, engine block, wheels, panels, tools). Fix each prop's rotation/offset using the model's real dimensions (GetModelDimensions) and the bone axes; document each offset. | anims |
| A7 | Remove the icons ("emojis") from the progress bar: no `icon` in Ap1le.Progress calls. | anims (+ any other caller) |
| A8 | Free camera: horizontal drag is inverted (left/right only; vertical is fine). | tuning client |
| A9 | Chameleon colours do not work. Find out how chameleon paints must be applied (paint type / both primary and secondary / pearlescent / mod kit; check how qbx_customs or other working resources do it) and make them work; keep the build check. | tuning client (+ server save whitelist if keys change) |

## B. Features

B1. Remove the parts visually while they are out (user request). Wheels: the wheel must really be gone
from the car while it is off (research the least destructive way: e.g. `SetVehicleWheelXOffset`/
`SetVehicleWheelWidth`/`SetVehicleWheelSize` tricks, or BreakOffVehicleWheel + full restore of
health/deformation/dirt afterwards; pick what really works and restores perfectly; never leave
the car damaged or repaired for free). Engine: GTA has no native to remove the engine mesh; if no
real way exists, keep the lifted-out engine prop and open bay, and say so in the report. (anims)

B2. Manual swap mode (`Config.ManualSwap.enabled`), performance parts only. The mechanic does every step
himself: walk to the toolbox/bench and take tools (E / ox_target), take the engine hoist and push it
to the car (the hoist prop moves with the player), press E at each bolt point marked on the car, lift
the part with keys (W/S raise/lower while holding the hoist), put it down, then the reverse for the new
part. Ap1le.ShowTextUI for the current instruction, Ap1le.Progress only for timed sub-steps (unbolting).
Cancel any time. Same server begin/finish callbacks; the server uses `Config.ManualSwap.minTimeFactor`
instead of `Config.MinTimeFactor` when manual mode is on. API: `Anim.SwapManual(vehicle, category,
step)` returning true/false like `Anim.Swap`; tuning.lua picks it when manual mode is enabled. (anims,
tuning client, server)

B3. Car wash ("Rens bil"): global vehicle ox_target for mechanics (anywhere unless `Config.Wash.workshopOnly`),
needs `Config.Wash.item` in the mechanic's inventory. Server `ap1le_mechanicjob:wash:begin` (netId) /
`wash:finish` () with the usual pending/time/distance checks, removes 1 item at finish. `Anim.Wash(vehicle,
totalMs)`: bucket + sponge around the car (verified props/anims), dirt level visibly goes down during the
sequence (`SetVehicleDirtLevel`), ends at 0 and `WashDecalsFromVehicle`. Afterwards open
`Billing.OpenCreate({ { label = <wash label>, price = price list 'wash' } })`. The price list includes id
`wash` (default Config.Wash.price). Add `cleaning_kit` to install/items.lua. (server, anims, business client, docs)

B4. Tuning UI:
- Neon: the v1 way of choosing sides is back: four toggles (left, right, front, back) that can be
  switched on/off individually, plus the colour. (tuning client payload + tuning NUI)
- The plate in the header looks like a real GTA plate for the vehicle's current plate type (blue on
  white, yellow on black, yellow on blue, blue on white 2/3, exempt/yankton). Prefer the game's own
  plate textures through `https://nui-img/<txd>/<txn>` if they can be requested (research: vehshare
  txd names, RequestStreamedTextureDict on the client first); otherwise a careful CSS recreation
  (font, "San Andreas" script line, colours, border). The tuning client sends `vehicle.plateIndex`. (tuning NUI + client)
- Better icons: review every group/category icon; e.g. the plate icon does not fit. Pick clearer Font
  Awesome 6 Free solid icons. (lead's config.lua group icons are only defaults: the tuning client may
  map ids to better icons in its payload; report the chosen map.)
- The breadcrumb ("Lakering > Primærfarve") is clickable: each crumb jumps back to that level.
- "Indlæs sidste": when tuning is closed without installing and the cart was not empty, the client stores
  that cart for the vehicle (resource KVP keyed by plate, newest 20 vehicles). Next time tuning opens on that
  vehicle, the NUI shows a "Indlæs sidste" action that restores it into the cart (with preview).
- Presets (section C).

B5. Laptop UI redesign: the user says it looks "completely wrong/AI-made". It must look like a MacBook
but in ap1le_core's design language: ap1le_core's dark glass, colours, radii, typography and calm
restraint (see ap1le_core html/css/*.css and its menu/dialog look). Fewer colours: no rainbow app icons,
no gradient wallpaper blobs, no emoji-like glyphs; one brand accent; quiet monochrome icons; realistic
macOS structure (menu bar, dock, windows, sidebars) rendered in ap1le_core style. Use the design skills
(see D). (laptop NUI)

B6. Tuning UI closer to ap1le_core's menu look (calmer: fewer badges/pills/colours, clear hierarchy,
the same list rows as ap1le_core menu.css). (tuning NUI)

## C. Presets

Storage (server, new table `ap1le_mechanicjob_presets`: id, owner identifier, owner name, name, model
hash, data JSON, created_at; and `ap1le_mechanicjob_workorders`: plate PK, model, data JSON, owner
identifier, owner name, created_at, expires_at).
Preset data = `{ cosmetic = { <ox_lib prop key> = value ... }, performance = { [category] = level } }`
(only keys from the tuning save whitelist / Config.Performance; validated on save like tuning:save).
Built-in presets from `Config.Presets.builtin`: `performance = 'max'` = every Config.Performance
category at its highest level, no cosmetics; works on every model.

Server callbacks:
- `preset:list` (model) -> `{ builtin = {...}, mine = { { id, name, created_at } } }` for this model (+ builtin).
- `preset:save` (model, name, data) -> mechanic or terminal user; name 1..maxNameLength, sanitised;
  max `maxPerPlayer` per owner; returns `{ id }`.
- `preset:delete` (id) -> own presets only.
- `preset:get` (id) -> own preset data (or builtin by id string).
- `workorder:save` (netId, data) -> any player at a workshop terminal (server checks distance to a
  `terminal` coords <= 3 m and vehicle within MaxVehicleDistance), the player must own the vehicle
  (owned_vehicles.owner) ; upsert by plate; expires after workOrderHours.
- `workorder:get` (netId) -> mechanic in a workshop; returns the vehicle's work order or nil.
- `workorder:clear` (netId) -> mechanic; after it has been installed.

Client:
- Mechanic tuning: a "Presets" entry in the tuning UI: apply builtin/own preset to the cart (cosmetic
  values that exist on this vehicle are previewed; performance levels become pending swaps listed in
  the cart, executed one by one with the normal swap flow after cosmetic install, each needing stock),
  "Gem som preset" (name via Ap1le.InputDialog), delete own. If the vehicle has a work order: a banner
  "Kundens ønske" with Indlæs.
- Customer terminal (`terminal` coords per workshop, ox_target for everyone, a small kiosk prop if
  available, e.g. verified `prop_atm_01`-style or a screen prop): the player must sit in / stand next to
  their own vehicle within MaxVehicleDistance; opens the same tuning NUI in **design mode**
  (`openTuning` data gets `mode = 'design'`): preview only, no install, no swap, no order, no prices
  total needed (show prices as estimate), performance shown as wish levels; the main action is
  "Send til mekaniker" -> `workorder:save`; also "Gem som preset" for the customer. Closing reverts
  the preview. (tuning client + tuning NUI + business client for the terminal target + server)

## D. Design/UX skills (user asked for them)

NUI devs must use the Skill tool with: `design:design-critique` (critique your before-screenshots
first, list what looks AI-made, then fix it), `design:ux-copy` (all visible strings in Danish: short,
plain, consistent verbs; no filler), and `anthropic-skills:de-ai` if it helps for copy. Take
before/after screenshots.

## E. New files

- client/presets.lua (tuning client dev): preset + work order client logic used by tuning.lua and the terminal.
- server/presets.lua (server dev). server/wash.lua (server dev).
- client/wash.lua (business client dev): target + flow.
The lead adds them to fxmanifest.lua (already done when you read this).
