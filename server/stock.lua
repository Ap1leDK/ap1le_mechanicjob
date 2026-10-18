-- ap1le_mechanicjob: workshop stashes, part orders and crate deliveries.
-- Orders are paid by the society account, stored in ap1le_mechanicjob_orders and survive restarts.
-- Order status: 'ordered' (on its way) -> 'arrived' (crate at the delivery point) -> 'collected'.
-- All times in the orders table are unix seconds (os.time()).

local CRATES_KEY = 'ap1le_mechanicjob:crates'
local DELIVERY_INTERVAL_MS = 15000
local CRATE_SPACING = 1.2           -- metres between crates along the delivery heading
local UNPACK_BEGIN_DISTANCE = 3.0   -- player <-> crate to start unpacking
local UNPACK_FINISH_DISTANCE = 4.0  -- small slack: Anim.Unpack moves the ped around the crate
local LIST_ROWS = 25
local MAX_ITEM_NAME = 64
local ORDER_ATTEMPT_MS = 750        -- min time between two order:place calls (any outcome)
local ORDER_COOLDOWN_MS = 3000      -- min time between two placed orders

-- Order limits for mechanics below Config.BossGrade (see Config.Shop.staffLimits); chefs keep the full
-- Config.Shop limits. Enough for the tuning menu's "Bestil" (one part) and small restocks, so a new
-- recruit cannot spend the society account on parts. Bigger orders are the chef's call.
local staffLimits = Config.Shop.staffLimits or {}
local STAFF_MAX_LINES = staffLimits.maxLines or 1
local STAFF_MAX_PER_LINE = staffLimits.maxPerLine or 2
local STAFF_MAX_TOTAL = staffLimits.maxTotal or 30000
local STAFF_MAX_OPEN = staffLimits.maxOpen or 2

-- [orderId] = { id, workshop, slot, coords = vector3 } for every arrived crate (rebuilt from the DB).
-- slot = the crate's fixed place at the delivery point, kept while the crate exists.
local crates = {}
-- Workshops with an order being placed right now (the open-order count check yields)
local placing = {}
-- Orders being unpacked right now (claimed between the stash check and the DB update)
local unpacking = {}

---Stash id of a workshop.
---@param workshop table Config.Workshops entry
---@return string
function Mechanic.StashId(workshop)
    return 'ap1le_mechanicjob_' .. workshop.id
end

---Display label of an item (ox_inventory item list), falling back to the item name.
---@param name string
---@return string
function Mechanic.ItemLabel(name)
    local ok, data = pcall(function() return exports.ox_inventory:Items(name) end)
    if ok and type(data) == 'table' and type(data.label) == 'string' then return data.label end
    return name
end

-- ---------------------------------------------------------------------------------------------
-- Stashes
-- ---------------------------------------------------------------------------------------------

local function registerStashes()
    for i = 1, #Config.Workshops do
        local ws = Config.Workshops[i]
        local stash = ws.stash
        if stash then
            -- RegisterStash(name, label, slots, maxWeight, owner, groups, coords); owner nil = shared stash
            local ok, err = pcall(function()
                exports.ox_inventory:RegisterStash(Mechanic.StashId(ws), stash.label or ws.label, stash.slots, stash.weight,
                    nil, { [Config.Job] = 0 }, stash.coords)
            end)
            if not ok then
                print(('[ap1le_mechanicjob] registering stash for workshop "%s" failed: %s'):format(ws.id, tostring(err)))
            end
        end
    end
end

registerStashes()

-- ox_inventory forgets registered stashes when it restarts
AddEventHandler('onResourceStart', function(resource)
    if resource == 'ox_inventory' then registerStashes() end
end)

