-- ap1le_mechanicjob: every GTA V vehicle paint index (primary, secondary, pearlescent, wheel,
-- interior and dashboard colours all use the same palette), grouped like the mod shop.
--
-- Colours = { groups = { { id, label, minBuild?, colours = { { index, label, hex } } } } }
--   index = value for SetVehicleColours / SetVehicleExtraColours / SetVehicleInteriorColor ...
--   label = Danish name, hex = approximate on-screen colour for the NUI swatch (not used in game).
--
-- Sources:
--  * Indices 0-160 and grouping: the game's own mod shop lists as used by vMenu
--    (github.com/TomGrobbe/vMenu, VehicleColorTables.cs: Classic/Matte/Metal/Utility/Worn) and the
--    material type per index from github.com/DurtyFree/gta-v-data-dumps (vehicleColors.json, MetallicId).
--    Names: FiveM docs "Vehicle Colors" (github.com/citizenfx/fivem-docs) and the data dump, in Danish.
--  * hex 0-160: median colour of the car body in the FiveM docs reference renders
--    (fivem-docs static/vehicle-colors/<index>.webp), a few metals tuned by hand.
--  * Chameleon 161-222: names from Qbox qbx_customs (config/client.lua, "Chameleon"), translated;
--    hex is only a rough main tone (these paints change colour with the viewing angle).
--    They need game build 2944 or newer (sv_enforceGameBuild); on older builds the client leaves the
--    group out (minBuild). qbx_customs also lists 223-242 ("Fubuki-jo Specials"); those could not be
--    confirmed as vanilla game colours (they show up in a paint add-on mod), so they are left out.
--  * Unused: index 255 is not a colour (xenon "default" uses it, see client/tuning.lua).

Colours = {}

