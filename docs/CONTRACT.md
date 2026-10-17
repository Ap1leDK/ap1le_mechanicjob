# ap1le_mechanicjob: architecture contract

Every file in this resource is written against this document. Do not rename events, callbacks,
globals, NUI actions or config keys defined here. If you need something that is not here, add it
inside your own files only, and list it in your final report under "contract additions".

Stack: ESX Legacy (`@es_extended/imports.lua`, `ESX` is global), ox_lib, oxmysql, ox_inventory,
ox_target, esx_addonaccount. Lua 5.4. Plain HTML/CSS/JS NUI, no frameworks, no CDN.
`config.lua` (shared) already exists and is final: read it, never redefine `Config`.
Locales: `locale('key', ...)` (ox_lib, string.format style). Keys are listed in section 9;
code may only use keys from that list.

## 1. Files and owners

| File | Owner |
|---|---|
| fxmanifest.lua, config.lua, CONTRACT.md | lead (done) |
| server/main.lua, repair.lua, performance.lua, tuning.lua, billing.lua | server dev |
| client/ui.lua, client/anims.lua | animation dev |
| client/main.lua, repair.lua, tuning.lua, billing.lua, towing.lua | client dev |
| html/index.html, style.css, script.js | NUI dev |
| locales/en.json, locales/da.json, sql/install.sql, install/items.lua, README.md | docs dev |

Load order: client/ui.lua, client/anims.lua, client/main.lua, client/repair.lua, client/tuning.lua,
client/billing.lua, client/towing.lua. Server: main, repair, performance, tuning, billing.

## 2. Core rules

- Only `Config.Job` players can use anything (server re-checks on every call; ox_target `groups`
  is only convenience). All grades can do everything.
- Workshop = inside any `Config.Workshops[i]` sphere (`#(coords - ws.coords) <= ws.radius`).
- Full repairs (`workshopOnly = true`), performance swaps and cosmetic tuning: workshop only.
  Field repair: anywhere.
- Server never trusts client values for items, amounts, prices, current part levels or timing.
- Performance tuning only works on vehicles in `owned_vehicles`. The server reads the current
  level from the DB JSON (`owned_vehicles.vehicle`), not from the client.
- Plates: always compare trimmed (`string.gsub(plate, '^%s*(.-)%s*$', '%1')`). Query with
  `WHERE TRIM(plate) = ?`.
- Performance level numbering in all APIs and NUI: `level` 0 = stock, 1..#levels = item index.
  GTA mod index = level - 1 (turbo: level 1 = ToggleVehicleMod on).
  In the DB JSON: modX = level - 1 (-1 = stock); modTurbo = true/false.

## 3. Server API (lib.callback.register, all return `ok, data`)

