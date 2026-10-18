-- ap1le_mechanicjob: ox_inventory item definitions
--
-- HOW TO INSTALL
-- 1. Open ox_inventory/data/items.lua on your server.
-- 2. Paste every entry below inside the main table that file returns
--    (the table that already holds the other items, e.g. ['bread'] = { ... }).
-- 3. Add one PNG per item to ox_inventory/web/images/<name>.png
--    (for example ox_inventory/web/images/engine_lvl1.png).
-- 4. Restart ox_inventory (or the server) so the items are loaded.
--
-- Weights are in grams.

-- Repair items (Config.Repair)
['engine_repair_kit'] = { label = 'Engine repair kit', weight = 3000, stack = true, close = true, description = 'Used to repair a damaged engine in a workshop.' },
['body_repair_kit'] = { label = 'Body repair kit', weight = 3000, stack = true, close = true, description = 'Used to repair vehicle body damage in a workshop.' },
['tyre'] = { label = 'Spare tyre', weight = 8000, stack = true, close = true, description = 'A replacement tyre for changing a damaged wheel.' },
['repair_kit'] = { label = 'Repair kit', weight = 2000, stack = true, close = true, description = 'Quick field repair for the engine, usable anywhere.' },

-- Car wash (Config.Wash)
['cleaning_kit'] = { label = 'Cleaning kit', weight = 1500, stack = true, close = true, description = 'Bucket, sponge and cleaner for washing a vehicle.' },

-- Performance: engine (Config.Performance.engine)
['engine_lvl1'] = { label = 'Engine upgrade Level 1', weight = 25000, stack = true, close = true, description = 'Engine block upgrade, stage 1.' },
['engine_lvl2'] = { label = 'Engine upgrade Level 2', weight = 25000, stack = true, close = true, description = 'Engine block upgrade, stage 2.' },
['engine_lvl3'] = { label = 'Engine upgrade Level 3', weight = 25000, stack = true, close = true, description = 'Engine block upgrade, stage 3.' },
['engine_lvl4'] = { label = 'Engine upgrade Level 4', weight = 25000, stack = true, close = true, description = 'Engine block upgrade, stage 4 (race spec).' },

-- Performance: brakes (Config.Performance.brakes)
['brakes_lvl1'] = { label = 'Brake upgrade Level 1', weight = 4000, stack = true, close = true, description = 'Brake pads and discs, stage 1.' },
['brakes_lvl2'] = { label = 'Brake upgrade Level 2', weight = 4000, stack = true, close = true, description = 'Brake pads and discs, stage 2.' },
['brakes_lvl3'] = { label = 'Brake upgrade Level 3', weight = 4000, stack = true, close = true, description = 'Brake pads and discs, stage 3 (race spec).' },

-- Performance: transmission (Config.Performance.transmission)
['transmission_lvl1'] = { label = 'Transmission upgrade Level 1', weight = 15000, stack = true, close = true, description = 'Gearbox upgrade, stage 1.' },
['transmission_lvl2'] = { label = 'Transmission upgrade Level 2', weight = 15000, stack = true, close = true, description = 'Gearbox upgrade, stage 2.' },
['transmission_lvl3'] = { label = 'Transmission upgrade Level 3', weight = 15000, stack = true, close = true, description = 'Gearbox upgrade, stage 3 (race spec).' },

-- Performance: suspension (Config.Performance.suspension)
['suspension_lvl1'] = { label = 'Suspension upgrade Level 1', weight = 6000, stack = true, close = true, description = 'Suspension kit, stage 1.' },
['suspension_lvl2'] = { label = 'Suspension upgrade Level 2', weight = 6000, stack = true, close = true, description = 'Suspension kit, stage 2.' },
['suspension_lvl3'] = { label = 'Suspension upgrade Level 3', weight = 6000, stack = true, close = true, description = 'Suspension kit, stage 3.' },
['suspension_lvl4'] = { label = 'Suspension upgrade Level 4', weight = 6000, stack = true, close = true, description = 'Suspension kit, stage 4 (race spec).' },

-- Performance: armor (Config.Performance.armor)
['armor_lvl1'] = { label = 'Armor upgrade Level 1', weight = 10000, stack = true, close = true, description = 'Reinforced body panels, stage 1.' },
['armor_lvl2'] = { label = 'Armor upgrade Level 2', weight = 10000, stack = true, close = true, description = 'Reinforced body panels, stage 2.' },
['armor_lvl3'] = { label = 'Armor upgrade Level 3', weight = 10000, stack = true, close = true, description = 'Reinforced body panels, stage 3.' },
['armor_lvl4'] = { label = 'Armor upgrade Level 4', weight = 10000, stack = true, close = true, description = 'Reinforced body panels, stage 4.' },
['armor_lvl5'] = { label = 'Armor upgrade Level 5', weight = 10000, stack = true, close = true, description = 'Reinforced body panels, stage 5 (full armour).' },

-- Performance: turbo (Config.Performance.turbo, toggle)
['turbo'] = { label = 'Turbocharger', weight = 5000, stack = true, close = true, description = 'Turbocharger kit for the engine bay.' },