Colours.groups = {
    { id = 'metallic', label = 'Metallisk', colours = {
        { index = 0, label = 'Sort', hex = '#202322' },
        { index = 1, label = 'Grafit', hex = '#232524' },
        { index = 2, label = 'Sort stål', hex = '#303437' },
        { index = 3, label = 'Mørkt stål', hex = '#393E41' },
        { index = 4, label = 'Sølv', hex = '#626C75' },
        { index = 5, label = 'Blålig sølv', hex = '#7B8590' },
        { index = 6, label = 'Valset stål', hex = '#5A6269' },
        { index = 7, label = 'Skyggesølv', hex = '#404B58' },
        { index = 8, label = 'Stensølv', hex = '#414546' },
        { index = 9, label = 'Midnatssølv', hex = '#31373A' },
        { index = 10, label = 'Støbejernssølv', hex = '#343C40' },
        { index = 11, label = 'Antracitsort', hex = '#2B2D2C' },
        { index = 27, label = 'Rød', hex = '#6F2828' },
        { index = 28, label = 'Torinorød', hex = '#892A28' },
        { index = 29, label = 'Formelrød', hex = '#712828' },
        { index = 30, label = 'Flammerød', hex = '#682C2A' },
        { index = 31, label = 'Elegant rød', hex = '#542A29' },
        { index = 32, label = 'Granatrød', hex = '#522B2B' },
        { index = 33, label = 'Solnedgangsrød', hex = '#442B27' },
        { index = 34, label = 'Cabernetrød', hex = '#36282A' },
        { index = 35, label = 'Bolsjerød', hex = '#6A282D' },
        { index = 36, label = 'Solopgangsorange', hex = '#813B27' },
        { index = 37, label = 'Klassisk guld', hex = '#8A6A3E' },
        { index = 38, label = 'Orange', hex = '#AB5727' },
        { index = 49, label = 'Mørkegrøn', hex = '#252D28' },
        { index = 50, label = 'Racergrøn', hex = '#25312A' },
        { index = 51, label = 'Havgrøn', hex = '#263635' },
        { index = 52, label = 'Olivengrøn', hex = '#313A35' },
        { index = 53, label = 'Klar grøn', hex = '#254828' },
        { index = 54, label = 'Benzingrøn', hex = '#285157' },
        { index = 61, label = 'Galakseblå', hex = '#252B2E' },
        { index = 62, label = 'Mørkeblå', hex = '#262C3E' },
        { index = 63, label = 'Saxonblå', hex = '#2F4160' },
        { index = 64, label = 'Blå', hex = '#253167' },
        { index = 65, label = 'Marineblå', hex = '#465C85' },
        { index = 66, label = 'Havneblå', hex = '#363F4C' },
        { index = 67, label = 'Diamantblå', hex = '#8FA9C2' },
        { index = 68, label = 'Surfblå', hex = '#486E87' },
        { index = 69, label = 'Nautisk blå', hex = '#2F4152' },
        { index = 70, label = 'Ultrablå', hex = '#2562B8' },
        { index = 71, label = 'Schafter-lilla', hex = '#2E3041' },
        { index = 72, label = 'Spinnaker-lilla', hex = '#2D2F3D' },
        { index = 73, label = 'Racerblå', hex = '#28427C' },
        { index = 74, label = 'Lyseblå', hex = '#44678D' },
        { index = 88, label = 'Gul', hex = '#C58D2A' },
        { index = 89, label = 'Racergul', hex = '#B6A126' },
        { index = 90, label = 'Bronze', hex = '#534432' },
        { index = 91, label = 'Duggul', hex = '#97A23A' },
        { index = 92, label = 'Limegrøn', hex = '#5C9227' },
        { index = 94, label = 'Feltzer-brun', hex = '#383228' },
        { index = 95, label = 'Creek-brun', hex = '#363630' },
        { index = 96, label = 'Chokoladebrun', hex = '#2A2A28' },
        { index = 97, label = 'Ahornbrun', hex = '#40362D' },
        { index = 98, label = 'Sadelbrun', hex = '#484138' },
        { index = 99, label = 'Halmbrun', hex = '#646053' },
        { index = 100, label = 'Mosbrun', hex = '#43483F' },
        { index = 101, label = 'Bisonbrun', hex = '#343130' },
        { index = 102, label = 'Bøgebrun', hex = '#5E5D48' },
        { index = 103, label = 'Mørk bøgebrun', hex = '#352D29' },
        { index = 104, label = 'Siennabrun', hex = '#473027' },
        { index = 105, label = 'Sandbrun', hex = '#716D56' },
        { index = 106, label = 'Blegbrun', hex = '#92917F' },
        { index = 107, label = 'Creme', hex = '#B1B0A3' },
        { index = 111, label = 'Ishvid', hex = '#C0C6CA' },
        { index = 112, label = 'Frosthvid', hex = '#A2ADB9' },
        { index = 135, label = 'Hot pink', hex = '#A32C68' },
        { index = 136, label = 'Laksepink', hex = '#C5969A' },
        { index = 137, label = 'Pfister-pink', hex = '#8C4063' },
        { index = 138, label = 'Klar orange', hex = '#AD702A' },
        { index = 141, label = 'Midnatsblå', hex = '#1E2021' },
        { index = 142, label = 'Midnatslilla', hex = '#1E2021' },
        { index = 143, label = 'Vinrød', hex = '#1F1F1F' },
        { index = 145, label = 'Klar lilla', hex = '#3E2852' },
        { index = 146, label = 'Meget mørkeblå', hex = '#26282A' },
        { index = 147, label = 'Carbonsort', hex = '#1F2121' },
        { index = 150, label = 'Lavarød', hex = '#6F2927' },
    } },
    { id = 'matte', label = 'Mat', colours = {
        { index = 12, label = 'Sort', hex = '#151515' },
        { index = 13, label = 'Grå', hex = '#1C1E1E' },
        { index = 14, label = 'Lysegrå', hex = '#353C3E' },
        { index = 39, label = 'Rød', hex = '#7A1414' },
        { index = 40, label = 'Mørkerød', hex = '#3C1413' },
        { index = 41, label = 'Orange', hex = '#9F4814' },
        { index = 42, label = 'Gul', hex = '#BC8313' },
        { index = 55, label = 'Limegrøn', hex = '#458A14' },
        { index = 82, label = 'Mørkeblå', hex = '#131A39' },
        { index = 83, label = 'Blå', hex = '#1A287E' },
        { index = 84, label = 'Midnatsblå', hex = '#13263D' },
        { index = 128, label = 'Grøn', hex = '#29372B' },
        { index = 129, label = 'Brun', hex = '#6B665E' },
        { index = 131, label = 'Ishvid', hex = '#B6BCBF' },
        { index = 148, label = 'Schafter-lilla', hex = '#37154C' },
        { index = 149, label = 'Midnatslilla', hex = '#141316' },
        { index = 151, label = 'Skovgrøn', hex = '#1B201B' },
        { index = 152, label = 'Militærgrøn', hex = '#363B2E' },
        { index = 153, label = 'Mørk jord', hex = '#3F3D36' },
        { index = 154, label = 'Ørkenbeige', hex = '#716D60' },
        { index = 155, label = 'Løvgrøn', hex = '#313834' },
    } },
    { id = 'metals', label = 'Metaller', colours = {
        { index = 117, label = 'Børstet stål', hex = '#626B6D' },
        { index = 118, label = 'Børstet sort stål', hex = '#3A3F42' },
        { index = 119, label = 'Børstet aluminium', hex = '#737D82' },
        { index = 158, label = 'Rent guld', hex = '#A88A4C' },
        { index = 159, label = 'Børstet guld', hex = '#8F7A4E' },
        { index = 160, label = 'Blankt guld', hex = '#D9B95A' },
    } },
    { id = 'chrome', label = 'Krom', colours = {
        { index = 120, label = 'Krom', hex = '#B8BEC2' },
    } },
    { id = 'worn', label = 'Slidt/brugs', colours = {
        { index = 15, label = 'Brugs sort', hex = '#242626' },
        { index = 16, label = 'Brugs sort poly', hex = '#282B2A' },
        { index = 17, label = 'Brugs mørk sølv', hex = '#303437' },
        { index = 18, label = 'Brugs sølv', hex = '#5F676F' },
        { index = 19, label = 'Brugs gunmetal', hex = '#323B40' },
        { index = 20, label = 'Brugs skyggesølv', hex = '#3F4A57' },
        { index = 21, label = 'Slidt sort', hex = '#1F2123' },
        { index = 22, label = 'Slidt grafit', hex = '#2B2E2F' },
        { index = 23, label = 'Slidt sølvgrå', hex = '#5F676B' },
        { index = 24, label = 'Slidt sølv', hex = '#858E9D' },
        { index = 25, label = 'Slidt blåsølv', hex = '#6B798F' },
        { index = 26, label = 'Slidt skyggesølv', hex = '#425160' },
        { index = 43, label = 'Brugs rød', hex = '#5B2524' },
        { index = 44, label = 'Brugs klar rød', hex = '#8B2525' },
        { index = 45, label = 'Brugs granatrød', hex = '#542C27' },
        { index = 46, label = 'Slidt rød', hex = '#5E3133' },
        { index = 47, label = 'Slidt gyldenrød', hex = '#764D3E' },
        { index = 48, label = 'Slidt mørkerød', hex = '#2B1D1C' },
        { index = 56, label = 'Brugs mørkegrøn', hex = '#27322D' },
        { index = 57, label = 'Brugs grøn', hex = '#23452B' },
        { index = 58, label = 'Slidt mørkegrøn', hex = '#233127' },
        { index = 59, label = 'Slidt grøn', hex = '#324133' },
        { index = 60, label = 'Slidt havskum', hex = '#4A6663' },
        { index = 75, label = 'Brugs mørkeblå', hex = '#242B40' },
        { index = 76, label = 'Brugs midnatsblå', hex = '#272A34' },
        { index = 77, label = 'Brugs blå', hex = '#293B61' },
        { index = 78, label = 'Brugs havskumsblå', hex = '#3D5363' },
        { index = 79, label = 'Brugs lynblå', hex = '#293773' },
        { index = 80, label = 'Brugs Maui-blå', hex = '#314AA4' },
        { index = 81, label = 'Brugs klar blå', hex = '#2F32A4' },
        { index = 85, label = 'Slidt mørkeblå', hex = '#324160' },
        { index = 86, label = 'Slidt blå', hex = '#38466A' },
        { index = 87, label = 'Slidt lyseblå', hex = '#406F9A' },
        { index = 93, label = 'Brugs champagne', hex = '#5E5F5C' },
        { index = 108, label = 'Brugs brun', hex = '#2F2E26' },
        { index = 109, label = 'Brugs mellembrun', hex = '#464031' },
        { index = 110, label = 'Brugs lysebrun', hex = '#6B6557' },
        { index = 113, label = 'Slidt honningbeige', hex = '#646861' },
        { index = 114, label = 'Slidt brun', hex = '#2D2B28' },
        { index = 115, label = 'Slidt mørkebrun', hex = '#232323' },
        { index = 116, label = 'Slidt halmbeige', hex = '#40413B' },
        { index = 121, label = 'Slidt råhvid', hex = '#9FA5A9' },
        { index = 122, label = 'Brugs råhvid', hex = '#91989B' },
        { index = 123, label = 'Slidt orange', hex = '#A46B26' },
        { index = 124, label = 'Slidt lys orange', hex = '#AC633D' },
        { index = 125, label = 'Securicor-grøn', hex = '#507F4C' },
        { index = 126, label = 'Slidt taxagul', hex = '#A6862F' },
        { index = 127, label = 'Politiblå', hex = '#377FA2' },
        { index = 130, label = 'Slidt brændt orange', hex = '#AE743E' },
        { index = 132, label = 'Slidt hvid', hex = '#BFC5C8' },
        { index = 133, label = 'Slidt militærgrøn', hex = '#424930' },
        { index = 134, label = 'Ren hvid', hex = '#C6CCCF' },
        { index = 139, label = 'Brugs limegrøn', hex = '#6CAF53' },
        { index = 140, label = 'Brugs himmelblå', hex = '#24A6CC' },
        { index = 144, label = 'Brugs grå', hex = '#5D635F' },
        { index = 156, label = 'Standard alufælg', hex = '#484F55' },
        { index = 157, label = 'Epsilon-blå', hex = '#6C93AF' },
    } },
    { id = 'chameleon', label = 'Kamæleon', minBuild = 2944, colours = {
        { index = 161, label = 'Anodiseret rød', hex = '#9E1B22' },
        { index = 162, label = 'Anodiseret vin', hex = '#6A1530' },
        { index = 163, label = 'Anodiseret lilla', hex = '#5B2A86' },
        { index = 164, label = 'Anodiseret blå', hex = '#1F4FA8' },
        { index = 165, label = 'Anodiseret grøn', hex = '#1E7A3A' },
        { index = 166, label = 'Anodiseret lime', hex = '#7FB51E' },
        { index = 167, label = 'Anodiseret kobber', hex = '#A4552C' },
        { index = 168, label = 'Anodiseret bronze', hex = '#8C6A35' },
        { index = 169, label = 'Anodiseret champagne', hex = '#C2A878' },
        { index = 170, label = 'Anodiseret guld', hex = '#C9A23A' },
        { index = 171, label = 'Grøn/blå skift', hex = '#1F8A6E' },
        { index = 172, label = 'Grøn/rød skift', hex = '#5E6A2A' },
        { index = 173, label = 'Grøn/brun skift', hex = '#4E5A2C' },
        { index = 174, label = 'Grøn/turkis skift', hex = '#1E9A7E' },
        { index = 175, label = 'Grøn/lilla skift', hex = '#3E6A6A' },
        { index = 176, label = 'Petrol/lilla skift', hex = '#2E5E7A' },
        { index = 177, label = 'Turkis/rød skift', hex = '#2E8A8A' },
        { index = 178, label = 'Turkis/lilla skift', hex = '#3A7A9A' },
        { index = 179, label = 'Cyan/lilla skift', hex = '#3A8AB8' },
        { index = 180, label = 'Blå/pink skift', hex = '#5A5AB8' },
        { index = 181, label = 'Blå/grøn skift', hex = '#2A6A9A' },
        { index = 182, label = 'Lilla/rød skift', hex = '#7A2A6A' },
        { index = 183, label = 'Lilla/grøn skift', hex = '#5A4A7A' },
        { index = 184, label = 'Magenta/grøn skift', hex = '#8A3A7A' },
        { index = 185, label = 'Magenta/gul skift', hex = '#B04A6A' },
        { index = 186, label = 'Bordeaux/grøn skift', hex = '#6A2A3A' },
        { index = 187, label = 'Magenta/cyan skift', hex = '#9A4AA0' },
        { index = 188, label = 'Kobber/lilla skift', hex = '#9A5A4A' },
        { index = 189, label = 'Magenta/orange skift', hex = '#B04A5A' },
        { index = 190, label = 'Rød/orange skift', hex = '#B83A2A' },
        { index = 191, label = 'Orange/lilla skift', hex = '#B8642A' },
        { index = 192, label = 'Orange/blå skift', hex = '#B8762A' },
        { index = 193, label = 'Hvid/lilla skift', hex = '#C8C0D8' },
        { index = 194, label = 'Rød/regnbue skift', hex = '#B8302E' },
        { index = 195, label = 'Blå/regnbue skift', hex = '#2E5AB8' },
        { index = 196, label = 'Mørkegrøn perle', hex = '#1A4A2E' },
        { index = 197, label = 'Mørk petrol perle', hex = '#1A4A4E' },
        { index = 198, label = 'Mørkeblå perle', hex = '#1A2A5E' },
        { index = 199, label = 'Mørklilla perle', hex = '#3A1E5A' },
        { index = 200, label = 'Olieglans perle', hex = '#2A2A3A' },
        { index = 201, label = 'Lysegrøn perle', hex = '#8AD8A0' },
        { index = 202, label = 'Lyseblå perle', hex = '#8AB8E8' },
        { index = 203, label = 'Lyselilla perle', hex = '#B8A0E0' },
        { index = 204, label = 'Lyserød perle', hex = '#E8A8C8' },
        { index = 205, label = 'Råhvid perle', hex = '#E8E4D8' },
        { index = 206, label = 'Sød pink perle', hex = '#F0A0C8' },
        { index = 207, label = 'Babygul perle', hex = '#F0E098' },
        { index = 208, label = 'Babygrøn perle', hex = '#A8E0A8' },
        { index = 209, label = 'Babyblå perle', hex = '#A8D0F0' },
        { index = 210, label = 'Creme perle', hex = '#E8D8B8' },
        { index = 211, label = 'Hvid prismatisk', hex = '#E0E4EC' },
        { index = 212, label = 'Grafit prismatisk', hex = '#4A4E58' },
        { index = 213, label = 'Blå prismatisk', hex = '#2A4AA8' },
        { index = 214, label = 'Lilla prismatisk', hex = '#5A2A98' },
        { index = 215, label = 'Hot pink prismatisk', hex = '#D0307A' },
        { index = 216, label = 'Rød prismatisk', hex = '#B0202A' },
        { index = 217, label = 'Grøn prismatisk', hex = '#2A9A4A' },
        { index = 218, label = 'Sort prismatisk', hex = '#1A1A22' },
        { index = 219, label = 'Oliespild prismatisk', hex = '#3A3A4A' },
        { index = 220, label = 'Regnbue prismatisk', hex = '#8A6AB8' },
        { index = 221, label = 'Sort holografisk', hex = '#202028' },
        { index = 222, label = 'Hvid holografisk', hex = '#D8DCE4' },
    } },
}

