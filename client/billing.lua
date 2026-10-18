-- ap1le_mechanicjob: invoices (client side), built on ap1le_core dialogs.
-- Mechanic: Ap1le.InputDialog (customer, price lines). Customer: Ap1le.Confirm with the lines and total.
-- All amounts, expiry and the money transfer are handled and validated by the server.

Billing = {}

local MAX_LABEL = 48          -- server limit for a line label
local BUSY_MS = 300           -- a Confirm that returns false faster than this never reached the player
local RETRY_BUSY_MS = 700     -- wait before asking again when another dialog was open
local MAX_ERROR_RETRIES = 3   -- re-asks after a server error (e.g. not enough money) before giving up

-- Server errors after which the invoice no longer exists, so the dialog must go away
local GONE_ERRORS = { invoice_expired = true, not_available = true }

local creating = false        -- the mechanic's input dialog is being built or shown
local shown = nil             -- customer side: { id, asking, askedAt, deadline }

---Trim a label and cut it to the server's limit (by characters, not bytes).
---@param text string
---@return string
local function cutLabel(text)
    text = text:gsub('[%c<>]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then return locale('invoice_extra_default') end

    local length = utf8.len(text)
    if length and length > MAX_LABEL then
        text = text:sub(1, utf8.offset(text, MAX_LABEL + 1) - 1)
    elseif not length then
        text = text:sub(1, MAX_LABEL):gsub('[\192-\255][\128-\191]*$', '')
    end

    return text
end

---@return boolean
function Billing.IsOpen()
    return creating or shown ~= nil
end

-- ---------------------------------------------------------------------------
-- Mechanic: create an invoice
-- ---------------------------------------------------------------------------

---Nearby players as select options for the dialog.
---@return table[]
local function nearbyPlayers()
    local nearby = lib.getNearbyPlayers(GetEntityCoords(cache.ped), Config.Invoice.maxDistance, false)
    local options = {}

    for i = 1, #nearby do
        local playerIndex = nearby[i].id
        local serverId = GetPlayerServerId(playerIndex)

        options[#options + 1] = {
            value = tostring(serverId),
            label = ('%s (%d)'):format(GetPlayerName(playerIndex), serverId),
        }
    end

    return options
end

---Clean prefill lines: labels trimmed, amounts whole numbers >= 0. One field is reserved for the
---mechanic's own extra line, so surplus lines are merged into one "other" line instead of being lost.
---@param prefill any
---@return { label: string, amount: integer }[]
local function cleanPrefill(prefill)
    local lines = {}

    if type(prefill) == 'table' then
        for i = 1, #prefill do
            local line = prefill[i]
            local amount = type(line) == 'table' and tonumber(line.amount)

            if amount and type(line.label) == 'string' then
                lines[#lines + 1] = {
                    label = cutLabel(line.label),
                    amount = math.max(0, math.floor(amount)),
                }
            end
        end
    end

    local limit = Config.Invoice.maxLines - 1

    if #lines > limit then
        local rest = 0
        for i = limit, #lines do rest = rest + lines[i].amount end

        for i = #lines, limit, -1 do lines[i] = nil end
        lines[limit] = { label = locale('invoice_other_lines'), amount = rest }
    end

    return lines
end

---Open the create-invoice dialog for the nearest customers. Must run in a thread (the dialog waits).
---@param prefill? { label: string, amount: integer }[]
function Billing.OpenCreate(prefill)
    if creating then return end

    if not Mechanic.IsMechanic() then
        Ap1le.Notify(locale('not_mechanic'), 'error')
        return
    end

    creating = true

    local ok, err = pcall(function()
        local players = nearbyPlayers()

        if #players == 0 then
            Ap1le.Notify(locale('invoice_no_players'), 'error')
            return
        end

        local lines = cleanPrefill(prefill)

        local fields = {
            { type = 'select', label = locale('invoice_customer'), options = players, required = true, icon = 'user' },
        }

        for i = 1, #lines do
            fields[#fields + 1] = {
                type = 'number',
                label = lines[i].label,
                default = lines[i].amount,
                min = 0,
                max = Config.Invoice.maxTotal,
                icon = 'dollar-sign',
            }
        end

        -- One free line: description + amount
        fields[#fields + 1] = {
            type = 'input',
            label = locale('invoice_extra_label'),
            maxLength = MAX_LABEL,
            icon = 'pen',
        }
        fields[#fields + 1] = {
            type = 'number',
            label = locale('invoice_extra_amount'),
            min = 0,
            max = Config.Invoice.maxTotal,
            icon = 'dollar-sign',
        }

        local result = Ap1le.InputDialog(locale('invoice_dialog_title'), fields, {
            confirmLabel = locale('invoice_send'),
        })

        -- nil = cancelled (or another dialog was already open)
        if not result then return end

        local target = math.tointeger(tonumber(result[1]))
        if not target then
            Ap1le.Notify(locale('error'), 'error')
            return
        end

        local send, total = {}, 0

        for i = 1, #lines do
            local amount = math.floor(tonumber(result[1 + i]) or 0)

            if amount >= 1 then
                send[#send + 1] = { label = lines[i].label, amount = amount }
                total = total + amount
            end
        end

        local extraAmount = math.floor(tonumber(result[#lines + 3]) or 0)

        if extraAmount >= 1 then
            send[#send + 1] = { label = cutLabel(tostring(result[#lines + 2] or '')), amount = extraAmount }
            total = total + extraAmount
        end

        if #send == 0 then
            Ap1le.Notify(locale('invoice_empty'), 'error')
            return
        end

        if #send > Config.Invoice.maxLines or total > Config.Invoice.maxTotal then
            Ap1le.Notify(locale('invoice_too_high', Mechanic.FormatMoney(Config.Invoice.maxTotal)), 'error')
            return
        end

        -- The server notifies both sides on success
        local created, data = lib.callback.await('ap1le_mechanicjob:invoice:create', false, target, send)

        if not created then
            Ap1le.Notify(Mechanic.ErrorText(data), 'error')
        end
    end)

    creating = false

    if not ok then
        print(('^1[ap1le_mechanicjob] invoice dialog failed: %s^0'):format(tostring(err)))
        Ap1le.Notify(locale('error'), 'error')
    end
end

-- ---------------------------------------------------------------------------
-- Customer: answer an invoice
-- ---------------------------------------------------------------------------

---Text of the confirm dialog: total and expiry first (so a long line list never cuts them off), then the lines.
local function confirmContent(invoice)
    local rows = {}

    if type(invoice.lines) == 'table' then
        for i = 1, #invoice.lines do
            local line = invoice.lines[i]

            if type(line) == 'table' then
                rows[#rows + 1] = ('%s: %s'):format(tostring(line.label), Mechanic.FormatMoney(line.amount))
            end
        end
    end

    local seconds = math.floor(tonumber(invoice.expireSeconds) or Config.Invoice.expireSeconds)

    return ('%s\n%s\n\n%s'):format(
        locale('invoice_total', Mechanic.FormatMoney(invoice.total)),
        locale('invoice_expires', seconds),
        table.concat(rows, '\n')
    )
end

---Ask the customer (runs in its own thread). Ends when answered, hidden by the server or expired.
---@param invoice table
local function present(invoice)
    local id = invoice.id
    local expireSeconds = tonumber(invoice.expireSeconds) or Config.Invoice.expireSeconds

    local session = { id = id, asking = false, askedAt = 0, deadline = GetGameTimer() + (expireSeconds + 5) * 1000 }
    shown = session

    local content = confirmContent(invoice)
    local errors = 0

    while shown == session and GetGameTimer() < session.deadline do
        session.asking = true
        session.askedAt = GetGameTimer()

        local accepted = Ap1le.Confirm({
            title = locale('invoice_confirm_title', tostring(invoice.from)),
            content = content,
            confirmLabel = locale('invoice_pay'),
        })

        session.asking = false

        -- Hidden by the server (paid, expired, mechanic left) while the dialog was open
        if shown ~= session then return end

        -- Confirm answers false at once when another dialog is open: that is no decision, ask again later
        if not accepted and GetGameTimer() - session.askedAt < BUSY_MS then
            Wait(RETRY_BUSY_MS)
        else
            local ok, result = lib.callback.await('ap1le_mechanicjob:invoice:respond', false, id, accepted)

            if ok then
                -- The server also sends invoice:hide
                if shown == session then shown = nil end
                return
            end

            if GONE_ERRORS[result] then
                if shown == session then shown = nil end
                Ap1le.Notify(Mechanic.ErrorText(result), 'error')
                return
            end

            -- e.g. no_money: the invoice stays open, so ask again (the customer can still decline)
            errors = errors + 1
            Ap1le.Notify(Mechanic.ErrorText(result), 'error')

            if errors > MAX_ERROR_RETRIES then
                if shown == session then shown = nil end
                return
            end

            Wait(1100) -- the server rate-limits invoice:respond to one call per second
        end
    end

    if shown == session then shown = nil end
end

RegisterNetEvent('ap1le_mechanicjob:invoice:show', function(invoice)
    if type(invoice) ~= 'table' or not math.tointeger(tonumber(invoice.id)) then return end

    invoice.id = math.tointeger(tonumber(invoice.id))

    -- A newer invoice replaces the old one
    if shown then
        local old = shown
        shown = nil
        if old.asking and GetGameTimer() - old.askedAt >= BUSY_MS then Ap1le.CloseDialog() end
    end

    CreateThread(function()
        present(invoice)
    end)
end)

RegisterNetEvent('ap1le_mechanicjob:invoice:hide', function(id)
    local session = shown
    if not session then return end
    if id ~= nil and math.tointeger(tonumber(id)) ~= session.id then return end

    shown = nil

    -- Only close the dialog if it is ours: it must be on screen (not rejected because another one was open)
    if session.asking and GetGameTimer() - session.askedAt >= BUSY_MS then
        Ap1le.CloseDialog()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local session = shown
    shown = nil

    if session and session.asking then
        pcall(Ap1le.CloseDialog)
    end

    creating = false
end)