---Items in a stash, aggregated per item name and sorted by label.
---@param stashId string
---@return table { { name, label, count } }
local function stashItems(stashId)
    local slots = exports.ox_inventory:GetInventoryItems(stashId)
    local byName, list = {}, {}

    if type(slots) == 'table' then
        for _, slot in pairs(slots) do
            if type(slot) == 'table' and type(slot.name) == 'string' and type(slot.count) == 'number' and slot.count > 0 then
                local entry = byName[slot.name]
                if not entry then
                    entry = { name = slot.name, label = type(slot.label) == 'string' and slot.label or Mechanic.ItemLabel(slot.name), count = 0 }
                    byName[slot.name] = entry
                    list[#list + 1] = entry
                end
                entry.count = entry.count + math.floor(slot.count)
            end
        end
    end

    table.sort(list, function(a, b)
        if a.label == b.label then return a.name < b.name end
        return a.label < b.label
    end)

    return list
end

---{ [item] = count } in a stash for the given item names (0 when missing).
---@param stashId string
---@param names string[]
---@return table
function Mechanic.StashCounts(stashId, names)
    local result = {}
    if #names == 0 then return result end

    local counts = exports.ox_inventory:Search(stashId, 'count', names)
    for i = 1, #names do
        local count
        if type(counts) == 'table' then
            count = counts[names[i]]
        elseif type(counts) == 'number' and #names == 1 then
            count = counts
        end
        result[names[i]] = math.tointeger(tonumber(count) or 0) or 0
    end

    return result
end

lib.callback.register('ap1le_mechanicjob:stock:get', function(source)
    if not Mechanic.GetMechanic(source) then return false, 'not_mechanic' end
    if not Mechanic.RateLimit(source, 'stock:get', 500) then return false, 'too_fast' end

    local workshop = Mechanic.ContextWorkshop(source)
    if not workshop then return false, 'not_in_workshop' end

    return true, {
        workshop = workshop.id,
        label = workshop.label,
        items = stashItems(Mechanic.StashId(workshop)),
    }
end)

-- ---------------------------------------------------------------------------------------------
-- Crates (GlobalState)
-- ---------------------------------------------------------------------------------------------

---Position of crate slot n (1-based) of a workshop: the delivery point, moved CRATE_SPACING m
---forward along the delivery heading per slot.
---@param workshop table
---@param n integer
---@return table { x, y, z, w }
local function cratePosition(workshop, n)
    local d = workshop.delivery
    local heading = d.w or 0.0
    local rad = math.rad(heading)
    local offset = (n - 1) * CRATE_SPACING
    -- GTA heading 0 = north (+Y), increasing counter-clockwise: forward = (-sin, cos)
    return { x = d.x - math.sin(rad) * offset, y = d.y + math.cos(rad) * offset, z = d.z, w = heading }
end

---Give a crate the lowest slot of its workshop that no other crate uses. A slot is freed when its
---crate is removed from `crates`, so the positions of the other crates never change.
---@param crate table
local function assignSlot(crate)
    local used = {}
    for _, other in pairs(crates) do
        if other ~= crate and other.workshop == crate.workshop and other.slot then used[other.slot] = true end
    end
    local slot = 1
    while used[slot] do slot = slot + 1 end
    crate.slot = slot
end

---Add an arrived order's crate (ids must be added in ascending order so slots follow the order ids).
---@param id integer
---@param workshop string
local function addCrate(id, workshop)
    local crate = { id = id, workshop = workshop }
    crates[id] = crate
    assignSlot(crate)
end

---Publish every arrived crate to all clients.
local function publishCrates()
    local ids = {}
    for id in pairs(crates) do ids[#ids + 1] = id end
    table.sort(ids)

    local list = {}
    for i = 1, #ids do
        local crate = crates[ids[i]]
        local ws = Mechanic.WorkshopById(crate.workshop)
        if ws and ws.delivery then
            if not crate.slot then assignSlot(crate) end
            local pos = cratePosition(ws, crate.slot)
            crate.coords = vec3(pos.x, pos.y, pos.z)
            list[#list + 1] = { id = crate.id, workshop = ws.id, coords = pos }
        else
            crate.coords = nil
        end
    end

    GlobalState[CRATES_KEY] = list
end

---Online mechanics (server ids).
local function onlineMechanics()
    local ok, players = pcall(ESX.GetExtendedPlayers, 'job', Config.Job)
    local ids = {}
    if ok and type(players) == 'table' then
        for i = 1, #players do ids[#ids + 1] = players[i].source end
    end
    return ids
end

---Rebuild the crate list from the DB (start-up) and move due orders to 'arrived'.
---@param initial boolean true on resource start (always rebuild from the DB)
local function processDeliveries(initial)
    local now = os.time()

    local okDue, due = pcall(MySQL.query.await,
        "SELECT `id`, `workshop` FROM `ap1le_mechanicjob_orders` WHERE `status` = 'ordered' AND `ready_at` <= ? ORDER BY `id`", { now })
    if not okDue then
        print(('[ap1le_mechanicjob] reading ap1le_mechanicjob_orders failed (was sql/install.sql run?): %s'):format(tostring(due)))
        return
    end

    local arrivedWorkshops = {}
    for i = 1, #(due or {}) do
        local row = due[i]
        local okUpd, affected = pcall(MySQL.update.await,
            "UPDATE `ap1le_mechanicjob_orders` SET `status` = 'arrived' WHERE `id` = ? AND `status` = 'ordered'", { row.id })
        if okUpd and affected == 1 then
            addCrate(row.id, row.workshop)
            arrivedWorkshops[row.workshop] = true
            if not Mechanic.WorkshopById(row.workshop) then
                print(('[ap1le_mechanicjob] order %d belongs to unknown workshop "%s", its crate is not shown'):format(row.id, tostring(row.workshop)))
            end
        end
    end

    if initial then
        local okAll, rows = pcall(MySQL.query.await,
            "SELECT `id`, `workshop` FROM `ap1le_mechanicjob_orders` WHERE `status` = 'arrived' ORDER BY `id`")
        if okAll and type(rows) == 'table' then
            crates = {}
            for i = 1, #rows do
                addCrate(rows[i].id, rows[i].workshop)
            end
        end
    end

    if initial or next(arrivedWorkshops) then
        publishCrates()
    end

    -- Tell online mechanics that parts arrived
    if next(arrivedWorkshops) and not initial then
        local mechanics = onlineMechanics()
        for wsId in pairs(arrivedWorkshops) do
            local ws = Mechanic.WorkshopById(wsId)
            if ws then
                for i = 1, #mechanics do
                    Mechanic.Notify(mechanics[i], locale('order_arrived', ws.label), 'info')
                end
            end
        end
    end
end

-- Exposed for the mocked tests and for admins who want to force a delivery check
Mechanic.ProcessDeliveries = processDeliveries

GlobalState[CRATES_KEY] = {}

MySQL.ready(function()
    processDeliveries(true)

    CreateThread(function()
        while true do
            Wait(DELIVERY_INTERVAL_MS)
            processDeliveries(false)
        end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        GlobalState[CRATES_KEY] = {}
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------------------------------

---Validate and merge order lines. Returns { { item, count } } sorted by item and the total, or nil.
---@param lines any
---@return table|nil clean
---@return integer|nil total
local function sanitiseOrder(lines)
    local shop = Config.Shop
    -- Before merging duplicates a client may send each item at most a few times; cap the raw size
    if not Mechanic.IsArray(lines, shop.maxLines * 2) then return nil end

    local merged, names = {}, {}
    for i = 1, #lines do
        local line = lines[i]
        if type(line) ~= 'table' then return nil end

        local item, count = line.item, line.count
        if type(item) ~= 'string' or #item > MAX_ITEM_NAME or not shop.items[item] then return nil end
        if not Mechanic.IsInt(count, 1, shop.maxPerLine) then return nil end

        if not merged[item] then
            merged[item] = 0
            names[#names + 1] = item
        end
        merged[item] = merged[item] + math.tointeger(count)
        if merged[item] > shop.maxPerLine then return nil end
    end

    if #names > shop.maxLines then return nil end
    table.sort(names)

    local clean, total = {}, 0
    for i = 1, #names do
        local item = names[i]
        local price = math.tointeger(shop.items[item])
        if not price or price < 0 then
            print(('[ap1le_mechanicjob] Config.Shop.items.%s has an invalid price'):format(item))
            return nil
        end
        clean[i] = { item = item, count = merged[item] }
        total = total + price * merged[item]
    end

    if total < 1 or total > 2147483647 then return nil end
    return clean, total
end

---Order limits of a mechanic: { maxLines, maxPerLine, maxTotal?, maxOpen?, boss }.
---maxTotal/maxOpen are only set for non-chefs (chefs are limited by Config.Shop and the society balance).
---@param xPlayer table
---@return table
function Mechanic.OrderLimits(xPlayer)
    if Mechanic.IsBoss(xPlayer) then
        return { maxLines = Config.Shop.maxLines, maxPerLine = Config.Shop.maxPerLine, boss = true }
    end
    return {
        maxLines = math.min(STAFF_MAX_LINES, Config.Shop.maxLines),
        maxPerLine = math.min(STAFF_MAX_PER_LINE, Config.Shop.maxPerLine),
        maxTotal = STAFF_MAX_TOTAL,
        maxOpen = STAFF_MAX_OPEN,
        boss = false,
    }
end

---Place an order (body of order:place, runs while the workshop is locked).
local function placeOrder(source, xPlayer, workshop, clean, total, limits)
    local okCount, open = pcall(MySQL.scalar.await,
        "SELECT COUNT(*) FROM `ap1le_mechanicjob_orders` WHERE `workshop` = ? AND `status` IN ('ordered', 'arrived')", { workshop.id })
    if not okCount then
        print(('[ap1le_mechanicjob] counting orders failed (was sql/install.sql run?): %s'):format(tostring(open)))
        return false, 'error'
    end
    if (tonumber(open) or 0) >= Config.Shop.maxOpenOrders then return false, 'order_max_open' end

    if limits.maxOpen then
        local okOwn, own = pcall(MySQL.scalar.await,
            "SELECT COUNT(*) FROM `ap1le_mechanicjob_orders` WHERE `ordered_by` = ? AND `status` IN ('ordered', 'arrived')", { xPlayer.identifier })
        if not okOwn then
            print(('[ap1le_mechanicjob] counting orders failed: %s'):format(tostring(own)))
            return false, 'error'
        end
        if (tonumber(own) or 0) >= limits.maxOpen then return false, 'order_limit_staff' end
    end

    -- The query yielded: the player must still be a mechanic at that workshop
    if not Mechanic.GetMechanic(source) or Mechanic.ContextWorkshop(source) ~= workshop then
        return false, 'not_in_workshop'
    end

    local paid, payErr = Mechanic.SocietyRemove(total)
    if not paid then return false, payErr end

    local now = os.time()
    local readyAt = now + math.floor(Config.Shop.deliveryMinutes * 60)
    local okIns, id = pcall(MySQL.insert.await, [[
        INSERT INTO `ap1le_mechanicjob_orders`
            (`workshop`, `items`, `total`, `status`, `ordered_by`, `ordered_by_name`, `created_at`, `ready_at`)
        VALUES (?, ?, ?, 'ordered', ?, ?, ?, ?)
    ]], { workshop.id, json.encode(clean), total, xPlayer.identifier, Mechanic.PlayerName(xPlayer), now, readyAt })

    if not okIns or not id or id == 0 then
        -- Never keep the money for an order that was not saved
        if not Mechanic.SocietyAdd(total) then
            print(('[ap1le_mechanicjob] ORDER REFUND FAILED: %d was taken from "%s" for an unsaved order by %s')
                :format(total, Config.Invoice.society, xPlayer.identifier))
        end
        print(('[ap1le_mechanicjob] saving order failed: %s'):format(tostring(id)))
        return false, 'error'
    end

    return true, { id = id, total = total, eta = readyAt - now }
end

lib.callback.register('ap1le_mechanicjob:order:place', function(source, lines)
    local xPlayer = Mechanic.GetMechanic(source)
    if not xPlayer then return false, 'not_mechanic' end

    -- v2 recorded the 3 s order cooldown on every attempt, so the retry after a failed order (the false
    -- society failure, see server/main.lua) always answered too_fast. Attempts now have a short
    -- anti-spam window only; the order cooldown starts when an order was actually placed.
    if not Mechanic.RateLimit(source, 'order:place:attempt', ORDER_ATTEMPT_MS) then return false, 'too_fast' end
    if not Mechanic.RateLimitCheck(source, 'order:place', ORDER_COOLDOWN_MS) then return false, 'too_fast' end

    local workshop = Mechanic.ContextWorkshop(source)
    if not workshop then return false, 'not_in_workshop' end

    local clean, total = sanitiseOrder(lines)
    if not clean then
        Mechanic.Flag(source, 'order:place with invalid lines')
        return false, 'order_invalid'
    end

    -- Mechanics below chef grade may only place small orders
    local limits = Mechanic.OrderLimits(xPlayer)
    if not limits.boss then
        local tooBig = #clean > limits.maxLines or total > limits.maxTotal
        for i = 1, #clean do
            if clean[i].count > limits.maxPerLine then tooBig = true end
        end
        if tooBig then return false, 'order_limit_staff' end
    end

    -- Every item must exist in ox_inventory, or the crate could never be unpacked
    for i = 1, #clean do
        local ok, data = pcall(function() return exports.ox_inventory:Items(clean[i].item) end)
        if not ok or type(data) ~= 'table' then
            print(('[ap1le_mechanicjob] Config.Shop item "%s" does not exist in ox_inventory'):format(clean[i].item))
            return false, 'error'
        end
    end

    if placing[workshop.id] then return false, 'busy' end
    placing[workshop.id] = true

    local ok, success, data = pcall(placeOrder, source, xPlayer, workshop, clean, total, limits)
    placing[workshop.id] = nil

    if not ok then
        print(('[ap1le_mechanicjob] order:place error: %s'):format(tostring(success)))
        return false, 'error'
    end

    if success then Mechanic.RateLimitMark(source, 'order:place') end
    return success, data
end)

---Decode an order's items JSON into { { item, label, count } }; nil if unreadable.
local function decodeItems(raw)
    if type(raw) ~= 'string' then return nil end
    local ok, items = pcall(json.decode, raw)
    if not ok or type(items) ~= 'table' then return nil end

    local list = {}
    for i = 1, #items do
        local line = items[i]
        if type(line) == 'table' and type(line.item) == 'string' and Mechanic.IsInt(line.count, 1, 100000) then
            list[#list + 1] = { item = line.item, label = Mechanic.ItemLabel(line.item), count = math.tointeger(line.count) }
        end
    end
    return list
end

lib.callback.register('ap1le_mechanicjob:order:list', function(source)
    if not Mechanic.GetMechanic(source) then return false, 'not_mechanic' end
    if not Mechanic.RateLimit(source, 'order:list', 500) then return false, 'too_fast' end

    local workshop = Mechanic.ContextWorkshop(source)
    if not workshop then return false, 'not_in_workshop' end

    -- LIST_ROWS is a constant integer, so it is formatted in (some MySQL versions reject a bound LIMIT)
    local ok, rows = pcall(MySQL.query.await, ([[
        SELECT `id`, `items`, `total`, `status`, `ordered_by_name`, `created_at`, `ready_at`
        FROM `ap1le_mechanicjob_orders` WHERE `workshop` = ? ORDER BY `id` DESC LIMIT %d
    ]]):format(LIST_ROWS), { workshop.id })
    if not ok or type(rows) ~= 'table' then
        print(('[ap1le_mechanicjob] order:list failed: %s'):format(tostring(rows)))
        return false, 'error'
    end

    local now = os.time()
    local list = {}
    for i = 1, #rows do
        local row = rows[i]
        local status = row.status
        list[i] = {
            id = row.id,
            items = decodeItems(row.items) or {},
            total = tonumber(row.total) or 0,
            status = status,
            eta = status == 'ordered' and math.max(0, (tonumber(row.ready_at) or now) - now) or nil,
            ordered_by = row.ordered_by_name,
            created_at = tonumber(row.created_at),
        }
    end

    return true, list
end)

-- ---------------------------------------------------------------------------------------------
-- Unpacking
-- ---------------------------------------------------------------------------------------------

---Crate of an arrived order and the distance from the player to it, or nil.
local function crateInReach(source, orderId, maxDistance)
    local crate = crates[orderId]
    if not crate or not crate.coords then return nil end

    local coords, ped = Mechanic.PedCoords(source)
    if not coords or GetEntityRoutingBucket(ped) ~= 0 then return nil end
    if #(coords - crate.coords) > maxDistance then return nil end

    return crate
end

---True if another player has a pending unpack of this order.
local function orderBusy(source, orderId)
    for src, pending in pairs(Mechanic.Pending) do
        if src ~= source and pending.kind == 'unpack' and pending.orderId == orderId and Mechanic.GetPending(src) then
            return true
        end
    end
    return unpacking[orderId] ~= nil
end

lib.callback.register('ap1le_mechanicjob:order:unpackBegin', function(source, orderId)
    if not Mechanic.GetMechanic(source) then return false, 'not_mechanic' end
    if not Mechanic.RateLimit(source, 'order:unpackBegin', 1000) then return false, 'too_fast' end

    if not Mechanic.IsInt(orderId, 1, 2147483647) then
        Mechanic.Flag(source, 'order:unpackBegin with invalid order id')
        return false, 'error'
    end
    orderId = math.tointeger(orderId)

    if Mechanic.GetPending(source) then return false, 'busy' end

    if not crates[orderId] then return false, 'order_not_found' end
    if not crateInReach(source, orderId, UNPACK_BEGIN_DISTANCE) then return false, 'too_far' end
    if orderBusy(source, orderId) then return false, 'busy' end

    local time = Config.Shop.unpackTime
    Mechanic.SetPending(source, {
        kind = 'unpack',
        orderId = orderId,
        minMs = math.floor(time * Config.MinTimeFactor),
        expectedMs = time,
    })

    return true, { time = time }
end)

---Move the order's items into the stash. Runs while the order is claimed in `unpacking`.
local function unpackOrder(source, xPlayer, orderId)
    local crate = crates[orderId]
    local workshop = crate and Mechanic.WorkshopById(crate.workshop)
    if not workshop then return false, 'order_not_found' end

    local okRow, row = pcall(MySQL.single.await,
        'SELECT `id`, `workshop`, `items`, `status` FROM `ap1le_mechanicjob_orders` WHERE `id` = ?', { orderId })
    if not okRow then return false, 'error' end
    if not row or row.status ~= 'arrived' or row.workshop ~= workshop.id then
        crates[orderId] = nil
        publishCrates()
        return false, 'order_not_found'
    end

    local items = decodeItems(row.items)
    if not items or #items == 0 then
        print(('[ap1le_mechanicjob] order %d has unreadable items, left as arrived'):format(orderId))
        return false, 'error'
    end

    -- The query yielded: re-check the player
    if not Mechanic.GetMechanic(source) then return false, 'not_mechanic' end
    if not crateInReach(source, orderId, UNPACK_FINISH_DISTANCE) then return false, 'too_far' end

    -- The stash must fit everything: each item on its own, and the combined weight
    local stashId = Mechanic.StashId(workshop)
    local weight = 0
    for i = 1, #items do
        local line = items[i]
        if exports.ox_inventory:CanCarryItem(stashId, line.item, line.count) ~= true then return false, 'stock_full' end
        local ok, data = pcall(function() return exports.ox_inventory:Items(line.item) end)
        weight = weight + ((ok and type(data) == 'table' and tonumber(data.weight)) or 0) * line.count
    end
    if weight > 0 and exports.ox_inventory:CanCarryWeight(stashId, weight) == false then return false, 'stock_full' end

    -- Claim the order in the DB first: if anything after this fails, items are never duplicated
    local okUpd, affected = pcall(MySQL.update.await, [[
        UPDATE `ap1le_mechanicjob_orders` SET `status` = 'collected', `collected_by` = ?, `collected_at` = ?
        WHERE `id` = ? AND `status` = 'arrived'
    ]], { xPlayer.identifier, os.time(), orderId })
    if not okUpd or affected ~= 1 then return false, 'order_not_found' end

    local added = {}
    for i = 1, #items do
        local line = items[i]
        local ok = exports.ox_inventory:AddItem(stashId, line.item, line.count)
        if not ok then
            -- Undo the lines already added and give the order back
            for j = 1, #added do
                exports.ox_inventory:RemoveItem(stashId, added[j].item, added[j].count)
            end
            local okRevert, reverted = pcall(MySQL.update.await,
                "UPDATE `ap1le_mechanicjob_orders` SET `status` = 'arrived', `collected_by` = NULL, `collected_at` = NULL WHERE `id` = ?",
                { orderId })
            if not okRevert or reverted ~= 1 then
                print(('[ap1le_mechanicjob] ORDER %d: stash full while unpacking and reverting the status failed'):format(orderId))
                crates[orderId] = nil
                publishCrates()
            end
            return false, 'stock_full'
        end
        added[#added + 1] = line
    end

    crates[orderId] = nil
    publishCrates()

    return true, { id = orderId, items = items, workshop = workshop.id }
end

lib.callback.register('ap1le_mechanicjob:order:unpackFinish', function(source)
    if not Mechanic.RateLimit(source, 'order:unpackFinish', 500) then return false, 'too_fast' end

    local pending = Mechanic.GetPending(source)
    if not pending or pending.kind ~= 'unpack' then
        if Mechanic.RateLimit(source, 'flag:order:unpackFinish', 10000) then
            Mechanic.Flag(source, 'order:unpackFinish without a pending unpack')
        end
        return false, 'error'
    end

    -- Any outcome below ends this pending action
    Mechanic.Pending[source] = nil

    local xPlayer = Mechanic.GetMechanic(source)
    if not xPlayer then return false, 'not_mechanic' end

    if not Mechanic.ElapsedOk(pending) then
        Mechanic.Flag(source, ('order:unpackFinish too fast (%d ms < %d ms)'):format(GetGameTimer() - pending.startedAt, pending.minMs))
        return false, 'too_fast'
    end

    local orderId = pending.orderId
    if not crates[orderId] then return false, 'order_not_found' end
    if not crateInReach(source, orderId, UNPACK_FINISH_DISTANCE) then return false, 'too_far' end
    if unpacking[orderId] then return false, 'busy' end

    unpacking[orderId] = source
    local ok, success, data = pcall(unpackOrder, source, xPlayer, orderId)
    unpacking[orderId] = nil

    if not ok then
        print(('[ap1le_mechanicjob] unpack error for order %d: %s'):format(orderId, tostring(success)))
        return false, 'error'
    end

    return success, data
end)
