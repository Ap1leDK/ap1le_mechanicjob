-- ap1le_mechanicjob: the workshop computer (laptop) API and the cosmetic price list.
-- Every call: mechanic AND within Config.Computer.serverDistance of a workshop computer (that workshop is the
-- context). Chef calls also need grade >= Config.BossGrade. Stock, ordering and the order list are shared with
-- the workshop (server/stock.lua) and accept the computer position as well. Deposit/withdraw go through
-- esx_society (see "Chef: economy").

-- ---------------------------------------------------------------------------------------------
-- Price list (Config.Cosmetic defaults and the 'wash' service, overridden by rows in ap1le_mechanicjob_prices)
-- ---------------------------------------------------------------------------------------------

-- Ordered list of every priced option (cosmetics + 'wash'): { id, label, group, sub, default }
local priceEntries = {}
-- [id] = entry
local priceById = {}
-- [id] = current price (default or DB override)
local prices = {}

do
    local groupOrder = {}
    for i = 1, #Config.Cosmetic.groups do
        groupOrder[Config.Cosmetic.groups[i].id] = i
    end

    for i = 1, #Config.Cosmetic.mods do
        local mod = Config.Cosmetic.mods[i]
        local entry = { id = mod.id, label = mod.label, group = mod.group, sub = mod.sub, default = math.tointeger(mod.price) or 0 }
        priceEntries[#priceEntries + 1] = entry
        priceById[mod.id] = entry
    end

    local extraIds = {}
    for id in pairs(Config.Cosmetic.extras) do extraIds[#extraIds + 1] = id end
    table.sort(extraIds, function(a, b)
        local ga = groupOrder[Config.Cosmetic.extras[a].group] or math.huge
        local gb = groupOrder[Config.Cosmetic.extras[b].group] or math.huge
        if ga == gb then return a < b end
        return ga < gb
    end)

    for i = 1, #extraIds do
        local id = extraIds[i]
        local extra = Config.Cosmetic.extras[id]
        if not priceById[id] then
            local entry = { id = id, label = extra.label, group = extra.group, default = math.tointeger(extra.price) or 0 }
            priceEntries[#priceEntries + 1] = entry
            priceById[id] = entry
        end
    end

    -- Car wash ("Rens bil"): a service, listed with the "other" group so the price list app shows it
    if Config.Wash and not priceById.wash then
        local entry = { id = 'wash', label = locale('price_wash'), group = 'other', default = math.tointeger(Config.Wash.price) or 0 }
        priceEntries[#priceEntries + 1] = entry
        priceById.wash = entry
    end

    -- Keep mods and extras of the same group together, in the configured group order
    local index = {}
    for i = 1, #priceEntries do index[priceEntries[i]] = i end
    table.sort(priceEntries, function(a, b)
        local ga, gb = groupOrder[a.group] or math.huge, groupOrder[b.group] or math.huge
        if ga == gb then return index[a] < index[b] end
        return ga < gb
    end)

    for i = 1, #priceEntries do
        prices[priceEntries[i].id] = priceEntries[i].default
    end
end

---Current price of every priced option (cosmetics + 'wash'): { [id] = price }. Returns a copy.
---@return table
function Mechanic.GetPrices()
    local copy = {}
    for id, price in pairs(prices) do copy[id] = price end
    return copy
end

local function loadPrices()
    local ok, rows = pcall(MySQL.query.await, 'SELECT `id`, `price` FROM `ap1le_mechanicjob_prices`')
    if not ok or type(rows) ~= 'table' then
        print(('[ap1le_mechanicjob] reading ap1le_mechanicjob_prices failed (was sql/install.sql run?): %s'):format(tostring(rows)))
        return
    end

    for i = 1, #rows do
        local id, price = rows[i].id, tonumber(rows[i].price)
        if priceById[id] and price and Mechanic.IsInt(price, 0, Config.Cosmetic.maxPrice) then
            prices[id] = math.tointeger(price)
        end
    end
end

-- Exposed for the mocked tests
Mechanic.LoadPrices = loadPrices

MySQL.ready(loadPrices)

-- ---------------------------------------------------------------------------------------------
-- Access checks
-- ---------------------------------------------------------------------------------------------

---Mechanic at a computer (and chef when boss = true). Returns xPlayer + workshop, or nil + locale key.
---@param source number
---@param boss boolean
---@param key string rate-limit key
---@param ms integer rate-limit window
---@return table|nil xPlayer
---@return table|string workshop or error key
local function atComputer(source, boss, key, ms)
    local xPlayer = Mechanic.GetMechanic(source)
    if not xPlayer then return nil, 'not_mechanic' end
    if not Mechanic.RateLimit(source, key, ms) then return nil, 'too_fast' end

    local workshop = Mechanic.ComputerWorkshop(source)
    if not workshop then return nil, 'pc_too_far' end

    if boss and not Mechanic.IsBoss(xPlayer) then
        Mechanic.Flag(source, ('%s by a non-chef'):format(key))
        return nil, 'pc_not_boss'
    end

    return xPlayer, workshop
end

---Re-check a chef after a yielding query: still online, still chef, still at the same computer.
local function stillChef(source, workshop)
    local xPlayer = Mechanic.GetMechanic(source)
    if not xPlayer or not Mechanic.IsBoss(xPlayer) then return nil end
    if Mechanic.ComputerWorkshop(source) ~= workshop then return nil end
    return xPlayer
end

---{ { grade, label } } for Config.Job from job_grades, sorted by grade; nil on error.
local function loadGrades()
    local ok, rows = pcall(MySQL.query.await,
        'SELECT `grade`, `label` FROM `job_grades` WHERE `job_name` = ? ORDER BY `grade`', { Config.Job })
    if not ok or type(rows) ~= 'table' then
        print(('[ap1le_mechanicjob] reading job_grades failed: %s'):format(tostring(rows)))
        return nil
    end

    local list = {}
    for i = 1, #rows do
        local grade = math.tointeger(tonumber(rows[i].grade))
        if grade then list[#list + 1] = { grade = grade, label = tostring(rows[i].label or grade) } end
    end
    return list
end

local function gradeLabel(grades, grade)
    for i = 1, #grades do
        if grades[i].grade == grade then return grades[i].label end
    end
    return tostring(grade)
end

---True if ESX knows the job/grade (setJob silently ignores unknown ones).
local function jobExists(job, grade)
    local ok, exists = pcall(ESX.DoesJobExist, job, grade)
    return ok and exists == true
end

---setJob and verify ESX accepted it.
local function setJob(xTarget, job, grade)
    local ok, err = pcall(xTarget.setJob, job, grade)
    if not ok then
        print(('[ap1le_mechanicjob] setJob(%s, %d) for %s failed: %s'):format(job, grade, tostring(xTarget.identifier), tostring(err)))
        return false
    end
    return xTarget.job and xTarget.job.name == job and Mechanic.GetGrade(xTarget) == grade
end

-- ---------------------------------------------------------------------------------------------
-- Shared apps
-- ---------------------------------------------------------------------------------------------

lib.callback.register('ap1le_mechanicjob:computer:open', function(source)
    local xPlayer, workshop = atComputer(source, false, 'computer:open', 1000)
    if not xPlayer then return false, workshop end

    return true, {
        name = Mechanic.PlayerName(xPlayer),
        grade = Mechanic.GetGrade(xPlayer),
        gradeLabel = xPlayer.job.grade_label or tostring(Mechanic.GetGrade(xPlayer)),
        isBoss = Mechanic.IsBoss(xPlayer),
        workshop = { id = workshop.id, label = workshop.label },
        -- This player's order limits (smaller below chef grade), so the Bestil cart can apply them
        orderLimits = Mechanic.OrderLimits(xPlayer),
    }
end)

-- Category of a shop item: 'repair' for repair kits, the Config.Performance key for parts, else 'other'
local itemCategory, itemLevel = {}, {}
for _, cfg in pairs(Config.Repair) do itemCategory[cfg.item] = 'repair' end
for category, cfg in pairs(Config.Performance) do
    for level = 1, #cfg.levels do
        itemCategory[cfg.levels[level]] = category
        itemLevel[cfg.levels[level]] = level
    end
end

local CATEGORY_ORDER = { repair = 1, engine = 2, brakes = 3, transmission = 4, suspension = 5, armor = 6, turbo = 7 }

local function categoryLabel(category)
    if category == 'repair' then return locale('pc_cat_repair') end
    local cfg = Config.Performance[category]
    if cfg then return cfg.label end
    return locale('pc_cat_other')
end

lib.callback.register('ap1le_mechanicjob:computer:catalog', function(source)
    local xPlayer, workshop = atComputer(source, false, 'computer:catalog', 500)
    if not xPlayer then return false, workshop end

    local names = {}
    for item in pairs(Config.Shop.items) do names[#names + 1] = item end

    local function rank(item)
        local category = itemCategory[item] or 'other'
        return CATEGORY_ORDER[category] or 99, category
    end
    table.sort(names, function(a, b)
        local ra, ca = rank(a)
        local rb, cb = rank(b)
        if ra ~= rb then return ra < rb end
        if ca ~= cb then return ca < cb end
        local la, lb = itemLevel[a] or 0, itemLevel[b] or 0
        if la ~= lb then return la < lb end
        return a < b
    end)

    local stock = Mechanic.StashCounts(Mechanic.StashId(workshop), names)
    local list = {}
    for i = 1, #names do
        local item = names[i]
        local category = itemCategory[item] or 'other'
        list[i] = {
            item = item,
            label = Mechanic.ItemLabel(item),
            price = math.tointeger(Config.Shop.items[item]) or 0,
            stock = stock[item] or 0,
            category = category,
            categoryLabel = categoryLabel(category),
        }
    end

    return true, list
end)

-- ---------------------------------------------------------------------------------------------
-- Chef: staff
-- ---------------------------------------------------------------------------------------------

---Employees from users (job = Config.Job), merged with the live ESX state of online players.
local function loadStaffRows()
    local ok, rows = pcall(MySQL.query.await,
        'SELECT `identifier`, `firstname`, `lastname`, `job_grade` FROM `users` WHERE `job` = ?', { Config.Job })
    if not ok or type(rows) ~= 'table' then
        -- Servers without esx_identity have no name columns
        ok, rows = pcall(MySQL.query.await, 'SELECT `identifier`, `job_grade` FROM `users` WHERE `job` = ?', { Config.Job })
    end
    if not ok or type(rows) ~= 'table' then
        print(('[ap1le_mechanicjob] reading users failed: %s'):format(tostring(rows)))
        return nil
    end
    return rows
end

lib.callback.register('ap1le_mechanicjob:computer:staff', function(source)
    local xPlayer, workshop = atComputer(source, true, 'computer:staff', 1000)
    if not xPlayer then return false, workshop end

    local grades = loadGrades()
    local rows = loadStaffRows()
    if not grades or not rows then return false, 'error' end

    if not stillChef(source, workshop) then return false, 'pc_not_boss' end

    local chefGrade = Mechanic.GetGrade(xPlayer)
    local byId, list = {}, {}

    local function add(identifier, name, grade, xTarget)
        if byId[identifier] then return end
        local entry = {
            identifier = identifier,
            name = name,
            grade = grade,
            gradeLabel = gradeLabel(grades, grade),
            online = xTarget ~= nil,
            serverId = xTarget and xTarget.source or nil,
            isSelf = identifier == xPlayer.identifier,
            canManage = identifier ~= xPlayer.identifier and grade < chefGrade,
        }
        byId[identifier] = entry
        list[#list + 1] = entry
    end

    -- Online players first: their ESX job is newer than the users row (saved later)
    local okPlayers, online = pcall(ESX.GetExtendedPlayers)
    if okPlayers and type(online) == 'table' then
        for i = 1, #online do
            local xTarget = online[i]
            if xTarget.job and xTarget.job.name == Config.Job and type(xTarget.identifier) == 'string' then
                add(xTarget.identifier, Mechanic.PlayerName(xTarget), Mechanic.GetGrade(xTarget), xTarget)
            end
        end
    end

    for i = 1, #rows do
        local row = rows[i]
        local identifier = row.identifier
        -- Online players whose live job is no longer mechanic are skipped (fired, not saved yet)
        if type(identifier) == 'string' and not byId[identifier] and not ESX.GetPlayerFromIdentifier(identifier) then
            local name = ((row.firstname or '') .. ' ' .. (row.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
            add(identifier, name ~= '' and name or identifier, math.tointeger(tonumber(row.job_grade)) or 0, nil)
        end
    end

    table.sort(list, function(a, b)
        if a.grade ~= b.grade then return a.grade > b.grade end
        return a.name < b.name
    end)

    return true, { staff = list, grades = grades }
end)

lib.callback.register('ap1le_mechanicjob:computer:nearby', function(source)
    local xPlayer, workshop = atComputer(source, true, 'computer:nearby', 1000)
    if not xPlayer then return false, workshop end

    local pcCoords = Mechanic.ToVec3(workshop.computer.coords)
    local _, ped = Mechanic.PedCoords(source)
    local bucket = ped and GetEntityRoutingBucket(ped)
    local list = {}

    local ok, players = pcall(ESX.GetExtendedPlayers)
    if ok and type(players) == 'table' then
        for i = 1, #players do
            local xTarget = players[i]
            if xTarget.source ~= source and (not xTarget.job or xTarget.job.name ~= Config.Job) then
                local coords, targetPed = Mechanic.PedCoords(xTarget.source)
                if coords and GetEntityRoutingBucket(targetPed) == bucket
                    and #(coords - pcCoords) <= Config.Computer.hireDistance then
                    list[#list + 1] = { serverId = xTarget.source, name = Mechanic.PlayerName(xTarget) }
                end
            end
        end
    end

    table.sort(list, function(a, b) return a.name < b.name end)
    return true, list
end)

-- Hire offers: the target must accept on their own screen before their job changes
local HIRE_ANSWER_SECONDS = 30      -- the offer closes on the target's screen after this
local HIRE_OFFER_COOLDOWN_MS = 30000 -- per target, after an offer ended without a yes
local hireOffers = {}               -- [target server id] = true while an offer is open
local hireCooldown = {}             -- [target server id] = GetGameTimer() when the last offer ended

---Target is online, not a mechanic and near the workshop computer (same routing bucket as the chef).
---@return table|nil xTarget
---@return string|nil err
local function hireTarget(source, workshop, serverId)
    local xTarget = ESX.GetPlayerFromId(serverId)
    if not xTarget then return nil, 'not_available' end
    if xTarget.job and xTarget.job.name == Config.Job then return nil, 'pc_already_employed' end

    local coords, targetPed = Mechanic.PedCoords(serverId)
    local _, ped = Mechanic.PedCoords(source)
    if not coords or not ped or GetEntityRoutingBucket(targetPed) ~= GetEntityRoutingBucket(ped)
        or #(coords - Mechanic.ToVec3(workshop.computer.coords)) > Config.Computer.hireDistance then
        return nil, 'too_far'
    end

    return xTarget
end

---Ask the target (client callback ap1le_mechanicjob:hire:ask) and wait at most a few seconds longer
---than the offer is shown, so a client that never answers cannot hold the chef's request.
---@return string|nil answer 'accepted' | 'declined' | 'busy' | nil (no answer)
local function askTarget(serverId, workshop, chefName)
    local p = promise.new()
    local done = false
    local function answer(value)
        if done then return end
        done = true
        p:resolve(value)
    end

    local ok = pcall(lib.callback, 'ap1le_mechanicjob:hire:ask', serverId, function(value)
        answer(type(value) == 'string' and value or nil)
    end, workshop.label, chefName, HIRE_ANSWER_SECONDS)
    if not ok then return nil end

    SetTimeout((HIRE_ANSWER_SECONDS + 5) * 1000, function() answer(nil) end)
    return Citizen.Await(p)
end

lib.callback.register('ap1le_mechanicjob:computer:hire', function(source, serverId)
    local xPlayer, workshop = atComputer(source, true, 'computer:hire', 1000)
    if not xPlayer then return false, workshop end

    if not Mechanic.IsInt(serverId, 1, 0xFFFF) then
        Mechanic.Flag(source, 'computer:hire with invalid server id')
        return false, 'error'
    end
    serverId = math.tointeger(serverId)
    if serverId == source then return false, 'pc_self' end

    local _, targetErr = hireTarget(source, workshop, serverId)
    if targetErr then return false, targetErr end

    if not jobExists(Config.Job, 0) then
        print(('[ap1le_mechanicjob] job "%s" grade 0 does not exist in ESX (was sql/install.sql run?)'):format(Config.Job))
        return false, 'error'
    end

    if hireOffers[serverId] then return false, 'pc_hire_pending' end
    local last = hireCooldown[serverId]
    if last and GetGameTimer() - last < HIRE_OFFER_COOLDOWN_MS then return false, 'pc_hire_cooldown' end

    hireOffers[serverId] = true
    local okAsk, answer = pcall(askTarget, serverId, workshop, Mechanic.PlayerName(xPlayer))
    hireOffers[serverId] = nil

    if not okAsk or answer ~= 'accepted' then
        -- A busy screen (another dialog open) is no answer: the chef may simply try again
        if okAsk and answer == 'busy' then return false, 'pc_hire_busy' end
        hireCooldown[serverId] = GetGameTimer()
        if okAsk and answer == 'declined' then
            Mechanic.Notify(serverId, locale('pc_hire_declined_target'), 'info')
            return false, 'pc_hire_declined'
        end
        return false, 'pc_hire_no_answer'
    end

    -- The answer took a while: everything may have changed meanwhile
    xPlayer = stillChef(source, workshop)
    if not xPlayer then return false, 'pc_not_boss' end

    local xTarget, err = hireTarget(source, workshop, serverId)
    if not xTarget then return false, err end

    if not setJob(xTarget, Config.Job, 0) then return false, 'error' end

    Mechanic.Notify(serverId, locale('pc_hired_target', workshop.label), 'success')
    return true, { serverId = serverId, name = Mechanic.PlayerName(xTarget) }
end)

AddEventHandler('playerDropped', function()
    local src = source
    hireOffers[src] = nil
    hireCooldown[src] = nil
end)

---Shared target checks for setGrade and fire. Returns a target record or nil + locale key.
---target = { identifier, online = xTarget|nil, grade }
local function resolveEmployee(source, xPlayer, identifier)
    if not Mechanic.IsIdentifier(identifier) then
        Mechanic.Flag(source, 'computer staff call with invalid identifier')
        return nil, 'error'
    end
    if identifier == xPlayer.identifier then return nil, 'pc_self' end

    local chefGrade = Mechanic.GetGrade(xPlayer)
    local xTarget = ESX.GetPlayerFromIdentifier(identifier)

    if xTarget then
        if not xTarget.job or xTarget.job.name ~= Config.Job then return nil, 'pc_not_employee' end
        local grade = Mechanic.GetGrade(xTarget)
        if grade >= chefGrade then return nil, 'pc_rank' end
        return { identifier = identifier, online = xTarget, grade = grade }
    end

    local ok, row = pcall(MySQL.single.await, 'SELECT `job`, `job_grade` FROM `users` WHERE `identifier` = ?', { identifier })
    if not ok then return nil, 'error' end
    if not row or row.job ~= Config.Job then return nil, 'pc_not_employee' end

    local grade = math.tointeger(tonumber(row.job_grade)) or 0
    if grade >= chefGrade then return nil, 'pc_rank' end

    return { identifier = identifier, grade = grade }
end

lib.callback.register('ap1le_mechanicjob:computer:setGrade', function(source, identifier, grade)
    local xPlayer, workshop = atComputer(source, true, 'computer:setGrade', 1000)
    if not xPlayer then return false, workshop end

    local chefGrade = Mechanic.GetGrade(xPlayer)
    if not Mechanic.IsInt(grade, 0, chefGrade - 1) then
        if not Mechanic.IsInt(grade, 0, 255) then Mechanic.Flag(source, 'computer:setGrade with invalid grade') end
        return false, 'pc_invalid_grade'
    end
    grade = math.tointeger(grade)

    local grades = loadGrades()
    if not grades then return false, 'error' end
    local exists = false
    for i = 1, #grades do
        if grades[i].grade == grade then exists = true break end
    end
    if not exists or not jobExists(Config.Job, grade) then return false, 'pc_invalid_grade' end

    local target, err = resolveEmployee(source, xPlayer, identifier)
    if not target then return false, err end

    -- The queries yielded: the caller must still be chef (with the same or a higher grade) at the computer
    xPlayer = stillChef(source, workshop)
    if not xPlayer or grade >= Mechanic.GetGrade(xPlayer) or target.grade >= Mechanic.GetGrade(xPlayer) then
        return false, 'pc_not_boss'
    end

    if target.grade == grade then return true, { identifier = identifier, grade = grade } end

    local xTarget = target.online or ESX.GetPlayerFromIdentifier(identifier)
    if xTarget then
        if not xTarget.job or xTarget.job.name ~= Config.Job or Mechanic.GetGrade(xTarget) >= Mechanic.GetGrade(xPlayer) then
            return false, 'pc_rank'
        end
        if not setJob(xTarget, Config.Job, grade) then return false, 'error' end
        Mechanic.Notify(xTarget.source, locale('pc_grade_target', gradeLabel(grades, grade)), 'info')
        return true, { identifier = identifier, grade = grade }
    end

    local ok, affected = pcall(MySQL.update.await,
        'UPDATE `users` SET `job_grade` = ? WHERE `identifier` = ? AND `job` = ?', { grade, identifier, Config.Job })
    if not ok or type(affected) ~= 'number' or affected < 1 then return false, 'error' end

    -- Logged in while the update ran: ESX already loaded the old grade and would save it back
    local xLate = ESX.GetPlayerFromIdentifier(identifier)
    if xLate and xLate.job and xLate.job.name == Config.Job and Mechanic.GetGrade(xLate) ~= grade then
        setJob(xLate, Config.Job, grade)
    end

    return true, { identifier = identifier, grade = grade }
end)

lib.callback.register('ap1le_mechanicjob:computer:fire', function(source, identifier)
    local xPlayer, workshop = atComputer(source, true, 'computer:fire', 1000)
    if not xPlayer then return false, workshop end

    local target, err = resolveEmployee(source, xPlayer, identifier)
    if not target then return false, err end

    xPlayer = stillChef(source, workshop)
    if not xPlayer or target.grade >= Mechanic.GetGrade(xPlayer) then return false, 'pc_not_boss' end

    local xTarget = target.online or ESX.GetPlayerFromIdentifier(identifier)
    if xTarget then
        if not xTarget.job or xTarget.job.name ~= Config.Job or Mechanic.GetGrade(xTarget) >= Mechanic.GetGrade(xPlayer) then
            return false, 'pc_rank'
        end
        local ok = pcall(xTarget.setJob, 'unemployed', 0)
        if not ok or not xTarget.job or xTarget.job.name ~= 'unemployed' then
            print(('[ap1le_mechanicjob] firing %s failed (does the job "unemployed" exist?)'):format(identifier))
            return false, 'error'
        end
        Mechanic.Notify(xTarget.source, locale('pc_fired_target', workshop.label), 'warning')
        return true, { identifier = identifier }
    end

    local ok, affected = pcall(MySQL.update.await,
        "UPDATE `users` SET `job` = 'unemployed', `job_grade` = 0 WHERE `identifier` = ? AND `job` = ?", { identifier, Config.Job })
    if not ok or type(affected) ~= 'number' or affected < 1 then return false, 'error' end

    local xLate = ESX.GetPlayerFromIdentifier(identifier)
    if xLate and xLate.job and xLate.job.name == Config.Job then
        pcall(xLate.setJob, 'unemployed', 0)
    end

    return true, { identifier = identifier }
end)

-- ---------------------------------------------------------------------------------------------
-- Chef: economy
-- ---------------------------------------------------------------------------------------------

local function workshopLabel(id)
    local ws = Mechanic.WorkshopById(id)
    return ws and ws.label or (id and tostring(id)) or ''
end

lib.callback.register('ap1le_mechanicjob:computer:economy', function(source)
    local xPlayer, workshop = atComputer(source, true, 'computer:economy', 1000)
    if not xPlayer then return false, workshop end

    local rowsLimit = math.tointeger(Config.Computer.historyRows) or 50
    if rowsLimit < 1 then rowsLimit = 1 elseif rowsLimit > 500 then rowsLimit = 500 end

    -- rowsLimit is a validated integer from config, so it is formatted in (some MySQL versions reject a bound LIMIT)
    local okInv, invoices = pcall(MySQL.query.await, ([[
        SELECT `workshop`, `mechanic_name`, `customer_name`, `total`, `society_share`, `created_at`
        FROM `ap1le_mechanicjob_invoices` ORDER BY `id` DESC LIMIT %d]]):format(rowsLimit))
    local okOrd, orders = pcall(MySQL.query.await, ([[
        SELECT `workshop`, `ordered_by_name`, `total`, `created_at`
        FROM `ap1le_mechanicjob_orders` ORDER BY `id` DESC LIMIT %d]]):format(rowsLimit))
    local okTx, transfers = pcall(MySQL.query.await, ([[
        SELECT `workshop`, `type`, `amount`, `name`, `created_at`
        FROM `ap1le_mechanicjob_transactions` ORDER BY `id` DESC LIMIT %d]]):format(rowsLimit))

    if not (okInv and okOrd and okTx) or type(invoices) ~= 'table' or type(orders) ~= 'table' or type(transfers) ~= 'table' then
        print('[ap1le_mechanicjob] computer:economy: reading the history failed (was sql/install.sql run?)')
        return false, 'error'
    end

    if not stillChef(source, workshop) then return false, 'pc_not_boss' end

    local balance = Mechanic.SocietyBalance()
    if not balance then return false, 'error' end

    local history = {}
    for i = 1, #invoices do
        local r = invoices[i]
        history[#history + 1] = {
            type = 'invoice', amount = tonumber(r.society_share) or 0, total = tonumber(r.total) or 0,
            by = r.mechanic_name or '', detail = r.customer_name or '', workshop = workshopLabel(r.workshop),
            created_at = tonumber(r.created_at) or 0,
        }
    end
    for i = 1, #orders do
        local r = orders[i]
        history[#history + 1] = {
            type = 'order', amount = tonumber(r.total) or 0,
            by = r.ordered_by_name or '', detail = workshopLabel(r.workshop), workshop = workshopLabel(r.workshop),
            created_at = tonumber(r.created_at) or 0,
        }
    end
    for i = 1, #transfers do
        local r = transfers[i]
        if r.type == 'deposit' or r.type == 'withdraw' then
            history[#history + 1] = {
                type = r.type, amount = tonumber(r.amount) or 0,
                by = r.name or '', detail = workshopLabel(r.workshop), workshop = workshopLabel(r.workshop),
                created_at = tonumber(r.created_at) or 0,
            }
        end
    end

    table.sort(history, function(a, b) return a.created_at > b.created_at end)
    for i = #history, rowsLimit + 1, -1 do history[i] = nil end

    return true, { balance = balance, history = history }
end)

-- Deposit/withdraw (v3 A1). The money is moved here on the server with the standard ESX calls:
-- xPlayer.addAccountMoney/removeAccountMoney for the chef and esx_addonaccount:getSharedAccount for the
-- society (the same pattern esx_society and esx_billing use internally). The client never fires
-- esx_society's net events, so our chef rule, the computer distance check and Config.Computer.maxTransfer
-- always apply, whatever esx_society version the server runs.

---Shared checks for deposit/withdraw. Returns xPlayer, workshop, amount or nil + locale key.
local function transferArgs(source, amount, key)
    local xPlayer, workshop = atComputer(source, true, key, 1000)
    if not xPlayer then return nil, workshop end

    if not Mechanic.IsInt(amount, 1, Config.Computer.maxTransfer) then
        if type(amount) ~= 'number' then Mechanic.Flag(source, ('%s with a non-number amount'):format(key)) end
        return nil, 'pc_invalid_amount'
    end

    if not Mechanic.GetSociety() then
        print(('[ap1le_mechanicjob] society account "%s" not found (run sql/install.sql, then restart esx_addonaccount)')
            :format(Config.Invoice.society))
        return nil, 'error'
    end

    return xPlayer, workshop, math.tointeger(amount)
end

lib.callback.register('ap1le_mechanicjob:computer:deposit', function(source, amount)
    local xPlayer, workshop, value = transferArgs(source, amount, 'computer:deposit')
    if not xPlayer then return false, workshop end

    local accountName = Config.Computer.account
    local account = xPlayer.getAccount(accountName)
    if not account or type(account.money) ~= 'number' or account.money < value then return false, 'pc_no_money' end

    if not Mechanic.MovePlayerMoney(xPlayer, accountName, value, false, 'ap1le_mechanicjob society deposit') then
        return false, 'error'
    end

    if not Mechanic.SocietyAdd(value) then
        if not Mechanic.MovePlayerMoney(xPlayer, accountName, value, true, 'ap1le_mechanicjob society deposit refund') then
            print(('[ap1le_mechanicjob] DEPOSIT REFUND FAILED: %d taken from %s'):format(value, xPlayer.identifier))
        end
        return false, 'error'
    end

    Mechanic.LogTransaction(workshop.id, 'deposit', value, xPlayer)
    return true, { kind = 'deposit', amount = value, balance = Mechanic.SocietyBalance() }
end)

lib.callback.register('ap1le_mechanicjob:computer:withdraw', function(source, amount)
    local xPlayer, workshop, value = transferArgs(source, amount, 'computer:withdraw')
    if not xPlayer then return false, workshop end

    local accountName = Config.Computer.account
    if not xPlayer.getAccount(accountName) then return false, 'error' end

    local removed, err = Mechanic.SocietyRemove(value)
    if not removed then return false, err == 'order_no_money' and 'pc_society_no_money' or 'error' end

    if not Mechanic.MovePlayerMoney(xPlayer, accountName, value, true, 'ap1le_mechanicjob society withdraw') then
        if not Mechanic.SocietyAdd(value) then
            print(('[ap1le_mechanicjob] WITHDRAW REFUND FAILED: %d taken from "%s"'):format(value, Config.Invoice.society))
        end
        return false, 'error'
    end

    Mechanic.LogTransaction(workshop.id, 'withdraw', value, xPlayer)
    return true, { kind = 'withdraw', amount = value, balance = Mechanic.SocietyBalance() }
end)

-- ---------------------------------------------------------------------------------------------
-- Chef: price list
-- ---------------------------------------------------------------------------------------------

lib.callback.register('ap1le_mechanicjob:computer:prices', function(source)
    local xPlayer, workshop = atComputer(source, true, 'computer:prices', 500)
    if not xPlayer then return false, workshop end

    local list = {}
    for i = 1, #priceEntries do
        local e = priceEntries[i]
        list[i] = { id = e.id, label = e.label, group = e.group, sub = e.sub, default = e.default, price = prices[e.id] }
    end

    return true, list
end)

lib.callback.register('ap1le_mechanicjob:computer:setPrices', function(source, map)
    local xPlayer, workshop = atComputer(source, true, 'computer:setPrices', 2000)
    if not xPlayer then return false, workshop end

    if type(map) ~= 'table' then
        Mechanic.Flag(source, 'computer:setPrices with a non-table')
        return false, 'pc_invalid_price'
    end

    local changes, count = {}, 0
    for id, price in pairs(map) do
        count = count + 1
        if count > #priceEntries or type(id) ~= 'string' or not priceById[id] then
            Mechanic.Flag(source, 'computer:setPrices with an unknown id')
            return false, 'pc_invalid_price'
        end
        if not Mechanic.IsInt(price, 0, Config.Cosmetic.maxPrice) then return false, 'pc_invalid_price' end
        changes[#changes + 1] = { id = id, price = math.tointeger(price) }
    end

    if #changes == 0 then return true, Mechanic.GetPrices() end
    table.sort(changes, function(a, b) return a.id < b.id end)

    -- A price equal to its config default removes the override
    local queries = {}
    for i = 1, #changes do
        local c = changes[i]
        if c.price == priceById[c.id].default then
            queries[i] = { query = 'DELETE FROM `ap1le_mechanicjob_prices` WHERE `id` = ?', values = { c.id } }
        else
            queries[i] = {
                query = 'INSERT INTO `ap1le_mechanicjob_prices` (`id`, `price`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `price` = VALUES(`price`)',
                values = { c.id, c.price },
            }
        end
    end

    local ok, result = pcall(MySQL.transaction.await, queries)
    if not ok or result ~= true then
        print(('[ap1le_mechanicjob] saving prices failed: %s'):format(tostring(result)))
        return false, 'error'
    end

    for i = 1, #changes do
        prices[changes[i].id] = changes[i].price
    end

    return true, Mechanic.GetPrices()
end)
