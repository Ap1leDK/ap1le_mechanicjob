-- ap1le_mechanicjob: thin compatibility layer over ap1le_core (global `UI`, CONTRACT.md section 4).
-- v1 drew GTA:O timer bars, instructional buttons, help text and shards here; v2 uses ap1le_core for
-- every notification and progress bar, so only small wrappers are left. New code should call
-- Ap1le.* directly; these exist so older call sites keep working and so a missing/restarting
-- ap1le_core never throws inside a sequence.

UI = {}

-- v1 notify types -> ap1le_core types (success | error | warning | info)
local NOTIFY_TYPES = {
    success = 'success',
    error = 'error',
    warning = 'warning',
    warn = 'warning',
    info = 'info',
    inform = 'info',
}

local warned = false

local function coreMissing(err)
    if warned then return end
    warned = true
    print(('^3[ap1le_mechanicjob] ap1le_core is not available (%s). Is it started before this resource?^0'):format(tostring(err)))
end

local function core()
    return type(Ap1le) == 'table' and Ap1le or nil
end

-- UI.Notify(msg, type?, duration?) -> Ap1le.Notify. msg may also be an ap1le_core notify table.
function UI.Notify(msg, notifyType, duration)
    if msg == nil then return end
    local ap = core()
    if not ap then return coreMissing('Ap1le is nil') end

    local nType = NOTIFY_TYPES[notifyType or 'info'] or 'info'
    local ok, err
    if type(msg) == 'table' then
        local data = {}
        for k, v in pairs(msg) do data[k] = v end
        data.type = NOTIFY_TYPES[data.type or nType] or nType
        ok, err = pcall(ap.Notify, data)
    else
        ok, err = pcall(ap.Notify, tostring(msg), nType, tonumber(duration))
    end
    if not ok then coreMissing(err) end
end

-- UI.Progress(data) -> Ap1le.Progress(data). Blocks (call inside a thread). Returns true when the bar
-- completed, false when it was cancelled, interrupted or another bar was already running.
-- v3 (A7): the bar never shows an icon. `icon` is stripped here, so no caller can bring the icons
-- back by accident. If ap1le_core is unavailable the duration is simply waited out (the sequence
-- still works, just without a bar and without the cancel key).
function UI.Progress(data)
    local bar = {}
    if type(data) == 'table' then
        for k, v in pairs(data) do bar[k] = v end
    end
    bar.icon = nil

    local ap = core()
    if ap then
        local ok, result = pcall(ap.Progress, bar)
        if ok then return result == true end
        coreMissing(result)
    else
        coreMissing('Ap1le is nil')
    end
    Wait(math.max(0, math.floor(tonumber(bar.duration) or 0)))
    return true
end

function UI.CancelProgress()
    local ap = core()
    if ap then pcall(ap.CancelProgress) end
end

function UI.IsProgressActive()
    local ap = core()
    if not ap then return false end
    local ok, result = pcall(ap.IsProgressActive)
    return ok and result == true
end

-- Help text box ("[E] Do something"). key is a short key label ('E', 'W/S') or nil.
-- Calling it again with the same text and key is free (ap1le_core does not resend it).
function UI.ShowTextUI(text, key)
    local ap = core()
    if not ap or text == nil or text == '' then return end
    local ok, err = pcall(ap.ShowTextUI, tostring(text), key)
    if not ok then coreMissing(err) end
end

function UI.HideTextUI()
    local ap = core()
    if ap then pcall(ap.HideTextUI) end
end

-- Blocks GTA's pause menu for a moment after an NUI released focus. A player who closed the tuning
-- screen or the laptop with Escape may still hold the key when the game gets the keyboard back, which
-- would open the pause menu (same guard as ap1le_core's ResetUiFocus). Overlapping calls extend the
-- running guard instead of starting another thread.
local PAUSE_BLOCK_MS = 500
local blockPauseUntil = 0

function UI.BlockPauseMenu()
    local running = GetGameTimer() < blockPauseUntil
    blockPauseUntil = GetGameTimer() + PAUSE_BLOCK_MS
    if running then return end

    CreateThread(function()
        while GetGameTimer() < blockPauseUntil do
            DisableControlAction(0, 199, true) -- INPUT_FRONTEND_PAUSE (P)
            DisableControlAction(0, 200, true) -- INPUT_FRONTEND_PAUSE_ALTERNATE (Escape)
            Wait(0)
        end
    end)
end
