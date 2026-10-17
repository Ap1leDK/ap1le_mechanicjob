lib.locale()

Config = {}

Config.Job = 'mechanic'

-- Grade (ESX job_grade) that counts as "chef": staff, economy and price list on the computer.
-- Every mechanic can use the computer's stock and order apps.
Config.BossGrade = 3

-- Workshops: repair (full), performance swaps and cosmetic tuning only work inside these.
-- stash    = the workshop's shared parts storage (ox_inventory stash). Swaps take parts from here
--            and put the old part back here.
-- computer = a physical laptop on a desk (spawned by the script when spawnProp = true).
--            coords.w = heading of the laptop.
-- delivery = where ordered crates are dropped off for pickup.
-- All coordinates are defaults for the vanilla map; adjust to your MLOs.
Config.Workshops = {
    {
        id = 'bennys',
        label = "Benny's Original Motor Works",
        coords = vec3(-205.62, -1310.62, 31.30),
        radius = 25.0,
        blip = { sprite = 446, colour = 5, scale = 0.8 },
        stash = { coords = vec3(-199.90, -1318.40, 31.09), label = "Benny's lager", slots = 80, weight = 2000000 },
        computer = { coords = vec4(-196.85, -1317.30, 31.95, 90.0), spawnProp = true },
        delivery = vec4(-189.20, -1290.60, 31.30, 0.0),
    },
    {
        id = 'lsc_burton',
        label = 'Los Santos Customs Burton',
        coords = vec3(-337.38, -136.92, 39.01),
        radius = 20.0,
        blip = { sprite = 72, colour = 5, scale = 0.8 },
        stash = { coords = vec3(-345.55, -130.20, 39.01), label = 'LSC lager', slots = 80, weight = 2000000 },
        computer = { coords = vec4(-347.10, -133.20, 39.90, 250.0), spawnProp = true },
        delivery = vec4(-356.40, -114.30, 38.70, 70.0),
    },
}

-- Max distance between the mechanic and the vehicle for any action (server-checked)
Config.MaxVehicleDistance = 6.0

-- Repairs. Items come from the mechanic's own inventory (field repair works anywhere).
-- time = total sequence length in ms; the server rejects a finish that arrives sooner than
-- time * Config.MinTimeFactor.
Config.Repair = {
    engine = { item = 'engine_repair_kit', time = 15000, workshopOnly = true },
    body   = { item = 'body_repair_kit',   time = 20000, workshopOnly = true },
    tyre   = { item = 'tyre',              time = 10000, workshopOnly = true },
    -- field repair: anywhere, engine only, up to maxEngineHealth (1000 = perfect)
    field  = { item = 'repair_kit',        time = 12000, workshopOnly = false, maxEngineHealth = 600.0 },
}

-- Performance parts. One item per level; levels[1] = GTA mod index 0, levels[2] = index 1 ...
-- Stock (mod index -1) has no item. Parts are taken from the workshop stash, and the old part
-- goes back into the stash. removeTime/installTime: length (ms) of the remove/install sequences.
Config.Performance = {
    engine = {
        label = 'Motor', modType = 11, propKey = 'modEngine',
        levels = { 'engine_lvl1', 'engine_lvl2', 'engine_lvl3', 'engine_lvl4' },
        removeTime = 25000, installTime = 25000,
    },
    brakes = {
        label = 'Bremser', modType = 12, propKey = 'modBrakes',
        levels = { 'brakes_lvl1', 'brakes_lvl2', 'brakes_lvl3' },
        removeTime = 15000, installTime = 15000,
    },
    transmission = {
        label = 'Gearkasse', modType = 13, propKey = 'modTransmission',
        levels = { 'transmission_lvl1', 'transmission_lvl2', 'transmission_lvl3' },
        removeTime = 20000, installTime = 20000,
    },
    suspension = {
        label = 'Undervogn', modType = 15, propKey = 'modSuspension',
        levels = { 'suspension_lvl1', 'suspension_lvl2', 'suspension_lvl3', 'suspension_lvl4' },
        removeTime = 20000, installTime = 20000,
    },
    armor = {
        label = 'Panser', modType = 16, propKey = 'modArmor',
        levels = { 'armor_lvl1', 'armor_lvl2', 'armor_lvl3', 'armor_lvl4', 'armor_lvl5' },
        removeTime = 15000, installTime = 15000,
    },
    turbo = {
        label = 'Turbo', modType = 18, propKey = 'modTurbo', toggle = true,
        levels = { 'turbo' },
        removeTime = 12000, installTime = 12000,
    },
}

