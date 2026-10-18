-- ap1le_mechanicjob: physical, step-by-step mechanic choreography with native GTA V animations,
-- scenarios and props. Global `Anim` (see CONTRACT.md section 4 and v3 A5-A7, B1-B3).
--
-- Every public sequence blocks (call it inside a thread) and returns true when completed,
-- false when cancelled. Each step shows an ap1le_core progress bar "<step> (i/n)" while the
-- step's choreography runs; the bar has no anim/prop and no icon (this file drives the ped) and
-- ends together with its step. Cancel = ap1le_core's cancel key (X) or anything that makes
-- Ap1le.Progress return false (death, ragdoll, falling ...), plus our own checks (walked away,
-- vehicle/crate gone), which call Ap1le.CancelProgress.
-- Anim.SwapManual is the interactive variant (Config.ManualSwap): the player walks and presses the
-- keys himself; only the timed sub-steps (unbolting ...) show a bar.
-- All exit paths run the same cleanup: props deleted, wheel restored, tasks cleared, doors closed,
-- vehicle lowered, unfrozen and put back on the ground, ropes/particles removed, help text hidden.
--
-- v3 notes
-- * A5 (engine swap cancelled while fetching the hoist): the per-frame monitor measured the ped's
--   distance to the vehicle ORIGIN and cancelled above MaxVehicleDistance + 2 (8 m). The install
--   sequence parked the hoist 1.8 m beyond its retreat point and the ped walked to a spot 0.95 m
--   behind it: bumper + ~6-6.8 m, i.e. 8.2-9.4 m from the origin of a normal car, so the walk to
--   the hoist always cancelled the swap (the removal walk ended at ~7 m and only failed on long
--   vehicles). Fix: every walking step is checked against the distance to the vehicle's FOOTPRINT
--   (bounding box edge), with a leash of MaxVehicleDistance + 1 m, and no planned position is more
--   than ~4.2 m from the body. The server still checks the real distance at finish.
-- * A6 (prop rotations): see the PROP PLACEMENT table below. Poses are computed at runtime from
--   GetModelDimensions on an invisible local "probe" copy of each prop: the rotation that puts the
--   model's thin/long axis where it belongs is found by measuring the rotated axis in world space
--   (so it does not depend on Euler conventions), and floor/hub/pallet positions are computed from
--   the eight rotated bounding-box corners.
-- * A7: no `icon` in any progress bar (UI.Progress also strips it).
-- * B1: the wheel is really removed while it is off (BreakOffVehicleWheel + exact restore), or
--   hidden under the car when the car has damage that SetVehicleFixed would repair for free.
--   The engine mesh cannot be hidden (no native); the engine prop and the open bay stay.
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
    -- hand on a lever: pumping the hoist's hydraulic jack
    lever      = { dict = 'anim@scripted@heist@ig2_hand_lever@male@', clip = 'idle_lever', flag = 49 },
    -- crate looting with a crowbar (Tuners train robbery; the dict also has 'loot_crowbar'/'loot_crate'
    -- companion clips, which confirms it is the crowbar pry). Played on the ped only.
    pry        = { dict = 'anim@scripted@player@mission@trn_ig1_loot@male@', clip = 'loot', flag = 1 },
    -- standing at a keyboard (FIB heist computer). Same clips as the "type4"/"type" emotes of rpemotes.
    typeEnter  = { dict = 'mp_fbi_heist', clip = 'intro', flag = 0 },
    typeLoop   = { dict = 'mp_fbi_heist', clip = 'loop', flag = 1 },
    typeExit   = { dict = 'mp_fbi_heist', clip = 'outro', flag = 0 },
    typeAlt    = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle', flag = 1 },
    -- car wash (B3): standing wipe (rpemotes "clean2" uses this dict with prop_sponge_01) and kneeling
    -- at the bucket (the low "bum wash" scrubs at ground level)
    wipe       = { dict = 'amb@world_human_maid_clean@', clip = 'base', flag = 1 },
    wipeAlt    = { dict = 'amb@world_human_maid_clean@', clip = 'idle_a', flag = 1 },
    soak       = { dict = 'amb@world_human_bum_wash@male@low@idle_a', clip = 'idle_a', flag = 1 },
    -- one-hand carry at the side (rpemotes "toolbox" emote), pick up / set down low
    holdSide   = { dict = 'move_weapon@jerrycan@generic', clip = 'idle', flag = 49 },
    pickLow    = { dict = 'pickup_object', clip = 'pickup_low', flag = 0 },
    putLow     = { dict = 'pickup_object', clip = 'putdown_low', flag = 0 },
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
    wrench  = 'w_me_wrench',
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
    bucket  = 'prop_bucket_01a',
    sponge  = 'prop_sponge_01',
}

local FX = {
    sprayAsset = 'scr_playerlamgraff',
    sprayName = 'scr_lamgraff_paint_spray',
}

local BONE_PH_R_HAND = 28422
local BONE_SKEL_L_HAND = 60309
local BONE_ROOT = 0

---------------------------------------------------------------------------------------------
-- PROP PLACEMENT (A6). Every prop, how it is placed and why.
--
-- prop_engine_hoist  The boom (and the hook) is on the model's local -Y side: jg-mechanic hangs
--                    prop_car_engine_01 at hoist-local (0, -1.1, 1.25), nano-mechanic at
--                    (0, -0.9, 1.4), renzu_projectcars puts the hoist in front of the car with the
--                    car's heading and the engine at the hoist's min.y. v2 turned +Y towards the car,
--                    so the boom pointed AWAY from the car. Now the hoist yaw makes +Y point away
--                    from the car (boom towards the bay) and the hoist origin stands HOOK_REACH (1.1 m)
--                    out from the bay, so the hook is exactly above the engine bone. Bottom on the
--                    floor from its rotated bounding box.
-- prop_car_engine_01 Hangs with its origin at the hook and the hoist's rotation (as jg-mechanic
--                    attaches it: rot 0 relative to the hoist). In the bay its bounding-box centre is
--                    at the engine bone height; on the pallet its lowest corner rests on the pallet top.
-- prop_wheel_01      The thinnest bounding-box axis is the tyre width = the axle. At the hub that
--                    axis is turned along the car's X axis and the box centre is put on the wheel
--                    bone; lying on the floor the axle is vertical and the lowest corner is on the
--                    floor. (v2 assumed the axle was model X and the floor height from the X size.)
-- prop_carjack       Longest axis (the handle) across the car, under the sill, on the floor.
-- prop_tool_box_04   Upright, rotated 90 deg to the car, on the floor. Carried with rpemotes'
--                    "toolbox" placement: bone 28422, (0.396, 0.041, -0.003), rot (-90, 0, 90),
--                    clip move_weapon@jerrycan@generic idle.
-- w_me_wrench        Hand tool (replaces imp_prop_impact_driver_01a, whose grip position is not
--                    documented anywhere and showed floating/rotated in the hand). Weapon models are
--                    authored for PH_R_Hand (28422) with zero offset/rotation (rpemotes attaches
--                    w_me_nightstick there with all zeros). Same for w_me_crowbar.
-- prop_cs_spray_can  28422, (0, 0, 0.07), rot 0 (rpemotes "tag").
-- prop_sponge_01     28422, (0, 0, -0.01), rot (90, 0, 0) (rpemotes "clean"/"clean2").
-- prop_bucket_01a    Floor: upright on the floor. Carried like the toolbox (same bone and rotation;
--                    the x offset is the bucket's own height from GetModelDimensions, so the hand is
--                    at the handle).
-- hei_prop_heist_box 60309, (0.025, 0.08, 0.255), rot (-145, 290, 0) (rpemotes "box").
-- caliper            Thinnest axis along the axle at the hub (box centre 12 cm outside the hub),
--                    thinnest axis vertical when it lies on the floor.
-- strut compressor   Upright on the floor.
-- gearbox            Longest axis along the car (gearboxes sit lengthwise), on the floor under the
--                    car, 22 cm higher when mounted.
-- car panel          Thinnest axis across the car when it stands against the side, vertical when it
--                    lies on the floor or on the pallet, along the ped's forward when carried.
-- carburettor        Upright; in the bay, on the floor or carried in front of the chest.
-- pallet             Upright on the floor; its top (from the rotated box) is the surface for parts.
---------------------------------------------------------------------------------------------

local HOIST_HOOK = vec3(0.0, -1.1, 1.25)   -- hoist-local position of the hook (see above)
local HOOK_REACH = -HOIST_HOOK.y           -- horizontal distance hoist origin -> hook

-- Attachments copied from verified emotes (AttachEntityToEntity rotation order 1, as rpemotes)
local GRIP = {
    wrench  = { model = P.wrench,  bone = BONE_PH_R_HAND, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
    crowbar = { model = P.crowbar, bone = BONE_PH_R_HAND, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
    spray   = { model = P.spray,   bone = BONE_PH_R_HAND, pos = vec3(0.0, 0.0, 0.07), rot = vec3(0.0, 0.0, 0.0) },
    sponge  = { model = P.sponge,  bone = BONE_PH_R_HAND, pos = vec3(0.0, 0.0, -0.01), rot = vec3(90.0, 0.0, 0.0) },
    toolbox = { model = P.toolbox, bone = BONE_PH_R_HAND, pos = vec3(0.396, 0.041, -0.003), rot = vec3(-90.0, 0.0, 90.0) },
    box     = { model = P.box,     bone = BONE_SKEL_L_HAND, pos = vec3(0.025, 0.08, 0.255), rot = vec3(-145.0, 290.0, 0.0) },
}

-- Disabled for the whole sequence (also in the frames between two progress bars). The bars
-- disable move/car/combat themselves; 23 (INPUT_ENTER) would pull the ped out of its task.
-- The cancel key belongs to ap1le_core (X by default), so no cancel control is captured here.
local DISABLED_CONTROLS = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 44, 140, 141, 142, 143, 257, 263, 264 }

-- index = CWheel index for BreakOffVehicleWheel / SetVehicleWheelXOffset (0 lf, 1 rf, 2 lr, 3 rr,
-- the order the CFX docs use for the front track example); tyre = id for SetVehicleTyreBurst
local WHEELS = {
    { bone = 'wheel_lf', tyre = 0, index = 0 },
    { bone = 'wheel_rf', tyre = 1, index = 1 },
    { bone = 'wheel_lr', tyre = 4, index = 2 },
    { bone = 'wheel_rr', tyre = 5, index = 3 },
}

local UP = vec3(0.0, 0.0, 1.0)

---------------------------------------------------------------------------------------------
-- Small math helpers
---------------------------------------------------------------------------------------------

local function smooth(t) return t * t * (3.0 - 2.0 * t) end
local function lerp(a, b, t) return a + (b - a) * t end
-- lerp with a small hop, so a prop that turns over while it moves never dips through the floor
local function arc(a, b, t, h) return a + (b - a) * t + vec3(0.0, 0.0, h * math.sin(math.pi * t)) end
local function sign(x) return x < 0.0 and -1.0 or 1.0 end
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function dot2(a, b) return a.x * b.x + a.y * b.y end

-- Euler lerp with the heading taking the short way round
local function lerpRot(a, b, t)
    local dz = ((b.z - a.z + 180.0) % 360.0) - 180.0
    return vec3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + dz * t)
end

local function headingTo(from, to)
    return GetHeadingFromVector_2d(to.x - from.x, to.y - from.y)
end

-- Distance from point p to the segment a-b (2D)
local function distToSegment2(p, a, b)
    local abx, aby = b.x - a.x, b.y - a.y
    local len2 = abx * abx + aby * aby
    local t = len2 > 0.0 and clamp(((p.x - a.x) * abx + (p.y - a.y) * aby) / len2, 0.0, 1.0) or 0.0
    local dx, dy = p.x - (a.x + abx * t), p.y - (a.y + aby * t)
    return math.sqrt(dx * dx + dy * dy)
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

