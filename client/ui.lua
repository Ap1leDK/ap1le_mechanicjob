-- ap1le_mechanicjob: GTA Online style native UI helpers (help text, feed, shards, timer bars,
-- instructional buttons). Global `UI` (see CONTRACT.md section 4).

UI = {}

---------------------------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------------------------

-- AddTextComponentSubstringPlayerName is limited to ~99 bytes per component, so long strings
-- are split on UTF-8 boundaries (Danish text contains multi-byte characters).
local MAX_COMPONENT_BYTES = 90

local function addLongString(msg)
    msg = tostring(msg or '')
    if #msg <= MAX_COMPONENT_BYTES then
        AddTextComponentSubstringPlayerName(msg)
        return
    end

    local ok = pcall(function()
        local chunk, size = {}, 0
        for _, code in utf8.codes(msg) do
            local char = utf8.char(code)
            if size + #char > MAX_COMPONENT_BYTES then
                AddTextComponentSubstringPlayerName(table.concat(chunk))
                chunk, size = {}, 0
            end
            chunk[#chunk + 1] = char
            size = size + #char
        end
        if size > 0 then AddTextComponentSubstringPlayerName(table.concat(chunk)) end
    end)

    -- Invalid UTF-8: fall back to plain byte chunks
    if not ok then
        for i = 1, #msg, MAX_COMPONENT_BYTES do
            AddTextComponentSubstringPlayerName(msg:sub(i, i + MAX_COMPONENT_BYTES - 1))
        end
    end
end

local function loadScaleform(name)
    local sf = RequestScaleformMovie(name)
    local timeout = GetGameTimer() + 5000
    while not HasScaleformMovieLoaded(sf) do
        if GetGameTimer() > timeout then
            SetScaleformMovieAsNoLongerNeeded(sf)
            return nil
        end
        Wait(0)
    end
    return sf
end

local function sfCall(sf, method, ...)
    BeginScaleformMovieMethod(sf, method)
    for _, v in ipairs({ ... }) do
        local t = type(v)
        if t == 'number' then
            if math.type(v) == 'integer' then
                ScaleformMovieMethodAddParamInt(v)
            else
                ScaleformMovieMethodAddParamFloat(v)
            end
        elseif t == 'boolean' then
            ScaleformMovieMethodAddParamBool(v)
        else
            -- Text goes through a text command so special characters render correctly
            BeginTextCommandScaleformString('STRING')
            addLongString(v)
            EndTextCommandScaleformString()
        end
    end
    EndScaleformMovieMethod()
end

---------------------------------------------------------------------------------------------
-- Help text (top-left). Call every frame while it should be visible.
---------------------------------------------------------------------------------------------

function UI.HelpText(msg)
    if not msg then return end
    BeginTextCommandDisplayHelp('STRING')
    addLongString(msg)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

---------------------------------------------------------------------------------------------
-- Feed notification (above the minimap)
---------------------------------------------------------------------------------------------

local NOTIFY_PREFIX = {
    success = '~g~',
    error = '~r~',
    inform = '~w~',
}

function UI.Notify(msg, notifyType)
    if msg == nil then return end
    local prefix = NOTIFY_PREFIX[notifyType or 'inform'] or NOTIFY_PREFIX.inform
    BeginTextCommandThefeedPost('STRING')
    addLongString(prefix .. tostring(msg))
    EndTextCommandThefeedPostTicker(false, true)
end

---------------------------------------------------------------------------------------------
-- Centered shard (MP_BIG_MESSAGE_FREEMODE). Non-blocking; a new shard replaces the old one.
---------------------------------------------------------------------------------------------

local HUD_COLOUR_BLACK = 2
local shard = { sf = nil, token = 0 }

local function releaseShard()
    if shard.sf then
        SetScaleformMovieAsNoLongerNeeded(shard.sf)
        shard.sf = nil
    end
end

function UI.Shard(title, text, ms)
    shard.token = shard.token + 1
    local token = shard.token
    local duration = tonumber(ms) or 4000

    CreateThread(function()
        local sf = shard.sf or loadScaleform('MP_BIG_MESSAGE_FREEMODE')
        if not sf or token ~= shard.token then
            if sf and sf ~= shard.sf then SetScaleformMovieAsNoLongerNeeded(sf) end
            return
        end
        shard.sf = sf

        sfCall(sf, 'SHOW_SHARD_CENTERED_MP_MESSAGE', tostring(title or ''), tostring(text or ''))
        PlaySoundFrontend(-1, 'MP_WAVE_COMPLETE', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)

        local outAt = GetGameTimer() + duration
        local endAt = outAt + 600
        local animatedOut = false

        while token == shard.token and GetGameTimer() < endAt do
            if not animatedOut and GetGameTimer() >= outAt then
                animatedOut = true
                sfCall(sf, 'SHARD_ANIM_OUT', HUD_COLOUR_BLACK, 0.33)
            end
            DrawScaleformMovieFullscreen(sf, 255, 255, 255, 255, 0)
            Wait(0)
        end

        -- Only release if no newer shard took over the movie
        if token == shard.token then releaseShard() end
    end)
end

---------------------------------------------------------------------------------------------
-- Timer bars (GTA:O bottom-right bars, "timerbars" texture dictionary)
-- UI.TimerBar.Draw(bars) every frame; bars[1] is the bottom bar. Each bar:
--   { label = string, progress = 0..1 }        -> label + progress bar
--   { label = string, text = string }          -> label + right-aligned value (e.g. "0:12")
-- UI.TimerBar.Release() unloads the texture dictionary.
---------------------------------------------------------------------------------------------

local TimerBar = {
    dict = 'timerbars',
    requested = false,
    widthCache = {},
    fill = { 240, 200, 80, 255 },      -- HUD_COLOUR_YELLOW
    back = { 240, 200, 80, 70 },
}
UI.TimerBar = TimerBar

-- Layout in a virtual 720px-high canvas (same metrics as the vanilla timer bars)
local BAR_W, BAR_H, BAR_GAP = 300.0, 37.0, 3.0
local LABEL_RIGHT = 180.0       -- label right edge, from the right border of the bar
local PROGRESS_W, PROGRESS_H = 150.0, 15.0
local PROGRESS_RIGHT = 10.0
local LABEL_PAD = 12.0

local function labelWidthPx(label, canvasW)
    local cached = TimerBar.widthCache[label]
    if cached then return cached end
    BeginTextCommandGetWidth('STRING')
    addLongString(label)
    SetTextFont(0)
    SetTextScale(0.0, 0.3)
    local w = EndTextCommandGetWidth(true) * canvasW
    TimerBar.widthCache[label] = w
    return w
end

local function drawText(msg, x, y, scale, rightEdge)
    SetTextFont(0)
    SetTextScale(0.0, scale)
    SetTextColour(255, 255, 255, 255)
    SetTextJustification(2)
    SetTextWrap(0.0, rightEdge)
    BeginTextCommandDisplayText('STRING')
    addLongString(msg)
    EndTextCommandDisplayText(x, y)
end

function TimerBar.Draw(bars)
    if type(bars) ~= 'table' or #bars == 0 then return end

    if not TimerBar.requested then
        TimerBar.requested = true
        RequestStreamedTextureDict(TimerBar.dict, true)
    end
    local spriteReady = HasStreamedTextureDictLoaded(TimerBar.dict)

    -- Vanilla HUD hides these while timer bars are on screen
    HideHudComponentThisFrame(6)  -- vehicle name
    HideHudComponentThisFrame(7)  -- area name
    HideHudComponentThisFrame(8)  -- vehicle class
    HideHudComponentThisFrame(9)  -- street name

    local canvasH = 720.0
    local canvasW = canvasH * GetAspectRatio(false)
    local margin = (1.0 - GetSafeZoneSize()) * 0.5
    local right = canvasW * (1.0 - margin)
    local bottom = canvasH * (1.0 - margin)

    -- Stack above the instructional buttons when they are visible
    if UI.ButtonsVisible() then bottom = bottom - 40.0 end

    for i, bar in ipairs(bars) do
        local label = tostring(bar.label or '')
        local top = bottom - (BAR_H + BAR_GAP) * i

        -- Widen the bar when a long (translated) label would overflow on the left
        local width = BAR_W
        local labelW = labelWidthPx(label, canvasW)
        local labelSpace = BAR_W - LABEL_RIGHT - LABEL_PAD
        if labelW > labelSpace then width = BAR_W + (labelW - labelSpace) end

        local cx = (right - width * 0.5) / canvasW
        local cy = (top + BAR_H * 0.5) / canvasH
        if spriteReady then
            DrawSprite(TimerBar.dict, 'all_black_bg', cx, cy, width / canvasW, BAR_H / canvasH, 0.0, 255, 255, 255, 180)
        else
            DrawRect(cx, cy, width / canvasW, BAR_H / canvasH, 0, 0, 0, 140)
        end

        drawText(label, 0.0, (top + 7.0) / canvasH, 0.3, (right - LABEL_RIGHT) / canvasW)

        if bar.progress ~= nil then
            local p = math.max(0.0, math.min(1.0, tonumber(bar.progress) or 0.0))
            local px = right - PROGRESS_RIGHT - PROGRESS_W
            local py = top + (BAR_H - PROGRESS_H) * 0.5
            local b, f = TimerBar.back, TimerBar.fill
            DrawRect((px + PROGRESS_W * 0.5) / canvasW, (py + PROGRESS_H * 0.5) / canvasH,
                PROGRESS_W / canvasW, PROGRESS_H / canvasH, b[1], b[2], b[3], b[4])
            if p > 0.0 then
                DrawRect((px + PROGRESS_W * p * 0.5) / canvasW, (py + PROGRESS_H * 0.5) / canvasH,
                    PROGRESS_W * p / canvasW, PROGRESS_H / canvasH, f[1], f[2], f[3], f[4])
            end
        elseif bar.text ~= nil then
            drawText(tostring(bar.text), 0.0, (top + 1.0) / canvasH, 0.5, (right - PROGRESS_RIGHT) / canvasW)
        end
    end
end

function TimerBar.Release()
    if TimerBar.requested then
        SetStreamedTextureDictAsNoLongerNeeded(TimerBar.dict)
        TimerBar.requested = false
    end
    TimerBar.widthCache = {}
end

---------------------------------------------------------------------------------------------
-- Instructional buttons (bottom-right). list = { { control = 202, label = 'Cancel' }, ... }
-- Draws itself every frame until UI.ClearButtons(). Rebuilds when switching keyboard/pad.
---------------------------------------------------------------------------------------------

local buttons = { sf = nil, list = nil, token = 0 }

local function buildButtons(sf, list)
    sfCall(sf, 'CLEAR_ALL')
    sfCall(sf, 'SET_CLEAR_SPACE', 200)
    for i, b in ipairs(list) do
        BeginScaleformMovieMethod(sf, 'SET_DATA_SLOT')
        ScaleformMovieMethodAddParamInt(i - 1)
        ScaleformMovieMethodAddParamPlayerNameString(GetControlInstructionalButton(2, b.control, true))
        BeginTextCommandScaleformString('STRING')
        addLongString(b.label or '')
        EndTextCommandScaleformString()
        EndScaleformMovieMethod()
    end
    sfCall(sf, 'SET_BACKGROUND_COLOUR', 0, 0, 0, 80)
    sfCall(sf, 'DRAW_INSTRUCTIONAL_BUTTONS')
end

function UI.ButtonsVisible()
    return buttons.sf ~= nil
end

function UI.ClearButtons()
    buttons.token = buttons.token + 1
    buttons.list = nil
    if buttons.sf then
        SetScaleformMovieAsNoLongerNeeded(buttons.sf)
        buttons.sf = nil
    end
end

function UI.Buttons(list)
    if type(list) ~= 'table' or #list == 0 then
        UI.ClearButtons()
        return
    end

    buttons.token = buttons.token + 1
    local token = buttons.token
    buttons.list = list

    local sf = buttons.sf or loadScaleform('INSTRUCTIONAL_BUTTONS')
    if not sf then return end
    if token ~= buttons.token then
        -- Cleared or replaced while loading
        if sf ~= buttons.sf then SetScaleformMovieAsNoLongerNeeded(sf) end
        return
    end

    local firstOwner = buttons.sf == nil
    buttons.sf = sf
    buildButtons(sf, list)

    -- One draw thread per scaleform handle; it stops when the buttons are cleared
    if firstOwner then
        CreateThread(function()
            local usingKeyboard = IsUsingKeyboard(2)
            local nextCheck = 0
            while buttons.sf == sf do
                local now = GetGameTimer()
                if now >= nextCheck then
                    nextCheck = now + 500
                    local kb = IsUsingKeyboard(2)
                    if kb ~= usingKeyboard and buttons.list then
                        usingKeyboard = kb
                        buildButtons(sf, buttons.list)
                    end
                end
                DrawScaleformMovieFullscreen(sf, 255, 255, 255, 255, 0)
                Wait(0)
            end
        end)
    end
end

---------------------------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    UI.ClearButtons()
    shard.token = shard.token + 1
    releaseShard()
    TimerBar.Release()
end)
