lib.locale()

Config = {}

Config.Job = 'mechanic'

-- Workshops: repair (full), performance swaps and cosmetic tuning only work inside these.
-- Coordinates are defaults for the vanilla map; adjust to your MLOs.
Config.Workshops = {
    {
        id = 'bennys',
        label = "Benny's Original Motor Works",
        coords = vec3(-205.62, -1310.62, 31.30),
        radius = 25.0,
        blip = { sprite = 446, colour = 5, scale = 0.8 },
    },
    {
        id = 'lsc_burton',
        label = 'Los Santos Customs Burton',
        coords = vec3(-337.38, -136.92, 39.01),
        radius = 20.0,
        blip = { sprite = 72, colour = 5, scale = 0.8 },
    },
}

-- Max distance between the mechanic and the vehicle for any action (server-checked)
Config.MaxVehicleDistance = 6.0

-- Repairs. time = total sequence length in ms; the server rejects a finish
-- that arrives sooner than time * Config.MinTimeFactor.
Config.Repair = {
    engine = { item = 'engine_repair_kit', time = 15000, workshopOnly = true },
    body   = { item = 'body_repair_kit',   time = 20000, workshopOnly = true },
    tyre   = { item = 'tyre',              time = 10000, workshopOnly = true },
    -- field repair: anywhere, engine only, up to maxEngineHealth (1000 = perfect)
    field  = { item = 'repair_kit',        time = 12000, workshopOnly = false, maxEngineHealth = 600.0 },
}

-- Performance parts. One item per level; levels[1] = GTA mod index 0, levels[2] = index 1 ...
-- Stock (mod index -1) has no item. Swapping returns the old part's item to the mechanic.
-- removeTime/installTime: length (ms) of the remove and install sequences.
-- Property key = the key in lib.getVehicleProperties / owned_vehicles.vehicle JSON.
Config.Performance = {
    engine = {
        label = 'Engine', modType = 11, propKey = 'modEngine',
        levels = { 'engine_lvl1', 'engine_lvl2', 'engine_lvl3', 'engine_lvl4' },
        removeTime = 25000, installTime = 25000,
    },
    brakes = {
        label = 'Brakes', modType = 12, propKey = 'modBrakes',
        levels = { 'brakes_lvl1', 'brakes_lvl2', 'brakes_lvl3' },
        removeTime = 15000, installTime = 15000,
    },
    transmission = {
        label = 'Transmission', modType = 13, propKey = 'modTransmission',
        levels = { 'transmission_lvl1', 'transmission_lvl2', 'transmission_lvl3' },
        removeTime = 20000, installTime = 20000,
    },
    suspension = {
        label = 'Suspension', modType = 15, propKey = 'modSuspension',
        levels = { 'suspension_lvl1', 'suspension_lvl2', 'suspension_lvl3', 'suspension_lvl4' },
        removeTime = 20000, installTime = 20000,
    },
    armor = {
        label = 'Armor', modType = 16, propKey = 'modArmor',
        levels = { 'armor_lvl1', 'armor_lvl2', 'armor_lvl3', 'armor_lvl4', 'armor_lvl5' },
        removeTime = 15000, installTime = 15000,
    },
    turbo = {
        label = 'Turbo', modType = 18, propKey = 'modTurbo', toggle = true,
        levels = { 'turbo' },
        removeTime = 12000, installTime = 12000,
    },
}