Shared validation helper in server/main.lua, global `Mechanic` table:
- `Mechanic.GetMechanic(source)` -> xPlayer or nil (exists + job == Config.Job)
- `Mechanic.InWorkshop(coords)` -> workshop table or nil
- `Mechanic.GetVehicle(source, netId)` -> entity or nil (exists, is a vehicle, within
  Config.MaxVehicleDistance of the player's ped)
- `Mechanic.Trim(plate)`
- `Mechanic.Flag(source, reason)` -> logs `[ap1le_mechanicjob] suspicious: <name> (<id>): <reason>`
- `Mechanic.RateLimit(source, key, ms)` -> true if allowed
- `Mechanic.Pending[source]` = the one pending action per player (repair or swap); cleared on
  playerDropped. Each pending: `{ kind, netId, startedAt (GetGameTimer), minMs, ... }`.

Error strings returned as `data` on failure are locale keys from section 9 (`not_mechanic`,
`not_in_workshop`, `too_far`, `missing_item`, `cant_carry`, `not_owned`, `busy`, `too_fast`,
`not_available`, `error`).

Repair:
- `ap1le_mechanicjob:repair:begin` (netId, kind)  kind in `engine|body|tyre|field`
  Checks: mechanic, vehicle, workshop if `workshopOnly`, has 1x `Config.Repair[kind].item`,
  no other pending. Stores pending `{ kind='repair', repair=kind, minMs = time*MinTimeFactor }`.
  Returns `true, { time = Config.Repair[kind].time }`.
- `ap1le_mechanicjob:repair:finish` () -> checks pending, elapsed >= minMs, vehicle still close
  (and in workshop if required), removes the item (RemoveItem must succeed). Returns
  `true, { kind, maxEngineHealth? }`. Client then repairs locally.
- `ap1le_mechanicjob:cancel` () -> clears pending, returns true. (Shared by repair and swap.)

Performance swap:
- `ap1le_mechanicjob:perf:begin` (netId, category, level)  level 0..#levels (0 = remove to stock)
  Checks: mechanic, vehicle, workshop, plate in owned_vehicles, category valid, level valid,
  level ~= current, has the new item (unless level 0), can carry the old item (unless current 0).
  Stores pending `{ kind='perf', category, level, oldLevel, plate, minMs }` where
  minMs = ((oldLevel > 0 and removeTime or 0) + (level > 0 and installTime or 0)) * MinTimeFactor.
  Returns `true, { oldLevel, level, removeTime, installTime }`.
- `ap1le_mechanicjob:perf:finish` () -> re-check pending, elapsed, distance, workshop. RemoveItem new
  (must succeed, else fail), AddItem old (if oldLevel > 0), UPDATE DB JSON key. Returns
  `true, { category, level }`. Client then applies the mod.

Cosmetic:
- `ap1le_mechanicjob:tuning:canOpen` (netId) -> mechanic, vehicle, workshop. Returns `true, { owned = bool, levels = { [category] = level } }`
  (levels read from DB, empty if not owned).
- `ap1le_mechanicjob:tuning:save` (netId, props) -> mechanic, vehicle, workshop, owned plate, props
  is a table and props.plate (trimmed) == the entity's plate (trimmed). Server merges: takes
  the stored JSON, overwrites ONLY cosmetic keys from `props`, never the performance propKeys
  (those stay as stored). Rate limit 3 s. Returns `true`.
  Cosmetic keys allowed: every `Config.Cosmetic.mods[i].id`, `color1, color2, pearlescentColor,
  wheelColor, wheels, windowTint, modXenon, xenonColor, neonEnabled, neonColor, plateIndex,
  modLivery, modCustomTiresF, modCustomTiresR`. Values must be number/boolean/table-of-numbers.
  Unowned vehicles: cosmetic still applies client-side, not saved (return `true, { saved = false }`).

Invoices (server/billing.lua):
- `ap1le_mechanicjob:invoice:create` (targetId, lines)  lines = `{ { label = string, amount = int }, ... }`
  Checks: mechanic, target online and not self, distance <= Config.Invoice.maxDistance,
  1..maxLines lines, label string 1..48 chars (strip control chars), amount integer 1..maxTotal,
  total <= maxTotal, cooldown, target has no open invoice. Stores
  `invoices[id] = { id, from, to, lines, total, expires }`, sends client event
  `ap1le_mechanicjob:invoice:show` to target with `{ id, from = mechanic name, lines, total, expireSeconds }`.
  Returns `true, { id }`.
- `ap1le_mechanicjob:invoice:respond` (id, accept) -> invoice exists, `to == source`, not expired.
  Decline: notify mechanic. Accept: customer `Config.Invoice.account` >= total, else fail with
  `no_money`; removeAccountMoney, society share via
  `TriggerEvent('esx_addonaccount:getSharedAccount', society, function(acc) acc.addMoney(n) end)`,
  rest to mechanic's bank. Notify both via `ap1le_mechanicjob:notify`. Returns `true`.
  Expired invoices are cleaned up and the target gets `ap1le_mechanicjob:invoice:hide`.

Server -> client events:
- `ap1le_mechanicjob:notify` (msg, type)   type `success|error|inform`
- `ap1le_mechanicjob:invoice:show` (invoice)
- `ap1le_mechanicjob:invoice:hide` (id)

## 4. Client globals

client/ui.lua (animation dev), global `UI`:
- `UI.HelpText(msg)` per-frame help text
- `UI.Notify(msg, type)` GTA feed notification (colour prefix by type)
- `UI.Shard(title, text, ms)` MP_BIG_MESSAGE_FREEMODE centered shard
- `UI.TimerBar` GTA:O style bottom-right progress bar (timerbars textures), used by Anim
- `UI.Buttons(list)` / `UI.ClearButtons()` instructional buttons scaleform

client/anims.lua (animation dev), global `Anim`. Every function blocks (call inside a thread),
returns `true` if completed, `false` if cancelled (player pressed cancel ~INPUT_FRONTEND_CANCEL~,
died, moved away, or vehicle gone). Must clean up all props, tasks, doors, freeze state, raised
vehicle position and scaleforms on both outcomes and on resource stop.
- `Anim.Repair(vehicle, kind, totalMs)` kind `engine|body|tyre|field`
- `Anim.Swap(vehicle, category, step, totalMs)` category = Config.Performance key, step `remove|install`
- `Anim.Cosmetic(vehicle, animType, totalMs)` animType from Config.Cosmetic `anim` values:
  `body|under|interior|hood|paint|wheel`
- `Anim.Winch(truck, vehicle, totalMs)` towing load/unload
- `Anim.IsBusy()` -> bool
- `Anim.StopAll()` immediate cleanup

Swap realism requirement (user requirement): every performance swap is two physical steps.
`remove` takes the old part OUT (e.g. engine: open hood, bring engine hoist, unbolt, lift the old
engine block out with the hoist and set it down) and `install` puts the new one IN (bring new part,
lift in, bolt down, close up). Same idea for brakes (jack up, wheel off, old brake parts off/new
on, wheel back), suspension, transmission (under the car), armor (welding panels), turbo (engine
bay). Real GTA V animations, scenarios and props only; every dict/clip/model verified to exist.

client/main.lua (client dev), global `Mechanic`:
- `Mechanic.IsMechanic()`, `Mechanic.InWorkshop()` -> workshop or nil (uses cache.coords)
- `Mechanic.GetTargetVehicle()` -> nearest vehicle in front of player within 5 m or nil
- `Mechanic.RequestControl(vehicle)` -> bool (NetworkRequestControlOfEntity with timeout)
- blips for workshops, ox_target global vehicle options (see 5), F6 job menu
  (lib.registerContext): send invoice, field repair; keybind via `lib.addKeybind` name
  `mechanic_menu`, default key F6.
- `RegisterNetEvent('ap1le_mechanicjob:notify')` -> UI.Notify

## 5. ox_target options (client/main.lua registers, handlers live in the feature files)

Global vehicle (`exports.ox_target:addGlobalVehicle`), all with `groups = { [Config.Job] = 0 }`,
`canInteract` checks `not Anim.IsBusy()` and workshop where needed:
- Repair engine / Repair body / Change tyre (workshop) -> `Repair.Start(vehicle, kind)`
- Field repair (anywhere, if player has repair_kit via `exports.ox_inventory:Search('count', item)`) -> `Repair.Start(vehicle, 'field')`
- Open tuning (workshop) -> `Tuning.Open(vehicle)`
- Load onto flatbed (vehicle not a tow truck, a Config.Towing truck within maxDistance) -> `Towing.Load(vehicle)`
Model options on `Config.Towing.trucks`: Unload vehicle -> `Towing.Unload(truck)`.

Feature globals: `Repair.Start(vehicle, kind)`, `Tuning.Open(vehicle)`, `Billing.OpenCreate(prefillLines?)`,
`Towing.Load(vehicle)`, `Towing.Unload(truck)`.

## 6. NUI protocol

All messages: `SendNUIMessage({ action = '<name>', data = <table> })`. NUI is hidden by default.
Callbacks: `fetch('https://' + GetParentResourceName() + '/<name>', POST JSON)`; every Lua
callback calls `cb(...)` exactly once.

Lua -> NUI:
- `openTuning` data:
  ```
  { vehicle = { label, plate, owned },
    performance = { { id = 'engine', label, current = level, options = { { level = 0, label = 'Stock' }, { level = 1, label = 'Level 1', item = 'engine_lvl1', hasItem = bool }, ... } }, ... },
    cosmetic = { { id = 'modSpoilers', label, price, current = modIndex, options = { { value = -1, label = 'Stock' }, { value = 0, label = <GetLabelText> }, ... } }, ... },
    paint = { colours = Config.Colours, current = { color1, color2, pearlescentColor, wheelColor }, price },
    extras = { windowTint = { current, price, options = {...} }, xenon = { enabled, colour, price }, neon = { enabled = {l,r,f,b}, colour = {r,g,b}, price }, plate = { current, price, options } } }
  ```
  Only categories the vehicle supports (GetNumVehicleMods > 0) are sent.
- `closeTuning` {}
- `openInvoice` data: `{ players = { { id, name } }, prefill = { { label, amount } }, maxLines, maxTotal }`
- `showInvoice` data: `{ id, from, lines, total, expireSeconds }`
- `hideInvoice` data: `{ id }`

NUI -> Lua callbacks:
- `tuning:preview` `{ type = 'mod'|'paint'|'extra', id, value }` -> Lua applies locally; cb `{ ok }`
- `tuning:camera` `{ focus = 'default'|'front'|'rear'|'wheel'|'engine'|'side' }` -> cb `{ ok }`
- `tuning:install` `{ changes = { { type, id, value, label, price } } }` -> Lua closes NUI, plays
  `Anim.Cosmetic` once per distinct anim type, saves via `tuning:save`, then opens
  `Billing.OpenCreate(prefill from changes)`; cb `{ ok }`
- `tuning:swap` `{ category, level }` -> Lua closes NUI and runs the swap flow; cb `{ ok }`
- `tuning:close` {} -> Lua reverts preview to the original props, closes, releases focus; cb `{ ok }`
- `invoice:send` `{ target, lines }` -> Lua calls server; cb `{ ok, error? }` (error = translated text)
- `invoice:cancel` {} -> cb `{ ok }`
- `invoice:respond` `{ id, accept }` -> cb `{ ok, error? }`
- `locale` {} -> cb `{ <all NUI strings> }` (Lua returns `lib.getLocales()` filtered to keys starting `ui_`)

The NUI must request `locale` once at load and use those strings for every visible label.
Escape always closes the open view (tuning -> `tuning:close`, invoice create -> `invoice:cancel`;
the customer invoice popup does NOT close on Escape, only via Accept/Decline, and needs
`SetNuiFocus(true, true)` while shown).

## 7. Swap flow (client/tuning.lua)

1. `ok, d = lib.callback.await('ap1le_mechanicjob:perf:begin', false, netId, category, level)`
2. If `d.oldLevel > 0`: `Anim.Swap(vehicle, category, 'remove', d.removeTime)`; cancelled -> `ap1le_mechanicjob:cancel`, stop.
   Between steps, visibly set the vehicle mod to stock (SetVehicleMod -1 / ToggleVehicleMod false).
3. If `d.level > 0`: `Anim.Swap(vehicle, category, 'install', d.installTime)`; cancelled -> cancel; restore the old mod visually.
4. `lib.callback.await('ap1le_mechanicjob:perf:finish', false)` -> on ok, `Mechanic.RequestControl`, SetVehicleModKit(veh, 0), apply level, `UI.Notify`.

## 8. Glassmorphism NUI notes

FiveM renders the NUI page as a transparent layer over the game, so `backdrop-filter` blurs only
HTML behind the element, not the game world. The glass look must come from translucent layered
gradients, 1px light borders, inner highlights, soft shadows and subtle noise; backdrop-filter
may still be used between stacked HTML layers. Tuning panel: right side, the car stays visible.
Customer invoice popup: compact, centered-top.

## 9. Locale keys (the only allowed keys)

General: `job_label`, `blip_workshop`, `not_mechanic`, `not_in_workshop`, `too_far`, `missing_item`,
`cant_carry`, `not_owned`, `busy`, `too_fast`, `not_available`, `error`, `cancelled`, `no_money`.
Target: `target_repair_engine`, `target_repair_body`, `target_change_tyre`, `target_field_repair`,
`target_tuning`, `target_tow_load`, `target_tow_unload`.
Repair: `repair_engine_done`, `repair_body_done`, `repair_tyre_done`, `repair_field_done`.
Swap: `swap_removing` (%s part label), `swap_installing` (%s), `swap_done` (%s, %s level label), `swap_removed` (%s).
Anim steps (help text / timer bar labels): `step_open_hood`, `step_hoist`, `step_unbolt`, `step_lift_out`,
`step_lift_in`, `step_bolt`, `step_close_hood`, `step_jack_up`, `step_wheel_off`, `step_wheel_on`,
`step_jack_down`, `step_under_car`, `step_weld`, `step_paint`, `step_fit_part`, `step_winch`,
`help_cancel` ("Press ~INPUT_FRONTEND_CANCEL~ to cancel").
Tuning: `tuning_saved`, `tuning_not_saved`, `tuning_installing` (%s).
Towing: `tow_loaded`, `tow_unloaded`, `tow_no_truck`, `tow_no_vehicle`.
Invoice: `invoice_sent` (%s name), `invoice_received` (%s), `invoice_paid` (%s amount), `invoice_paid_mechanic` (%s, %s share),
`invoice_declined`, `invoice_expired`, `invoice_no_players`, `invoice_open`.
Menu: `menu_title`, `menu_invoice`, `menu_field_repair`.
NUI (`ui_` prefix): `ui_tuning_title`, `ui_performance`, `ui_cosmetic`, `ui_paint`, `ui_extras`, `ui_stock`,
`ui_level` (%s), `ui_installed`, `ui_no_item`, `ui_swap`, `ui_remove`, `ui_install`, `ui_cart`, `ui_total`,
`ui_close`, `ui_primary`, `ui_secondary`, `ui_pearl`, `ui_wheel_colour`, `ui_window_tint`, `ui_xenon`, `ui_neon`,
`ui_plate`, `ui_enabled`, `ui_not_owned`, `ui_invoice_title`, `ui_customer`, `ui_line_label`, `ui_amount`,
`ui_add_line`, `ui_send`, `ui_cancel`, `ui_invoice_from`, `ui_accept`, `ui_decline`, `ui_expires` (%s seconds),
`ui_camera`, `ui_empty_cart`.