-- Parts shop (ordered from the computer or from the tuning menu). Paid by the society account.
-- price = purchase price per unit. Orders arrive as a crate at the workshop's delivery point after
-- deliveryMinutes; a mechanic unpacks the crate into the workshop stash.
Config.Shop = {
    deliveryMinutes = 5,
    unpackTime = 8000,            -- ms, server-checked like repairs
    maxPerLine = 20,              -- max units of one item per order
    maxLines = 15,                -- max different items per order
    maxOpenOrders = 5,            -- per workshop (ordered or waiting for pickup)
    crateModel = `prop_box_wood05a`,
    items = {
        repair_kit = 400, engine_repair_kit = 900, body_repair_kit = 900, tyre = 250,
        engine_lvl1 = 6000, engine_lvl2 = 11000, engine_lvl3 = 18000, engine_lvl4 = 27000,
        brakes_lvl1 = 3000, brakes_lvl2 = 6000, brakes_lvl3 = 10000,
        transmission_lvl1 = 5000, transmission_lvl2 = 9000, transmission_lvl3 = 14000,
        suspension_lvl1 = 2500, suspension_lvl2 = 4500, suspension_lvl3 = 7000, suspension_lvl4 = 10000,
        armor_lvl1 = 5000, armor_lvl2 = 9000, armor_lvl3 = 14000, armor_lvl4 = 20000, armor_lvl5 = 28000,
        turbo = 15000,
    },
}