-- Safe locale lookup (a missing key must never break a running sequence)
local function T(key, ...)
    local ok, text = pcall(locale, key, ...)
    if ok and type(text) == 'string' then return text end
    return key
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
        probes = {},
        dimsCache = {},
        carryCache = {},
        dicts = {},
        models = {},
        ptfxAssets = {},
        ptfx = {},
        ropes = {},
        doors = {},
        frozen = {},
        markers = {},
        lift = nil,
        anim = nil,
        scenario = false,
        lying = false,
        cancelled = false,
        completed = false,
        cleaned = false,
        stepLabel = '',
        stepIndex = 0,
        stepCount = 0,
        stepStart = GetGameTimer(),
        stepMs = 1,
        baseMs = 0,
    }

    -- Unit axes of the vehicle in world space
    local o = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, 0.0)
    c.right = GetOffsetFromEntityInWorldCoords(vehicle, 1.0, 0.0, 0.0) - o
    c.fwd = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 1.0, 0.0) - o

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

local function dims(c, name)
    local cached = c.dimsCache[name]
    if cached then return cached[1], cached[2] end
    local hash = loadModel(c, name)
    local min, max
    if hash then min, max = GetModelDimensions(hash) end
    if not min then return vec3(-0.25, -0.25, 0.0), vec3(0.25, 0.25, 0.5) end
    c.dimsCache[name] = { min, max }
    return min, max
end

-- Invisible local copy of a model, used only to measure rotated bounding boxes. Never visible,
-- never networked, never touching the props the players see.
local function probe(c, name)
    local hash = loadModel(c, name)
    if not hash then return nil end
    local p = c.probes[hash]
    if p and DoesEntityExist(p) then return p end
    local base = GetEntityCoords(c.vehicle)
    p = CreateObjectNoOffset(hash, base.x, base.y, base.z - 50.0, false, false, false)
    if not p or p == 0 then return nil end
    SetEntityVisible(p, false, false)
    SetEntityCollision(p, false, false)
    FreezeEntityPosition(p, true)
    c.probes[hash] = p
    return p
end

-- Rotated bounding box of a model, relative to its origin: lowest/highest z, y extent and the
-- box centre. Measured from the eight corners of GetModelDimensions on the probe.
local function measure(c, name, rot)
    local min, max = dims(c, name)
    local p = probe(c, name)
    if not p then
        return { low = min.z, high = max.z, minY = min.y, maxY = max.y, ctr = (min + max) * 0.5 }
    end
    SetEntityRotation(p, rot.x, rot.y, rot.z, 2, true)
    local o = GetEntityCoords(p)
    local low, high, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for i = 0, 7 do
        local w = GetOffsetFromEntityInWorldCoords(p,
            (i & 1) == 0 and min.x or max.x,
            (i & 2) == 0 and min.y or max.y,
            (i & 4) == 0 and min.z or max.z)
        if w.z < low then low = w.z end
        if w.z > high then high = w.z end
        if w.y < minY then minY = w.y end
        if w.y > maxY then maxY = w.y end
    end
    local ctr = GetOffsetFromEntityInWorldCoords(p, (min.x + max.x) * 0.5, (min.y + max.y) * 0.5, (min.z + max.z) * 0.5)
    return { low = low - o.z, high = high - o.z, minY = minY - o.y, maxY = maxY - o.y, ctr = ctr - o }
end

-- Index (1 x, 2 y, 3 z) of the model's thinnest or longest bounding-box axis
local function axisIndex(min, max, which)
    local s = { max.x - min.x, max.y - min.y, max.z - min.z }
    local best = 1
    for i = 2, 3 do
        if (which == 'thin' and s[i] < s[best]) or (which == 'long' and s[i] > s[best]) then best = i end
    end
    return best
end

-- (pitch, roll, extra yaw) candidates; the first one that puts the wanted axis along the target wins
local ROT_CANDIDATES = { vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 90.0), vec3(0.0, 90.0, 0.0), vec3(90.0, 0.0, 0.0) }

-- Rotation (order 2, as SetEntityRotation below) that turns the model's thin/long axis along the
-- world direction `target`, with `heading` as the base yaw. Verified by measuring the rotated axis on
-- the probe, so it holds whatever the model's own axes are.
local function alignRot(c, name, which, target, heading)
    local min, max = dims(c, name)
    local idx = axisIndex(min, max, which)
    local axis = idx == 1 and vec3(1.0, 0.0, 0.0) or (idx == 2 and vec3(0.0, 1.0, 0.0) or UP)
    local p = probe(c, name)
    if not p then return vec3(0.0, 0.0, heading) end
    for _, k in ipairs(ROT_CANDIDATES) do
        local rot = vec3(k.x, k.y, heading + k.z)
        SetEntityRotation(p, rot.x, rot.y, rot.z, 2, true)
        local o = GetEntityCoords(p)
        local w = GetOffsetFromEntityInWorldCoords(p, axis.x, axis.y, axis.z) - o
        if math.abs(w.x * target.x + w.y * target.y + w.z * target.z) > 0.9 then return rot end
    end
    return vec3(0.0, 0.0, heading)
end

-- Where the origin of `name` (rotated by `rot`) must be so that:
--   'floor'         the box centre is above anchor.xy and the lowest corner is on the floor
--   'floorOrigin'   the origin is at anchor.xy and the lowest corner is on the floor
--   'surface'       like 'floor', on a surface at height surfaceZ
--   'surfaceOrigin' like 'floorOrigin', on a surface at height surfaceZ
--   'center'        the box centre is at anchor
--   'centerZOrigin' the origin is at anchor.xy and the box centre at anchor.z
local function pose(c, name, rot, anchor, mode, surfaceZ)
    local m = measure(c, name, rot)
    local keep = mode == 'floorOrigin' or mode == 'surfaceOrigin' or mode == 'centerZOrigin'
    local x = keep and anchor.x or (anchor.x - m.ctr.x)
    local y = keep and anchor.y or (anchor.y - m.ctr.y)
    local z
    if mode == 'center' or mode == 'centerZOrigin' then
        z = anchor.z - m.ctr.z
    elseif mode == 'surface' or mode == 'surfaceOrigin' then
        z = (surfaceZ or c.groundZ) - m.low
    else
        z = c.groundZ - m.low
    end
    return vec3(x, y, z)
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
    SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z, false, false, false)
    c.props[#c.props + 1] = obj
    return obj
end

-- Spawn a prop upright (yaw only) standing on the floor, box centred above `xy`
local function spawnGround(c, name, xy, heading)
    local rot = vec3(0.0, 0.0, heading or c.heading)
    return spawnProp(c, name, pose(c, name, rot, xy, 'floor'), rot)
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

local function attachTo(c, obj, boneId, off, rot, order)
    if not obj or c.cancelled then return end
    AttachEntityToEntity(obj, c.ped, GetPedBoneIndex(c.ped, boneId), off.x, off.y, off.z, rot.x, rot.y, rot.z,
        true, true, false, true, order or 1, true)
end

local function attachGrip(c, obj, grip)
    attachTo(c, obj, grip.bone, grip.pos, grip.rot, 1)
end

-- Tool in the hand (see GRIP)
local function holdTool(c, gripName)
    local grip = GRIP[gripName]
    if not grip then return nil end
    local obj = spawnProp(c, grip.model, GetEntityCoords(c.ped), nil)
    attachGrip(c, obj, grip)
    return obj
end

-- Bucket in the right hand, toolbox-style: hand at the handle (the bucket's own height)
local function bucketGrip(c)
    local _, max = dims(c, P.bucket)
    return { bone = BONE_PH_R_HAND, pos = vec3(math.max(0.15, max.z - 0.02), 0.041, -0.003), rot = vec3(-90.0, 0.0, 90.0) }
end

-- Carried part in front of the chest (with the box carry upper-body clip): box centre 22 cm plus
-- half its depth in front of the root bone, 8 cm up. Panels are held flat against the chest.
local function carryPose(c, name)
    local cached = c.carryCache[name]
    if cached then return cached end
    local rot = name == P.panel and alignRot(c, name, 'thin', vec3(0.0, 1.0, 0.0), 0.0) or vec3(0.0, 0.0, 0.0)
    local p = probe(c, name)
    local result
    if p then
        local m = measure(c, name, rot)
        local depth = m.maxY - m.minY
        local o = GetEntityCoords(p)
        local origin = pose(c, name, rot, o + vec3(0.0, 0.22 + depth * 0.5, 0.08), 'center')
        result = { off = origin - o, rot = rot }
    else
        result = { off = vec3(0.0, 0.42, 0.08), rot = rot }
    end
    c.carryCache[name] = result
    return result
end

local function carry(c, obj, name)
    local cp = carryPose(c, name)
    attachTo(c, obj, BONE_ROOT, cp.off, cp.rot, 2)
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
    local ours = {}
    for _, obj in ipairs(c.props) do ours[obj] = true end
    for _, obj in ipairs(GetGamePool('CObject')) do
        if not ours[obj] and hashes[GetEntityModel(obj)] and IsEntityAttachedToEntity(obj, c.ped) then
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
        if carrying then playAnim(c, carrying == true and A.carry or carrying) end

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
        if carrying then playAnim(c, carrying == true and A.carry or carrying) end
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

-- Kneel at the ped's position, bring `obj` (model `name`) up to the chest and attach it
local function pickUp(c, obj, name)
    if not obj then return not c.cancelled end
    playAnim(c, A.kneelDown)
    if not sleep(c, 800) then return false end
    local cp = carryPose(c, name)
    local from = GetEntityCoords(obj)
    if not tween(c, 350, function(t)
        moveProp(obj, lerp(from, GetOffsetFromEntityInWorldCoords(c.ped, cp.off.x, cp.off.y, cp.off.z), t))
    end) then return false end
    carry(c, obj, name)
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
        local fromRot = GetEntityRotation(obj, 2)
        if not tween(c, 300, function(t)
            moveProp(obj, lerp(from, pos, t), rot and lerpRot(fromRot, rot, t) or nil)
        end) then return false end
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
    if c.lift then return c.lift end
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
-- B1: the wheel is really gone while it is off
--
-- GTA has no "hide wheel" native. BreakOffVehicleWheel(deleteWheel = true) removes it for real, but
-- the only way to get a broken-off wheel back is SetVehicleFixed, which also repairs dents, lights,
-- bumpers, doors, windows, tyres and health. So before breaking it off we take a snapshot:
--  * values that can be put back exactly afterwards: engine/body/petrol tank health, wheel health,
--    burst tyres (and whether on the rim), dirt;
--  * things that cannot: deformation (sampled with GetVehicleDeformationAtPos), broken-off bumpers,
--    damaged headlights, damaged doors, broken windows, a dead engine (SetVehicleFixed does not fix it).
-- Only when the second list is empty ("pristine") the wheel is broken off and later restored with
-- SetVehicleFixed + the exact snapshot values, so the car ends exactly as it came in. Otherwise the
-- wheel is pulled in under the car every frame with SetVehicleWheelXOffset (visual only, nothing is
-- repaired) and the offset is put back afterwards.
---------------------------------------------------------------------------------------------

local TYRE_IDS = { 0, 1, 2, 3, 4, 5, 45, 47 }
local WINDOW_BONES = {
    [0] = 'window_lf', [1] = 'window_rf', [2] = 'window_lr', [3] = 'window_rr',
    [4] = 'window_lm', [5] = 'window_rm', [6] = 'windscreen', [7] = 'windscreen_r',
}
local DEFORM_LIMIT = 0.03

local function isDeformed(c)
    local veh = c.vehicle
    local xs = { c.min.x * 0.8, 0.0, c.max.x * 0.8 }
    local ys = { c.min.y * 0.85, c.min.y * 0.4, 0.0, c.max.y * 0.4, c.max.y * 0.85 }
    local zs = { c.min.z * 0.4, c.max.z * 0.4 }
    for _, x in ipairs(xs) do
        for _, y in ipairs(ys) do
            for _, z in ipairs(zs) do
                local d = GetVehicleDeformationAtPos(veh, x + 0.0, y + 0.0, z + 0.0)
                if d and #d > DEFORM_LIMIT then return true end
            end
        end
    end
    return false
end

local function damageSnapshot(c)
    local veh = c.vehicle
    local s = {
        engine = GetVehicleEngineHealth(veh),
        body = GetVehicleBodyHealth(veh),
        tank = GetVehiclePetrolTankHealth(veh),
        dirt = GetVehicleDirtLevel(veh),
        tyres = {},
        wheels = {},
    }
    for _, id in ipairs(TYRE_IDS) do
        if IsVehicleTyreBurst(veh, id, false) then
            s.tyres[#s.tyres + 1] = { id = id, rim = IsVehicleTyreBurst(veh, id, true) }
        end
    end
    for i = 0, GetVehicleNumberOfWheels(veh) - 1 do s.wheels[i] = GetVehicleWheelHealth(veh, i) end

    local pristine = s.engine > 0.0
    if pristine and (IsVehicleBumperBrokenOff(veh, true) or IsVehicleBumperBrokenOff(veh, false)) then pristine = false end
    if pristine and (GetIsLeftVehicleHeadlightDamaged(veh) or GetIsRightVehicleHeadlightDamaged(veh)) then pristine = false end
    if pristine then
        for door = 0, 5 do
            if GetIsDoorValid(veh, door) and IsVehicleDoorDamaged(veh, door) then pristine = false break end
        end
    end
    if pristine then
        for index, bone in pairs(WINDOW_BONES) do
            if GetEntityBoneIndexByName(veh, bone) ~= -1 and not IsVehicleWindowIntact(veh, index) then pristine = false break end
        end
    end
    if pristine and isDeformed(c) then pristine = false end
    s.pristine = pristine
    return s
end

local function applySnapshot(veh, s)
    SetVehicleFixed(veh)
    SetVehicleEngineHealth(veh, s.engine + 0.0)
    SetVehicleBodyHealth(veh, s.body + 0.0)
    SetVehiclePetrolTankHealth(veh, s.tank + 0.0)
    for i, health in pairs(s.wheels) do SetVehicleWheelHealth(veh, i, health + 0.0) end
    for _, t in ipairs(s.tyres) do SetVehicleTyreBurst(veh, t.id, t.rim, 1000.0) end
    SetVehicleDirtLevel(veh, s.dirt + 0.0)
end

local function hideWheel(c, wheel)
    local veh = c.vehicle
    if c.hiddenWheel or not wheel or not wheel.index or not DoesEntityExist(veh) then return end
    if GetVehicleNumberOfWheels(veh) ~= 4 then return end -- bikes, trikes, 6-wheelers: keep it on

    local idx = wheel.index
    local xo = GetVehicleWheelXOffset(veh, idx)
    -- the offset is the wheel's lateral position; its sign proves the index is the wheel we mean
    local absolute = math.abs(xo) > 0.2
    if absolute and sign(xo) ~= sign(wheel.localPos.x) then return end

    requestControl(veh)
    local snap = damageSnapshot(c)
    if snap.pristine then
        BreakOffVehicleWheel(veh, idx, false, true, false, false)
        c.hiddenWheel = { mode = 'broken', index = idx, snap = snap }
        return
    end

    -- Damaged car: visual only. Pull the wheel in under the body until it is put back.
    local h = { mode = 'offset', index = idx, orig = xo, target = absolute and sign(xo) * 0.05 or (xo - wheel.localPos.x * 0.95) }
    c.hiddenWheel = h
    CreateThread(function()
        while c.hiddenWheel == h and DoesEntityExist(veh) do
            SetVehicleWheelXOffset(veh, idx, h.target + 0.0)
            Wait(0)
        end
    end)
end

local function restoreWheel(c)
    local h = c.hiddenWheel
    if not h then return end
    c.hiddenWheel = nil
    local veh = c.vehicle
    if not DoesEntityExist(veh) then return end
    requestControl(veh)
    if h.mode == 'broken' then
        applySnapshot(veh, h.snap)
        if IsVehicleWheelBrokenOff and IsVehicleWheelBrokenOff(veh, h.index) then
            print('[ap1le_mechanicjob] wheel restore: the wheel is still broken off after SetVehicleFixed')
        end
    else
        SetVehicleWheelXOffset(veh, h.index, h.orig + 0.0)
    end
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

    if c.textShown then pcall(UI.HideTextUI) end
    c.markers = {}

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
        for _, p in pairs(c.probes) do
            if DoesEntityExist(p) then DeleteEntity(p) end
        end
        c.probes = {}
    end)

    -- The wheel goes back on before the car comes down (a cancelled swap never leaves it off)
    pcall(restoreWheel, c)

    -- A cancelled wash puts the dirt back: nothing is done for free
    pcall(function()
        if c.washFrom and not c.completed and DoesEntityExist(c.vehicle) then
            SetVehicleDirtLevel(c.vehicle, c.washFrom + 0.0)
        end
    end)

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
--  * CancelProgress only flags the running bar; that call then returns false a frame later;
--  * `disable.move` only disables the player's controls, AI tasks such as TaskGoStraightToCoord
--    keep walking (so walking steps are not what cancelled the v2 engine swap; see A5 at the top).
-- Every bar is a small object owned by its step (`c.bar`). A bar that is no longer the current
-- one, or that we released ourselves, can never cancel the sequence when it resolves false.
-- No `icon` (A7).
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

local function startBar(c, label, ms)
    local bar = { running = false, done = false, ok = nil, stepDone = false, released = false, filler = false }
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
            bar.filler = true
        end
        bar.running = false
        bar.done = true
    end)

    return bar
end

-- The step's work is done: let its bar run out so both end together. A filler bar (the step
-- overran) is released at once instead of making the next step wait for it.
local function finishBar(c, bar, deadline)
    bar.stepDone = true
    if bar.filler and bar.running then
        bar.released = true
        UI.CancelProgress()
    end
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
-- Distance leash (A5) and the per-frame monitor (only alive while a sequence runs)
---------------------------------------------------------------------------------------------

