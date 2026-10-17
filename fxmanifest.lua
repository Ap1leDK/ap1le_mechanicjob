fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'ap1le_mechanicjob'
author 'Ap1leDK'
description 'Mechanic job: repair, part swaps, cosmetic tuning, towing and invoices'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'config.lua',
}

client_scripts {
    'client/ui.lua',
    'client/anims.lua',
    'client/main.lua',
    'client/repair.lua',
    'client/tuning.lua',
    'client/billing.lua',
    'client/towing.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/repair.lua',
    'server/performance.lua',
    'server/tuning.lua',
    'server/billing.lua',
}

ui_page 'html/index.html'

files {
    'locales/*.json',
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

dependencies { 'es_extended', 'ox_lib', 'oxmysql', 'ox_inventory', 'ox_target', 'esx_addonaccount' }