-- Cosmetic tuning: no items. price = default price per change (the chef can override every price
-- from the computer's price list). Prices pre-fill the invoice.
-- groups: the top-level menu in the order shown. Every mod has a group, and optionally a sub
-- (sub-category inside the group). propKey = key in lib.getVehicleProperties.
-- anim = which Anim.Cosmetic animation is played when it is installed.
Config.Cosmetic = {
    animTime = 6000,  -- ms per distinct animation type played during install
    maxPrice = 250000,

    groups = {
        { id = 'bodywork', label = 'Karosseri',      icon = 'car-side' },
        { id = 'wheels',   label = 'Hjul',           icon = 'circle-dot' },
        { id = 'respray',  label = 'Lakering',       icon = 'fill-drip' },
        { id = 'interior', label = 'Kabine',         icon = 'couch' },
        { id = 'engine',   label = 'Motorrum',       icon = 'gears' },
        { id = 'lights',   label = 'Lys',            icon = 'lightbulb' },
        { id = 'plates',   label = 'Nummerplade',    icon = 'id-card' },
        { id = 'other',    label = 'Andet',          icon = 'ellipsis' },
    },

    -- Standard GTA mod slots (only shown when GetNumVehicleMods > 0 for the vehicle)
    mods = {
        { id = 'modSpoilers',       modType = 0,  group = 'bodywork', sub = 'Bagende', label = 'Spoiler',       price = 1500, anim = 'body' },
        { id = 'modFrontBumper',    modType = 1,  group = 'bodywork', sub = 'Front',   label = 'Frontkofanger', price = 1500, anim = 'body' },
        { id = 'modRearBumper',     modType = 2,  group = 'bodywork', sub = 'Bagende', label = 'Bagkofanger',   price = 1500, anim = 'body' },
        { id = 'modSideSkirt',      modType = 3,  group = 'bodywork', sub = 'Sider',   label = 'Sideskørter',   price = 1200, anim = 'body' },
        { id = 'modExhaust',        modType = 4,  group = 'bodywork', sub = 'Bagende', label = 'Udstødning',    price = 1000, anim = 'under' },
        { id = 'modFrame',          modType = 5,  group = 'bodywork', sub = 'Sider',   label = 'Rullebur',      price = 2000, anim = 'interior' },
        { id = 'modGrille',         modType = 6,  group = 'bodywork', sub = 'Front',   label = 'Grill',         price = 800,  anim = 'body' },
        { id = 'modHood',           modType = 7,  group = 'bodywork', sub = 'Front',   label = 'Motorhjelm',    price = 1500, anim = 'body' },
        { id = 'modFender',         modType = 8,  group = 'bodywork', sub = 'Sider',   label = 'Venstre skærm', price = 1000, anim = 'body' },
        { id = 'modRightFender',    modType = 9,  group = 'bodywork', sub = 'Sider',   label = 'Højre skærm',   price = 1000, anim = 'body' },
        { id = 'modRoof',           modType = 10, group = 'bodywork', sub = 'Tag',     label = 'Tag',           price = 1200, anim = 'body' },
        { id = 'modTrimA',          modType = 27, group = 'bodywork', sub = 'Sider',   label = 'Pynteliste',    price = 800,  anim = 'body' },
        { id = 'modAerials',        modType = 43, group = 'bodywork', sub = 'Tag',     label = 'Antenner',      price = 500,  anim = 'body' },
        { id = 'modTank',           modType = 45, group = 'bodywork', sub = 'Sider',   label = 'Tankdæksel',    price = 500,  anim = 'body' },
        { id = 'modWindows',        modType = 46, group = 'bodywork', sub = 'Sider',   label = 'Ruder',         price = 800,  anim = 'body' },

        -- Wheels: rims are sub-categorised per wheel type (sport, muscle, ...) by the client
        { id = 'modFrontWheels',    modType = 23, group = 'wheels',   label = 'Fælge',          price = 2000, anim = 'wheel' },
        { id = 'modBackWheels',     modType = 24, group = 'wheels',   label = 'Baghjul (MC)',   price = 2000, anim = 'wheel' },

        { id = 'modOrnaments',      modType = 28, group = 'interior', sub = 'Instrumentbræt', label = 'Ornamenter',   price = 400,  anim = 'interior' },
        { id = 'modDashboard',      modType = 29, group = 'interior', sub = 'Instrumentbræt', label = 'Instrumentbræt', price = 1200, anim = 'interior' },
        { id = 'modDial',           modType = 30, group = 'interior', sub = 'Instrumentbræt', label = 'Måleur',       price = 800,  anim = 'interior' },
        { id = 'modDoorSpeaker',    modType = 31, group = 'interior', sub = 'Lyd',            label = 'Dørhøjttalere', price = 800, anim = 'interior' },
        { id = 'modSeats',          modType = 32, group = 'interior', sub = 'Sæder',          label = 'Sæder',        price = 1500, anim = 'interior' },
        { id = 'modSteeringWheel',  modType = 33, group = 'interior', sub = 'Instrumentbræt', label = 'Rat',          price = 1000, anim = 'interior' },
        { id = 'modShifterLeavers', modType = 34, group = 'interior', sub = 'Instrumentbræt', label = 'Gearstang',    price = 600,  anim = 'interior' },
        { id = 'modAPlate',         modType = 35, group = 'interior', sub = 'Sæder',          label = 'Skilte',       price = 400,  anim = 'interior' },
        { id = 'modSpeakers',       modType = 36, group = 'interior', sub = 'Lyd',            label = 'Højttalere',   price = 1000, anim = 'interior' },
        { id = 'modTrunk',          modType = 37, group = 'interior', sub = 'Bagagerum',      label = 'Bagagerum',    price = 1200, anim = 'interior' },

        { id = 'modHydrolic',       modType = 38, group = 'engine',   label = 'Hydraulik',      price = 3000, anim = 'under' },
        { id = 'modEngineBlock',    modType = 39, group = 'engine',   label = 'Motorblok',      price = 1500, anim = 'hood' },
        { id = 'modAirFilter',      modType = 40, group = 'engine',   label = 'Luftfilter',     price = 800,  anim = 'hood' },
        { id = 'modStruts',         modType = 41, group = 'engine',   label = 'Fjederbensstivere', price = 1000, anim = 'hood' },
        { id = 'modArchCover',      modType = 42, group = 'engine',   label = 'Hjulkasser',     price = 800,  anim = 'body' },
        { id = 'modTrimB',          modType = 44, group = 'engine',   label = 'Motorpynt',      price = 600,  anim = 'hood' },

        { id = 'modPlateHolder',    modType = 25, group = 'plates',   label = 'Pladeholder',    price = 300,  anim = 'body' },
        { id = 'modVanityPlate',    modType = 26, group = 'plates',   label = 'Forfængelighedsplade', price = 300, anim = 'body' },

        { id = 'modHorns',          modType = 14, group = 'other',    label = 'Horn',           price = 500,  anim = 'hood' },
        { id = 'modLivery',         modType = 48, group = 'other',    label = 'Livery',         price = 2500, anim = 'paint' },
    },

    -- Non-slot options. id = the price-list id. The client builds their sub-categories.
    extras = {
        wheelType     = { group = 'wheels',   label = 'Fælgtype',        price = 0,    anim = 'wheel' },
        customTires   = { group = 'wheels',   label = 'Specialdæk',      price = 800,  anim = 'wheel' },
        tyreSmoke     = { group = 'wheels',   label = 'Dækrøg',          price = 1500, anim = 'wheel' },
        wheelColor    = { group = 'wheels',   label = 'Fælgfarve',       price = 1000, anim = 'paint' },
        color1        = { group = 'respray',  label = 'Primærfarve',     price = 2500, anim = 'paint' },
        color2        = { group = 'respray',  label = 'Sekundærfarve',   price = 2000, anim = 'paint' },
        pearlescent   = { group = 'respray',  label = 'Perlemor',        price = 1500, anim = 'paint' },
        interiorColor = { group = 'interior', label = 'Kabinefarve',     price = 1000, anim = 'interior' },
        dashboardColor= { group = 'interior', label = 'Instrumentfarve', price = 800,  anim = 'interior' },
        xenon         = { group = 'lights',   label = 'Xenon',           price = 1500, anim = 'hood' },
        neon          = { group = 'lights',   label = 'Neon',            price = 3000, anim = 'under' },
        windowTint    = { group = 'other',    label = 'Rudetoning',      price = 800,  anim = 'interior' },
        plateIndex    = { group = 'plates',   label = 'Pladetype',       price = 300,  anim = 'body' },
        oldLivery     = { group = 'other',    label = 'Livery (klassisk)', price = 2500, anim = 'paint' },
    },
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

-- Chef's computer
Config.Computer = {
    useDistance = 2.0,            -- client target distance
    serverDistance = 4.0,         -- server: max distance to a computer for every computer call
    hireDistance = 10.0,          -- players that can be hired must be this close to the computer
    account = 'bank',             -- chef's own account for society deposit/withdraw
    maxTransfer = 1000000,
    historyRows = 50,
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