-- How far (m) the ped may be from the EDGE of the vehicle (or crate / truck) before the sequence is
-- cancelled. Every position a sequence walks to is within ~4.2 m of the body.
local function leash()
    return (Config.MaxVehicleDistance or 6.0) + 1.0
end

-- 2D distance from `pos` to the entity's bounding-box footprint (0 inside it)
local function footprintDistance(entity, min, max, pos)
    local l = GetOffsetFromEntityGivenWorldCoords(entity, pos.x, pos.y, pos.z)
    local dx = math.max(min.x - l.x, 0.0, l.x - max.x)
    local dy = math.max(min.y - l.y, 0.0, l.y - max.y)
    return math.sqrt(dx * dx + dy * dy)
end

local function setRef(c, ref)
    c.ref = ref or c.vehicle
    if c.ref == c.vehicle then
        c.refMin, c.refMax = c.min, c.max
    else
        c.refMin, c.refMax = GetModelDimensions(GetEntityModel(c.ref))
    end
end

-- true when the sequence must stop (ped dead, entities gone, too far)
local function lostContact(c)
    local ped = c.ped
    if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then return true end
    if not DoesEntityExist(c.vehicle) or (c.extra and not DoesEntityExist(c.extra)) then return true end
    if not DoesEntityExist(c.ref) then return true end
    if footprintDistance(c.ref, c.refMin, c.refMax, GetEntityCoords(ped)) > leash() then
        c.tooFar = true
        return true
    end
    return false
end

