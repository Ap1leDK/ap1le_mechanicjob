-- ap1le_mechanicjob: physical, step-by-step mechanic choreography with native GTA V animations,
-- scenarios and props. Global `Anim` (see CONTRACT.md section 4).
--
-- Every public sequence blocks (call it inside a thread) and returns true when completed,
-- false when cancelled. Each step shows an ap1le_core progress bar "<step> (i/n)" while the
-- step's choreography runs; the bar has no anim/prop (this file drives the ped) and ends together
-- with its step. Cancel = ap1le_core's cancel key (X) or anything that makes Ap1le.Progress return
-- false (death, ragdoll, falling ...), plus our own checks (too far, vehicle/crate gone), which
-- call Ap1le.CancelProgress.
-- All exit paths run the same cleanup: props deleted, tasks cleared, doors closed, vehicle
-- lowered, unfrozen and put back on the ground, ropes/particles removed.
--
-- All dicts/clips, scenarios, props and particle effects below were checked against
-- github.com/DurtyFree/gta-v-data-dumps (animDictsCompact.json, scenariosCompact.json,
-- ObjectList.ini, particleEffectsCompact.json).

Anim = {}

local active = nil

---------------------------------------------------------------------------------------------
-- Verified assets
---------------------------------------------------------------------------------------------

-- flag: 1 loop, 2 hold last frame, 16 upper body, 32 secondary, 512 no collision
local A = {
    bayLean    = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
    standWork  = { dict = 'mini@repair', clip = 'fixing_a_player', flag = 1 },
    lidOpen    = { dict = 'anim@scripted@hs4f@ig14_open_car_trunk@male@', clip = 'open_trunk_rushed', flag = 0 },
    lidClose   = { dict = 'anim@scripted@hs4f@ig14_open_car_trunk@male@', clip = 'close_trunk', flag = 0 },
    carry      = { dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49 },
    under      = { dict = 'amb@world_human_vehicle_mechanic@male@base', clip = 'base', flag = 513 },
    underWork  = { dict = 'amb@world_human_vehicle_mechanic@male@idle_a', clip = 'idle_a', flag = 513 },
    underExit  = { dict = 'amb@world_human_vehicle_mechanic@male@exit', clip = 'exit', flag = 512 },
    crouchWork = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 1 },
    kneelDown  = { dict = 'amb@medic@standing@kneel@enter', clip = 'enter', flag = 2 },
    kneel      = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
    groundWork = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a', flag = 1 },
    spray      = { dict = 'switch@franklin@lamar_tagging_wall', clip = 'lamar_tagging_wall_loop_lamar', flag = 49 },
    lever      = { dict = 'anim@scripted@heist@ig2_hand_lever@male@', clip = 'idle_lever', flag = 49 },
    -- crate looting with a crowbar (Tuners train robbery; the dict also has 'loot_crowbar'/'loot_crate'
    -- companion clips, which confirms it is the crowbar pry). Played on the ped only.
    pry        = { dict = 'anim@scripted@player@mission@trn_ig1_loot@male@', clip = 'loot', flag = 1 },
    -- standing at a keyboard (FIB heist computer). Same clips as the "type4"/"type" emotes of rpemotes.
    typeEnter  = { dict = 'mp_fbi_heist', clip = 'intro', flag = 0 },
    typeLoop   = { dict = 'mp_fbi_heist', clip = 'loop', flag = 1 },
    typeExit   = { dict = 'mp_fbi_heist', clip = 'outro', flag = 0 },
    typeAlt    = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle', flag = 1 },
}

local SCENARIO = {
    weld = 'WORLD_HUMAN_WELDING',
    hammer = 'WORLD_HUMAN_HAMMERING',
    polish = 'WORLD_HUMAN_MAID_CLEAN',
}

-- Props spawned by the scenarios above; swept from the ped on cleanup if still attached
local SCENARIO_PROPS = { 'prop_weld_torch', 'prop_welding_mask_01', 'prop_tool_hammer', 'prop_sponge_01', 'prop_rag_01' }

local P = {
    hoist   = 'prop_engine_hoist',
    engine  = 'prop_car_engine_01',
    pallet  = 'prop_pallet_02a',
    toolbox = 'prop_tool_box_04',
    impact  = 'imp_prop_impact_driver_01a',
    jack    = 'prop_carjack',
    wheel   = 'prop_wheel_01',
    caliper = 'imp_prop_impexp_brake_caliper_01a',
    strut   = 'imp_prop_strut_compressor_01a',
    gearbox = 'imp_prop_impexp_gearbox_01',
    panel   = 'imp_prop_impexp_car_panel_01a',
    turbo   = 'lr_prop_carburettor_01',  -- turbo-sized intake part (no turbo prop exists)
    spray   = 'prop_cs_spray_can',
    crowbar = 'w_me_crowbar',
    box     = 'hei_prop_heist_box',
}

local FX = {
    sprayAsset = 'scr_playerlamgraff',
    sprayName = 'scr_lamgraff_paint_spray',
}

local BONE_PH_R_HAND = 28422
local BONE_SKEL_L_HAND = 60309
local BONE_ROOT = 0

-- Yaw correction for the hoist model so its boom points at the vehicle. The model's forward
-- axis is not documented; adjust here if the boom faces the wrong way in your build.
local HOIST_YAW = 0.0

-- Disabled for the whole sequence (also in the frames between two progress bars). The bars
-- disable move/car/combat themselves; 23 (INPUT_ENTER) would pull the ped out of its task.
-- The cancel key belongs to ap1le_core (X by default), so no cancel control is captured here.
local DISABLED_CONTROLS = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 44, 140, 141, 142, 143, 257, 263, 264 }

-- Font Awesome (6.7 free, bundled with ap1le_core) icon per step label
local STEP_ICONS = {
    step_open_hood = 'car',
    step_close_hood = 'car-side',
    step_hoist = 'dolly',
    step_unbolt = 'screwdriver-wrench',
    step_bolt = 'wrench',
    step_lift_out = 'up-long',
    step_lift_in = 'down-long',
    step_jack_up = 'arrow-up',
    step_jack_down = 'arrow-down',
    step_wheel_off = 'circle-dot',
    step_wheel_on = 'circle-dot',
    step_under_car = 'screwdriver',
    step_weld = 'fire-flame-curved',
    step_paint = 'spray-can',
    step_fit_part = 'gears',
    step_winch = 'truck-pickup',
    step_crate_open = 'box-open',
    step_crate_unload = 'boxes-stacked',
}

local WHEELS = {
    { bone = 'wheel_lf', tyre = 0 },
    { bone = 'wheel_rf', tyre = 1 },
    { bone = 'wheel_lr', tyre = 4 },
    { bone = 'wheel_rr', tyre = 5 },
}

---------------------------------------------------------------------------------------------
-- Small math helpers
---------------------------------------------------------------------------------------------

local function smooth(t) return t * t * (3.0 - 2.0 * t) end
local function lerp(a, b, t) return a + (b - a) * t end
local function sign(x) return x < 0.0 and -1.0 or 1.0 end

local function headingTo(from, to)
    return GetHeadingFromVector_2d(to.x - from.x, to.y - from.y)
end

-- Liang-Barsky: does the 2D segment a-b cross the axis aligned box?
local function segmentHitsBox(ax, ay, bx, by, minX, minY, maxX, maxY)
    local dx, dy = bx - ax, by - ay
    local t0, t1 = 0.0, 1.0
    local p = { -dx, dx, -dy, dy }
    local q = { ax - minX, maxX - ax, ay - minY, maxY - ay }
    for i = 1, 4 do
        if p[i] == 0.0 then
            if q[i] < 0.0 then return false end
        else
            local t = q[i] / p[i]
            if p[i] < 0.0 then
                if t > t1 then return false end
                if t > t0 then t0 = t end
            else
                if t < t0 then return false end
                if t < t1 then t1 = t end
            end
        end
    end
    return true
end

---------------------------------------------------------------------------------------------
-- Context, assets and entities
---------------------------------------------------------------------------------------------

local function newContext(vehicle, totalMs, extra)
    local ped = cache.ped or PlayerPedId()
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local coords = GetEntityCoords(vehicle)

    local c = {
        ped = ped,
        vehicle = vehicle,
        extra = extra,
        min = min,
        max = max,
        halfW = math.max(math.abs(min.x), math.abs(max.x)),
        groundZ = coords.z - GetEntityHeightAboveGround(vehicle),
        heading = GetEntityHeading(vehicle),
        totalMs = totalMs,
        props = {},
        dicts = {},
        models = {},
        ptfxAssets = {},
        ptfx = {},
        ropes = {},
        doors = {},
        frozen = {},
        lift = nil,
        anim = nil,
        scenario = false,
        lying = false,
        cancelled = false,
        cleaned = false,
        stepLabel = '',
        stepIndex = 0,
        stepCount = 0,
        stepStart = GetGameTimer(),
        stepMs = 1,
        baseMs = 0,
    }

    -- Side of the vehicle the mechanic works on: the side the ped is standing on
    local pedPos = GetEntityCoords(ped)
    local pedLocal = GetOffsetFromEntityGivenWorldCoords(vehicle, pedPos.x, pedPos.y, pedPos.z)
    c.side = pedLocal.x >= 0.0 and 1.0 or -1.0
    c.endSign = pedLocal.y >= 0.0 and 1.0 or -1.0

    return c
end

-- Local offset -> world
local function L(c, x, y, z)
    return GetOffsetFromEntityInWorldCoords(c.vehicle, x + 0.0, y + 0.0, (z or 0.0) + 0.0)
end

-- Local offset -> world on the workshop floor
local function G(c, x, y)
    local p = GetOffsetFromEntityInWorldCoords(c.vehicle, x + 0.0, y + 0.0, 0.0)
    return vec3(p.x, p.y, c.groundZ)
end

local function sideX(c, side, pad)
    return side > 0 and (c.max.x + pad) or (c.min.x - pad)
end

local function endY(c, dir, pad)
    return dir > 0 and (c.max.y + pad) or (c.min.y - pad)
end

local function boneLocal(c, names)
    for _, name in ipairs(names) do
        local idx = GetEntityBoneIndexByName(c.vehicle, name)
        if idx ~= -1 then
            local w = GetWorldPositionOfEntityBone(c.vehicle, idx)
            return GetOffsetFromEntityGivenWorldCoords(c.vehicle, w.x, w.y, w.z), idx
        end
    end
    return nil
end

local function loadDict(c, dict)
    if c.dicts[dict] then return true end
    local ok = pcall(lib.requestAnimDict, dict, 5000)
    if not ok then return false end
    if c.cleaned then
        -- the sequence was stopped while loading: release right away
        RemoveAnimDict(dict)
        return false
    end
    c.dicts[dict] = true
    return not c.cancelled
end

local function loadModel(c, name)
    local hash = joaat(name)
    if c.models[hash] then return hash end
    local ok = pcall(lib.requestModel, hash, 5000)
    if not ok then return nil end
    if c.cleaned then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end
    c.models[hash] = true
    if c.cancelled then return nil end
    return hash
end

local function modelDims(c, name)
    loadModel(c, name)
    local min, max = GetModelDimensions(joaat(name))
    return min, max
end