-- Cosmetic tuning: no items. Prices are suggestions that pre-fill the invoice.
Config.Cosmetic = {
    mods = {
        { id = 'modSpoilers',     label = 'Spoiler',        modType = 0,  price = 1500, anim = 'body' },
        { id = 'modFrontBumper',  label = 'Front bumper',   modType = 1,  price = 1500, anim = 'body' },
        { id = 'modRearBumper',   label = 'Rear bumper',    modType = 2,  price = 1500, anim = 'body' },
        { id = 'modSideSkirt',    label = 'Side skirts',    modType = 3,  price = 1200, anim = 'body' },
        { id = 'modExhaust',      label = 'Exhaust',        modType = 4,  price = 1000, anim = 'under' },
        { id = 'modFrame',        label = 'Roll cage',      modType = 5,  price = 2000, anim = 'interior' },
        { id = 'modGrille',       label = 'Grille',         modType = 6,  price = 800,  anim = 'body' },
        { id = 'modHood',         label = 'Hood',           modType = 7,  price = 1500, anim = 'body' },
        { id = 'modFender',       label = 'Left fender',    modType = 8,  price = 1000, anim = 'body' },
        { id = 'modRightFender',  label = 'Right fender',   modType = 9,  price = 1000, anim = 'body' },
        { id = 'modRoof',         label = 'Roof',           modType = 10, price = 1200, anim = 'body' },
        { id = 'modHorns',        label = 'Horn',           modType = 14, price = 500,  anim = 'hood' },
        { id = 'modLivery',       label = 'Livery',         modType = 48, price = 2500, anim = 'paint' },
        { id = 'modFrontWheels',  label = 'Wheels',         modType = 23, price = 2000, anim = 'wheel' },
    },
    extras = {
        paint      = { label = 'Paint',        price = 2500, anim = 'paint' }, -- primary/secondary/pearl/wheel colour
        windowTint = { label = 'Window tint',  price = 800,  anim = 'interior' },
        xenon      = { label = 'Xenon lights', price = 1500, anim = 'hood' },
        neon       = { label = 'Neon',         price = 3000, anim = 'under' },
        plate      = { label = 'Plate style',  price = 300,  anim = 'body' },
    },
    -- length (ms) of the native animation played per installed cosmetic category
    animTime = 6000,
}

-- Paint palette shown in the NUI: GTA colour index + label + preview hex
Config.Colours = {
    { index = 0,   label = 'Metallic Black',      hex = '#0d1116' },
    { index = 1,   label = 'Metallic Graphite',   hex = '#1c1d21' },
    { index = 4,   label = 'Metallic Silver',     hex = '#99a1a8' },
    { index = 111, label = 'Metallic White',      hex = '#fffff6' },
    { index = 27,  label = 'Metallic Red',        hex = '#c00e1a' },
    { index = 35,  label = 'Metallic Candy Red',  hex = '#b6111b' },
    { index = 38,  label = 'Metallic Orange',     hex = '#f78616' },
    { index = 88,  label = 'Metallic Yellow',     hex = '#ffcf20' },
    { index = 53,  label = 'Metallic Green',      hex = '#155c2d' },
    { index = 55,  label = 'Lime Green',          hex = '#66b81f' },
    { index = 64,  label = 'Metallic Blue',       hex = '#47578f' },
    { index = 70,  label = 'Ultra Blue',          hex = '#0b9cf1' },
    { index = 145, label = 'Metallic Purple',     hex = '#621276' },
    { index = 137, label = 'Metallic Pink',       hex = '#df5891' },
    { index = 12,  label = 'Matte Black',         hex = '#13181f' },
    { index = 131, label = 'Matte White',         hex = '#fcf9f1' },
    { index = 120, label = 'Chrome',              hex = '#b1b1b1' },
    { index = 158, label = 'Pure Gold',           hex = '#7a5f2c' },
}

-- Invoices (built-in)
Config.Invoice = {
    society = 'society_mechanic', -- esx_addonaccount shared account
    societyShare = 0.7,           -- 70% to society, 30% to the mechanic who sent it
    account = 'bank',             -- customer pays from this account
    maxLines = 10,
    maxTotal = 100000,
    expireSeconds = 60,           -- customer must accept within this time
    maxDistance = 5.0,            -- mechanic <-> customer
    cooldownSeconds = 10,         -- per mechanic
}

-- Towing
Config.Towing = {
    trucks = { `flatbed` },
    attachOffset = vec3(0.0, -2.2, 0.85), -- vehicle position on the bed, relative to the truck
    unloadOffset = vec3(0.0, -9.0, 0.0),  -- where the vehicle is dropped, relative to the truck
    maxDistance = 12.0,                   -- truck <-> vehicle to load
    winchTime = 8000,
}

-- Server rejects a "finish" that arrives faster than expected time * this factor
Config.MinTimeFactor = 0.8