-- index -> { index, label, hex, group } (shared helper for labels, e.g. on invoices)
Colours.byIndex = {}

for g = 1, #Colours.groups do
    local group = Colours.groups[g]
    for c = 1, #group.colours do
        local colour = group.colours[c]
        Colours.byIndex[colour.index] = { index = colour.index, label = colour.label, hex = colour.hex, group = group.id }
    end
end

---Label of a paint index ("Metallisk rød"), or "#<index>" when unknown.
---@param index integer
---@return string
function Colours.Label(index)
    local colour = Colours.byIndex[index]
    if not colour then return ("#%s"):format(tostring(index)) end

    for g = 1, #Colours.groups do
        local group = Colours.groups[g]
        if group.id == colour.group then
            -- Worn/utility names already say what they are
            if group.id == 'worn' or group.id == 'chrome' or group.id == 'metals' or group.id == 'chameleon' then
                return colour.label
            end
            return ('%s %s'):format(group.label, colour.label:lower())
        end
    end

    return colour.label
end

---Groups usable on the given game build (chameleon needs 2944+). Returns the shared tables, do not modify.
---@param build? integer GetGameBuildNumber() on the client; nil = every group
---@return table[]
function Colours.GroupsForBuild(build)
    if not build then return Colours.groups end

    local list = {}
    for g = 1, #Colours.groups do
        local group = Colours.groups[g]
        if not group.minBuild or build >= group.minBuild then
            list[#list + 1] = group
        end
    end
    return list
end