local function spawnProp(c, name, pos, rot)
    if c.cancelled then return nil end
    local hash = loadModel(c, name)
    if not hash or c.cancelled then return nil end

    -- Networked so other players see the work; fall back to local if entity lockdown refuses it
    local obj = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, true, false, false)
    if not obj or obj == 0 then
        obj = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
    end
    if not obj or obj == 0 then return nil end

    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)
    SetEntityRotation(obj, rot and rot.x or 0.0, rot and rot.y or 0.0, rot and rot.z or c.heading, 2, true)
    c.props[#c.props + 1] = obj
    return obj
end

-- Position of a prop standing on the floor (bottom of its bounding box on the ground)
local function onFloor(c, name, pos)
    local min = modelDims(c, name)
    return vec3(pos.x, pos.y, c.groundZ - min.z)
end

local function spawnGround(c, name, pos, heading)
    return spawnProp(c, name, onFloor(c, name, pos), vec3(0.0, 0.0, heading or c.heading))
end

local function moveProp(obj, pos, rot)
    if not obj or not DoesEntityExist(obj) then return end
    SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z, false, false, false)
    if rot then SetEntityRotation(obj, rot.x, rot.y, rot.z, 2, true) end
end

local function deleteProp(c, obj)
    if not obj then return end
    for i = #c.props, 1, -1 do
        if c.props[i] == obj then table.remove(c.props, i) end
    end
    if DoesEntityExist(obj) then
        if IsEntityAttached(obj) then DetachEntity(obj, false, false) end
        SetEntityAsMissionEntity(obj, true, true)
        DeleteEntity(obj)
    end
end

local function attachTo(c, obj, boneId, off, rot)
    if not obj or c.cancelled then return end
    AttachEntityToEntity(obj, c.ped, GetPedBoneIndex(c.ped, boneId), off.x, off.y, off.z, rot.x, rot.y, rot.z,
        true, true, false, true, 1, true)
end

-- Hand tool in the right hand
local function holdTool(c, name)
    local obj = spawnProp(c, name, GetEntityCoords(c.ped), nil)
    attachTo(c, obj, BONE_PH_R_HAND, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0))
    return obj
end

-- Carried part in front of the chest (with the box carry upper-body anim)
local CARRY_OFFSET = vec3(0.0, 0.42, 0.08)

local function carry(c, obj)
    attachTo(c, obj, BONE_ROOT, CARRY_OFFSET, vec3(0.0, 0.0, 90.0))
end

local function release(obj)
    if obj and DoesEntityExist(obj) and IsEntityAttached(obj) then DetachEntity(obj, false, false) end
end

