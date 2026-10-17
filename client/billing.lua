-- ap1le_mechanicjob: invoices (client side).
-- Mechanic: create-invoice view in the NUI. Customer: popup with accept/decline.
-- All amounts, expiry and the money transfer are handled and validated by the server.

Billing = {}

local createOpen = false   -- mechanic's create view is showing
local customerId = nil     -- id of the invoice the customer popup is showing

-- Server errors after which the invoice no longer exists, so the popup must go away
local GONE_ERRORS = { invoice_expired = true, not_available = true }

local function errorText(err)
    if type(err) == 'string' and err ~= '' then return locale(err) end
    return locale('error')
end

---Give the mouse back unless another NUI view still needs it.
local function releaseFocus()
    if createOpen or customerId then return end
    if Tuning and Tuning.IsOpen and Tuning.IsOpen() then return end

    SetNuiFocus(false, false)
end

---@return boolean
function Billing.IsOpen()
    return createOpen or customerId ~= nil
end

---Open the create-invoice view for the nearest customers.
---@param prefill? { label: string, amount: integer }[]
function Billing.OpenCreate(prefill)
    if createOpen then return end

    if not Mechanic.IsMechanic() then
        UI.Notify(locale('not_mechanic'), 'error')
        return
    end

    local nearby = lib.getNearbyPlayers(GetEntityCoords(cache.ped), Config.Invoice.maxDistance, false)
    local players = {}

    for i = 1, #nearby do
        local playerIndex = nearby[i].id
        players[#players + 1] = {
            id = GetPlayerServerId(playerIndex),
            name = GetPlayerName(playerIndex),
        }
    end

    if #players == 0 then
        UI.Notify(locale('invoice_no_players'), 'error')
        return
    end

    local lines = {}

    if type(prefill) == 'table' then
        for i = 1, #prefill do
            local line = prefill[i]

            if type(line) == 'table' and type(line.label) == 'string' and tonumber(line.amount) then
                lines[#lines + 1] = { label = line.label, amount = math.floor(tonumber(line.amount)) }
            end
        end
    end

    createOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'openInvoice',
        data = {
            players = players,
            prefill = lines,
            maxLines = Config.Invoice.maxLines,
            maxTotal = Config.Invoice.maxTotal,
        },
    })
end

-- ---------------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------------

RegisterNUICallback('invoice:send', function(data, cb)
    if not createOpen or type(data) ~= 'table' then
        cb({ ok = false, error = locale('error') })
        return
    end

    local target = math.tointeger(tonumber(data.target))
    local lines = {}

    if target and type(data.lines) == 'table' then
        for i = 1, #data.lines do
            local line = data.lines[i]
            local amount = type(line) == 'table' and tonumber(line.amount)

            if not amount or type(line.label) ~= 'string' then
                target = nil
                break
            end

            lines[i] = { label = line.label, amount = math.tointeger(amount) or amount }
        end
    else
        target = nil
    end

    if not target then
        cb({ ok = false, error = locale('error') })
        return
    end

    local ok, result = lib.callback.await('ap1le_mechanicjob:invoice:create', false, target, lines)

    if not ok then
        -- Keep the view open so the mechanic can fix the problem
        cb({ ok = false, error = errorText(result) })
        return
    end

    createOpen = false
    releaseFocus()
    cb({ ok = true })
end)

RegisterNUICallback('invoice:cancel', function(_, cb)
    createOpen = false
    releaseFocus()
    cb({ ok = true })
end)

RegisterNUICallback('invoice:respond', function(data, cb)
    local id = type(data) == 'table' and math.tointeger(tonumber(data.id))

    if not id or type(data.accept) ~= 'boolean' then
        cb({ ok = false, error = locale('error') })
        return
    end

    local ok, result = lib.callback.await('ap1le_mechanicjob:invoice:respond', false, id, data.accept)

    if ok then
        -- The server also sends invoice:hide; clear the state right away so focus is never stuck
        if customerId == id then customerId = nil end
        releaseFocus()
        cb({ ok = true })
        return
    end

    -- Invoice vanished on the server (expired, mechanic left): close the popup
    if GONE_ERRORS[result] and customerId == id then
        customerId = nil
        SendNUIMessage({ action = 'hideInvoice', data = { id = id } })
        releaseFocus()
    end

    -- e.g. no_money: the popup stays so the customer can still decline
    cb({ ok = false, error = errorText(result) })
end)

-- ---------------------------------------------------------------------------
-- Server events (customer side)
-- ---------------------------------------------------------------------------

RegisterNetEvent('ap1le_mechanicjob:invoice:show', function(invoice)
    if type(invoice) ~= 'table' or not invoice.id then return end

    customerId = invoice.id
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'showInvoice',
        data = {
            id = invoice.id,
            from = invoice.from,
            lines = invoice.lines,
            total = invoice.total,
            expireSeconds = invoice.expireSeconds,
        },
    })

    -- Safety net: if the hide event is ever lost the mouse must not stay captured
    local id = invoice.id
    local timeout = ((tonumber(invoice.expireSeconds) or Config.Invoice.expireSeconds) + 5) * 1000

    SetTimeout(timeout, function()
        if customerId == id then
            customerId = nil
            SendNUIMessage({ action = 'hideInvoice', data = { id = id } })
            releaseFocus()
        end
    end)
end)

RegisterNetEvent('ap1le_mechanicjob:invoice:hide', function(id)
    if customerId == nil or (id ~= nil and id ~= customerId) then return end

    local hidden = customerId
    customerId = nil

    SendNUIMessage({ action = 'hideInvoice', data = { id = hidden } })
    releaseFocus()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    createOpen = false
    customerId = nil
    SetNuiFocus(false, false)
end)
