-- Levelling guides for the gathering professions, by skill line: what to
-- gather in each stretch of skill and the zones to find it in. Skill levels
-- and zones are Classic's (zone names are English); Fishing's guide is built
-- from the fishing zone table in Windfall.lua.
--   steps: { from, to, what = { { name, skill needed }, ... }, zones = { ... } }
--   ranks: { rank, skill it can be trained at, character level needed }
local _, ns = ...
ns.GatherGuides = {
    [182] = { -- Herbalism
        verb = "Pick",
        ranks = { { rank = "Journeyman", skill = 50, level = 10 }, { rank = "Expert", skill = 125, level = 20 },
            { rank = "Artisan", skill = 200, level = 35 } },
        steps = {
            { from = 1, to = 50, what = { { "Peacebloom", 1 }, { "Silverleaf", 1 }, { "Earthroot", 15 } },
                zones = { "Elwynn Forest", "Dun Morogh", "Teldrassil", "Durotar", "Mulgore", "Tirisfal Glades" } },
            { from = 50, to = 100, what = { { "Mageroyal", 50 }, { "Briarthorn", 70 }, { "Stranglekelp", 85 } },
                zones = { "Westfall", "Loch Modan", "Darkshore", "The Barrens", "Silverpine Forest" } },
            { from = 100, to = 150, what = { { "Bruiseweed", 100 }, { "Wild Steelbloom", 115 }, { "Grave Moss", 120 }, { "Kingsblood", 125 } },
                zones = { "Hillsbrad Foothills", "Wetlands", "Duskwood", "Ashenvale", "Stonetalon Mountains" } },
            { from = 150, to = 205, what = { { "Liferoot", 150 }, { "Fadeleaf", 160 }, { "Goldthorn", 170 }, { "Khadgar's Whisker", 185 }, { "Wintersbite", 195 } },
                zones = { "Arathi Highlands", "Stranglethorn Vale", "Swamp of Sorrows", "Alterac Mountains", "Desolace", "Dustwallow Marsh" } },
            { from = 205, to = 260, what = { { "Firebloom", 205 }, { "Purple Lotus", 210 }, { "Arthas' Tears", 220 }, { "Sungrass", 230 }, { "Blindweed", 235 }, { "Ghost Mushroom", 245 }, { "Gromsblood", 250 } },
                zones = { "Tanaris", "The Hinterlands", "Feralas", "Searing Gorge", "Badlands", "Swamp of Sorrows" } },
            { from = 260, to = 300, what = { { "Golden Sansam", 260 }, { "Dreamfoil", 270 }, { "Mountain Silversage", 280 }, { "Plaguebloom", 285 }, { "Icecap", 290 } },
                zones = { "Felwood", "Un'Goro Crater", "Azshara", "Western Plaguelands", "Eastern Plaguelands", "Winterspring", "Burning Steppes", "Silithus" } },
        },
        tip = "A herb gives a point every time for its first 25 points of skill, then less and less often, and none once you are 100 past it.",
    },
    [186] = { -- Mining
        verb = "Mine",
        ranks = { { rank = "Journeyman", skill = 50, level = 10 }, { rank = "Expert", skill = 125, level = 20 },
            { rank = "Artisan", skill = 200, level = 35 } },
        steps = {
            { from = 1, to = 65, what = { { "Copper Vein", 1 } },
                zones = { "Elwynn Forest", "Dun Morogh", "Durotar", "Mulgore", "Tirisfal Glades", "Darkshore", "Westfall", "Loch Modan", "The Barrens" } },
            { from = 65, to = 125, what = { { "Tin Vein", 65 }, { "Silver Vein", 75 } },
                zones = { "Redridge Mountains", "Duskwood", "Wetlands", "Hillsbrad Foothills", "Ashenvale", "Stonetalon Mountains", "The Barrens" } },
            { from = 125, to = 175, what = { { "Iron Deposit", 125 }, { "Gold Vein", 155 } },
                zones = { "Arathi Highlands", "Alterac Mountains", "Stranglethorn Vale", "Desolace", "Thousand Needles", "Badlands" } },
            { from = 175, to = 245, what = { { "Mithril Deposit", 175 }, { "Truesilver Deposit", 230 } },
                zones = { "Badlands", "Tanaris", "The Hinterlands", "Searing Gorge", "Feralas", "Blasted Lands" } },
            { from = 245, to = 300, what = { { "Small Thorium Vein", 245 }, { "Rich Thorium Vein", 275 } },
                zones = { "Un'Goro Crater", "Burning Steppes", "Winterspring", "Eastern Plaguelands", "Western Plaguelands", "Silithus", "Felwood" } },
        },
        tip = "A vein gives a point every time for its first 25 points of skill, then less and less often, and none once you are 100 past it. Smelting what you mine gives points too while the bar is new to you.",
    },
    [393] = { -- Skinning
        verb = "Skin",
        ranks = { { rank = "Journeyman", skill = 50, level = 10 }, { rank = "Expert", skill = 125, level = 20 },
            { rank = "Artisan", skill = 200, level = 35 } },
        steps = {
            { from = 1, to = 75, what = { { "Beasts up to level 10", 1 }, { "Beasts of level 11 to 17", 10 } },
                zones = { "Elwynn Forest", "Dun Morogh", "Teldrassil", "Durotar", "Mulgore", "Tirisfal Glades", "Westfall", "Loch Modan", "Darkshore", "The Barrens" } },
            { from = 75, to = 150, what = { { "Beasts of level 17 to 30", 75 } },
                zones = { "Redridge Mountains", "Duskwood", "Wetlands", "Hillsbrad Foothills", "Ashenvale", "Stonetalon Mountains", "Thousand Needles" } },
            { from = 150, to = 225, what = { { "Beasts of level 30 to 45", 150 } },
                zones = { "Stranglethorn Vale", "Arathi Highlands", "Desolace", "Badlands", "Swamp of Sorrows", "Dustwallow Marsh" } },
            { from = 225, to = 300, what = { { "Beasts of level 45 to 60", 225 } },
                zones = { "Tanaris", "Feralas", "The Hinterlands", "Un'Goro Crater", "Felwood", "Winterspring", "Western Plaguelands", "Eastern Plaguelands", "Burning Steppes" } },
        },
        tip = "From level 20 up, a beast can be skinned when your skill is 5 times its level (below that, 10 for every level over 10). Beasts close to that limit give a point nearly every time.",
    },
}