local function startSprayFx(c, can)
    if not can or c.cancelled then return end
    local asset = FX.sprayAsset
    if not c.ptfxAssets[asset] then
        if not pcall(lib.requestNamedPtfxAsset, asset, 5000) then return end
        c.ptfxAssets[asset] = true
        if c.cancelled then return end
    end
    UseParticleFxAsset(asset)
    local fx = StartParticleFxLoopedOnEntity(FX.sprayName, can, 0.0, 0.0, 0.12, 0.0, 0.0, 0.0, 0.6, false, false, false)
    if fx and fx ~= 0 then c.ptfx[#c.ptfx + 1] = fx end
end

local function stopFx(c)
    for _, fx in ipairs(c.ptfx) do StopParticleFxLooped(fx, false) end
    c.ptfx = {}
end

---------------------------------------------------------------------------------------------
-- Waiting, ped tasks and movement
---------------------------------------------------------------------------------------------

local function sleep(c, ms)
    local untilAt = GetGameTimer() + math.max(0, math.floor(ms))
    while GetGameTimer() < untilAt do
        if c.cancelled then return false end
        Wait(0)
    end
    return not c.cancelled
end

local function waitUntil(c, at)
    return sleep(c, at - GetGameTimer())
end

local function tween(c, ms, fn)
    ms = math.max(1, math.floor(ms))
    local start = GetGameTimer()
    while true do
        if c.cancelled then return false end
        local t = math.min(1.0, (GetGameTimer() - start) / ms)
        fn(smooth(t), t)
        if t >= 1.0 then return true end
        Wait(0)
    end
end

-- Remaining time of the current step, at least `minMs`
local function remaining(endAt, minMs)
    return math.max(minMs or 0, endAt - GetGameTimer())
end

local function playAnim(c, a, duration)
    if c.cancelled then return false end
    if not loadDict(c, a.dict) then return not c.cancelled end
    TaskPlayAnim(c.ped, a.dict, a.clip, 3.0, 3.0, duration or -1, a.flag or 1, 0.0, false, false, false)
    c.anim = a
    c.scenario = false
    c.lying = a == A.under or a == A.underWork
    return true
end

local function sweepScenarioProps(c)
    local hashes = {}
    for _, name in ipairs(SCENARIO_PROPS) do hashes[joaat(name)] = true end
    for _, obj in ipairs(GetGamePool('CObject')) do
        if hashes[GetEntityModel(obj)] and IsEntityAttachedToEntity(obj, c.ped) then
            SetEntityAsMissionEntity(obj, true, true)
            DeleteEntity(obj)
        end
    end
end

local function stopTask(c)
    local ped = c.ped
    if c.scenario then
        ClearPedTasks(ped)
        local deadline = GetGameTimer() + 2000
        while IsPedUsingAnyScenario(ped) and GetGameTimer() < deadline do
            if c.cancelled then break end
            Wait(0)
        end
        sweepScenarioProps(c)
    elseif c.lying then
        -- roll out from under the car with the scenario's own exit clip
        local exit = A.underExit
        if loadDict(c, exit.dict) then
            TaskPlayAnim(ped, exit.dict, exit.clip, 4.0, 2.0, -1, exit.flag, 0.0, false, false, false)
            local duration = GetAnimDuration(exit.dict, exit.clip)
            sleep(c, math.min(3000, math.max(800, (duration or 1.5) * 1000 - 150)))
        end
        ClearPedTasks(ped)
    elseif c.anim then
        StopAnimTask(ped, c.anim.dict, c.anim.clip, 2.0)
    end
    c.anim = nil
    c.scenario = false
    c.lying = false
end

local function scenario(c, name)
    if c.cancelled then return false end
    TaskStartScenarioInPlace(c.ped, name, 0, true)
    c.scenario = true
    c.anim = nil
    c.lying = false
    return true
end

local function face(c, point)
    if c.cancelled then return false end
    local pos = GetEntityCoords(c.ped)
    local h = headingTo(pos, point)
    TaskAchieveHeading(c.ped, h, 1000)
    local deadline = GetGameTimer() + 1000
    while GetGameTimer() < deadline do
        if c.cancelled then return false end
        local diff = math.abs(((GetEntityHeading(c.ped) - h + 180.0) % 360.0) - 180.0)
        if diff < 8.0 then break end
        Wait(0)
    end
    SetEntityHeading(c.ped, h)
    return not c.cancelled
end

-- Path around the vehicle footprint so the ped never walks through the car
local function planPath(c, target)
    local veh = c.vehicle
    local pos = GetEntityCoords(c.ped)
    local a = GetOffsetFromEntityGivenWorldCoords(veh, pos.x, pos.y, pos.z)
    local b = GetOffsetFromEntityGivenWorldCoords(veh, target.x, target.y, target.z)
    local x0, y0, x1, y1 = c.min.x, c.min.y, c.max.x, c.max.y

    if not segmentHitsBox(a.x, a.y, b.x, b.y, x0, y0, x1, y1) then return { target } end

    local e = 0.9
    local corners = {
        vec2(x0 - e, y0 - e), vec2(x1 + e, y0 - e), vec2(x1 + e, y1 + e), vec2(x0 - e, y1 + e),
    }
    local function clear(p, q) return not segmentHitsBox(p.x, p.y, q.x, q.y, x0, y0, x1, y1) end
    local function toWorld(p) return G(c, p.x, p.y) end

    local best, bestCost
    for _, k in ipairs(corners) do
        if clear(a.xy, k) and clear(k, b.xy) then
            local cost = #(a.xy - k) + #(k - b.xy)
            if not bestCost or cost < bestCost then best, bestCost = { toWorld(k), target }, cost end
        end
    end
    if best then return best end

    for i = 1, 4 do
        for _, j in ipairs({ i % 4 + 1, (i + 2) % 4 + 1 }) do
            local k1, k2 = corners[i], corners[j]
            if clear(a.xy, k1) and clear(k1, k2) and clear(k2, b.xy) then
                local cost = #(a.xy - k1) + #(k1 - k2) + #(k2 - b.xy)
                if not bestCost or cost < bestCost then
                    best, bestCost = { toWorld(k1), toWorld(k2), target }, cost
                end
            end
        end
    end
    return best or { target }
end

-- Walk to `target` (TaskGoStraightToCoord) and face `faceTo`.
-- carrying = true keeps the box-carry upper-body anim running while walking.
local function goTo(c, target, faceTo, carrying)
    if c.cancelled then return false end
    stopTask(c)
    if c.cancelled then return false end

    local ped = c.ped
    local path = planPath(c, target)
    for i, p in ipairs(path) do
        local last = i == #path
        local heading = (last and faceTo) and headingTo(p, faceTo) or GetEntityHeading(ped)
        TaskGoStraightToCoord(ped, p.x, p.y, p.z, 1.0, -1, heading, last and 0.3 or 0.0)
        if carrying then playAnim(c, A.carry) end

        local started = GetGameTimer()
        local deadline = started + 8000
        local stillSince = nil
        local radius = last and 0.3 or 0.7
        while true do
            if c.cancelled then return false end
            local pos = GetEntityCoords(ped)
            if #(pos.xy - p.xy) <= radius then break end
            local now = GetGameTimer()
            if now > deadline then break end
            if now - started > 800 and GetEntitySpeed(ped) < 0.05 then
                stillSince = stillSince or now
                if now - stillSince > 600 then break end
            else
                stillSince = nil
            end
            Wait(0)
        end
    end

    if faceTo then
        if not face(c, faceTo) then return false end
        if carrying then playAnim(c, A.carry) end
    end
    return not c.cancelled
end

-- A point `dist` short of `point`, on the line from the ped
local function approach(c, point, dist)
    local pos = GetEntityCoords(c.ped)
    local d = vec3(pos.x - point.x, pos.y - point.y, 0.0)
    local len = #d
    if len < 0.01 then return vec3(point.x, point.y, c.groundZ) end
    local p = point + d / len * (dist or 0.7)
    return vec3(p.x, p.y, c.groundZ)
end

-- Kneel at the ped's position, bring `obj` up to the chest and attach it
local function pickUp(c, obj)
    if not obj then return not c.cancelled end
    playAnim(c, A.kneelDown)
    if not sleep(c, 800) then return false end
    local from = GetEntityCoords(obj)
    if not tween(c, 350, function(t)
        moveProp(obj, lerp(from, GetOffsetFromEntityInWorldCoords(c.ped, CARRY_OFFSET.x, CARRY_OFFSET.y, CARRY_OFFSET.z), t))
    end) then return false end
    carry(c, obj)
    playAnim(c, A.carry)
    return not c.cancelled
end

-- Kneel and set the carried `obj` down at `pos` (rot optional)
local function putDown(c, obj, pos, rot)
    playAnim(c, A.kneelDown)
    if not sleep(c, 700) then return false end
    release(obj)
    if obj then
        local from = GetEntityCoords(obj)
        if not tween(c, 300, function(t) moveProp(obj, lerp(from, pos, t), rot) end) then return false end
    end
    return sleep(c, 300)
end

---------------------------------------------------------------------------------------------
-- Vehicle state: control, freeze, doors, jack lift
---------------------------------------------------------------------------------------------

local function requestControl(veh)
    if Mechanic and Mechanic.RequestControl then
        local ok, res = pcall(Mechanic.RequestControl, veh)
        if ok then return res end
    end
    if NetworkHasControlOfEntity(veh) then return true end
    local deadline = GetGameTimer() + 1500
    NetworkRequestControlOfEntity(veh)
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < deadline do
        Wait(0)
        NetworkRequestControlOfEntity(veh)
    end
    return NetworkHasControlOfEntity(veh)
end

local function freeze(c, veh)
    if not veh or not DoesEntityExist(veh) then return end
    for _, f in ipairs(c.frozen) do
        if f.entity == veh then return end
    end
    requestControl(veh)
    local was = IsEntityPositionFrozen and IsEntityPositionFrozen(veh) or false
    c.frozen[#c.frozen + 1] = { entity = veh, was = was }
    FreezeEntityPosition(veh, true)
end

local function openDoor(c, door, veh)
    veh = veh or c.vehicle
    if c.cancelled or not DoesEntityExist(veh) or not GetIsDoorValid(veh, door) then return end
    if GetVehicleDoorAngleRatio(veh, door) < 0.1 then
        c.doors[#c.doors + 1] = { entity = veh, door = door }
    end
    SetVehicleDoorOpen(veh, door, false, false)
end

local function closeDoor(c, door, veh)
    veh = veh or c.vehicle
    if not DoesEntityExist(veh) or not GetIsDoorValid(veh, door) then return end
    SetVehicleDoorShut(veh, door, false)
    for i = #c.doors, 1, -1 do
        if c.doors[i].entity == veh and c.doors[i].door == door then table.remove(c.doors, i) end
    end
end

-- Prepare a jack lift. corner = local wheel position for a corner lift, nil = lift the whole car.
local function prepareLift(c, corner)
    local veh = c.vehicle
    local origin = GetEntityCoords(veh)
    local rot = GetEntityRotation(veh, 2)
    local lift = { origin = origin, rot = rot, dz = 0.16, pitch = 0.0, roll = 0.0, t = 0.0 }

    if corner then
        lift.dz = 0.08
        local function zAt(x, y) return GetOffsetFromEntityInWorldCoords(veh, x, y, 0.0).z end

        -- Raise the jacked side ~6 cm and the jacked end ~3 cm on top of the base lift.
        -- Rotation sign conventions are calibrated by measuring, so the right corner goes up.
        if math.abs(corner.x) > 0.2 then
            local roll = math.deg(math.atan(0.06, math.abs(corner.x)))
            local before = zAt(corner.x, 0.0)
            SetEntityRotation(veh, rot.x, rot.y + roll, rot.z, 2, false)
            if zAt(corner.x, 0.0) < before then roll = -roll end
            lift.roll = roll
        end
        if math.abs(corner.y) > 0.2 then
            SetEntityRotation(veh, rot.x, rot.y, rot.z, 2, false)
            local pitch = math.deg(math.atan(0.03, math.abs(corner.y)))
            local before = zAt(0.0, corner.y)
            SetEntityRotation(veh, rot.x + pitch, rot.y, rot.z, 2, false)
            if zAt(0.0, corner.y) < before then pitch = -pitch end
            lift.pitch = pitch
        end
        SetEntityRotation(veh, rot.x, rot.y, rot.z, 2, false)
    end

    c.lift = lift
    return lift
end

local function setLift(c, t)
    local lift = c.lift
    local veh = c.vehicle
    if not lift or not DoesEntityExist(veh) then return end
    lift.t = t
    SetEntityCoordsNoOffset(veh, lift.origin.x, lift.origin.y, lift.origin.z + lift.dz * t, false, false, false)
    SetEntityRotation(veh, lift.rot.x + lift.pitch * t, lift.rot.y + lift.roll * t, lift.rot.z, 2, false)
end

---------------------------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------------------------

local cancelBar -- defined with the progress bar helpers below

local function cleanup(c)
    if c.cleaned then return end
    c.cleaned = true
    c.cancelled = true
    if active == c then active = nil end
    pcall(cancelBar, c)

    local ped = c.ped

    pcall(stopFx, c)
    for asset in pairs(c.ptfxAssets) do RemoveNamedPtfxAsset(asset) end

    pcall(function()
        for _, rope in ipairs(c.ropes) do
            if DoesRopeExist(rope) then DeleteRope(rope) end
        end
        if #c.ropes > 0 and GetAllRopes and #GetAllRopes() == 0 then RopeUnloadTextures() end
        c.ropes = {}
    end)

    pcall(function()
        if DoesEntityExist(ped) then
            if c.scenario or c.lying then
                ClearPedTasksImmediately(ped)
            else
                ClearPedTasks(ped)
            end
            sweepScenarioProps(c)
        end
    end)

    for i = #c.props, 1, -1 do
        pcall(deleteProp, c, c.props[i])
    end
    c.props = {}

    pcall(function()
        for _, d in ipairs(c.doors) do
            if DoesEntityExist(d.entity) then SetVehicleDoorShut(d.entity, d.door, false) end
        end
        c.doors = {}
    end)

    local lifted = c.lift ~= nil
    pcall(function()
        if c.lift and DoesEntityExist(c.vehicle) then
            local lift = c.lift
            SetEntityCoordsNoOffset(c.vehicle, lift.origin.x, lift.origin.y, lift.origin.z, false, false, false)
            SetEntityRotation(c.vehicle, lift.rot.x, lift.rot.y, lift.rot.z, 2, false)
        end
        c.lift = nil
    end)

    pcall(function()
        for _, f in ipairs(c.frozen) do
            if DoesEntityExist(f.entity) then
                FreezeEntityPosition(f.entity, f.was)
                if lifted and f.entity == c.vehicle and not f.was then
                    SetVehicleOnGroundProperly(f.entity)
                end
            end
        end
        c.frozen = {}
    end)

    for dict in pairs(c.dicts) do RemoveAnimDict(dict) end
    for hash in pairs(c.models) do SetModelAsNoLongerNeeded(hash) end
    c.dicts, c.models = {}, {}
end

---------------------------------------------------------------------------------------------
-- Progress bars (ap1le_core). One bar per step, started together with the step.
--
-- ap1le_core facts this relies on (client/progress.lua of ap1le_core):
--  * a Progress without `anim` never touches the ped's tasks (stopAnim only runs for its own
--    anim), so our choreography keeps running across bar boundaries;
--  * Progress returns false at once while another bar is active, and its `active` slot is cleared
--    before it returns, so the next step's bar can start as soon as the previous call returned;
--  * CancelProgress only flags the running bar; that call then returns false a frame later.
-- Every bar is a small object owned by its step (`c.bar`). A bar that is no longer the current
-- one, or that we released ourselves, can never cancel the sequence when it resolves false.
---------------------------------------------------------------------------------------------

local BAR_DISABLE = { move = true, car = true, combat = true }
local BAR_FILLER_MS = 1500   -- extra bar while a step overruns its share (e.g. a long walk)
local BAR_GRACE_MS = 150     -- the step may finish a few frames after its bar

cancelBar = function(c)
    local bar = c.bar
    if not bar then return end
    bar.released = true
    if bar.running then UI.CancelProgress() end
end

local function startBar(c, label, icon, ms)
    local bar = { running = false, done = false, ok = nil, stepDone = false, released = false }
    c.bar = bar

    CreateThread(function()
        local duration = ms
        while true do
            -- released before it even started (sequence cancelled in the same frame)
            if bar.released or c.cancelled then break end
            -- no Wait between this flag and the core registering the bar (the export runs
            -- synchronously up to its first wait), so cancelBar can never hit another resource's bar
            bar.running = true
            local ok = UI.Progress({
                label = label,
                duration = math.max(500, math.floor(duration)),
                icon = icon,
                canCancel = true,
                disable = BAR_DISABLE,
            })
            bar.running = false

            if not ok then
                bar.ok = false
                -- cancel key, death, ragdoll ... cancels the sequence; a stale bar does not
                if c.bar == bar and not bar.released and not c.cleaned then
                    c.cancelled = true
                end
                break
            end
            bar.ok = true

            -- the step usually ends in the same frame or the next one
            local grace = GetGameTimer() + BAR_GRACE_MS
            while not bar.stepDone and not bar.released and not c.cancelled and GetGameTimer() < grace do
                Wait(0)
            end
            if bar.stepDone or bar.released or c.cancelled or c.bar ~= bar then break end

            -- the step overran: keep a bar (and with it the cancel key) up until it finishes
            duration = BAR_FILLER_MS
        end
        bar.running = false
        bar.done = true
    end)

    return bar
end

-- The step's work is done: let its bar run out so both end together
local function finishBar(c, bar, deadline)
    bar.stepDone = true
    while not bar.done do
        if c.cancelled then return false end
        if GetGameTimer() > deadline then
            -- never resolved (ap1le_core restarting?): drop it and carry on
            bar.released = true
            if bar.running then UI.CancelProgress() end
            break
        end
        Wait(0)
    end
    if bar.ok == false and not bar.released then return false end
    return not c.cancelled
end

-- Another resource's bar may still be on screen: give it a moment instead of failing the step
local function waitForFreeBar(timeoutMs)
    local deadline = GetGameTimer() + timeoutMs
    while UI.IsProgressActive() do
        if GetGameTimer() > deadline then return false end
        Wait(50)
    end
    return true
end

---------------------------------------------------------------------------------------------
-- Per-frame monitor (only alive while a sequence runs)
---------------------------------------------------------------------------------------------

local function monitor(c)
    CreateThread(function()
        local maxDist = (Config.MaxVehicleDistance or 6.0) + 2.0

        while active == c and not c.cancelled do
            for i = 1, #DISABLED_CONTROLS do DisableControlAction(0, DISABLED_CONTROLS[i], true) end

            local ped = c.ped
            local ref = c.distanceRef or c.vehicle
            if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then
                c.cancelled = true
            elseif not DoesEntityExist(c.vehicle) or (c.extra and not DoesEntityExist(c.extra)) then
                c.cancelled = true
            elseif not DoesEntityExist(ref) or #(GetEntityCoords(ped) - GetEntityCoords(ref)) > maxDist then
                c.cancelled = true
            end

            if c.cancelled then
                cancelBar(c)
                break
            end
            Wait(0)
        end
    end)
end

---------------------------------------------------------------------------------------------
-- Sequence runner
---------------------------------------------------------------------------------------------

local function runSteps(c, steps)
    local weight = 0.0
    for _, s in ipairs(steps) do weight = weight + (s.w or 1.0) end

    c.stepCount = #steps
    local acc = 0
    for i, s in ipairs(steps) do
        local ms = math.floor(c.totalMs * (s.w or 1.0) / weight)
        local started = GetGameTimer()
        local endAt = started + ms
        c.stepIndex = i
        c.stepLabel = locale(s.label)
        c.stepStart = started
        c.stepMs = math.max(1, ms)
        c.baseMs = acc

        local label = ('%s (%d/%d)'):format(c.stepLabel, i, c.stepCount)
        local bar = startBar(c, label, s.icon or STEP_ICONS[s.label] or 'wrench', ms)

        local ok = s.fn(c, ms, endAt)
        if ok == false or c.cancelled then return false end
        if not waitUntil(c, endAt) then return false end
        if not finishBar(c, bar, GetGameTimer() + 8000) then return false end
        acc = acc + ms
    end
    return true
end

local function run(entity, totalMs, buildSteps, opts)
    if active or Anim.IsAtLaptop() then return false end
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    opts = opts or {}

    -- A bar of another resource would make our first step fail at once
    if not waitForFreeBar(3000) then return false end
    if active or not DoesEntityExist(entity) then return false end

    totalMs = math.max(1000, math.floor(tonumber(totalMs) or 0))
    local c = newContext(entity, totalMs, opts.extra)
    c.distanceRef = opts.distanceRef
    active = c

    if not opts.noFreeze then freeze(c, entity) end
    if opts.extra then freeze(c, opts.extra) end
    monitor(c)

    local ok, result = pcall(function()
        local steps = buildSteps(c)
        return runSteps(c, steps)
    end)
    if not ok then
        print(('[ap1le_mechanicjob] animation error: %s'):format(tostring(result)))
        result = false
    end

    local completed = result == true and not c.cancelled
    cleanup(c)
    return completed
end

---------------------------------------------------------------------------------------------
-- Building blocks: engine bay
---------------------------------------------------------------------------------------------

-- Engine bay layout. dir = 1 front engine, -1 rear engine (lid = boot)
local function bayLayout(c)
    if c.bay then return c.bay end

    local engine = boneLocal(c, { 'engine' })
    local bonnet = boneLocal(c, { 'bonnet' })
    local dir = 1.0
    if engine and math.abs(engine.y) > 0.3 then
        dir = sign(engine.y)
    elseif bonnet and math.abs(bonnet.y) > 0.3 then
        dir = sign(bonnet.y)
    end

    local bay
    if engine and math.abs(engine.y) > 0.3 then
        bay = engine
    elseif bonnet and math.abs(bonnet.y) > 0.3 then
        -- the bonnet bone sits on the hinge; the bay is between hinge and bumper
        local edgeY = dir > 0 and c.max.y or c.min.y
        bay = vec3(0.0, (bonnet.y + edgeY) * 0.5, bonnet.z - 0.25)
    else
        bay = vec3(0.0, dir > 0 and (c.max.y - 0.9) or (c.min.y + 0.9), 0.1)
    end

    local edge = dir > 0 and c.max.y or c.min.y
    local side = c.side
    local layout = {
        dir = dir,
        door = dir > 0 and 4 or 5,
        bayLocal = bay,
        bayWorld = L(c, bay.x, bay.y, bay.z),
        edge = edge,
        frontPos = G(c, 0.0, edge + dir * 0.6),
        sidePos = G(c, sideX(c, side, 0.45), bay.y),
        benchPos = G(c, sideX(c, side, 1.4), edge - dir * 0.2),
        hoistFinal = G(c, 0.0, edge + dir * 1.0),
        palletPos = G(c, 0.0, edge + dir * 1.6),
        crankPos = G(c, side * (c.halfW + 0.15), edge + dir * 1.3),
    }
    -- Distance the hoist travels when it pulls the block clear of the bumper
    layout.travel = math.abs((edge + dir * 1.6) - bay.y)
    layout.hoistRetreat = G(c, 0.0, edge + dir * (1.0 + layout.travel))
    layout.away = (L(c, 0.0, dir, 0.0) - L(c, 0.0, 0.0, 0.0))
    c.bay = layout
    return layout
end

local function stepOpenHood(label)
    return {
        label = label or 'step_open_hood', w = 0.8,
        fn = function(c, ms, endAt)
            local bay = bayLayout(c)
            if not goTo(c, bay.frontPos, bay.bayWorld) then return false end
            playAnim(c, A.lidOpen, 1800)
            if not sleep(c, 550) then return false end
            openDoor(c, bay.door)
            if not sleep(c, 1000) then return false end
            playAnim(c, A.bayLean)
            return true
        end,
    }
end

local function stepCloseHood(w)
    return {
        label = 'step_close_hood', w = w or 0.6,
        fn = function(c, ms, endAt)
            local bay = bayLayout(c)
            -- close from the side: the hoist may still stand at the bumper
            if not goTo(c, bay.sidePos, bay.bayWorld) then return false end
            playAnim(c, A.lidClose, 1800)
            if not sleep(c, 650) then return false end
            closeDoor(c, bay.door)
            return sleep(c, 900)
        end,
    }
end

-- Leaning into the bay, optionally with the impact driver
local function stepBayWork(label, w, withTool, onEnd)
    return {
        label = label, w = w or 1.2,
        fn = function(c, ms, endAt)
            local bay = bayLayout(c)
            if not c.toolbox then
                c.toolbox = spawnGround(c, P.toolbox, bay.benchPos, c.heading + 90.0)
            end
            if not goTo(c, bay.sidePos, bay.bayWorld) then return false end
            local tool = withTool and holdTool(c, P.impact) or nil
            playAnim(c, withTool and A.bayLean or A.standWork)
            local ok = waitUntil(c, endAt - 150)
            deleteProp(c, tool)
            if ok and onEnd then onEnd(c) end
            return ok
        end,
    }
end

-- Engine block position helpers
local function blockAt(c, world, onPallet)
    local min, max = modelDims(c, P.engine)
    if onPallet then
        local pMin, pMax = modelDims(c, P.pallet)
        return vec3(world.x, world.y, c.groundZ + (pMax.z - pMin.z) - min.z)
    end
    return vec3(world.x, world.y, world.z - (min.z + max.z) * 0.5)
end

-- Push the hoist from `from` to `to` (both floor positions), ped walks behind it
local function pushHoist(c, hoist, from, to, faceTo)
    local towards = vec3(to.x - from.x, to.y - from.y, 0.0)
    local len = #towards
    if len < 0.05 then return true end
    local dirV = towards / len
    local behind = 0.95
    local hoistHeading = headingTo(from, faceTo) + HOIST_YAW
    local hz = onFloor(c, P.hoist, from).z
    local origin = from - dirV * behind

    if not goTo(c, origin, to) then return false end
    local endPos = to - dirV * behind
    TaskGoStraightToCoord(c.ped, endPos.x, endPos.y, endPos.z, 0.8, -1, headingTo(endPos, to), 0.2)
    playAnim(c, A.carry)

    local deadline = GetGameTimer() + 9000
    while true do
        if c.cancelled then return false end
        -- project the ped onto the push line; the hoist rolls just in front of the hands
        local pos = GetEntityCoords(c.ped)
        local along = (pos.x - origin.x) * dirV.x + (pos.y - origin.y) * dirV.y
        along = math.max(0.0, math.min(len, along))
        local p = from + dirV * along
        moveProp(hoist, vec3(p.x, p.y, hz), vec3(0.0, 0.0, hoistHeading))
        if along >= len - 0.08 or GetGameTimer() > deadline then break end
        Wait(0)
    end
    moveProp(hoist, vec3(to.x, to.y, hz), vec3(0.0, 0.0, hoistHeading))
    stopTask(c)
    return not c.cancelled
end

---------------------------------------------------------------------------------------------
-- Building blocks: wheel corner (jack, wheel, hub)
---------------------------------------------------------------------------------------------

local function pickWheel(c, mode)
    local veh = c.vehicle
    local pedPos = GetEntityCoords(c.ped)
    local list = {}
    for _, w in ipairs(WHEELS) do
        local idx = GetEntityBoneIndexByName(veh, w.bone)
        if idx ~= -1 then
            local wp = GetWorldPositionOfEntityBone(veh, idx)
            local lp = GetOffsetFromEntityGivenWorldCoords(veh, wp.x, wp.y, wp.z)
            list[#list + 1] = { bone = w.bone, boneIndex = idx, tyre = w.tyre, localPos = lp, dist = #(pedPos - wp) }
        end
    end

    local choice
    if mode == 'burst' then
        for _, w in ipairs(list) do
            if IsVehicleTyreBurst(veh, w.tyre, false) then choice = w break end
        end
    end
    if not choice then
        local pool = list
        if mode == 'front' then
            local fronts = {}
            for _, w in ipairs(list) do if w.localPos.y > 0.0 then fronts[#fronts + 1] = w end end
            if #fronts > 0 then pool = fronts end
        end
        for _, w in ipairs(pool) do
            if not choice or w.dist < choice.dist then choice = w end
        end
    end
    if not choice then
        choice = { localPos = vec3(c.side * (c.halfW - 0.2), c.max.y * 0.6, c.min.z + 0.35), dist = 0.0 }
    end

    local lp = choice.localPos
    choice.side = math.abs(lp.x) > 0.15 and sign(lp.x) or c.side
    choice.kneelPos = G(c, lp.x + choice.side * 0.75, lp.y)
    choice.jackPos = G(c, choice.side * math.max(0.3, c.halfW - 0.25), lp.y - sign(lp.y) * 0.75)
    choice.groundPos = G(c, lp.x + choice.side * 1.35, lp.y - sign(lp.y) * 0.55)  -- wheel lying flat
    choice.partPos = G(c, lp.x + choice.side * 1.1, lp.y + sign(lp.y) * 0.55)     -- small parts
    choice.toolPos = G(c, lp.x + choice.side * 1.6, lp.y + sign(lp.y) * 1.2)      -- floor tools
    return choice
end

local function hubWorld(c, wheel)
    if wheel.boneIndex then return GetWorldPositionOfEntityBone(c.vehicle, wheel.boneIndex) end
    local lp = wheel.localPos
    return L(c, lp.x, lp.y, lp.z)
end

local function wheelLying(c, pos)
    local min, max = modelDims(c, P.wheel)
    return vec3(pos.x, pos.y, c.groundZ + (max.x - min.x) * 0.5), vec3(0.0, 90.0, c.heading)
end

local function kneelAt(c, wheel, anim)
    if not goTo(c, wheel.kneelPos, hubWorld(c, wheel)) then return false end
    return playAnim(c, anim or A.crouchWork)
end

local function stepJackUp(wheelMode, uniform)
    return {
        label = 'step_jack_up', w = 1.0,
        fn = function(c, ms, endAt)
            c.wheel = c.wheel or pickWheel(c, wheelMode)
            local wheel = c.wheel
            if not kneelAt(c, wheel, A.crouchWork) then return false end
            c.jack = spawnGround(c, P.jack, wheel.jackPos, c.heading + 90.0)
            prepareLift(c, (not uniform) and wheel.localPos or nil)
            if not sleep(c, 400) then return false end
            return tween(c, remaining(endAt, 1200) - 200, function(t) setLift(c, t) end)
        end,
    }
end

local function stepJackDown()
    return {
        label = 'step_jack_down', w = 0.8,
        fn = function(c, ms, endAt)
            local wheel = c.wheel or pickWheel(c, 'near')
            if not kneelAt(c, wheel, A.crouchWork) then return false end
            local ok = tween(c, remaining(endAt, 1000) - 300, function(t) setLift(c, 1.0 - t) end)
            if not ok then return false end
            deleteProp(c, c.jack)
            c.jack = nil
            return true
        end,
    }
end

local function stepWheelOff()
    return {
        label = 'step_wheel_off', w = 1.2,
        fn = function(c, ms, endAt)
            local wheel = c.wheel or pickWheel(c, 'near')
            c.wheel = wheel
            if not kneelAt(c, wheel, A.crouchWork) then return false end
            local tool = holdTool(c, P.impact)
            local total = remaining(endAt, 2000)
            if not sleep(c, total * 0.5) then return false end
            deleteProp(c, tool)

            local hub = hubWorld(c, wheel)
            local obj = spawnProp(c, P.wheel, hub, vec3(0.0, 0.0, c.heading))
            local outPos = hub + (L(c, wheel.side, 0.0, 0.0) - L(c, 0.0, 0.0, 0.0)) * 0.35
            local restPos, restRot = wheelLying(c, wheel.groundPos)
            local total2 = remaining(endAt, 1200) - 150
            if not tween(c, total2 * 0.35, function(t) moveProp(obj, lerp(hub, outPos, t)) end) then return false end
            if not tween(c, total2 * 0.65, function(t)
                moveProp(obj, lerp(outPos, restPos, t), vec3(0.0, 90.0 * t, c.heading))
            end) then return false end
            moveProp(obj, restPos, restRot)
            c.wheelProp = obj
            return true
        end,
    }
end

local function stepWheelOn()
    return {
        label = 'step_wheel_on', w = 1.2,
        fn = function(c, ms, endAt)
            local wheel = c.wheel or pickWheel(c, 'near')
            c.wheel = wheel
            if not kneelAt(c, wheel, A.crouchWork) then return false end

            local obj = c.wheelProp
            local restPos = wheelLying(c, wheel.groundPos)
            if not obj then
                obj = spawnProp(c, P.wheel, restPos, vec3(0.0, 90.0, c.heading))
            end
            local hub = hubWorld(c, wheel)
            local outPos = hub + (L(c, wheel.side, 0.0, 0.0) - L(c, 0.0, 0.0, 0.0)) * 0.35
            local total = remaining(endAt, 2000)
            if not tween(c, total * 0.25, function(t)
                moveProp(obj, lerp(restPos, outPos, t), vec3(0.0, 90.0 * (1.0 - t), c.heading))
            end) then return false end
            if not tween(c, total * 0.15, function(t) moveProp(obj, lerp(outPos, hub, t)) end) then return false end
            deleteProp(c, obj)
            c.wheelProp = nil

            local tool = holdTool(c, P.impact)
            local ok = waitUntil(c, endAt - 150)
            deleteProp(c, tool)
            return ok
        end,
    }
end

-- Work at the hub. part = prop moving hub -> ground ('out') or ground -> hub ('in')
local function stepHubWork(label, w, part, direction, tool)
    return {
        label = label, w = w or 1.2,
        fn = function(c, ms, endAt)
            local wheel = c.wheel or pickWheel(c, 'near')
            c.wheel = wheel
            if tool and not c.hubTool then c.hubTool = spawnGround(c, tool, wheel.toolPos, c.heading) end
            if not kneelAt(c, wheel, A.crouchWork) then return false end

            local total = remaining(endAt, 2000)
            if not part then
                -- work at the hub with the impact driver for the whole step
                local held = holdTool(c, P.impact)
                local ok = waitUntil(c, endAt - 150)
                deleteProp(c, held)
                return ok
            end

            local hub = hubWorld(c, wheel) + (L(c, wheel.side, 0.0, 0.0) - L(c, 0.0, 0.0, 0.0)) * 0.12
            local floor = onFloor(c, part, wheel.partPos)
            if direction == 'out' then
                -- unbolt the old part, then set it down on the floor
                local held = holdTool(c, P.impact)
                if not sleep(c, total * 0.5) then return false end
                deleteProp(c, held)
                local obj = spawnProp(c, part, hub, vec3(0.0, 0.0, c.heading))
                if not tween(c, total * 0.35, function(t) moveProp(obj, lerp(hub, floor, t)) end) then return false end
            else
                -- new part from the floor onto the hub, then bolt it
                local obj = spawnProp(c, part, floor, vec3(0.0, 0.0, c.heading))
                if not sleep(c, total * 0.1) then return false end
                if not tween(c, total * 0.35, function(t) moveProp(obj, lerp(floor, hub, t)) end) then return false end
                local held = holdTool(c, P.impact)
                if not waitUntil(c, endAt - 200) then return false end
                deleteProp(c, held)
                deleteProp(c, obj)
            end
            return true
        end,
    }
end

---------------------------------------------------------------------------------------------
-- Building blocks: under the car, welding, painting, body work
---------------------------------------------------------------------------------------------

local function underLayout(c, y)
    local side = c.side
    local lieY = y or 0.0
    return {
        liePos = G(c, sideX(c, side, 0.35), lieY),
        lookAt = G(c, 0.0, lieY),
        kneelPos = G(c, sideX(c, side, 0.75), lieY + 0.9),
        jackPos = G(c, side * math.max(0.3, c.halfW - 0.25), lieY + 0.9),
        outPos = G(c, sideX(c, side, 1.2), lieY - 0.6),
        underPos = G(c, 0.0, lieY),
    }
end

local function lieUnder(c, u, anim)
    if not goTo(c, u.liePos, u.lookAt) then return false end
    return playAnim(c, anim or A.under)
end

local function sidePoint(c, side)
    return G(c, sideX(c, side, 0.7), 0.0), G(c, side > 0 and c.max.x or c.min.x, 0.0)
end

local function endPoint(c, dir)
    return G(c, 0.0, endY(c, dir, 0.8)), G(c, 0.0, dir > 0 and c.max.y or c.min.y)
end

local function stepScenarioAt(label, w, scenarioName, where)
    return {
        label = label, w = w or 1.0,
        fn = function(c, ms, endAt)
            local pos, look = where(c)
            if not goTo(c, pos, look) then return false end
            scenario(c, scenarioName)
            if not waitUntil(c, endAt - 700) then return false end
            stopTask(c)
            return not c.cancelled
        end,
    }
end

local function stepPaint(where, w)
    return {
        label = 'step_paint', w = w or 1.0,
        fn = function(c, ms, endAt)
            local pos, look = where(c)
            if not goTo(c, pos, look) then return false end
            local can = holdTool(c, P.spray)
            playAnim(c, A.spray)
            startSprayFx(c, can)
            local ok = waitUntil(c, endAt - 200)
            stopFx(c)
            deleteProp(c, can)
            stopTask(c)
            return ok
        end,
    }
end

---------------------------------------------------------------------------------------------
-- Performance swaps: remove / install choreography per category
---------------------------------------------------------------------------------------------

local Swaps = {}

-- Engine: hood up, hoist rolled to the bumper, block lifted out onto a pallet (and back in)
Swaps.engine = {
    remove = function(c)
        return {
            stepOpenHood(),
            {
                label = 'step_hoist', w = 1.4,
                fn = function(c, ms, endAt)
                    local bay = bayLayout(c)
                    local start = bay.hoistFinal + bay.away * 2.6
                    c.hoist = spawnGround(c, P.hoist, start, headingTo(start, bay.bayWorld) + HOIST_YAW)
                    if not c.hoist then return true end
                    return pushHoist(c, c.hoist, start, bay.hoistFinal, bay.bayWorld)
                end,
            },
            stepBayWork('step_unbolt', 1.4, true),
            {
                label = 'step_lift_out', w = 2.2,
                fn = function(c, ms, endAt)
                    local bay = bayLayout(c)
                    local inBay = blockAt(c, bay.bayWorld)
                    local up = inBay + vec3(0.0, 0.0, 1.15)
                    local out = vec3(bay.palletPos.x, bay.palletPos.y, up.z)
                    local onPallet = blockAt(c, bay.palletPos, true)

                    c.block = spawnProp(c, P.engine, inBay, vec3(0.0, 0.0, c.heading))
                    c.pallet = c.pallet or spawnGround(c, P.pallet, bay.palletPos, c.heading)
                    if not goTo(c, bay.crankPos, bay.hoistFinal) then return false end
                    playAnim(c, A.standWork)

                    local total = remaining(endAt, 3000) - 200
                    local hoistHeading = headingTo(bay.hoistFinal, bay.bayWorld) + HOIST_YAW
                    if not tween(c, total * 0.4, function(t) moveProp(c.block, lerp(inBay, up, t)) end) then return false end
                    if not tween(c, total * 0.3, function(t)
                        moveProp(c.block, lerp(up, out, t))
                        moveProp(c.hoist, onFloor(c, P.hoist, lerp(bay.hoistFinal, bay.hoistRetreat, t)), vec3(0.0, 0.0, hoistHeading))
                    end) then return false end
                    return tween(c, total * 0.3, function(t) moveProp(c.block, lerp(out, onPallet, t)) end)
                end,
            },
        }
    end,
    install = function(c)
        return {
            stepOpenHood(),
            {
                label = 'step_hoist', w = 1.5,
                fn = function(c, ms, endAt)
                    local bay = bayLayout(c)
                    c.pallet = spawnGround(c, P.pallet, bay.palletPos, c.heading)
                    c.block = spawnProp(c, P.engine, blockAt(c, bay.palletPos, true), vec3(0.0, 0.0, c.heading))
                    local start = bay.hoistRetreat + bay.away * 1.8
                    c.hoist = spawnGround(c, P.hoist, start, headingTo(start, bay.bayWorld) + HOIST_YAW)
                    if c.hoist and not pushHoist(c, c.hoist, start, bay.hoistRetreat, bay.bayWorld) then return false end

                    -- Hook the new block and lift it off the pallet
                    if not goTo(c, bay.crankPos, bay.palletPos) then return false end
                    playAnim(c, A.standWork)
                    local from = blockAt(c, bay.palletPos, true)
                    local up = vec3(from.x, from.y, blockAt(c, bay.bayWorld).z + 1.15)
                    return tween(c, remaining(endAt, 1500) - 150, function(t) moveProp(c.block, lerp(from, up, t)) end)
                end,
            },
            {
                label = 'step_lift_in', w = 2.0,
                fn = function(c, ms, endAt)
                    local bay = bayLayout(c)
                    local inBay = blockAt(c, bay.bayWorld)
                    local up = inBay + vec3(0.0, 0.0, 1.15)
                    local out = vec3(bay.palletPos.x, bay.palletPos.y, up.z)
                    if not c.block then c.block = spawnProp(c, P.engine, out, vec3(0.0, 0.0, c.heading)) end
                    if not goTo(c, bay.crankPos, bay.hoistFinal) then return false end
                    playAnim(c, A.standWork)

                    local total = remaining(endAt, 3000) - 200
                    local hoistHeading = headingTo(bay.hoistFinal, bay.bayWorld) + HOIST_YAW
                    if not tween(c, total * 0.45, function(t)
                        moveProp(c.block, lerp(out, up, t))
                        moveProp(c.hoist, onFloor(c, P.hoist, lerp(bay.hoistRetreat, bay.hoistFinal, t)), vec3(0.0, 0.0, hoistHeading))
                    end) then return false end
                    return tween(c, total * 0.55, function(t) moveProp(c.block, lerp(up, inBay, t)) end)
                end,
            },
            stepBayWork('step_bolt', 1.5, true, function(c)
                deleteProp(c, c.block)
                c.block = nil
            end),
            stepCloseHood(0.8),
        }
    end,
}

-- Brakes: jack up the corner, wheel off, caliper off/on at the hub, wheel on, jack down
Swaps.brakes = {
    remove = function(c)
        return {
            stepJackUp('front'),
            stepWheelOff(),
            stepHubWork('step_unbolt', 1.3, P.caliper, 'out'),
            stepWheelOn(),
            stepJackDown(),
        }
    end,
    install = function(c)
        return {
            stepJackUp('front'),
            stepWheelOff(),
            stepHubWork('step_fit_part', 1.3, P.caliper, 'in'),
            stepWheelOn(),
            stepJackDown(),
        }
    end,
}

-- Suspension: same corner work with the strut compressor on the floor
Swaps.suspension = {
    remove = function(c)
        return {
            stepJackUp('front'),
            stepWheelOff(),
            stepHubWork('step_unbolt', 1.4, nil, nil, P.strut),
            stepWheelOn(),
            stepJackDown(),
        }
    end,
    install = function(c)
        return {
            stepJackUp('front'),
            stepWheelOff(),
            stepHubWork('step_fit_part', 1.4, nil, nil, P.strut),
            stepWheelOn(),
            stepJackDown(),
        }
    end,
}

-- Transmission: whole car on the jack, mechanic underneath, gearbox lowered out / raised in
local function gearboxY(c)
    local bay = bayLayout(c)
    local y = bay.bayLocal.y - bay.dir * 1.1
    return math.max(c.min.y + 0.8, math.min(c.max.y - 0.8, y))
end

local function stepTransJack()
    return {
        label = 'step_jack_up', w = 1.0,
        fn = function(c, ms, endAt)
            local u = underLayout(c, gearboxY(c))
            c.under = u
            if not goTo(c, u.kneelPos, u.jackPos) then return false end
            playAnim(c, A.crouchWork)
            c.jack = spawnGround(c, P.jack, u.jackPos, c.heading + 90.0)
            prepareLift(c, nil)
            if not sleep(c, 400) then return false end
            return tween(c, remaining(endAt, 1200) - 200, function(t) setLift(c, t) end)
        end,
    }
end

local function stepTransJackDown()
    return {
        label = 'step_jack_down', w = 0.8,
        fn = function(c, ms, endAt)
            local u = c.under or underLayout(c, gearboxY(c))
            if not goTo(c, u.kneelPos, u.jackPos) then return false end
            playAnim(c, A.crouchWork)
            if not tween(c, remaining(endAt, 1000) - 300, function(t) setLift(c, 1.0 - t) end) then return false end
            deleteProp(c, c.jack)
            c.jack = nil
            return true
        end,
    }
end

local function gearboxHeights(c, u)
    local min = modelDims(c, P.gearbox)
    local floor = vec3(u.underPos.x, u.underPos.y, c.groundZ - min.z)
    local mounted = floor + vec3(0.0, 0.0, 0.22)
    local outside = vec3(u.outPos.x, u.outPos.y, c.groundZ - min.z)
    return floor, mounted, outside
end

Swaps.transmission = {
    remove = function(c)
        return {
            stepTransJack(),
            {
                label = 'step_under_car', w = 1.0,
                fn = function(c, ms, endAt)
                    local u = c.under
                    if not lieUnder(c, u, A.under) then return false end
                    return true
                end,
            },
            {
                label = 'step_unbolt', w = 1.5,
                fn = function(c, ms, endAt)
                    local u = c.under
                    if not c.lying and not lieUnder(c, u, A.underWork) then return false end
                    playAnim(c, A.underWork)
                    local floor, mounted = gearboxHeights(c, u)
                    c.gearbox = spawnProp(c, P.gearbox, mounted, vec3(0.0, 0.0, c.heading + 90.0))
                    local total = remaining(endAt, 2000) - 150
                    if not sleep(c, total * 0.55) then return false end
                    return tween(c, total * 0.45, function(t) moveProp(c.gearbox, lerp(mounted, floor, t)) end)
                end,
            },
            {
                label = 'step_lift_out', w = 1.2,
                fn = function(c, ms, endAt)
                    local u = c.under
                    if not goTo(c, u.kneelPos, u.underPos) then return false end
                    playAnim(c, A.crouchWork)
                    local floor, _, outside = gearboxHeights(c, u)
                    if not c.gearbox then c.gearbox = spawnProp(c, P.gearbox, floor, vec3(0.0, 0.0, c.heading + 90.0)) end
                    return tween(c, remaining(endAt, 1500) - 150, function(t) moveProp(c.gearbox, lerp(floor, outside, t)) end)
                end,
            },
            stepTransJackDown(),
        }
    end,
    install = function(c)
        return {
            stepTransJack(),
            {
                label = 'step_under_car', w = 1.2,
                fn = function(c, ms, endAt)
                    local u = c.under
                    local floor, _, outside = gearboxHeights(c, u)
                    c.gearbox = spawnProp(c, P.gearbox, outside, vec3(0.0, 0.0, c.heading + 90.0))
                    if not goTo(c, u.kneelPos, u.underPos) then return false end
                    playAnim(c, A.crouchWork)
                    if not tween(c, remaining(endAt, 2500) * 0.5, function(t) moveProp(c.gearbox, lerp(outside, floor, t)) end) then return false end
                    return lieUnder(c, u, A.under)
                end,
            },
            {
                label = 'step_lift_in', w = 1.0,
                fn = function(c, ms, endAt)
                    local u = c.under
                    if not c.lying and not lieUnder(c, u, A.under) then return false end
                    local floor, mounted = gearboxHeights(c, u)
                    if not c.gearbox then c.gearbox = spawnProp(c, P.gearbox, floor, vec3(0.0, 0.0, c.heading + 90.0)) end
                    return tween(c, remaining(endAt, 1200) - 150, function(t) moveProp(c.gearbox, lerp(floor, mounted, t)) end)
                end,
            },
            {
                label = 'step_bolt', w = 1.2,
                fn = function(c, ms, endAt)
                    local u = c.under
                    if not c.lying and not lieUnder(c, u, A.underWork) then return false end
                    playAnim(c, A.underWork)
                    if not waitUntil(c, endAt - 200) then return false end
                    deleteProp(c, c.gearbox)
                    c.gearbox = nil
                    return true
                end,
            },
            stepTransJackDown(),
        }
    end,
}

-- Armor: plates cut off / welded on along both sides, carried to / from a pallet
local function panelAt(c, side)
    local min = modelDims(c, P.panel)
    local p = G(c, side > 0 and (c.max.x + 0.12) or (c.min.x - 0.12), 0.0)
    return vec3(p.x, p.y, c.groundZ - min.z), vec3(0.0, 0.0, c.heading + 90.0)
end

local function armorStack(c)
    local bay = bayLayout(c)
    return G(c, sideX(c, c.side, 1.5), bay.edge - bay.dir * 0.4)
end

local function stepWeldSide(side, mode, w)
    return {
        label = 'step_weld', w = w or 1.0,
        fn = function(c, ms, endAt)
            local s = side == 'near' and c.side or -c.side
            local pos, look = sidePoint(c, s)
            local panelPos, panelRot = panelAt(c, s)
            local panel
            if mode == 'remove' then
                panel = spawnProp(c, P.panel, panelPos, panelRot)
            else
                panel = c.carried == s and c.carriedPanel or spawnProp(c, P.panel, panelPos, panelRot)
            end
            if not goTo(c, pos, look) then return false end
            scenario(c, SCENARIO.weld)
            if not waitUntil(c, endAt - 900) then return false end
            stopTask(c)
            if mode == 'remove' then
                -- the cut plate tips away from the body onto the floor
                local floorPos = G(c, sideX(c, s, 0.9), 0.6)
                local pMin = modelDims(c, P.panel)
                floorPos = vec3(floorPos.x, floorPos.y, c.groundZ - pMin.z)
                tween(c, 500, function(t) moveProp(panel, lerp(panelPos, floorPos, t)) end)
                c.cutPanel = panel
            else
                deleteProp(c, panel)
                c.carriedPanel = nil
            end
            return not c.cancelled
        end,
    }
end

local function onStack(c, stack)
    local pMin, pMax = modelDims(c, P.pallet)
    local panelMin = modelDims(c, P.panel)
    return vec3(stack.x, stack.y, c.groundZ + (pMax.z - pMin.z) - panelMin.z)
end

Swaps.armor = {
    remove = function(c)
        return {
            stepWeldSide('near', 'remove', 1.0),
            stepWeldSide('far', 'remove', 1.0),
            {
                label = 'step_lift_out', w = 1.0,
                fn = function(c, ms, endAt)
                    local stack = armorStack(c)
                    c.stack = c.stack or spawnGround(c, P.pallet, stack, c.heading)
                    local panel = c.cutPanel
                    if not panel then return true end
                    -- pick the cut plate up from the floor and stack it on the pallet
                    local pp = GetEntityCoords(panel)
                    if not goTo(c, approach(c, pp, 0.6), pp) then return false end
                    if not pickUp(c, panel) then return false end
                    if not goTo(c, approach(c, stack, 0.75), stack, true) then return false end
                    if not putDown(c, panel, onStack(c, stack), vec3(0.0, 0.0, c.heading)) then return false end
                    c.cutPanel = nil
                    stopTask(c)
                    return not c.cancelled
                end,
            },
        }
    end,
    install = function(c)
        return {
            {
                label = 'step_fit_part', w = 1.0,
                fn = function(c, ms, endAt)
                    local stack = armorStack(c)
                    c.stack = c.stack or spawnGround(c, P.pallet, stack, c.heading)
                    local panel = spawnProp(c, P.panel, onStack(c, stack), vec3(0.0, 0.0, c.heading))
                    -- new plate from the pallet to the body panel
                    if not goTo(c, approach(c, stack, 0.75), stack) then return false end
                    if not pickUp(c, panel) then return false end
                    local pos, look = sidePoint(c, c.side)
                    if not goTo(c, pos, look, true) then return false end
                    if not sleep(c, 300) then return false end
                    release(panel)
                    local panelPos, panelRot = panelAt(c, c.side)
                    if panel then
                        local from = GetEntityCoords(panel)
                        if not tween(c, 450, function(t) moveProp(panel, lerp(from, panelPos, t), panelRot) end) then return false end
                    end
                    c.carriedPanel, c.carried = panel, c.side
                    stopTask(c)
                    return not c.cancelled
                end,
            },
            stepWeldSide('near', 'install', 1.0),
            stepWeldSide('far', 'install', 1.0),
        }
    end,
}

-- Turbo: engine bay work, the part is carried out to / in from the tool box
local function turboSpot(c, bay)
    return onFloor(c, P.turbo, bay.benchPos + (bay.sidePos - bay.benchPos) * 0.2)
end

Swaps.turbo = {
    remove = function(c)
        return {
            stepOpenHood(),
            stepBayWork('step_unbolt', 1.2, true),
            {
                label = 'step_lift_out', w = 1.4,
                fn = function(c, ms, endAt)
                    local bay = bayLayout(c)
                    local from = bay.bayWorld + vec3(0.0, 0.0, 0.05)
                    local part = spawnProp(c, P.turbo, from, vec3(0.0, 0.0, c.heading))
                    if not goTo(c, bay.sidePos, bay.bayWorld) then return false end
                    playAnim(c, A.bayLean)
                    -- lift the old unit out of the bay into the hands
                    local up = from + vec3(0.0, 0.0, 0.35)
                    if not tween(c, 900, function(t) moveProp(part, lerp(from, up, t)) end) then return false end
                    if not tween(c, 350, function(t)
                        moveProp(part, lerp(up, GetOffsetFromEntityInWorldCoords(c.ped, CARRY_OFFSET.x, CARRY_OFFSET.y, CARRY_OFFSET.z), t))
                    end) then return false end
                    carry(c, part)
                    -- carry it to the tool box and set it down on the floor
                    local spot = turboSpot(c, bay)
                    if not goTo(c, approach(c, spot, 0.6), spot, true) then return false end
                    if not putDown(c, part, spot, vec3(0.0, 0.0, c.heading)) then return false end
                    stopTask(c)
                    return not c.cancelled
                end,
            },
            stepCloseHood(0.6),
        }
    end,
    install = function(c)
        return {
            stepOpenHood(),
            {
                label = 'step_fit_part', w = 1.4,
                fn = function(c, ms, endAt)
                    local bay = bayLayout(c)
                    c.toolbox = c.toolbox or spawnGround(c, P.toolbox, bay.benchPos, c.heading + 90.0)
                    local spot = turboSpot(c, bay)
                    local part = spawnProp(c, P.turbo, spot, vec3(0.0, 0.0, c.heading))
                    -- pick the new unit up next to the tool box
                    if not goTo(c, approach(c, spot, 0.6), spot) then return false end
                    if not pickUp(c, part) then return false end
                    -- carry it to the bay and lower it in
                    if not goTo(c, bay.sidePos, bay.bayWorld, true) then return false end
                    if not sleep(c, 300) then return false end
                    release(part)
                    playAnim(c, A.bayLean)
                    if part then
                        local held = GetEntityCoords(part)
                        local into = bay.bayWorld + vec3(0.0, 0.0, 0.05)
                        if not tween(c, 1000, function(t) moveProp(part, lerp(held, into, t)) end) then return false end
                    end
                    c.turboPart = part
                    return true
                end,
            },
            stepBayWork('step_bolt', 1.2, true, function(c)
                deleteProp(c, c.turboPart)
                c.turboPart = nil
            end),
            stepCloseHood(0.6),
        }
    end,
}

---------------------------------------------------------------------------------------------
-- Repairs
---------------------------------------------------------------------------------------------

local Repairs = {
    engine = function(c)
        return {
            stepOpenHood(),
            stepBayWork('step_unbolt', 1.2, true),
            stepBayWork('step_fit_part', 1.2, false),
            stepBayWork('step_bolt', 1.0, true),
            stepCloseHood(0.6),
        }
    end,
    body = function(c)
        return {
            stepScenarioAt('step_fit_part', 1.0, SCENARIO.hammer, function(c) return sidePoint(c, c.side) end),
            stepScenarioAt('step_weld', 1.0, SCENARIO.weld, function(c) return sidePoint(c, -c.side) end),
            stepPaint(function(c) return endPoint(c, -c.endSign) end, 1.0),
        }
    end,
    tyre = function(c)
        c.wheel = pickWheel(c, 'burst')
        return {
            stepJackUp('burst'),
            stepWheelOff(),
            stepWheelOn(),
            stepJackDown(),
        }
    end,
    field = function(c)
        return {
            stepOpenHood(),
            stepBayWork('step_fit_part', 2.0, true),
            stepCloseHood(0.6),
        }
    end,
}

---------------------------------------------------------------------------------------------
-- Cosmetic installs
---------------------------------------------------------------------------------------------

local function interiorDoor(c)
    if c.side > 0 then
        return 1, boneLocal(c, { 'door_pside_f' })
    end
    return 0, boneLocal(c, { 'door_dside_f' })
end

local function stepInterior(label, openIt)
    return {
        label = label, w = 1.0,
        fn = function(c, ms, endAt)
            local door, doorLocal = interiorDoor(c)
            local y = doorLocal and (doorLocal.y - 0.55) or 0.2
            local pos = G(c, sideX(c, c.side, 0.55), y)
            local look = G(c, 0.0, y)
            if not goTo(c, pos, look) then return false end
            if openIt then
                openDoor(c, door)
                if not sleep(c, 600) then return false end
            end
            playAnim(c, A.standWork)
            if not waitUntil(c, endAt - 600) then return false end
            if not openIt then closeDoor(c, door) end
            return true
        end,
    }
end

local Cosmetics = {
    body = function(c)
        return {
            stepScenarioAt('step_fit_part', 1.2, SCENARIO.hammer, function(c) return sidePoint(c, c.side) end),
            {
                label = 'step_bolt', w = 1.0,
                fn = function(c, ms, endAt)
                    local wheel = pickWheel(c, 'near')
                    local pos = G(c, wheel.localPos.x + wheel.side * 0.75, wheel.localPos.y + sign(wheel.localPos.y) * 0.6)
                    if not goTo(c, pos, L(c, wheel.localPos.x, wheel.localPos.y + sign(wheel.localPos.y) * 0.6, 0.0)) then return false end
                    local tool = holdTool(c, P.impact)
                    playAnim(c, A.crouchWork)
                    local ok = waitUntil(c, endAt - 150)
                    deleteProp(c, tool)
                    return ok
                end,
            },
        }
    end,
    under = function(c)
        local y = (c.endSign < 0) and (c.min.y * 0.55) or (c.max.y * 0.55)
        return {
            {
                label = 'step_under_car', w = 1.0,
                fn = function(c, ms, endAt)
                    c.under = underLayout(c, y)
                    return lieUnder(c, c.under, A.under)
                end,
            },
            {
                label = 'step_bolt', w = 1.0,
                fn = function(c, ms, endAt)
                    if not c.lying and not lieUnder(c, c.under or underLayout(c, y), A.underWork) then return false end
                    playAnim(c, A.underWork)
                    if not waitUntil(c, endAt - 1600) then return false end
                    stopTask(c) -- roll out before the step ends
                    return not c.cancelled
                end,
            },
        }
    end,
    interior = function(c)
        return {
            stepInterior('step_fit_part', true),
            stepInterior('step_bolt', false),
        }
    end,
    hood = function(c)
        return {
            stepOpenHood(),
            stepBayWork('step_fit_part', 1.4, true),
            stepCloseHood(0.6),
        }
    end,
    paint = function(c)
        return {
            stepPaint(function(c) return sidePoint(c, c.side) end, 1.0),
            stepPaint(function(c) return endPoint(c, -c.endSign) end, 1.0),
            stepPaint(function(c) return sidePoint(c, -c.side) end, 1.0),
        }
    end,
    wheel = function(c)
        return {
            stepJackUp('near'),
            stepWheelOff(),
            stepWheelOn(),
            stepJackDown(),
        }
    end,
}

---------------------------------------------------------------------------------------------
-- Delivery crate: crowbar it open, take the boxes out and set them down beside it
---------------------------------------------------------------------------------------------

-- Box held in front of the chest with the box-carry clip (placement from rpemotes' "box" emote)
local BOX_CARRY_POS = vec3(0.025, 0.08, 0.255)
local BOX_CARRY_ROT = vec3(-145.0, 290.0, 0.0)
local BOX_CYCLE_MS = 4300   -- rough length of one take-walk-set-down cycle
local BOX_MAX = 6

-- c.vehicle is the crate entity here (the generic context works for any entity with a model)
local function crateLayout(c)
    if c.crateInfo then return c.crateInfo end
    local crate = c.vehicle
    local cx, cy = (c.min.x + c.max.x) * 0.5, (c.min.y + c.max.y) * 0.5
    local centre = G(c, cx, cy)
    local reach = math.max(c.max.x - c.min.x, c.max.y - c.min.y) * 0.5 + 0.5
    local work = approach(c, centre, reach)

    local towards = vec3(centre.x - work.x, centre.y - work.y, 0.0)
    local len = #towards
    local dir = len > 0.01 and towards / len or (L(c, 0.0, 1.0, 0.0) - L(c, 0.0, 0.0, 0.0))
    local right = vec3(dir.y, -dir.x, 0.0)
    local top = GetOffsetFromEntityInWorldCoords(crate, cx, cy, c.max.z)

    c.crateInfo = {
        centre = centre,
        work = work,
        dir = dir,
        right = right,
        top = top,
        height = top.z - c.groundZ,
        heading = headingTo(work, centre),
        -- boxes go in a row on the right of the crate, starting level with its middle
        rowStart = centre + right * (reach + 0.15),
    }
    return c.crateInfo
end

local function boxSpot(c, info, index)
    local min, max = modelDims(c, P.box)
    local col = (index - 1) % 3
    local layer = (index - 1) // 3
    local p = info.rowStart - info.dir * (0.45 * col)
    return vec3(p.x, p.y, c.groundZ - min.z + layer * (max.z - min.z)), vec3(p.x, p.y, c.groundZ)
end

-- Reach into the crate and bring a box up to the chest
local function takeBox(c, info)
    local min, max = modelDims(c, P.box)
    local inside = vec3(info.top.x, info.top.y, info.top.z - (max.z - min.z) * 0.6)
    local box = spawnProp(c, P.box, inside, vec3(0.0, 0.0, info.heading))
    if not box then return nil end

    if info.height > 0.6 then
        playAnim(c, A.standWork)
        if not sleep(c, 650) then return nil end
    else
        playAnim(c, A.kneelDown)
        if not sleep(c, 800) then return nil end
    end

    local up = inside + vec3(0.0, 0.0, (max.z - min.z) + 0.15)
    if not tween(c, 300, function(t) moveProp(box, lerp(inside, up, t)) end) then return nil end
    if not tween(c, 350, function(t)
        moveProp(box, lerp(up, GetOffsetFromEntityInWorldCoords(c.ped, CARRY_OFFSET.x, CARRY_OFFSET.y, CARRY_OFFSET.z), t))
    end) then return nil end
    attachTo(c, box, BONE_SKEL_L_HAND, BOX_CARRY_POS, BOX_CARRY_ROT)
    playAnim(c, A.carry)
    if c.cancelled then return nil end
    return box
end

local function buildUnpack(c)
    return {
        {
            label = 'step_crate_open', w = 1.0,
            fn = function(c, ms, endAt)
                local info = crateLayout(c)
                if not goTo(c, info.work, info.centre) then return false end
                local crowbar = holdTool(c, P.crowbar)
                playAnim(c, A.pry)
                -- clip missing in this game build: lean in and work at the lid instead
                if not c.dicts[A.pry.dict] then playAnim(c, A.standWork) end
                local ok = waitUntil(c, endAt - 250)
                deleteProp(c, crowbar)
                return ok
            end,
        },
        {
            label = 'step_crate_unload', w = 1.4,
            fn = function(c, ms, endAt)
                local info = crateLayout(c)
                local count = 0
                repeat
                    if not goTo(c, info.work, info.centre) then return false end
                    local box = takeBox(c, info)
                    if c.cancelled then return false end
                    if not box then break end
                    count = count + 1

                    local floorPos, spot = boxSpot(c, info, count)
                    if not goTo(c, approach(c, spot, 0.62), spot, true) then return false end
                    if not putDown(c, box, floorPos, vec3(0.0, 0.0, info.heading)) then return false end
                until count >= BOX_MAX or (endAt - GetGameTimer()) < BOX_CYCLE_MS + 1200

                -- finish standing at the crate
                if not goTo(c, info.work, info.centre) then return false end
                playAnim(c, A.standWork)
                if not waitUntil(c, endAt - 400) then return false end
                stopTask(c)
                return not c.cancelled
            end,
        },
    }
end

---------------------------------------------------------------------------------------------
-- Laptop: walk up to it and type until Anim.StopLaptop(). No progress bar.
---------------------------------------------------------------------------------------------

-- Where the user stands, in the laptop's local space. prop_laptop_01a's screen faces its -Y side
-- (the side a ped stands on when the prop is placed with the ped's heading); flip the sign here
-- if the ped ends up behind the screen in your build.
local LAPTOP_STAND = vec2(0.0, -0.7)
local LAPTOP_MOVE_CONTROLS = { 21, 22, 23, 30, 31, 32, 33, 34, 35, 36, 44 }

local laptop = nil -- { ped, entity, stopped, broken, anim, enter, exit, dicts }

local function laptopDict(l, a)
    if l.dicts[a.dict] then return true end
    if not pcall(lib.requestAnimDict, a.dict, 3000) then return false end
    l.dicts[a.dict] = true
    return true
end

-- Walk to `target` (2D) with a stuck check. Navmesh first (desks), straight line as fallback.
local function laptopWalk(l, target, heading)
    local ped = l.ped
    for attempt = 1, 2 do
        if attempt == 1 then
            TaskFollowNavMeshToCoord(ped, target.x, target.y, target.z, 1.0, 4000, 0.15, 0, heading)
        else
            TaskGoStraightToCoord(ped, target.x, target.y, target.z, 1.0, 3000, heading, 0.1)
        end
        local started = GetGameTimer()
        local stillSince = nil
        while true do
            if l.stopped then return false end
            for i = 1, #LAPTOP_MOVE_CONTROLS do DisableControlAction(0, LAPTOP_MOVE_CONTROLS[i], true) end
            local pos = GetEntityCoords(ped)
            if #(pos.xy - target.xy) <= 0.3 then return true end
            local now = GetGameTimer()
            if now - started > 4500 then break end
            if now - started > 700 and GetEntitySpeed(ped) < 0.05 then
                stillSince = stillSince or now
                if now - stillSince > 500 then break end
            else
                stillSince = nil
            end
            Wait(0)
        end
    end
    return not l.stopped
end

local function laptopFace(l, heading)
    local ped = l.ped
    TaskAchieveHeading(ped, heading, 800)
    local deadline = GetGameTimer() + 800
    while GetGameTimer() < deadline do
        if l.stopped then return end
        local diff = math.abs(((GetEntityHeading(ped) - heading + 180.0) % 360.0) - 180.0)
        if diff < 8.0 then break end
        Wait(0)
    end
    SetEntityHeading(ped, heading)
end

local function laptopPlay(ped, a, blendIn)
    TaskPlayAnim(ped, a.dict, a.clip, blendIn or 3.0, 2.0, -1, a.flag, 0.0, false, false, false)
end

local function laptopRelease(l)
    for dict in pairs(l.dicts) do RemoveAnimDict(dict) end
    l.dicts = {}
end

-- Keeps the typing loop alive (another script or a bump can stop it); no per-frame work
local function laptopKeepAlive(l)
    CreateThread(function()
        local ped = l.ped
        if l.enter then
            laptopPlay(ped, l.enter)
            local duration = (GetAnimDuration(l.enter.dict, l.enter.clip) or 1.0) * 1000
            local untilAt = GetGameTimer() + math.max(300, math.min(2500, duration - 200))
            while laptop == l and not l.stopped and GetGameTimer() < untilAt do Wait(50) end
        end
        while laptop == l and not l.stopped do
            if not DoesEntityExist(ped) or IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedInAnyVehicle(ped, false) then
                -- never fight the game: no restart and no outro after this
                l.broken = true
                break
            end
            if l.anim and not IsEntityPlayingAnim(ped, l.anim.dict, l.anim.clip, 3) then
                laptopPlay(ped, l.anim, 2.0)
            end
            Wait(300)
        end
    end)
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

function Anim.IsAtLaptop()
    return laptop ~= nil
end

function Anim.IsBusy()
    return active ~= nil or laptop ~= nil
end

-- Blocks while walking to the laptop (a few seconds at most), then returns: true when the ped is
-- at the laptop and typing (also when no typing clip could be loaded), false when busy, invalid or
-- stopped meanwhile. The typing loop keeps running until Anim.StopLaptop().
function Anim.Laptop(entity)
    if active or laptop then return false end
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local ped = cache.ped or PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return false end

    local l = { ped = ped, entity = entity, stopped = false, broken = false, dicts = {} }
    laptop = l

    local stand = GetOffsetFromEntityInWorldCoords(entity, LAPTOP_STAND.x, LAPTOP_STAND.y, 0.0)
    local pedPos = GetEntityCoords(ped)
    local target = vec3(stand.x, stand.y, pedPos.z)
    local heading = headingTo(target, GetEntityCoords(entity))

    if #(pedPos.xy - target.xy) > 0.3 and not laptopWalk(l, target, heading) then
        if laptop == l then laptop = nil end
        return false
    end
    if l.stopped or not DoesEntityExist(entity) then
        if laptop == l then laptop = nil end
        return false
    end
    laptopFace(l, headingTo(GetEntityCoords(ped), GetEntityCoords(entity)))

    if laptopDict(l, A.typeLoop) then
        l.anim, l.enter, l.exit = A.typeLoop, A.typeEnter, A.typeExit
    elseif laptopDict(l, A.typeAlt) then
        l.anim = A.typeAlt
    end

    if l.stopped then
        laptopRelease(l)
        if laptop == l then laptop = nil end
        return false
    end

    laptopKeepAlive(l)
    return true
end

-- Non-blocking: plays the short outro in its own thread, then lets go of the ped
function Anim.StopLaptop()
    local l = laptop
    if not l then return end
    l.stopped = true
    laptop = nil

    CreateThread(function()
        local ped = l.ped
        if not l.broken and l.exit and DoesEntityExist(ped) and not IsEntityDead(ped) and HasAnimDictLoaded(l.exit.dict) then
            laptopPlay(ped, l.exit, 2.0)
            local duration = (GetAnimDuration(l.exit.dict, l.exit.clip) or 1.0) * 1000
            local untilAt = GetGameTimer() + math.max(300, math.min(1800, duration - 150))
            while GetGameTimer() < untilAt and not active and not laptop do Wait(50) end
        end
        -- only stop our own clips; a new sequence or laptop session may already own the ped
        if not active and not laptop and DoesEntityExist(ped) then
            for _, a in ipairs({ A.typeEnter, A.typeLoop, A.typeExit, A.typeAlt }) do
                if IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then StopAnimTask(ped, a.dict, a.clip, 2.0) end
            end
        end
        laptopRelease(l)
    end)
end

function Anim.StopAll()
    local c = active
    if c then
        c.cancelled = true
        cleanup(c)
    end
    active = nil
    Anim.StopLaptop()
end

function Anim.Repair(vehicle, kind, totalMs)
    local build = Repairs[kind]
    if not build then return false end
    return run(vehicle, totalMs, build)
end

function Anim.Swap(vehicle, category, step, totalMs)
    local def = Swaps[category]
    if not def or (step ~= 'remove' and step ~= 'install') then return false end
    return run(vehicle, totalMs, def[step])
end

function Anim.Cosmetic(vehicle, animType, totalMs)
    local build = Cosmetics[animType] or Cosmetics.body
    return run(vehicle, totalMs or (Config.Cosmetic and Config.Cosmetic.animTime) or 6000, build)
end

-- crate = the (local) crate object. Ends standing next to the crate. Cancelled when the crate
-- disappears (collected by someone else, streamed out) or the mechanic walks away.
function Anim.Unpack(crate, totalMs)
    if not crate or crate == 0 or not DoesEntityExist(crate) then return false end
    return run(crate, totalMs or (Config.Shop and Config.Shop.unpackTime) or 8000, buildUnpack, { noFreeze = true })
end

function Anim.Winch(truck, vehicle, totalMs)
    if not truck or not DoesEntityExist(truck) or not vehicle or not DoesEntityExist(vehicle) then return false end

    return run(truck, totalMs or (Config.Towing and Config.Towing.winchTime) or 8000, function(c)
        return {
            {
                label = 'step_winch', w = 1.0,
                fn = function(c, ms, endAt)
                    -- Winch controls on the side of the bed, rear end of the truck
                    local pos = G(c, sideX(c, c.side, 0.45), c.min.y + 1.4)
                    local look = G(c, 0.0, c.min.y + 1.4)
                    if not goTo(c, pos, look) then return false end

                    -- Visual winch cable from the truck's rear to the nearest end of the vehicle
                    pcall(function()
                        if not RopeAreTexturesLoaded() then
                            RopeLoadTextures()
                            local deadline = GetGameTimer() + 2000
                            while not RopeAreTexturesLoaded() and GetGameTimer() < deadline do Wait(0) end
                        end
                        if c.cancelled then return end
                        local p1 = L(c, 0.0, c.min.y + 0.4, 0.2)
                        local vMin, vMax = GetModelDimensions(GetEntityModel(vehicle))
                        local front = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, vMax.y - 0.2, 0.0)
                        local back = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, vMin.y + 0.2, 0.0)
                        local p2 = #(front - p1) < #(back - p1) and front or back
                        local len = math.max(0.5, #(p2 - p1))
                        local rope = AddRope(p1.x, p1.y, p1.z, 0.0, 0.0, 0.0, len, 1, len, 0.5, 0.5, false, false, false, 1.0, false, 0)
                        if rope and DoesRopeExist(rope) then
                            c.ropes[#c.ropes + 1] = rope
                            AttachEntitiesToRope(rope, c.vehicle, vehicle, p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, len, false, false, nil, nil)
                        end
                    end)

                    playAnim(c, A.lever)
                    return true
                end,
            },
        }
    end, { extra = vehicle, distanceRef = truck })
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local c = active
    if c then
        c.cancelled = true
        cleanup(c)
    end
    active = nil

    -- no threads run any more: stop the typing clips right away
    local l = laptop
    laptop = nil
    if l and DoesEntityExist(l.ped) then
        for _, a in ipairs({ A.typeEnter, A.typeLoop, A.typeExit, A.typeAlt }) do
            if IsEntityPlayingAnim(l.ped, a.dict, a.clip, 3) then StopAnimTask(l.ped, a.dict, a.clip, 2.0) end
        end
        laptopRelease(l)
    end
end)
