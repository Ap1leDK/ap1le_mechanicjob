fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'ap1le_mechanicjob'
author 'Ap1leDK'
description 'Mekanikerjob: reparation, fysiske del-skift, tuning, lager og bestilling, chefens computer, bugsering og fakturaer'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    '@ap1le_core/imports.lua',
    'config.lua',
    'shared/colours.lua',
}

client_scripts {
    'client/ui.lua',
    'client/anims.lua',
    'client/main.lua',
    'client/repair.lua',
    'client/tuning.lua',
    'client/billing.lua',
    'client/towing.lua',
    'client/stock.lua',
    'client/computer.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/repair.lua',
    'server/performance.lua',
    'server/tuning.lua',
    'server/billing.lua',
    'server/stock.lua',
    'server/computer.lua',
}

ui_page 'html/index.html'

files {
    'locales/*.json',
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
}

dependencies { 'es_extended', 'ox_lib', 'oxmysql', 'ox_inventory', 'ox_target', 'esx_addonaccount', 'ap1le_core' }