local function monitor(c)
    CreateThread(function()
        while active == c and not c.cancelled do
            for i = 1, #DISABLED_CONTROLS do DisableControlAction(0, DISABLED_CONTROLS[i], true) end
            if lostContact(c) then c.cancelled = true end
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
        c.stepLabel = T(s.label)
        c.stepStart = started
        c.stepMs = math.max(1, ms)
        c.baseMs = acc

        local label = ('%s (%d/%d)'):format(c.stepLabel, i, c.stepCount)
        local bar = startBar(c, label, ms)

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
    setRef(c, opts.distanceRef)
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
    c.completed = completed
    cleanup(c)
    return completed
end

---------------------------------------------------------------------------------------------
-- Building blocks: engine bay and the engine hoist
---------------------------------------------------------------------------------------------

-- Engine bay layout. dir = 1 front engine, -1 rear engine (lid = boot).
-- The hoist moves on one line through the bay along the car's axis: `s` = distance (m) of the hoist
-- origin from the bay, outwards. s = HOOK_REACH puts the hook above the bay; at sRetreat the hook is
-- above the pallet, 0.75 m clear of the bumper; the hoist waits at sPark.
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
    local away = c.fwd * dir
    local clearY = edge + dir * 0.75
    local inset = math.abs(edge - bay.y)
    local layout = {
        dir = dir,
        door = dir > 0 and 4 or 5,
        bayLocal = bay,
        bayWorld = L(c, bay.x, bay.y, bay.z),
        bayFloor = G(c, bay.x, bay.y),
        edge = edge,
        away = away,
        lateral = c.right,
        -- beside the front corner (not on the hoist line), facing the bay
        frontPos = G(c, side * clamp(c.halfW * 0.6, 0.5, 0.85), edge + dir * 0.55),
        sidePos = G(c, sideX(c, side, 0.45), bay.y),
        benchPos = G(c, sideX(c, side, 1.4), edge - dir * 0.2),
        palletPos = G(c, bay.x, clearY),
        -- the hook reaches 1.1 m in front of the mast and the mast must stay 30 cm outside the body:
        -- on cars whose engine sits deeper the block hangs a bit in front of the engine bone
        sFinal = math.max(HOOK_REACH, inset + 0.3),
        sRetreat = HOOK_REACH + math.abs(clearY - bay.y),
        hoistYaw = GetHeadingFromVector_2d(away.x, away.y), -- hoist +Y away from the car, boom in
    }
    layout.sPark = layout.sRetreat + 0.9
    -- where the block sits in the bay: below the hook at sFinal, at the engine bone's height
    local hookBay = layout.bayWorld + away * (layout.sFinal - HOOK_REACH)
    layout.blockBay = vec3(hookBay.x, hookBay.y, layout.bayWorld.z)
    c.bay = layout
    return layout
end

local function hoistAt(c, s)
    local bay = bayLayout(c)
    local p = bay.bayFloor + bay.away * s
    return vec3(p.x, p.y, c.groundZ)
end

-- Where the mechanic stands to work the hoist's pump: beside the mast
local function crankPos(c, s)
    local bay = bayLayout(c)
    local p = hoistAt(c, s) + bay.lateral * (c.side * 0.85)
    return vec3(p.x, p.y, c.groundZ)
end

-- Distance between the hoist origin and the handle the ped pushes (model +Y end)
local function hoistBehind(c)
    local _, max = dims(c, P.hoist)
    return clamp(max.y + 0.5, 1.2, 1.6)
end

-- Heights and rotations shared by the engine steps (computed once per sequence)
local function engineSetup(c)
    if c.engineReady then return end
    local bay = bayLayout(c)
    c.hoistRot = vec3(0.0, 0.0, bay.hoistYaw)
    c.blockRot = vec3(0.0, 0.0, bay.hoistYaw)
    c.palletRot = vec3(0.0, 0.0, c.heading)
    c.palletPose = pose(c, P.pallet, c.palletRot, bay.palletPos, 'floor')
    c.palletTop = c.palletPose.z + measure(c, P.pallet, c.palletRot).high
    c.hoistZ = pose(c, P.hoist, c.hoistRot, bay.bayFloor, 'floorOrigin').z

    local hookZ = c.hoistZ + HOIST_HOOK.z
    local bayZ = pose(c, P.engine, c.blockRot, bay.blockBay, 'centerZOrigin').z
    local palletZ = pose(c, P.engine, c.blockRot, bay.palletPos, 'surfaceOrigin', c.palletTop).z
    -- hanging height of the block's origin; never below what clears the bay and the pallet
    c.liftZ = math.max(hookZ, bayZ + 0.5, palletZ + 0.3)
    c.dropBay = c.liftZ - bayZ
    c.dropPallet = c.liftZ - palletZ
    c.drop = 0.0
    c.hanging = false
    c.engineReady = true
end

-- Move the hoist to `s`; a hanging block follows the hook
local function setHoist(c, s)
    c.hoistS = s
    if not c.hoist then return end
    local p = hoistAt(c, s)
    moveProp(c.hoist, vec3(p.x, p.y, c.hoistZ), c.hoistRot)
    if c.block and c.hanging then
        local hook = GetOffsetFromEntityInWorldCoords(c.hoist, HOIST_HOOK.x, HOIST_HOOK.y, HOIST_HOOK.z)
        moveProp(c.block, vec3(hook.x, hook.y, c.liftZ - c.drop), c.blockRot)
    end
end

local function setDrop(c, d)
    c.drop = d
    setHoist(c, c.hoistS or HOOK_REACH)
end

local function spawnHoist(c, s)
    engineSetup(c)
    if c.hoist then return c.hoist end
    local p = hoistAt(c, s)
    c.hoist = spawnProp(c, P.hoist, vec3(p.x, p.y, c.hoistZ), c.hoistRot)
    setHoist(c, s)
    return c.hoist
end

local function spawnPallet(c)
    engineSetup(c)
    c.pallet = c.pallet or spawnProp(c, P.pallet, c.palletPose, c.palletRot)
    return c.pallet
end

-- The block in the bay (hanging from the hook at dropBay) or on the pallet
local function spawnBlock(c, where)
    engineSetup(c)
    if c.block then return c.block end
    local bay = bayLayout(c)
    local pos = where == 'bay' and pose(c, P.engine, c.blockRot, bay.blockBay, 'centerZOrigin')
        or pose(c, P.engine, c.blockRot, bay.palletPos, 'surfaceOrigin', c.palletTop)
    c.block = spawnProp(c, P.engine, pos, c.blockRot)
    c.drop = where == 'bay' and c.dropBay or c.dropPallet
    return c.block
end

-- Walk to `target`, going round the point `avoid` (e.g. the parked hoist) when the straight line
-- would pass through it
local function goAround(c, avoid, target, faceTo, carrying)
    local pos = GetEntityCoords(c.ped)
    if avoid and distToSegment2(avoid, pos, target) < 1.0 then
        local bay = bayLayout(c)
        local via = avoid + bay.lateral * (c.side * 1.3)
        if not goTo(c, vec3(via.x, via.y, c.groundZ), nil) then return false end
    end
    return goTo(c, target, faceTo, carrying)
end

-- Auto: walk to the hoist handle and push the hoist from s0 to s1 (towards the car)
local function pushHoist(c, s0, s1)
    local behind = hoistBehind(c)
    local bay = bayLayout(c)
    local handle0, handle1 = hoistAt(c, s0 + behind), hoistAt(c, s1 + behind)
    if not goAround(c, hoistAt(c, s0), handle0, hoistAt(c, s1)) then return false end

    TaskGoStraightToCoord(c.ped, handle1.x, handle1.y, handle1.z, 0.8, -1, bay.hoistYaw + 180.0, 0.2)
    playAnim(c, A.carry)

    local lo, hi = math.min(s0, s1), math.max(s0, s1)
    local deadline = GetGameTimer() + 10000
    while true do
        if c.cancelled then return false end
        -- project the ped onto the line; the hoist rolls just in front of the hands
        local sp = dot2(GetEntityCoords(c.ped) - bay.bayFloor, bay.away)
        local s = clamp(sp - behind, lo, hi)
        setHoist(c, s)
        if math.abs(s - s1) < 0.06 or GetGameTimer() > deadline then break end
        Wait(0)
    end
    setHoist(c, s1)
    stopTask(c)
    return not c.cancelled
end

-- Auto: walk beside the hoist (hand on the mast) and roll it from s0 out to s1
local function guideHoist(c, s0, s1)
    local bay = bayLayout(c)
    local start, finish = crankPos(c, s0), crankPos(c, s1)
    if not goTo(c, start, finish) then return false end
    TaskGoStraightToCoord(c.ped, finish.x, finish.y, finish.z, 0.6, -1, headingTo(start, finish), 0.2)

    local lo, hi = math.min(s0, s1), math.max(s0, s1)
    local deadline = GetGameTimer() + 10000
    while true do
        if c.cancelled then return false end
        local s = clamp(dot2(GetEntityCoords(c.ped) - bay.bayFloor, bay.away), lo, hi)
        setHoist(c, s)
        if math.abs(s - s1) < 0.06 or GetGameTimer() > deadline then break end
        Wait(0)
    end
    setHoist(c, s1)
    stopTask(c)
    return face(c, hoistAt(c, s1))
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

-- Leaning into the bay, optionally with the wrench
local function stepBayWork(label, w, withTool, onEnd)
    return {
        label = label, w = w or 1.2,
        fn = function(c, ms, endAt)
            local bay = bayLayout(c)
            if not c.toolbox then
                c.toolbox = spawnGround(c, P.toolbox, bay.benchPos, c.heading + 90.0)
            end
            if not goTo(c, bay.sidePos, bay.bayWorld) then return false end
            local tool = withTool and holdTool(c, 'wrench') or nil
            playAnim(c, withTool and A.bayLean or A.standWork)
            local ok = waitUntil(c, endAt - 150)
            deleteProp(c, tool)
            if ok and onEnd then onEnd(c) end
            return ok
        end,
    }
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
            list[#list + 1] = { bone = w.bone, boneIndex = idx, tyre = w.tyre, index = w.index, localPos = lp, dist = #(pedPos - wp) }
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

-- Wheel prop poses: on the hub (axle along the car's X), pulled out, lying on the floor
local function wheelPoses(c, wheel)
    local upright = alignRot(c, P.wheel, 'thin', c.right, c.heading)
    local lying = alignRot(c, P.wheel, 'thin', UP, c.heading)
    local atHub = pose(c, P.wheel, upright, hubWorld(c, wheel), 'center')
    return {
        upright = upright,
        lying = lying,
        hub = atHub,
        out = atHub + c.right * (wheel.side * 0.35),
        floor = pose(c, P.wheel, lying, wheel.groundPos, 'floor'),
    }
end

-- Wheel off the hub onto the floor: the prop replaces the real wheel in the same frame (B1)
local function wheelOut(c, wheel, ms)
    local wp = wheelPoses(c, wheel)
    local obj = spawnProp(c, P.wheel, wp.hub, wp.upright)
    if not obj then return not c.cancelled end
    hideWheel(c, wheel)
    c.wheelProp = obj
    if not tween(c, ms * 0.35, function(t) moveProp(obj, lerp(wp.hub, wp.out, t), wp.upright) end) then return false end
    if not tween(c, ms * 0.65, function(t)
        moveProp(obj, arc(wp.out, wp.floor, t, 0.18), lerpRot(wp.upright, wp.lying, t))
    end) then return false end
    moveProp(obj, wp.floor, wp.lying)
    return true
end

-- Wheel from the floor back onto the hub; the real wheel comes back as the prop disappears
local function wheelIn(c, wheel, ms)
    local wp = wheelPoses(c, wheel)
    local obj = c.wheelProp or spawnProp(c, P.wheel, wp.floor, wp.lying)
    if obj then
        if not tween(c, ms * 0.6, function(t)
            moveProp(obj, arc(wp.floor, wp.out, t, 0.18), lerpRot(wp.lying, wp.upright, t))
        end) then return false end
        if not tween(c, ms * 0.4, function(t) moveProp(obj, lerp(wp.out, wp.hub, t), wp.upright) end) then return false end
    end
    restoreWheel(c)
    deleteProp(c, obj)
    c.wheelProp = nil
    return not c.cancelled
end

local function kneelAt(c, wheel, anim)
    if not goTo(c, wheel.kneelPos, hubWorld(c, wheel)) then return false end
    return playAnim(c, anim or A.crouchWork)
end

local function spawnJack(c, at)
    if c.jack then return c.jack end
    local rot = alignRot(c, P.jack, 'long', c.right, c.heading)
    c.jack = spawnProp(c, P.jack, pose(c, P.jack, rot, at, 'floor'), rot)
    return c.jack
end

local function stepJackUp(wheelMode, uniform)
    return {
        label = 'step_jack_up', w = 1.0,
        fn = function(c, ms, endAt)
            c.wheel = c.wheel or pickWheel(c, wheelMode)
            local wheel = c.wheel
            if not kneelAt(c, wheel, A.crouchWork) then return false end
            spawnJack(c, wheel.jackPos)
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
            local tool = holdTool(c, 'wrench')
            local total = remaining(endAt, 2000)
            if not sleep(c, total * 0.5) then return false end
            deleteProp(c, tool)
            return wheelOut(c, wheel, remaining(endAt, 1200) - 150)
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
            if not wheelIn(c, wheel, remaining(endAt, 2000) * 0.4) then return false end
            local tool = holdTool(c, 'wrench')
            local ok = waitUntil(c, endAt - 150)
            deleteProp(c, tool)
            return ok
        end,
    }
end

-- Small hub part (caliper): on the hub (thin axis along the axle) and on the floor (thin axis up)
local function hubPartPoses(c, wheel, part)
    local onHub = alignRot(c, part, 'thin', c.right, c.heading)
    local onFloor = alignRot(c, part, 'thin', UP, c.heading)
    local hub = hubWorld(c, wheel) + c.right * (wheel.side * 0.12)
    return pose(c, part, onHub, hub, 'center'), onHub, pose(c, part, onFloor, wheel.partPos, 'floor'), onFloor
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
                -- work at the hub with the wrench for the whole step
                local held = holdTool(c, 'wrench')
                local ok = waitUntil(c, endAt - 150)
                deleteProp(c, held)
                return ok
            end

            local hubPos, hubRot, floorPos, floorRot = hubPartPoses(c, wheel, part)
            if direction == 'out' then
                -- unbolt the old part, then set it down on the floor
                local held = holdTool(c, 'wrench')
                if not sleep(c, total * 0.5) then return false end
                deleteProp(c, held)
                local obj = spawnProp(c, part, hubPos, hubRot)
                if not tween(c, total * 0.35, function(t)
                    moveProp(obj, arc(hubPos, floorPos, t, 0.1), lerpRot(hubRot, floorRot, t))
                end) then return false end
            else
                -- new part from the floor onto the hub, then bolt it
                local obj = spawnProp(c, part, floorPos, floorRot)
                if not sleep(c, total * 0.1) then return false end
                if not tween(c, total * 0.35, function(t)
                    moveProp(obj, arc(floorPos, hubPos, t, 0.1), lerpRot(floorRot, hubRot, t))
                end) then return false end
                local held = holdTool(c, 'wrench')
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

local function sidePoint(c, side, y)
    return G(c, sideX(c, side, 0.7), y or 0.0), G(c, side > 0 and c.max.x or c.min.x, y or 0.0)
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
            local can = holdTool(c, 'spray')
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

-- Engine: hood up, hoist pushed to the bumper with the hook above the bay, block lifted out,
-- hoist rolled clear and the block lowered onto a pallet (and the reverse)
Swaps.engine = {
    remove = function(c)
        return {
            stepOpenHood(),
            {
                label = 'step_hoist', w = 1.4,
                fn = function(c, ms, endAt)
                    local bay = bayLayout(c)
                    spawnPallet(c)
                    if not spawnHoist(c, bay.sPark) then return true end
                    return pushHoist(c, bay.sPark, bay.sFinal)
                end,
            },
            stepBayWork('step_unbolt', 1.4, true),
            {
                label = 'step_lift_out', w = 2.2,
                fn = function(c, ms, endAt)
                    local bay = bayLayout(c)
                    spawnPallet(c)
                    spawnHoist(c, bay.sFinal)
                    spawnBlock(c, 'bay')
                    c.hanging = true
                    setHoist(c, bay.sFinal)

                    if not goTo(c, crankPos(c, bay.sFinal), hoistAt(c, bay.sFinal)) then return false end
                    playAnim(c, A.lever)
                    local total = remaining(endAt, 3500) - 200
                    local from = c.drop
                    if not tween(c, total * 0.35, function(t) setDrop(c, lerp(from, 0.0, t)) end) then return false end
                    stopTask(c)

                    -- roll the hoist (block hanging) out until the block is above the pallet
                    if not guideHoist(c, bay.sFinal, bay.sRetreat) then return false end
                    playAnim(c, A.lever)
                    return tween(c, remaining(endAt, 900) - 150, function(t) setDrop(c, lerp(0.0, c.dropPallet, t)) end)
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
                    spawnPallet(c)
                    spawnBlock(c, 'pallet')
                    c.hanging = false
                    if not spawnHoist(c, bay.sPark) then return true end
                    if not pushHoist(c, bay.sPark, bay.sRetreat) then return false end

                    -- hook the new block and lift it off the pallet
                    if not goTo(c, crankPos(c, bay.sRetreat), hoistAt(c, bay.sRetreat)) then return false end
                    playAnim(c, A.lever)
                    c.hanging = true
                    local from = c.drop
                    return tween(c, remaining(endAt, 1500) - 150, function(t) setDrop(c, lerp(from, 0.0, t)) end)
                end,
            },
            {
                label = 'step_lift_in', w = 2.0,
                fn = function(c, ms, endAt)
                    local bay = bayLayout(c)
                    spawnHoist(c, bay.sRetreat)
                    if not c.block then spawnBlock(c, 'pallet') c.drop = 0.0 end
                    c.hanging = true
                    setHoist(c, c.hoistS or bay.sRetreat)

                    if not pushHoist(c, c.hoistS or bay.sRetreat, bay.sFinal) then return false end
                    if not goTo(c, crankPos(c, bay.sFinal), hoistAt(c, bay.sFinal)) then return false end
                    playAnim(c, A.lever)
                    local from = c.drop
                    return tween(c, remaining(endAt, 1200) - 150, function(t) setDrop(c, lerp(from, c.dropBay, t)) end)
                end,
            },
            stepBayWork('step_bolt', 1.5, true, function(c)
                c.hanging = false
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
            spawnJack(c, u.jackPos)
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

-- Gearbox poses: longest axis along the car; on the floor under the car, mounted 22 cm higher,
-- and outside next to the car
local function gearboxPoses(c, u)
    local rot = alignRot(c, P.gearbox, 'long', c.fwd, c.heading)
    local floor = pose(c, P.gearbox, rot, u.underPos, 'floor')
    local mounted = floor + vec3(0.0, 0.0, 0.22)
    local outside = pose(c, P.gearbox, rot, u.outPos, 'floor')
    return floor, mounted, outside, rot
end

Swaps.transmission = {
    remove = function(c)
        return {
            stepTransJack(),
            {
                label = 'step_under_car', w = 1.0,
                fn = function(c, ms, endAt)
                    return lieUnder(c, c.under, A.under)
                end,
            },
            {
                label = 'step_unbolt', w = 1.5,
                fn = function(c, ms, endAt)
                    local u = c.under
                    if not c.lying and not lieUnder(c, u, A.underWork) then return false end
                    playAnim(c, A.underWork)
                    local floor, mounted, _, rot = gearboxPoses(c, u)
                    c.gearbox = spawnProp(c, P.gearbox, mounted, rot)
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
                    local floor, _, outside, rot = gearboxPoses(c, u)
                    if not c.gearbox then c.gearbox = spawnProp(c, P.gearbox, floor, rot) end
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
                    local floor, _, outside, rot = gearboxPoses(c, u)
                    c.gearbox = spawnProp(c, P.gearbox, outside, rot)
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
                    local floor, mounted, _, rot = gearboxPoses(c, u)
                    if not c.gearbox then c.gearbox = spawnProp(c, P.gearbox, floor, rot) end
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
local function panelPoses(c, side)
    local rotSide = alignRot(c, P.panel, 'thin', c.right, c.heading)
    local rotFlat = alignRot(c, P.panel, 'thin', UP, c.heading)
    local against = pose(c, P.panel, rotSide, G(c, side > 0 and (c.max.x + 0.08) or (c.min.x - 0.08), 0.0), 'floor')
    local onFloor = pose(c, P.panel, rotFlat, G(c, sideX(c, side, 0.9), 0.6), 'floor')
    return against, rotSide, onFloor, rotFlat
end

local function armorStack(c)
    local bay = bayLayout(c)
    return G(c, sideX(c, c.side, 1.5), bay.edge - bay.dir * 0.4)
end

local function spawnStack(c)
    local stack = armorStack(c)
    if not c.stack then
        c.stackRot = vec3(0.0, 0.0, c.heading)
        local pos = pose(c, P.pallet, c.stackRot, stack, 'floor')
        c.stack = spawnProp(c, P.pallet, pos, c.stackRot)
        c.stackTop = pos.z + measure(c, P.pallet, c.stackRot).high
    end
    return stack
end

local function onStack(c, stack)
    local rotFlat = alignRot(c, P.panel, 'thin', UP, c.heading)
    return pose(c, P.panel, rotFlat, stack, 'surface', c.stackTop or c.groundZ), rotFlat
end

local function stepWeldSide(side, mode, w)
    return {
        label = 'step_weld', w = w or 1.0,
        fn = function(c, ms, endAt)
            local s = side == 'near' and c.side or -c.side
            local pos, look = sidePoint(c, s)
            local against, rotSide, onFloor, rotFlat = panelPoses(c, s)
            local panel
            if mode == 'remove' then
                panel = spawnProp(c, P.panel, against, rotSide)
            else
                panel = c.carried == s and c.carriedPanel or spawnProp(c, P.panel, against, rotSide)
            end
            if not goTo(c, pos, look) then return false end
            scenario(c, SCENARIO.weld)
            if not waitUntil(c, endAt - 900) then return false end
            stopTask(c)
            if mode == 'remove' then
                -- the cut plate tips away from the body onto the floor
                tween(c, 500, function(t) moveProp(panel, arc(against, onFloor, t, 0.3), lerpRot(rotSide, rotFlat, t)) end)
                c.cutPanel = panel
            else
                deleteProp(c, panel)
                c.carriedPanel = nil
            end
            return not c.cancelled
        end,
    }
end

Swaps.armor = {
    remove = function(c)
        return {
            stepWeldSide('near', 'remove', 1.0),
            stepWeldSide('far', 'remove', 1.0),
            {
                label = 'step_lift_out', w = 1.0,
                fn = function(c, ms, endAt)
                    local stack = spawnStack(c)
                    local panel = c.cutPanel
                    if not panel then return true end
                    -- pick the cut plate up from the floor and stack it on the pallet
                    local pp = GetEntityCoords(panel)
                    if not goTo(c, approach(c, pp, 0.6), pp) then return false end
                    if not pickUp(c, panel, P.panel) then return false end
                    if not goTo(c, approach(c, stack, 0.75), stack, true) then return false end
                    local pos, rot = onStack(c, stack)
                    if not putDown(c, panel, pos, rot) then return false end
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
                    local stack = spawnStack(c)
                    local pos, rot = onStack(c, stack)
                    local panel = spawnProp(c, P.panel, pos, rot)
                    -- new plate from the pallet to the body panel
                    if not goTo(c, approach(c, stack, 0.75), stack) then return false end
                    if not pickUp(c, panel, P.panel) then return false end
                    local spot, look = sidePoint(c, c.side)
                    if not goTo(c, spot, look, true) then return false end
                    if not sleep(c, 300) then return false end
                    release(panel)
                    local against, rotSide = panelPoses(c, c.side)
                    if panel then
                        local from, fromRot = GetEntityCoords(panel), GetEntityRotation(panel, 2)
                        if not tween(c, 450, function(t) moveProp(panel, lerp(from, against, t), lerpRot(fromRot, rotSide, t)) end) then return false end
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
    return pose(c, P.turbo, vec3(0.0, 0.0, c.heading), bay.benchPos + (bay.sidePos - bay.benchPos) * 0.2, 'floor')
end

local function turboInBay(c, bay)
    return pose(c, P.turbo, vec3(0.0, 0.0, c.heading), bay.bayWorld + vec3(0.0, 0.0, 0.05), 'center')
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
                    local rot = vec3(0.0, 0.0, c.heading)
                    local from = turboInBay(c, bay)
                    local part = spawnProp(c, P.turbo, from, rot)
                    if not goTo(c, bay.sidePos, bay.bayWorld) then return false end
                    playAnim(c, A.bayLean)
                    -- lift the old unit out of the bay into the hands
                    local up = from + vec3(0.0, 0.0, 0.35)
                    if not tween(c, 900, function(t) moveProp(part, lerp(from, up, t)) end) then return false end
                    local cp = carryPose(c, P.turbo)
                    if not tween(c, 350, function(t)
                        moveProp(part, lerp(up, GetOffsetFromEntityInWorldCoords(c.ped, cp.off.x, cp.off.y, cp.off.z), t))
                    end) then return false end
                    carry(c, part, P.turbo)
                    -- carry it to the tool box and set it down on the floor
                    local spot = turboSpot(c, bay)
                    if not goTo(c, approach(c, spot, 0.6), spot, true) then return false end
                    if not putDown(c, part, spot, rot) then return false end
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
                    local rot = vec3(0.0, 0.0, c.heading)
                    c.toolbox = c.toolbox or spawnGround(c, P.toolbox, bay.benchPos, c.heading + 90.0)
                    local spot = turboSpot(c, bay)
                    local part = spawnProp(c, P.turbo, spot, rot)
                    -- pick the new unit up next to the tool box
                    if not goTo(c, approach(c, spot, 0.6), spot) then return false end
                    if not pickUp(c, part, P.turbo) then return false end
                    -- carry it to the bay and lower it in
                    if not goTo(c, bay.sidePos, bay.bayWorld, true) then return false end
                    if not sleep(c, 300) then return false end
                    release(part)
                    playAnim(c, A.bayLean)
                    if part then
                        local held, heldRot = GetEntityCoords(part), GetEntityRotation(part, 2)
                        local into = turboInBay(c, bay)
                        if not tween(c, 1000, function(t) moveProp(part, lerp(held, into, t), lerpRot(heldRot, rot, t)) end) then return false end
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
                    local tool = holdTool(c, 'wrench')
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
    local dir = len > 0.01 and towards / len or c.fwd
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
    local rot = vec3(0.0, 0.0, info.heading)
    local m = measure(c, P.box, rot)
    local col = (index - 1) % 3
    local layer = (index - 1) // 3
    local p = info.rowStart - info.dir * (0.45 * col)
    local spot = vec3(p.x, p.y, c.groundZ)
    local pos = pose(c, P.box, rot, spot, 'surface', c.groundZ + layer * (m.high - m.low))
    return pos, spot
end

-- Reach into the crate and bring a box up to the chest
local function takeBox(c, info)
    local min, max = dims(c, P.box)
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
        moveProp(box, lerp(up, GetOffsetFromEntityInWorldCoords(c.ped, 0.0, 0.42, 0.08), t))
    end) then return nil end
    attachGrip(c, box, GRIP.box)
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
                local crowbar = holdTool(c, 'crowbar')
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
-- B3: car wash. Bucket on the floor, sponge in the hand, around the car; the dirt level goes down
-- while scrubbing and ends at 0 with the decals washed off. A cancelled wash restores the dirt.
---------------------------------------------------------------------------------------------

local function setDirt(c, level)
    if DoesEntityExist(c.vehicle) then SetVehicleDirtLevel(c.vehicle, math.max(0.0, level) + 0.0) end
end

local function buildWash(c)
    c.washFrom = GetVehicleDirtLevel(c.vehicle)
    local frontKey = c.endSign > 0 and 'step_wash_front' or 'step_wash_rear'
    local backKey = c.endSign > 0 and 'step_wash_rear' or 'step_wash_front'
    local passes = {
        { label = 'step_wash_side', where = function(c) return sidePoint(c, c.side) end, anim = A.wipe },
        { label = frontKey, where = function(c) return endPoint(c, c.endSign) end, anim = A.wipeAlt },
        { label = 'step_wash_side', where = function(c) return sidePoint(c, -c.side) end, anim = A.wipe },
        { label = backKey, where = function(c) return endPoint(c, -c.endSign) end, anim = A.wipeAlt },
    }

    local steps = {
        {
            label = 'step_wash_soak', w = 1.2,
            fn = function(c, ms, endAt)
                -- the bucket starts at the mechanic's feet; he carries it to the near side of the
                -- car, towards the end he stands at, and sets it down there
                local spot = G(c, sideX(c, c.side, 1.0), endY(c, c.endSign, -0.9))
                local feet = GetOffsetFromEntityInWorldCoords(c.ped, 0.45, 0.25, 0.0)
                c.bucket = spawnGround(c, P.bucket, vec3(feet.x, feet.y, c.groundZ), c.heading)
                if c.bucket then
                    playAnim(c, A.pickLow)
                    if not sleep(c, 600) then return false end
                    attachGrip(c, c.bucket, bucketGrip(c))
                end
                if not goTo(c, approach(c, spot, 0.55), spot, c.bucket and A.holdSide or nil) then return false end
                if c.bucket then
                    playAnim(c, A.putLow)
                    if not sleep(c, 550) then return false end
                    release(c.bucket)
                    local rot = vec3(0.0, 0.0, c.heading)
                    moveProp(c.bucket, pose(c, P.bucket, rot, spot, 'floor'), rot)
                end
                playAnim(c, A.kneelDown)
                if not sleep(c, 650) then return false end
                c.sponge = c.sponge or holdTool(c, 'sponge')
                playAnim(c, A.soak)
                return waitUntil(c, endAt - 150)
            end,
        },
    }

    for i, pass in ipairs(passes) do
        steps[#steps + 1] = {
            label = pass.label, w = 1.0,
            fn = function(c, ms, endAt)
                local pos, look = pass.where(c)
                if not goTo(c, pos, look) then return false end
                c.sponge = c.sponge or holdTool(c, 'sponge')
                playAnim(c, pass.anim)
                local from = c.washFrom * (1.0 - (i - 1) / #passes)
                local to = c.washFrom * (1.0 - i / #passes)
                if not tween(c, remaining(endAt, 1200) - 200, function(t) setDirt(c, lerp(from, to, t)) end) then return false end
                if i == #passes then
                    setDirt(c, 0.0)
                    WashDecalsFromVehicle(c.vehicle, 1.0)
                end
                return true
            end,
        }
    end
    return steps
end

---------------------------------------------------------------------------------------------
-- B2: manual swaps (Config.ManualSwap.enabled). The player does every step himself.
--  * Ap1le.ShowTextUI shows the current instruction ("[E] Løsn bolten", "[W/S] Hæv motoren").
--  * Markers show where to go: rings on the floor, small spheres on bolts, arrows above props.
--  * E (INPUT_PICKUP, 38) acts, W/S (32/33) raise/lower while working the hoist pump, the jack or
--    the gearbox jack (walking is locked meanwhile).
--  * Only timed sub-steps (unbolting, tightening, welding) show an Ap1le.Progress bar.
--  * Cancel any time: our own key mapping (Backspace by default, "ap1le_mechanic_cancel"), or X
--    during a bar. Walking more than leash() from the car, dying or the car disappearing cancel too.
--  * Same cleanup as the automatic sequences. At the end the sequence waits (a short bar) until
--    removeTime/installTime * Config.ManualSwap.minTimeFactor has passed, so the server's time check
--    never rejects a quick mechanic.
---------------------------------------------------------------------------------------------

local MANUAL_CANCEL_COMMAND = 'ap1le_mechanic_cancel'
local CONTROL_E, CONTROL_W, CONTROL_S = 38, 32, 33
local MANUAL_DISABLED = { 21, 22, 23, 24, 25, 37, 44, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264 }
local AXIS_DISABLED = { 30, 31, 32, 33, 34, 35 }
local NEAR = 0.9

RegisterCommand(MANUAL_CANCEL_COMMAND, function()
    local c = active
    if c and c.manual and not c.cancelled then
        c.cancelled = true
        if c.inBar then UI.CancelProgress() end
    end
end, false)
RegisterKeyMapping(MANUAL_CANCEL_COMMAND, T('manual_keymap'), 'keyboard', 'BACK')

local function manualKeyLabel()
    local ok, button = pcall(GetControlInstructionalButton, 0, joaat(MANUAL_CANCEL_COMMAND) | 0x80000000, true)
    if ok and type(button) == 'string' and button:sub(1, 2) == 't_' and #button > 2 then return button:sub(3) end
    return 'Backspace'
end

local function say(c, text, key)
    if c.sayText == text and c.sayKey == key then return end
    c.sayText, c.sayKey = text, key
    c.textShown = true
    UI.ShowTextUI(text, key)
end

local function unsay(c)
    if not c.sayText then return end
    c.sayText, c.sayKey = nil, nil
    UI.HideTextUI()
end

-- kind: 'floor' ring, 'bolt' small sphere, 'arrow' above a prop
local function addMarker(c, pos, kind)
    local m = { pos = pos, kind = kind or 'floor' }
    c.markers[m] = true
    return m
end

local function removeMarker(c, m)
    if m then c.markers[m] = nil end
end

local function drawMarker(c, m)
    local p = m.pos
    if m.kind == 'bolt' then
        DrawMarker(28, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.06, 0.06, 0.06, 255, 255, 255, 190,
            false, false, 2, false, nil, nil, false)
    elseif m.kind == 'arrow' then
        DrawMarker(2, p.x, p.y, p.z + 0.55, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.22, 0.22, 0.22, 255, 255, 255, 170,
            true, true, 2, false, nil, nil, false)
    else
        DrawMarker(25, p.x, p.y, c.groundZ + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.85, 0.85, 0.85, 255, 255, 255, 110,
            false, false, 2, false, nil, nil, false)
    end
end

local function manualMonitor(c)
    CreateThread(function()
        while active == c and not c.cancelled do
            for i = 1, #MANUAL_DISABLED do DisableControlAction(0, MANUAL_DISABLED[i], true) end
            if c.axis then
                for i = 1, #AXIS_DISABLED do DisableControlAction(0, AXIS_DISABLED[i], true) end
            end
            for m in pairs(c.markers) do drawMarker(c, m) end

            if lostContact(c) or IsPedInAnyVehicle(c.ped, false) then c.cancelled = true end
            if c.cancelled then
                if c.inBar then UI.CancelProgress() end
                break
            end
            Wait(0)
        end
    end)
end

-- Timed sub-step: an ap1le_core bar while the current animation keeps running
local function mProgress(c, label, ms)
    unsay(c)
    c.inBar = true
    local ok = UI.Progress({ label = label, duration = math.max(500, math.floor(ms)), canCancel = true, disable = BAR_DISABLE })
    c.inBar = false
    if not ok then c.cancelled = true end
    return ok and not c.cancelled
end

-- Walk up to `spot` and press E. opts: radius, mark (marker position), kind, face (point), walk (text)
local function mPress(c, spot, text, opts)
    opts = opts or {}
    local radius = opts.radius or NEAR
    local marker = addMarker(c, opts.mark or spot, opts.kind or 'floor')
    local pressed = false
    while not c.cancelled do
        local pos = GetEntityCoords(c.ped)
        if #(pos.xy - spot.xy) <= radius then
            say(c, text, 'E')
            if IsControlJustReleased(0, CONTROL_E) then
                pressed = true
                break
            end
        else
            say(c, opts.walk or T('manual_go_marker'))
        end
        Wait(0)
    end
    removeMarker(c, marker)
    unsay(c)
    if pressed and opts.face then face(c, opts.face) end
    return pressed and not c.cancelled
end

-- W/S control of a value between lo and hi. wSign = +1: W increases it, -1: W decreases it.
-- apply(value) every frame. Ends when the value is at `target` and E is pressed.
local function mAxis(c, text, value, lo, hi, speed, target, apply, wSign)
    c.axis = true
    local last = GetGameTimer()
    local done = false
    while not c.cancelled do
        local now = GetGameTimer()
        local dt = (now - last) / 1000.0
        last = now
        local dir = 0.0
        if IsDisabledControlPressed(0, CONTROL_W) then dir = wSign elseif IsDisabledControlPressed(0, CONTROL_S) then dir = -wSign end
        value = clamp(value + dir * speed * dt, lo, hi)
        apply(value)
        if math.abs(value - target) < 0.005 then
            say(c, T('manual_axis_done'), 'E')
            if IsControlJustReleased(0, CONTROL_E) then
                done = true
                break
            end
        else
            say(c, text, 'W/S')
        end
        Wait(0)
    end
    c.axis = false
    unsay(c)
    return done and not c.cancelled, value
end

-- Bolt points: walk to any marked point and press E; each one is a short bar.
-- points = { { pos = bolt (world), stand = floor spot, look = world, radius? } }
-- opts: anim (work clip), lying (stay lying under the car), scenario (instead of anim + wrench)
local function mBolts(c, points, verbKey, stepKey, ms, opts)
    opts = opts or {}
    local n, done = #points, 0
    for _, p in ipairs(points) do p.marker = addMarker(c, p.pos, 'bolt') end
    while done < n and not c.cancelled do
        local pos = GetEntityCoords(c.ped)
        local pick
        for _, p in ipairs(points) do
            if not p.done and #(pos.xy - p.stand.xy) <= (p.radius or NEAR) then pick = p break end
        end
        if pick then
            say(c, T(verbKey), 'E')
            if IsControlJustReleased(0, CONTROL_E) then
                unsay(c)
                if not opts.lying and not face(c, pick.look or pick.pos) then break end
                local tool
                if opts.scenario then
                    scenario(c, opts.scenario)
                else
                    playAnim(c, opts.anim or A.bayLean)
                    tool = holdTool(c, 'wrench')
                end
                local ok = mProgress(c, ('%s (%d/%d)'):format(T(stepKey), done + 1, n), ms)
                deleteProp(c, tool)
                if opts.lying then
                    playAnim(c, A.under)
                else
                    stopTask(c)
                end
                if not ok then break end
                pick.done = true
                done = done + 1
                removeMarker(c, pick.marker)
            end
        else
            say(c, T('manual_go_bolt'))
        end
        Wait(0)
    end
    for _, p in ipairs(points) do removeMarker(c, p.marker) end
    unsay(c)
    return done == n and not c.cancelled
end

-- Fetch the toolbox (a few metres away) and set it down at `dest`
local function mTools(c, dest)
    local start = G(c, sideX(c, c.side, 2.3), c.endSign * c.max.y * 0.35)
    local rot = vec3(0.0, 0.0, c.heading + 90.0)
    local box = spawnProp(c, P.toolbox, pose(c, P.toolbox, rot, start, 'floor'), rot)
    if not box then return not c.cancelled end
    if not mPress(c, start, T('manual_take_tools'), { radius = 1.2, mark = start, kind = 'arrow', face = start }) then return false end
    playAnim(c, A.pickLow)
    if not sleep(c, 650) then return false end
    attachGrip(c, box, GRIP.toolbox)
    playAnim(c, A.holdSide)
    if not mPress(c, dest, T('manual_place_tools')) then return false end
    playAnim(c, A.putLow)
    if not sleep(c, 600) then return false end
    release(box)
    local here = GetEntityCoords(c.ped) + c.right * (c.side * 0.45)
    moveProp(box, pose(c, P.toolbox, rot, vec3(here.x, here.y, c.groundZ), 'floor'), rot)
    stopTask(c)
    c.toolbox = box
    return not c.cancelled
end

local function mOpenHood(c)
    local bay = bayLayout(c)
    if GetIsDoorValid(c.vehicle, bay.door) and GetVehicleDoorAngleRatio(c.vehicle, bay.door) > 0.3 then return true end
    if not mPress(c, bay.frontPos, T('manual_open_hood'), { face = bay.bayWorld }) then return false end
    playAnim(c, A.lidOpen, 1800)
    if not sleep(c, 550) then return false end
    openDoor(c, bay.door)
    if not sleep(c, 1000) then return false end
    stopTask(c)
    return not c.cancelled
end

local function mCloseHood(c)
    local bay = bayLayout(c)
    if not mPress(c, bay.sidePos, T('manual_close_hood'), { face = bay.bayWorld }) then return false end
    playAnim(c, A.lidClose, 1800)
    if not sleep(c, 650) then return false end
    closeDoor(c, bay.door)
    if not sleep(c, 900) then return false end
    stopTask(c)
    return not c.cancelled
end

-- Take the hoist by its handle and move it from s0 to s1. The hoist rolls on its line and follows
-- the player as long as he stands at the handle; it stops at s1.
local function mHoist(c, s0, s1, moveKey)
    local bay = bayLayout(c)
    local behind = hoistBehind(c)
    local lo, hi = math.min(s0, s1), math.max(s0, s1)
    if not mPress(c, hoistAt(c, s0 + behind), T('manual_take_hoist'),
        { radius = 0.8, mark = hoistAt(c, s0), kind = 'arrow', face = hoistAt(c, s0) }) then return false end

    playAnim(c, A.carry)
    local target = addMarker(c, hoistAt(c, s1 + behind), 'floor')
    local s = c.hoistS or s0
    local ok = false
    local animCheck = GetGameTimer() + 500
    -- grip = distance (along the line) between the player and the hoist origin when he took hold;
    -- the hoist keeps that distance (no jump on grabbing) until he lets go by walking off
    local holding, grip = false, behind
    while not c.cancelled do
        -- position along the hoist line (sp) and across it (lat)
        local rel = GetEntityCoords(c.ped) - bay.bayFloor
        local sp = dot2(rel, bay.away)
        local lat = dot2(rel, bay.lateral)
        if holding then
            if math.abs(lat) > 1.1 or math.abs((sp - s) - grip) > 0.8 then holding = false end
        elseif math.abs(lat) < 0.9 and math.abs((sp - s) - behind) < 0.9 then
            holding, grip = true, sp - s
        end
        if holding then
            s = clamp(sp - grip, lo, hi)
            setHoist(c, s)
            -- the ring shows where the player must stand for the hoist to reach its spot
            target.pos = hoistAt(c, s1 + grip)
        end
        if math.abs(s - s1) < 0.05 then
            setHoist(c, s1)
            say(c, T('manual_park_hoist'), 'E')
            if IsControlJustReleased(0, CONTROL_E) then
                ok = true
                break
            end
        elseif holding then
            say(c, T(moveKey))
        else
            say(c, T('manual_hold_hoist'))
        end
        -- keep both hands on the handle (another script or a bump may stop the clip)
        if GetGameTimer() > animCheck then
            animCheck = GetGameTimer() + 500
            if not IsEntityPlayingAnim(c.ped, A.carry.dict, A.carry.clip, 3) then playAnim(c, A.carry) end
        end
        Wait(0)
    end
    removeMarker(c, target)
    unsay(c)
    stopTask(c)
    return ok and not c.cancelled
end

-- Work the hoist pump: W raises the block, S lowers it, until it reaches `targetDrop`
local function mCrank(c, targetDrop, textKey)
    local s = c.hoistS or HOOK_REACH
    if not mPress(c, crankPos(c, s), T('manual_crank'), { radius = 0.7, face = hoistAt(c, s) }) then return false end
    playAnim(c, A.lever)
    c.hanging = true
    local hi = math.max(c.drop, targetDrop)
    local ok = mAxis(c, T(textKey), c.drop, 0.0, hi, 0.3, targetDrop, function(v) setDrop(c, v) end, -1.0)
    stopTask(c)
    return ok
end

-- Place the jack and pump the car up (or lower it and take the jack away)
local function mJack(c, kneelPos, jackPos, corner, up)
    if up then
        spawnJack(c, jackPos)
        prepareLift(c, corner)
    end
    if not mPress(c, kneelPos, T(up and 'manual_jack_up' or 'manual_jack_down'),
        { mark = jackPos, kind = 'arrow', face = jackPos }) then return false end
    playAnim(c, A.crouchWork)
    local ok = mAxis(c, T(up and 'manual_jack_raise' or 'manual_jack_lower'), c.lift and c.lift.t or 0.0, 0.0, 1.0, 0.45,
        up and 1.0 or 0.0, function(v) setLift(c, v) end, 1.0)
    stopTask(c)
    if ok and not up then
        deleteProp(c, c.jack)
        c.jack = nil
    end
    return ok
end

-- Engine
local function manualEngine(c, step)
    local bay = bayLayout(c)
    local toolsAt = G(c, sideX(c, c.side, 0.9), bay.bayLocal.y - bay.dir * 0.6)
    local function mounts()
        local b = bay.bayLocal
        local pts = {}
        for _, off in ipairs({ { -0.32, 0.28 }, { 0.32, 0.28 }, { -0.32, -0.28 }, { 0.32, -0.28 } }) do
            local lx, ly = b.x + off[1], b.y + off[2] * bay.dir
            pts[#pts + 1] = { pos = L(c, lx, ly, b.z), stand = G(c, sideX(c, sign(off[1]), 0.45), ly), look = L(c, lx, ly, b.z) }
        end
        return pts
    end

    if step == 'remove' then
        return {
            function(c) return mOpenHood(c) end,
            function(c) return mTools(c, toolsAt) end,
            function(c)
                spawnPallet(c)
                spawnHoist(c, bay.sPark)
                return mHoist(c, bay.sPark, bay.sFinal, 'manual_push_hoist')
            end,
            function(c) return mBolts(c, mounts(), 'manual_unbolt', 'step_unbolt', 2200) end,
            function(c)
                spawnBlock(c, 'bay')
                c.hanging = true
                setHoist(c, bay.sFinal)
                return mCrank(c, 0.0, 'manual_raise_engine')
            end,
            function(c) return mHoist(c, bay.sFinal, bay.sRetreat, 'manual_pull_hoist') end,
            function(c) return mCrank(c, c.dropPallet, 'manual_lower_engine') end,
        }
    end
    return {
        function(c) return mOpenHood(c) end,
        function(c) return mTools(c, toolsAt) end,
        function(c)
            spawnPallet(c)
            spawnBlock(c, 'pallet')
            c.hanging = false
            spawnHoist(c, bay.sPark)
            return mHoist(c, bay.sPark, bay.sRetreat, 'manual_push_hoist')
        end,
        function(c) return mCrank(c, 0.0, 'manual_raise_engine') end,
        function(c) return mHoist(c, bay.sRetreat, bay.sFinal, 'manual_push_hoist') end,
        function(c) return mCrank(c, c.dropBay, 'manual_lower_engine') end,
        function(c)
            if not mBolts(c, mounts(), 'manual_bolt', 'step_bolt', 2200) then return false end
            c.hanging = false
            deleteProp(c, c.block)
            c.block = nil
            return true
        end,
        function(c) return mCloseHood(c) end,
    }
end

-- Brakes and suspension (wheel corner)
local function manualCorner(c, step, category)
    local wheel = pickWheel(c, 'front')
    c.wheel = wheel
    local function hubPoints(kind)
        local hub = hubWorld(c, wheel)
        local a, b
        if kind == 'strut' then
            a, b = hub + vec3(0.0, 0.0, 0.25), hub - vec3(0.0, 0.0, 0.08)
        else
            a, b = hub + c.fwd * 0.12, hub - c.fwd * 0.12
        end
        return {
            { pos = a, stand = wheel.kneelPos, look = hub },
            { pos = b, stand = wheel.kneelPos, look = hub },
        }
    end

    local tasks = {
        function(c) return mTools(c, wheel.toolPos) end,
        function(c) return mJack(c, wheel.kneelPos, wheel.jackPos, wheel.localPos, true) end,
        function(c)
            if not mPress(c, wheel.kneelPos, T('manual_wheel_off'), { mark = hubWorld(c, wheel), kind = 'bolt', face = hubWorld(c, wheel) }) then return false end
            playAnim(c, A.crouchWork)
            local tool = holdTool(c, 'wrench')
            local ok = mProgress(c, T('step_wheel_off'), 2500)
            deleteProp(c, tool)
            if not ok then return false end
            local done = wheelOut(c, wheel, 1300)
            stopTask(c)
            return done
        end,
    }

    if category == 'brakes' then
        if step == 'remove' then
            tasks[#tasks + 1] = function(c)
                if not mBolts(c, hubPoints('caliper'), 'manual_unbolt', 'step_unbolt', 2000, { anim = A.crouchWork }) then return false end
                local hubPos, hubRot, floorPos, floorRot = hubPartPoses(c, wheel, P.caliper)
                local obj = spawnProp(c, P.caliper, hubPos, hubRot)
                return tween(c, 900, function(t) moveProp(obj, arc(hubPos, floorPos, t, 0.1), lerpRot(hubRot, floorRot, t)) end)
            end
        else
            tasks[#tasks + 1] = function(c)
                local hubPos, hubRot, floorPos, floorRot = hubPartPoses(c, wheel, P.caliper)
                local obj = spawnProp(c, P.caliper, floorPos, floorRot)
                if not mPress(c, wheel.kneelPos, T('manual_fit_part'), { mark = floorPos, kind = 'arrow', face = hubWorld(c, wheel) }) then return false end
                playAnim(c, A.crouchWork)
                if not tween(c, 900, function(t) moveProp(obj, arc(floorPos, hubPos, t, 0.1), lerpRot(floorRot, hubRot, t)) end) then return false end
                stopTask(c)
                if not mBolts(c, hubPoints('caliper'), 'manual_bolt', 'step_bolt', 2000, { anim = A.crouchWork }) then return false end
                deleteProp(c, obj)
                return true
            end
        end
    else
        tasks[#tasks + 1] = function(c)
            if not c.hubTool then c.hubTool = spawnGround(c, P.strut, wheel.partPos, c.heading) end
            local remove = step == 'remove'
            return mBolts(c, hubPoints('strut'), remove and 'manual_unbolt' or 'manual_bolt',
                remove and 'step_unbolt' or 'step_bolt', 2400, { anim = A.crouchWork })
        end
    end

    tasks[#tasks + 1] = function(c)
        local wp = wheelPoses(c, wheel)
        if not mPress(c, wheel.kneelPos, T('manual_wheel_on'), { mark = wp.floor, kind = 'arrow', face = hubWorld(c, wheel) }) then return false end
        playAnim(c, A.crouchWork)
        if not wheelIn(c, wheel, 1200) then return false end
        local tool = holdTool(c, 'wrench')
        local ok = mProgress(c, T('step_wheel_on'), 2500)
        deleteProp(c, tool)
        stopTask(c)
        return ok
    end
    tasks[#tasks + 1] = function(c) return mJack(c, wheel.kneelPos, wheel.jackPos, wheel.localPos, false) end
    return tasks
end

-- Transmission (under the car)
local function manualTransmission(c, step)
    local u = underLayout(c, gearboxY(c))
    c.under = u
    local function gearboxPoints()
        local floor, mounted = gearboxPoses(c, u)
        local pts = {}
        for _, off in ipairs({ -0.3, 0.0, 0.3 }) do
            local p = mounted + c.fwd * off + vec3(0.0, 0.0, 0.15)
            pts[#pts + 1] = { pos = p, stand = u.liePos, radius = 3.0 }
        end
        return pts
    end
    local function lie(c)
        if not mPress(c, u.liePos, T('manual_lie_under'), { face = u.lookAt }) then return false end
        return playAnim(c, A.under)
    end
    local function rollOut(c)
        if not mPress(c, u.liePos, T('manual_roll_out'), { radius = 3.0, mark = u.liePos }) then return false end
        stopTask(c)
        return not c.cancelled
    end
    -- gearbox height above the floor pose: 0 on the floor, 0.22 mounted
    local function gearboxAxis(c, from, to, textKey)
        local floor, _, _, rot = gearboxPoses(c, u)
        c.gearbox = c.gearbox or spawnProp(c, P.gearbox, floor + vec3(0.0, 0.0, from), rot)
        return mAxis(c, T(textKey), from, 0.0, 0.22, 0.12, to, function(v) moveProp(c.gearbox, floor + vec3(0.0, 0.0, v)) end, 1.0)
    end

    local tasks = {
        function(c) return mTools(c, u.outPos + c.fwd * 1.0) end,
        function(c) return mJack(c, u.kneelPos, u.jackPos, nil, true) end,
    }
    if step == 'remove' then
        tasks[#tasks + 1] = lie
        tasks[#tasks + 1] = function(c)
            local _, mounted, _, rot = gearboxPoses(c, u)
            c.gearbox = c.gearbox or spawnProp(c, P.gearbox, mounted, rot)
            return mBolts(c, gearboxPoints(), 'manual_unbolt', 'step_unbolt', 2000, { anim = A.underWork, lying = true })
        end
        tasks[#tasks + 1] = function(c) return gearboxAxis(c, 0.22, 0.0, 'manual_lower_gearbox') end
        tasks[#tasks + 1] = rollOut
        tasks[#tasks + 1] = function(c)
            local floor, _, outside = gearboxPoses(c, u)
            if not mPress(c, u.kneelPos, T('manual_take_part'), { mark = floor, kind = 'arrow', face = u.underPos }) then return false end
            playAnim(c, A.crouchWork)
            local ok = tween(c, 1300, function(t) moveProp(c.gearbox, lerp(floor, outside, t)) end)
            stopTask(c)
            return ok
        end
    else
        tasks[#tasks + 1] = function(c)
            local floor, _, outside, rot = gearboxPoses(c, u)
            c.gearbox = c.gearbox or spawnProp(c, P.gearbox, outside, rot)
            if not mPress(c, u.kneelPos, T('manual_take_part'), { mark = outside, kind = 'arrow', face = u.underPos }) then return false end
            playAnim(c, A.crouchWork)
            local ok = tween(c, 1300, function(t) moveProp(c.gearbox, lerp(outside, floor, t)) end)
            stopTask(c)
            return ok
        end
        tasks[#tasks + 1] = lie
        tasks[#tasks + 1] = function(c) return gearboxAxis(c, 0.0, 0.22, 'manual_raise_gearbox') end
        tasks[#tasks + 1] = function(c)
            if not mBolts(c, gearboxPoints(), 'manual_bolt', 'step_bolt', 2000, { anim = A.underWork, lying = true }) then return false end
            deleteProp(c, c.gearbox)
            c.gearbox = nil
            return true
        end
        tasks[#tasks + 1] = rollOut
    end
    tasks[#tasks + 1] = function(c) return mJack(c, u.kneelPos, u.jackPos, nil, false) end
    return tasks
end

-- Armor (weld points on both sides, plates to / from the pallet)
local function manualArmor(c, step)
    local half = math.min(1.0, (c.max.y - c.min.y) * 0.22)
    local function weldPoints(s)
        local pts = {}
        for _, y in ipairs({ -half, half }) do
            local stand, look = sidePoint(c, s, y)
            local onBody = L(c, s > 0 and c.max.x or c.min.x, y, 0.0)
            pts[#pts + 1] = { pos = vec3(onBody.x, onBody.y, c.groundZ + 0.6), stand = stand, look = look }
        end
        return pts
    end

    local tasks = {}
    for _, which in ipairs({ 'near', 'far' }) do
        local s = which == 'near' and c.side or -c.side
        if step == 'remove' then
            tasks[#tasks + 1] = function(c)
                local against, rotSide, onFloor, rotFlat = panelPoses(c, s)
                local panel = spawnProp(c, P.panel, against, rotSide)
                if not mBolts(c, weldPoints(s), 'manual_weld', 'step_weld', 2500, { scenario = SCENARIO.weld }) then return false end
                if not tween(c, 500, function(t) moveProp(panel, arc(against, onFloor, t, 0.3), lerpRot(rotSide, rotFlat, t)) end) then return false end
                -- carry the cut plate to the pallet
                local stack = spawnStack(c)
                if not mPress(c, approach(c, onFloor, 0.6), T('manual_take_part'), { radius = 1.2, mark = onFloor, kind = 'arrow', face = onFloor }) then return false end
                if not pickUp(c, panel, P.panel) then return false end
                if not mPress(c, stack, T('manual_put_down'), { radius = 1.1, face = stack }) then return false end
                local pos, rot = onStack(c, stack)
                if not putDown(c, panel, pos + vec3(0.0, 0.0, (which == 'far') and 0.03 or 0.0), rot) then return false end
                stopTask(c)
                return not c.cancelled
            end
        else
            tasks[#tasks + 1] = function(c)
                local stack = spawnStack(c)
                local pos, rot = onStack(c, stack)
                local panel = spawnProp(c, P.panel, pos, rot)
                if not mPress(c, stack, T('manual_take_part'), { radius = 1.1, mark = stack, kind = 'arrow', face = stack }) then return false end
                if not pickUp(c, panel, P.panel) then return false end
                local spot, look = sidePoint(c, s)
                if not mPress(c, spot, T('manual_fit_part'), { face = look }) then return false end
                release(panel)
                local against, rotSide = panelPoses(c, s)
                local from, fromRot = GetEntityCoords(panel), GetEntityRotation(panel, 2)
                if not tween(c, 450, function(t) moveProp(panel, lerp(from, against, t), lerpRot(fromRot, rotSide, t)) end) then return false end
                stopTask(c)
                if not mBolts(c, weldPoints(s), 'manual_weld', 'step_weld', 2500, { scenario = SCENARIO.weld }) then return false end
                deleteProp(c, panel)
                return true
            end
        end
    end
    return tasks
end

-- Turbo (bay, carried to / from the floor by the toolbox)
local function manualTurbo(c, step)
    local bay = bayLayout(c)
    local rot = vec3(0.0, 0.0, c.heading)
    local toolsAt = G(c, sideX(c, c.side, 0.9), bay.bayLocal.y - bay.dir * 0.6)
    local function boltPoints()
        local b = bay.bayLocal
        return {
            { pos = L(c, b.x - 0.15, b.y, b.z + 0.1), stand = bay.sidePos, look = bay.bayWorld, radius = 1.0 },
            { pos = L(c, b.x + 0.15, b.y, b.z + 0.1), stand = bay.sidePos, look = bay.bayWorld, radius = 1.0 },
        }
    end
    local tasks = {
        function(c) return mOpenHood(c) end,
        function(c) return mTools(c, toolsAt) end,
    }
    if step == 'remove' then
        tasks[#tasks + 1] = function(c) return mBolts(c, boltPoints(), 'manual_unbolt', 'step_unbolt', 2000) end
        tasks[#tasks + 1] = function(c)
            local from = turboInBay(c, bay)
            local part = spawnProp(c, P.turbo, from, rot)
            if not mPress(c, bay.sidePos, T('manual_take_part'), { mark = from, kind = 'arrow', face = bay.bayWorld }) then return false end
            playAnim(c, A.bayLean)
            local up = from + vec3(0.0, 0.0, 0.35)
            if not tween(c, 800, function(t) moveProp(part, lerp(from, up, t)) end) then return false end
            local cp = carryPose(c, P.turbo)
            if not tween(c, 350, function(t)
                moveProp(part, lerp(up, GetOffsetFromEntityInWorldCoords(c.ped, cp.off.x, cp.off.y, cp.off.z), t))
            end) then return false end
            carry(c, part, P.turbo)
            playAnim(c, A.carry)
            local spot = turboSpot(c, bay)
            if not mPress(c, spot, T('manual_put_down'), { radius = 1.1, face = spot }) then return false end
            if not putDown(c, part, spot, rot) then return false end
            stopTask(c)
            return not c.cancelled
        end
        tasks[#tasks + 1] = function(c) return mCloseHood(c) end
    else
        tasks[#tasks + 1] = function(c)
            local spot = turboSpot(c, bay)
            local part = spawnProp(c, P.turbo, spot, rot)
            if not mPress(c, spot, T('manual_take_part'), { radius = 1.1, mark = spot, kind = 'arrow', face = spot }) then return false end
            if not pickUp(c, part, P.turbo) then return false end
            if not mPress(c, bay.sidePos, T('manual_fit_part'), { face = bay.bayWorld }) then return false end
            release(part)
            playAnim(c, A.bayLean)
            local held, heldRot = GetEntityCoords(part), GetEntityRotation(part, 2)
            local into = turboInBay(c, bay)
            if not tween(c, 900, function(t) moveProp(part, lerp(held, into, t), lerpRot(heldRot, rot, t)) end) then return false end
            stopTask(c)
            c.turboPart = part
            return true
        end
        tasks[#tasks + 1] = function(c)
            if not mBolts(c, boltPoints(), 'manual_bolt', 'step_bolt', 2000) then return false end
            deleteProp(c, c.turboPart)
            c.turboPart = nil
            return true
        end
        tasks[#tasks + 1] = function(c) return mCloseHood(c) end
    end
    return tasks
end

local ManualSwaps = {
    engine = manualEngine,
    brakes = function(c, step) return manualCorner(c, step, 'brakes') end,
    suspension = function(c, step) return manualCorner(c, step, 'suspension') end,
    transmission = manualTransmission,
    armor = manualArmor,
    turbo = manualTurbo,
}

-- The server rejects a finish faster than removeTime/installTime * ManualSwap.minTimeFactor
local function manualTimeFloor(c, category, step)
    local cfg = Config.Performance and Config.Performance[category]
    local base = cfg and (step == 'remove' and cfg.removeTime or cfg.installTime) or 0
    local factor = (Config.ManualSwap and Config.ManualSwap.minTimeFactor) or 0.5
    local need = math.floor(base * factor) + 600 - (GetGameTimer() - c.startedAt)
    if need <= 0 then return true end
    playAnim(c, A.standWork)
    local ok = mProgress(c, T('step_manual_check'), math.max(500, need))
    stopTask(c)
    return ok
end

local function runManual(vehicle, category, step)
    if active or Anim.IsAtLaptop() then return false end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if not waitForFreeBar(3000) then return false end
    if active or not DoesEntityExist(vehicle) then return false end

    local c = newContext(vehicle, 1000)
    setRef(c, nil)
    c.manual = true
    c.startedAt = GetGameTimer()
    active = c
    freeze(c, vehicle)
    manualMonitor(c)
    UI.Notify(T('manual_cancel_hint', manualKeyLabel()), 'info')

    local ok, result = pcall(function()
        local tasks = ManualSwaps[category](c, step)
        for _, task in ipairs(tasks) do
            if c.cancelled then return false end
            if task(c) == false or c.cancelled then return false end
        end
        return manualTimeFloor(c, category, step)
    end)
    if not ok then
        print(('[ap1le_mechanicjob] manual swap error: %s'):format(tostring(result)))
        result = false
    end

    local completed = result == true and not c.cancelled
    if c.tooFar then UI.Notify(T('manual_too_far'), 'error') end
    c.completed = completed
    cleanup(c)
    return completed
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

-- B2: interactive swap (Config.ManualSwap.enabled). Same return value as Anim.Swap. The time floor
-- uses Config.Performance[category].removeTime/installTime * Config.ManualSwap.minTimeFactor.
function Anim.SwapManual(vehicle, category, step)
    if not ManualSwaps[category] or (step ~= 'remove' and step ~= 'install') then return false end
    return runManual(vehicle, category, step)
end

function Anim.Cosmetic(vehicle, animType, totalMs)
    local build = Cosmetics[animType] or Cosmetics.body
    return run(vehicle, totalMs or (Config.Cosmetic and Config.Cosmetic.animTime) or 6000, build)
end

-- B3: wash the car (bucket + sponge). Dirt goes to 0 and the decals are washed off on completion;
-- a cancelled wash restores the original dirt level.
function Anim.Wash(vehicle, totalMs)
    return run(vehicle, totalMs or (Config.Wash and Config.Wash.time) or 15000, buildWash)
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
