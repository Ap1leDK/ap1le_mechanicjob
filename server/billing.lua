-- ap1le_mechanicjob: built-in invoices (mechanic -> nearby customer).
-- The server owns the amounts, the expiry and the money split; the client only shows the dialog.
-- Every paid invoice is logged in ap1le_mechanicjob_invoices (shown in the computer's economy app).

local invoices = {}       -- [id] = { id, from, to, lines, total, expires }
local openByTarget = {}   -- [targetId] = invoice id
local lastSent = {}       -- [mechanic source] = GetGameTimer() of the last created invoice
local nextId = 0

local MAX_LABEL = 48

local notify = Mechanic.Notify
local formatMoney = Mechanic.FormatMoney

---Log a paid invoice. Runs after the money moved, so a failed insert is only logged to the console.
local function logInvoice(invoice, xMechanic, xCustomer, societyShare)
    local ok, err = pcall(MySQL.insert.await, [[
        INSERT INTO `ap1le_mechanicjob_invoices`
            (`workshop`, `mechanic_identifier`, `mechanic_name`, `customer_identifier`, `customer_name`,
             `total`, `society_share`, `lines`, `created_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        invoice.workshop, xMechanic.identifier, Mechanic.PlayerName(xMechanic),
        xCustomer.identifier, Mechanic.PlayerName(xCustomer),
        invoice.total, societyShare, json.encode(invoice.lines), os.time(),
    })
    if not ok then
        print(('[ap1le_mechanicjob] logging invoice %d failed (was sql/install.sql run?): %s'):format(invoice.id, tostring(err)))
    end
end

local function removeInvoice(id)
    local invoice = invoices[id]
    if not invoice then return nil end

    invoices[id] = nil
    if openByTarget[invoice.to] == id then
        openByTarget[invoice.to] = nil
    end

    return invoice
end

local function expireInvoice(id, expires)
    local invoice = invoices[id]
    -- Only expire the exact invoice this timer was created for
    if not invoice or invoice.expires ~= expires then return end

    removeInvoice(id)
    TriggerClientEvent('ap1le_mechanicjob:invoice:hide', invoice.to, id)
    notify(invoice.to, locale('invoice_expired'), 'error')
    if GetPlayerName(invoice.from) then
        notify(invoice.from, locale('invoice_expired'), 'error')
    end
end

---Strip control characters and markup, trim; returns nil if the label is invalid.
local function sanitiseLabel(label)
    if type(label) ~= 'string' or #label > MAX_LABEL * 4 then return nil end

    label = label:gsub('%c', ' '):gsub('[<>]', ''):gsub('%s%s+', ' ')
    label = Mechanic.Trim(label)

    local len = label and utf8.len(label)
    if not len or len < 1 or len > MAX_LABEL then return nil end

    return label
end

---Validate the client's lines. Returns a clean copy and the total, or nil.
local function sanitiseLines(lines)
    if type(lines) ~= 'table' then return nil end

    local n = #lines
    if n < 1 or n > Config.Invoice.maxLines then return nil end

    local count = 0
    for k in pairs(lines) do
        count = count + 1
        if math.type(k) ~= 'integer' or k < 1 or k > n or count > n then return nil end
    end

    local clean, total = {}, 0

    for i = 1, n do
        local line = lines[i]
        if type(line) ~= 'table' then return nil end

        local label = sanitiseLabel(line.label)
        if not label then return nil end

        if not Mechanic.IsInt(line.amount, 1, Config.Invoice.maxTotal) then return nil end
        local amount = math.tointeger(line.amount)

        total = total + amount
        if total > Config.Invoice.maxTotal then return nil end

        clean[i] = { label = label, amount = amount }
    end

    return clean, total
end

lib.callback.register('ap1le_mechanicjob:invoice:create', function(source, targetId, lines)
    local xPlayer = Mechanic.GetMechanic(source)
    if not xPlayer then return false, 'not_mechanic' end

    if not Mechanic.RateLimit(source, 'invoice:create', 1000) then return false, 'too_fast' end

    if not Mechanic.IsInt(targetId, 1, 0xFFFF) then
        Mechanic.Flag(source, 'invoice:create with invalid target id')
        return false, 'error'
    end
    targetId = math.tointeger(targetId)

    if targetId == source then
        Mechanic.Flag(source, 'invoice:create to self')
        return false, 'error'
    end

    local xTarget = ESX.GetPlayerFromId(targetId)
    if not xTarget then return false, 'not_available' end

    local ped, targetPed = GetPlayerPed(source), GetPlayerPed(targetId)
    if not ped or ped == 0 or not targetPed or targetPed == 0 then return false, 'not_available' end

    if GetEntityRoutingBucket(ped) ~= GetEntityRoutingBucket(targetPed)
        or #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > Config.Invoice.maxDistance then
        return false, 'too_far'
    end

    local clean, total = sanitiseLines(lines)
    if not clean then
        Mechanic.Flag(source, 'invoice:create with invalid lines')
        return false, 'error'
    end

    local last = lastSent[source]
    if last and GetGameTimer() - last < Config.Invoice.cooldownSeconds * 1000 then
        return false, 'too_fast'
    end

    local openId = openByTarget[targetId]
    if openId and invoices[openId] then return false, 'invoice_open' end

    nextId = nextId + 1
    local id = nextId
    local expireSeconds = Config.Invoice.expireSeconds
    local expires = os.time() + expireSeconds

    invoices[id] = {
        id = id,
        from = source,
        to = targetId,
        lines = clean,
        total = total,
        expires = expires,
        -- Workshop the mechanic was in when sending it (nil for field invoices), for the invoice log
        workshop = (Mechanic.PlayerWorkshop(source) or {}).id,
    }
    openByTarget[targetId] = id
    lastSent[source] = GetGameTimer()

    SetTimeout(expireSeconds * 1000, function()
        expireInvoice(id, expires)
    end)

    local mechanicName = Mechanic.PlayerName(xPlayer)

    TriggerClientEvent('ap1le_mechanicjob:invoice:show', targetId, {
        id = id,
        from = mechanicName,
        lines = clean,
        total = total,
        expireSeconds = expireSeconds,
    })

    notify(source, locale('invoice_sent', Mechanic.PlayerName(xTarget)), 'success')
    notify(targetId, locale('invoice_received', mechanicName), 'info')

    return true, { id = id }
end)

lib.callback.register('ap1le_mechanicjob:invoice:respond', function(source, id, accept)
    if not Mechanic.RateLimit(source, 'invoice:respond', 1000) then return false, 'too_fast' end

    if not Mechanic.IsInt(id, 1, math.maxinteger) or type(accept) ~= 'boolean' then
        Mechanic.Flag(source, 'invoice:respond with invalid arguments')
        return false, 'error'
    end
    id = math.tointeger(id)

    local invoice = invoices[id]
    if not invoice then return false, 'invoice_expired' end

    if invoice.to ~= source then
        Mechanic.Flag(source, ('invoice:respond to invoice %d addressed to %d'):format(id, invoice.to))
        return false, 'error'
    end

    if os.time() > invoice.expires then
        expireInvoice(id, invoice.expires)
        return false, 'invoice_expired'
    end

    if not accept then
        removeInvoice(id)
        TriggerClientEvent('ap1le_mechanicjob:invoice:hide', source, id)
        if GetPlayerName(invoice.from) then
            notify(invoice.from, locale('invoice_declined'), 'error')
        end
        return true
    end

    local xTarget = ESX.GetPlayerFromId(source)
    if not xTarget then return false, 'error' end

    -- The sender must still be a mechanic: a fired or resigned mechanic cannot collect old invoices
    local xMechanic = ESX.GetPlayerFromId(invoice.from)
    if not xMechanic or not xMechanic.job or xMechanic.job.name ~= Config.Job then
        removeInvoice(id)
        TriggerClientEvent('ap1le_mechanicjob:invoice:hide', source, id)
        return false, 'not_available'
    end

    local accountName = Config.Invoice.account
    local account = xTarget.getAccount(accountName)
    local total = invoice.total

    -- Not enough money: keep the invoice open so the customer can still decline
    if not account or type(account.money) ~= 'number' or account.money < total then
        return false, 'no_money'
    end

    -- Remove the invoice before moving money so it can never be paid twice
    removeInvoice(id)

    if not Mechanic.MovePlayerMoney(xTarget, accountName, total, false, 'ap1le_mechanicjob invoice') then
        print(('[ap1le_mechanicjob] invoice %d: removing %d from %s failed'):format(id, total, xTarget.identifier))
        TriggerClientEvent('ap1le_mechanicjob:invoice:hide', source, id)
        return false, 'error'
    end

    -- Split: society gets the floored share, the mechanic gets the rest (no money lost to rounding)
    local societyShare = math.floor(total * Config.Invoice.societyShare)
    if societyShare < 0 then societyShare = 0 elseif societyShare > total then societyShare = total end
    local mechanicShare = total - societyShare

    if societyShare > 0 and not Mechanic.SocietyAdd(societyShare) then
        print(('[ap1le_mechanicjob] society account "%s" did not accept %d, paying its share to the mechanic'):format(Config.Invoice.society, societyShare))
        mechanicShare = mechanicShare + societyShare
        societyShare = 0
    end

    if mechanicShare > 0 and not Mechanic.MovePlayerMoney(xMechanic, 'bank', mechanicShare, true, 'ap1le_mechanicjob invoice') then
        -- Last resort so the customer's money is never lost: hand the mechanic's share to the society
        if Mechanic.SocietyAdd(mechanicShare) then
            societyShare = societyShare + mechanicShare
            mechanicShare = 0
        else
            print(('[ap1le_mechanicjob] invoice %d: could not pay %d to %s or the society'):format(id, mechanicShare, xMechanic.identifier))
        end
    end

    logInvoice(invoice, xMechanic, xTarget, societyShare)

    TriggerClientEvent('ap1le_mechanicjob:invoice:hide', source, id)
    notify(source, locale('invoice_paid', formatMoney(total)), 'success')
    notify(invoice.from, locale('invoice_paid_mechanic', formatMoney(total), formatMoney(mechanicShare)), 'success')

    return true
end)

---Drop every open invoice sent by a mechanic and close the customer's dialog.
---@param from number mechanic server id
local function dropInvoicesFrom(from)
    for id, invoice in pairs(invoices) do
        if invoice.from == from then
            removeInvoice(id)
            if GetPlayerName(invoice.to) then
                TriggerClientEvent('ap1le_mechanicjob:invoice:hide', invoice.to, id)
            end
        end
    end
end

-- A mechanic who leaves the job loses the invoices still waiting for an answer
-- (the job is re-read from ESX, so a forged trigger of this event cannot drop someone else's invoices)
AddEventHandler('esx:setJob', function(playerId)
    if type(playerId) ~= 'number' or Mechanic.GetMechanic(playerId) then return end
    dropInvoicesFrom(playerId)
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastSent[src] = nil

    for id, invoice in pairs(invoices) do
        if invoice.to == src or invoice.from == src then
            removeInvoice(id)
            -- The mechanic left: close the popup on the customer's screen
            if invoice.from == src and GetPlayerName(invoice.to) then
                TriggerClientEvent('ap1le_mechanicjob:invoice:hide', invoice.to, id)
            end
        end
    end
end)
