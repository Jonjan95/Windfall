-- Windfall: tracks what you loot, values it with Auctionator's scanned prices
-- and shows gold per hour for the current farming session.
--
-- Two views of the same session:
--   gather  only what came from herbalism, mining, skinning and fishing
--   loot    everything you loot, plus looted coins

local ADDON = "Windfall"
local ns = select(2, ...) or {}
ns.TrainerRecipes = ns.TrainerRecipes or {}
local ReadRecipe, SkillLineOf, ShowShoppingList, ShowRoute, SaveProfessionSoon
local ApplySparkles, StartSparkles, StopSparkles, SkillsChanged, GetawayText, SparkleRecheck
local MAX_ROWS = 14
local WIDTH = 340
local FARM_TOP = 64 -- where the loot list starts on the farming page
local ROW_H = 16
local COIN_ICON = 133784
local MODE_LABEL = { gather = "Gathering", loot = "All loot" }

local db            -- WindfallDB, set on ADDON_LOADED
local running = false
local lastTick      -- GetTime() of the previous timer tick while running
local shownMinute   -- minute of the clock at the last full refresh
local frame         -- main window, built on login
local historyFrame  -- zone history window, built on first use
local Refresh, RefreshHistory, ToggleHistory
local ToggleSettings, RefreshSettings
local ResetInteract
local ToggleProfessions, RefreshProfessions, RefreshHeader
local NewPage, TogglePanel, DockPanel, UndockPanel, PageOpeners
local PanelHeader, SetPanelHeaderRefresh, SetPanelPortrait, CurrentSelection, NoteCharacter, CharacterKeyNow
local SaveInventory, SetBankOpen, HaveCount, TopProfit, CanMake, ShowRecipeDetail
local bar, BuildBar, UpdateBar, UpdateBarIcons
local FISH_ICON, fishingNow, UpdateFishIcon, StartKeyCapture, ReleaseCVars, FishingSkill, OnLureCastStart, OnLureCastSucceeded, OnLureCastEnded
local UpdateAutoLoot, SetFishing, SetFishKey, OnMainHandChanged, OnCombatEnded, OnChannelStart, OnChannelStop, InitFishing

-- ---------------------------------------------------------- item helpers ----

local function ItemInfoInstant(itemID)
    if C_Item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(itemID)
    elseif GetItemInfoInstant then
        return GetItemInfoInstant(itemID)
    end
end

local function ItemIcon(itemID)
    local _, _, _, _, icon = ItemInfoInstant(itemID)
    return icon or 134400 -- question mark
end

local function VendorPrice(itemID)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not info then return nil end
    local price = select(11, info(itemID))
    if type(price) == "number" and price > 0 then return price end
    return nil
end

local function QualityColor(itemID)
    local quality
    if C_Item and C_Item.GetItemQualityByID then
        quality = C_Item.GetItemQualityByID(itemID)
    end
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return c and c.hex or "|cffffffff"
end

-- ------------------------------------------------------------ gathering ----

-- Safety net for clients where herbs are not flagged with the Herb subclass.
local KNOWN_HERBS = {
    [765] = true, [785] = true, [2447] = true, [2449] = true, [2450] = true,
    [2452] = true, [2453] = true, [3355] = true, [3356] = true, [3357] = true,
    [3358] = true, [3369] = true, [3818] = true, [3819] = true, [3820] = true,
    [3821] = true, [4625] = true, [8831] = true, [8836] = true, [8838] = true,
    [8839] = true, [8845] = true, [8846] = true, [13463] = true, [13464] = true,
    [13465] = true, [13466] = true, [13467] = true, [13468] = true, [19726] = true,
}

-- Trade goods subclasses that are always gathering materials.
local ITEM_CLASS_TRADEGOODS = 7
local GATHER_SUBCLASS = {
    [6] = true, -- Leather
    [7] = true, -- Metal & Stone
    [9] = true, -- Herb
}

-- Names of the gathering casts, looked up by spell id so they work in every
-- client language. Ids the client does not know are skipped.
local gatherSpellNames = {}
do
    local getName = (C_Spell and C_Spell.GetSpellName)
        or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
    if getName then
        for _, id in ipairs({
            2366,                              -- Herb Gathering
            2575, 195122,                      -- Mining
            8613, 8617, 8618, 10768, 32678,    -- Skinning
            7620, 131476,                      -- Fishing
        }) do
            local ok, name = pcall(getName, id)
            if ok and type(name) == "string" and name ~= "" then
                gatherSpellNames[name] = true
            end
        end
    end
end

local gatherCastAt = -100   -- when a gathering cast last finished
local gatherLootOpen = false
local gatherLootUntil = -100

local function OnSpellSucceeded(spellID)
    local getName = (C_Spell and C_Spell.GetSpellName)
        or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
    if not (getName and spellID) then return end
    local ok, name = pcall(getName, spellID)
    if ok and name and gatherSpellNames[name] then gatherCastAt = GetTime() end
end

local function OnLootOpened()
    if (IsFishingLoot and IsFishingLoot()) or GetTime() - gatherCastAt < 3 then
        gatherLootOpen = true
    end
end

local function OnLootClosed()
    if gatherLootOpen then
        gatherLootOpen = false
        gatherLootUntil = GetTime() + 1.5 -- loot messages can trail the window
    end
end

-- True when the item came from a node, a skinned corpse or a fishing bobber,
-- or is a gathering material whatever its source.
local function IsGathered(itemID)
    local now = GetTime()
    if gatherLootOpen or now < gatherLootUntil or now - gatherCastAt < 1.5 then
        return true
    end
    if KNOWN_HERBS[itemID] then return true end
    local _, _, _, _, _, classID, subClassID = ItemInfoInstant(itemID)
    return classID == ITEM_CLASS_TRADEGOODS and GATHER_SUBCLASS[subClassID] or false
end

-- --------------------------------------------------------------- prices ----

local function AuctionPrice(itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, itemID)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

-- Best price for one item in copper: the Auctionator price, or the vendor
-- price when that is higher or nothing was scanned. Second return is true
-- when the vendor price was used. nil when the item is worth nothing.
local function UnitPrice(itemID)
    local auction, vendor = AuctionPrice(itemID), VendorPrice(itemID)
    if auction and (not vendor or auction >= vendor) then return auction, false end
    if vendor then return vendor, true end
    return nil
end

local GOLD, SILVER, COPPER = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"

local function Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor(copper % 10000 / 100)
    local c = copper % 100
    if g > 0 then
        return string.format("%d%s %02d%s", g, GOLD, s, SILVER)
    elseif s > 0 then
        return string.format("%d%s %02d%s", s, SILVER, c, COPPER)
    end
    return string.format("%d%s", c, COPPER)
end

-- Minutes only, so the clock does not tick every second.
local function Clock(seconds)
    local minutes = math.floor((seconds or 0) / 60)
    if minutes >= 60 then
        return string.format("%d h %02d min", math.floor(minutes / 60), minutes % 60)
    end
    return minutes .. " min"
end

-- -------------------------------------------------------------- session ----

local function Start()
    if running then return end
    running = true
    lastTick = GetTime()
end

-- Zone bookkeeping. db.zones holds the running session, split by zone and by
-- the view that was active: db.zones[zone][mode] = { time, value }. Values are
-- fixed at the price the loot had when it was picked up.
local function ZoneName()
    local zone = GetRealZoneText and GetRealZoneText()
    if type(zone) ~= "string" or zone == "" then return "Unknown" end
    return zone
end

local function ZoneStat()
    local zone, mode = ZoneName(), db.mode
    db.zones[zone] = db.zones[zone] or {}
    local stat = db.zones[zone][mode]
    if not stat then
        stat = { time = 0, value = 0 }
        db.zones[zone][mode] = stat
    end
    return stat
end

-- Moves the clock forward to now.
local function Advance()
    local now = GetTime()
    local delta = now - lastTick
    lastTick = now
    db.elapsed = db.elapsed + delta
    local stat = ZoneStat()
    stat.time = stat.time + delta
end

local function Pause()
    if not running then return end
    Advance()
    running = false
end

-- Folds the running session into the saved history. Zones you only passed
-- through (under a minute) are left out.
local MIN_ZONE_TIME = 60

local function ArchiveSession()
    for zone, modes in pairs(db.zones) do
        for mode, stat in pairs(modes) do
            if stat.time >= MIN_ZONE_TIME then
                db.history[zone] = db.history[zone] or {}
                local h = db.history[zone][mode]
                if not h then
                    h = { time = 0, value = 0, runs = 0 }
                    db.history[zone][mode] = h
                end
                h.time = h.time + stat.time
                h.value = h.value + stat.value
                h.runs = h.runs + 1
            end
        end
    end
end

-- Ends the session and saves it to the zone history; discard = true throws
-- it away instead.
local function Reset(discard)
    Pause()
    if discard ~= true then ArchiveSession() end
    db.elapsed = 0
    db.items = {}
    db.money = 0
    db.zones = {}
    Refresh()
end

local function SetMode(mode)
    if mode ~= "gather" and mode ~= "loot" then
        mode = db.mode == "gather" and "loot" or "gather"
    end
    db.mode = mode
    Refresh()
end

-- The clock advances every second, but the window is only redrawn when the
-- minute changes (and whenever something is looted), so the numbers stay calm.
local function Tick()
    if not running then return end
    Advance()
    if math.floor(db.elapsed / 60) ~= shownMinute and frame then
        Refresh()
    end
end

-- Loot that counts in the current view starts (or resumes) the clock. While
-- the clock runs everything is recorded, so switching view loses nothing.
local function AddItem(itemID, count, name)
    local gathered = IsGathered(itemID)
    if not running and db.mode == "gather" and not gathered then return end
    local item = db.items[itemID]
    if not item then
        item = { count = 0, gathered = 0 }
        db.items[itemID] = item
    end
    item.count = item.count + count
    if gathered then item.gathered = item.gathered + count end
    if name then item.name = name end
    if gathered or db.mode == "loot" then
        local stat = ZoneStat()
        stat.value = stat.value + (UnitPrice(itemID) or 0) * count
    end
    Start()
    Refresh()
end

local function AddMoney(copper)
    if not running and db.mode ~= "loot" then return end
    db.money = db.money + copper
    if db.mode == "loot" then
        local stat = ZoneStat()
        stat.value = stat.value + copper
    end
    Start()
    Refresh()
end

-- ----------------------------------------------------------- chat parse ----

local function Escape(fmt)
    return (fmt:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"))
end

-- Turns a global format string like "You receive loot: %sx%d." into an
-- anchored Lua pattern, so it works in every client language.
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = Escape(fmt)
    p = p:gsub("%%%%%d%%%$s", ".+"):gsub("%%%%%d%%%$d", "%%d+")
    p = p:gsub("%%%%s", ".+"):gsub("%%%%d", "%%d+")
    return "^" .. p .. "$"
end

-- Only real loot ("You receive loot"), not vendor purchases, mail or crafts.
local selfLootPatterns = {}
for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }) do
    local p = ToPattern(_G[key])
    if p then selfLootPatterns[#selfLootPatterns + 1] = p end
end

local function OnLootMessage(msg)
    if type(msg) ~= "string" then return end
    if issecretvalue and issecretvalue(msg) then return end
    local mine = false
    for _, p in ipairs(selfLootPatterns) do
        if msg:find(p) then mine = true break end
    end
    if not mine then return end

    local itemID = tonumber(msg:match("|Hitem:(%d+)"))
    if not itemID then return end
    local count = tonumber(msg:match("|rx(%d+)")) or 1
    local name = msg:match("|h%[(.-)%]|h")
    AddItem(itemID, count, name)
end

-- "%d Gold" -> "(%d+) Gold"
local function AmountPattern(fmt, fallback)
    if type(fmt) ~= "string" then fmt = fallback end
    return (Escape(fmt):gsub("%%%%d", "(%%d+)"))
end

local goldPattern = AmountPattern(GOLD_AMOUNT, "%d Gold")
local silverPattern = AmountPattern(SILVER_AMOUNT, "%d Silver")
local copperPattern = AmountPattern(COPPER_AMOUNT, "%d Copper")

local function OnMoneyMessage(msg)
    if type(msg) ~= "string" then return end
    if issecretvalue and issecretvalue(msg) then return end
    local copper = (tonumber(msg:match(goldPattern)) or 0) * 10000
        + (tonumber(msg:match(silverPattern)) or 0) * 100
        + (tonumber(msg:match(copperPattern)) or 0)
    if copper > 0 then AddMoney(copper) end
end

-- ---------------------------------------------------------- fishing key ----

-- In a block of its own: the game allows a file at most 200 locals at the top.
do

-- One key for fishing, switched on and off at will. While it is on, the key
-- is taken over: a press casts Fishing, and while the line is out the same
-- key interacts with the bobber instead. Switched off, the key does whatever
-- it normally does. Every cast and every reel is still one key press.

local FISHING_SPELL_IDS = { 7620, 131474, 131476 }
FISH_ICON = "Interface\\Icons\\Trade_Fishing"
local fishingName
fishingNow = false    -- a Fishing channel is running
local reelEndedAt = 0       -- when the line last came in
local bindOwner = CreateFrame("Frame")
local bindPending = false   -- a binding change is waiting for combat to end


-- Lets the interact key reach the bobber from any angle while the line is
-- out. Changed for the length of a cast and put back afterwards.
local SOFT_INTERACT_CVARS = {
    SoftTargetInteract = "3",
    SoftTargetInteractArc = "2",
    SoftTargetInteractRange = "30",
}
local cvarLease = {}

-- Sound boost: while the line is out, sound effects go to full so the bobber
-- splash is easy to hear, and music and ambience drop to a quarter.
local QUIETED_CVARS = { "Sound_MusicVolume", "Sound_AmbienceVolume" }
local QUIET_LEVEL = 0.25

local function LeaseCVars()
    if not (C_CVar and C_CVar.GetCVar and C_CVar.SetCVar) then return end
    local wanted = {}
    for name, value in pairs(SOFT_INTERACT_CVARS) do wanted[name] = value end
    if db.fishSound ~= false then
        wanted.Sound_EnableSFX = "1"
        wanted.Sound_SFXVolume = "1"
        for _, name in ipairs(QUIETED_CVARS) do
            local current = tonumber(C_CVar.GetCVar(name))
            if current then
                wanted[name] = tostring(math.floor(current * QUIET_LEVEL * 100 + 0.5) / 100)
            end
        end
    end
    for name, value in pairs(wanted) do
        local current = C_CVar.GetCVar(name)
        if current ~= nil and not cvarLease[name] then
            pcall(C_CVar.SetCVar, name, value)
            cvarLease[name] = { original = current, ours = C_CVar.GetCVar(name) }
        end
    end
end

-- Each setting goes back only if nothing else changed it in the meantime.
function ReleaseCVars()
    local used = next(cvarLease) ~= nil
    for name, lease in pairs(cvarLease) do
        if C_CVar.GetCVar(name) == lease.ours then
            pcall(C_CVar.SetCVar, name, lease.original)
        end
        cvarLease[name] = nil
    end
    if used and ResetInteract then ResetInteract() end
end

local fishButton = CreateFrame("Button", "WindfallFishButton", UIParent, "SecureActionButtonTemplate")
fishButton:RegisterForClicks("AnyUp", "AnyDown")
fishButton:SetAttribute("type", "spell")
-- Lures. When the pole has no lure on (or it is about to run out), the next
-- press of the fishing key puts on the best lure in the bags instead of
-- casting. Using an item is still the player's own key press.
-- Fishing skill: rank, rank cap and bonus from lure and pole, or nil if the
-- character has not learned Fishing (or the game will not say).
function FishingSkill()
    if GetProfessions and GetProfessionInfo then
        local _, _, _, fishing = GetProfessions()
        if fishing then
            local _, _, rank, maxRank, _, _, _, modifier = GetProfessionInfo(fishing)
            if rank then return rank, maxRank or rank, modifier or 0 end
        end
    end
    if fishingName and GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, modifier, maxRank = GetSkillLineInfo(i)
            if not isHeader and name == fishingName then
                return rank, maxRank or rank, modifier or 0
            end
        end
    end
end

-- req is the Fishing skill a lure needs.
local LURES = {
    { id = 6529, spell = 8087, bonus = 25, minutes = 10, req = 0, name = "Shiny Bauble" },
    { id = 268880, spell = 8087, bonus = 25, minutes = 10, req = 0, name = "\"Secret\" Bait" },
    { id = 6530, spell = 8088, bonus = 50, minutes = 10, req = 50, name = "Nightcrawlers" },
    { id = 6811, spell = 8532, bonus = 50, minutes = 10, req = 50, name = "Aquadynamic Fish Lens" },
    { id = 6532, spell = 8090, bonus = 75, minutes = 10, req = 100, name = "Bright Baubles" },
    { id = 7307, spell = 9092, bonus = 75, minutes = 10, req = 100, name = "Flesh Eating Worm" },
    { id = 6533, spell = 8089, bonus = 100, minutes = 5, req = 100, name = "Aquadynamic Fish Attractor" },
}
local lureBySpell = {}
for _, lure in ipairs(LURES) do lureBySpell[lure.spell] = lureBySpell[lure.spell] or lure end

local MAIN_HAND = 16
local LURE_MIN_LEFT = 5        -- seconds: a lure this close to ending counts as gone
local lureCasting, lureCastingAt = false, 0
local lureAppliedAt, lureBelievedUntil = -100, 0
local enchantSeen = false      -- the game has reported a lure on the pole this session
local lureTried, lureTriedAt   -- the lure the last press tried to put on
local lureFailures, lureSkip = {}, {}
local lureNoneNoted = false

local function MainHandIsPole()
    local id = GetInventoryItemID and GetInventoryItemID("player", MAIN_HAND)
    if not id then return false end
    local _, _, _, _, _, classID, subClassID = ItemInfoInstant(id)
    return classID == 2 and subClassID == 20 -- Weapon, Fishing Pole
end

-- Seconds of lure left on the pole, 0 if none.
local function LureLeft()
    local ms
    if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
        local ok, info = pcall(C_PaperDollInfo.GetTemporaryEnchantmentInfo, MAIN_HAND)
        ms = ok and info and info.remainingTimeMs or nil
        if ms and issecretvalue and issecretvalue(ms) then ms = nil end
    elseif GetWeaponEnchantInfo then
        local has, left = GetWeaponEnchantInfo()
        ms = has and left or nil
    end
    if type(ms) == "number" and ms > 0 then
        enchantSeen = true
        return ms / 1000
    end
    -- The pole can lag behind a lure that just went on, and some clients never
    -- report it at all: until the game has shown it can, go by the clock.
    local now = GetTime()
    if now < lureBelievedUntil and (not enchantSeen or now - lureAppliedAt < 10) then
        return lureBelievedUntil - now
    end
    return 0
end

local function BagCount(itemID)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return count and count(itemID) or 0
end

local function BestLure()
    local best
    local rank = FishingSkill()
    for _, lure in ipairs(LURES) do
        if not lureSkip[lure.id] and (not rank or rank >= lure.req) and BagCount(lure.id) > 0
            and (not best or lure.bonus > best.bonus) then
            best = lure
        end
    end
    return best
end

-- What a press of the fishing key should do about lures: "wait" while one is
-- going on (casting would interrupt it), a macro to put one on, or nil to cast.
local function LurePress()
    local now = GetTime()
    if lureCasting then
        if now - lureCastingAt < 7 then return "wait" end
        lureCasting = false
    end
    if db.fishLure == false or not MainHandIsPole() or (IsMounted and IsMounted()) then
        return nil
    end
    -- An earlier press that never started the lure's cast has failed, most
    -- likely for lack of Fishing skill. Two of those and that lure is left alone.
    if lureTried and now - lureTriedAt > 1.5 then
        local id = lureTried.id
        lureTried = nil
        if SpellIsTargeting and SpellIsTargeting() and SpellStopTargeting then pcall(SpellStopTargeting) end
        lureFailures[id] = (lureFailures[id] or 0) + 1
        if lureFailures[id] >= 2 then
            lureSkip[id] = true
            local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or "that lure"
            print("|cff7fd36bWindfall|r: could not put " .. name .. " on, so it is skipped until you reload.")
        end
    end
    if LureLeft() >= LURE_MIN_LEFT then return nil end
    local lure = BestLure()
    if not lure then
        if not lureNoneNoted then
            lureNoneNoted = true
            print("|cff7fd36bWindfall|r: no usable lure in your bags, fishing without one.")
        end
        return nil
    end
    lureNoneNoted = false
    if not lureTried then lureTried, lureTriedAt = lure, now end
    return string.format("/use item:%d\n/use %d", lure.id, MAIN_HAND)
end

function OnLureCastStart(spellID)
    if lureBySpell[spellID] then
        lureCasting, lureCastingAt = true, GetTime()
        lureTried = nil
    end
end

function OnLureCastSucceeded(spellID)
    local lure = lureBySpell[spellID]
    if not lure then return end
    lureCasting = false
    lureAppliedAt = GetTime()
    lureBelievedUntil = lureAppliedAt + lure.minutes * 60
    lureFailures = {}
end

function OnLureCastEnded()
    lureCasting = false
end

-- Double right-click casting borrows the right mouse button for one click.
local clickOwner = CreateFrame("Frame")
local doubleArmed = false   -- a double right-click's mouse-up is about to cast
local lastRightClick = 0
local lastFishAt = 0        -- last time anything fishing-related happened

fishButton:HookScript("PreClick", function(self, _, down)
    if InCombatLockdown() then return end
    lastFishAt = GetTime()
    -- Letting go of the key that just reeled in must not count as a new cast.
    local reelRelease = not down and not doubleArmed and GetTime() - reelEndedAt < 1
    reelEndedAt = 0
    if reelRelease then
        self:SetAttribute("type", nil)
        return
    end
    local lure = LurePress()
    if lure == "wait" then
        self:SetAttribute("type", nil)
    elseif lure then
        self:SetAttribute("type", "macro")
        self:SetAttribute("macrotext", lure)
    end
end)
fishButton:HookScript("PostClick", function(self)
    if not InCombatLockdown() then
        self:SetAttribute("type", "spell")
        self:SetAttribute("macrotext", nil)
        -- The double-click takeover is one-shot: right-click goes back to the camera.
        ClearOverrideBindings(clickOwner)
        doubleArmed = false
    end
end)

-- The second of two quick right-clicks on the world rebinds the right button
-- to the cast button, so letting go of it casts.
if WorldFrame and WorldFrame.HookScript then
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if button ~= "RightButton" or not db or not db.fishOn or db.fishDouble == false then return end
        if fishingNow or InCombatLockdown() then return end
        local now = GetTime()
        if now - lastRightClick > 0.4 then
            lastRightClick = now
            return
        end
        lastRightClick = 0
        SetOverrideBindingClick(clickOwner, true, "BUTTON2", "WindfallFishButton", "LeftButton")
        doubleArmed = true
        -- If that click never reaches the button, give the mouse button back anyway.
        C_Timer.After(1, function()
            if doubleArmed and not InCombatLockdown() then
                ClearOverrideBindings(clickOwner)
                doubleArmed = false
            end
        end)
    end)
end

-- Points the fishing key at the right thing for the current state. Key
-- bindings cannot change in combat, so the change waits until it ends.
local function ApplyFishBinding()
    if InCombatLockdown() then
        bindPending = true
        return
    end
    bindPending = false
    ClearOverrideBindings(bindOwner)
    if db.fishOn and db.fishKey then
        if fishingNow then
            SetOverrideBinding(bindOwner, true, db.fishKey, "INTERACTTARGET")
        else
            SetOverrideBindingClick(bindOwner, true, db.fishKey, "WindfallFishButton", "LeftButton")
        end
    end
end

local function Announce(text)
    print("|cff7fd36bWindfall|r: " .. text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage("Windfall: " .. text, 0.5, 0.83, 0.42)
    end
end

-- Fishing pole: goes on when the fishing key is switched on, and the weapons
-- that were in your hands come back when it is switched off.
local OFF_HAND = 17
local Equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
local gearPending           -- "equip" or "restore", waiting for combat to end
local noPoleNoted = false

local function FindPoleInBags()
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return nil end
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local best, bestLevel
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                local _, _, _, _, _, classID, subClassID = ItemInfoInstant(id)
                if classID == 2 and subClassID == 20 then
                    local level = info and select(4, info(id)) or 0
                    if not best or level > bestLevel then best, bestLevel = id, level end
                end
            end
        end
    end
    return best
end

local function EquipPole()
    if db.fishEquip == false or not Equip or MainHandIsPole() then return end
    if InCombatLockdown() then
        gearPending = "equip"
        return
    end
    local pole = FindPoleInBags()
    if not pole then
        if not noPoleNoted then
            noPoleNoted = true
            print("|cff7fd36bWindfall|r: no fishing pole in your bags to equip.")
        end
        return
    end
    noPoleNoted = false
    db.savedWeapons = {
        main = GetInventoryItemLink("player", MAIN_HAND) or false,
        off = GetInventoryItemLink("player", OFF_HAND) or false,
    }
    Equip(pole, MAIN_HAND)
end

local function RestoreWeapons()
    local saved = db.savedWeapons
    if not saved or not Equip then return end
    if InCombatLockdown() then
        gearPending = "restore"
        return
    end
    db.savedWeapons = nil
    if not MainHandIsPole() then return end -- you already changed weapons yourself
    if saved.main then Equip(saved.main, MAIN_HAND) end
    if saved.off then
        -- The off hand only fits once the two-handed pole is gone.
        C_Timer.After(0.6, function()
            if not InCombatLockdown() then Equip(saved.off, OFF_HAND) end
        end)
    end
end

-- Auto loot is switched on for as long as the fishing key is on.
local lootLease

function UpdateAutoLoot(forceOff)
    if not (C_CVar and C_CVar.GetCVar and C_CVar.SetCVar) then return end
    local want = not forceOff and db.fishOn and db.fishLoot ~= false
    if want and not lootLease then
        local current = C_CVar.GetCVar("autoLootDefault")
        if current ~= nil then
            pcall(C_CVar.SetCVar, "autoLootDefault", "1")
            lootLease = { original = current, ours = C_CVar.GetCVar("autoLootDefault") }
        end
    elseif not want and lootLease then
        if C_CVar.GetCVar("autoLootDefault") == lootLease.ours then
            pcall(C_CVar.SetCVar, "autoLootDefault", lootLease.original)
        end
        lootLease = nil
    end
end

-- keepGear = true leaves your weapons as they are when switching off.
function SetFishing(on, keepGear)
    if on and not fishingName then
        Announce("this character does not know Fishing.")
        return
    end
    if on and not db.fishKey then
        StartKeyCapture() -- picking a key switches it on
        return
    end
    db.fishOn = on and true or false
    if not db.fishOn and fishingNow then
        fishingNow = false
        ReleaseCVars()
    end
    ApplyFishBinding()
    UpdateAutoLoot()
    if db.fishOn then
        lastFishAt = GetTime()
        EquipPole()
    elseif keepGear then
        db.savedWeapons = nil
    else
        RestoreWeapons()
    end
    Announce(db.fishOn and ("fishing key ON (" .. db.fishKey .. ")") or "fishing key off")
    UpdateFishIcon()
end

function SetFishKey(key)
    db.fishKey = key:upper()
    db.fishOn = false
    reelEndedAt = GetTime() -- letting go of the key just picked is not a cast
    SetFishing(true)
end

function Windfall_ToggleFishing()
    if db then SetFishing(not db.fishOn) end
end

-- Sleep and wake. The fishing key switches itself off after a while without
-- fishing, follows the pole when you put one on or take it off yourself.
local SLEEP_AFTER = 600 -- seconds

local function FishIdleCheck()
    if not (db and db.fishOn) or db.fishSleep == false or fishingNow then return end
    if GetTime() - lastFishAt >= SLEEP_AFTER then
        print("|cff7fd36bWindfall|r: no fishing for 10 minutes.")
        SetFishing(false)
    end
end

function OnMainHandChanged()
    if db.fishSleep == false then return end
    local pole = MainHandIsPole()
    if pole and not db.fishOn and db.fishKey and fishingName then
        SetFishing(true)
    elseif not pole and db.fishOn and not gearPending then
        SetFishing(false, true)
    end
end

function OnCombatEnded()
    if bindPending then ApplyFishBinding() end
    local pending = gearPending
    gearPending = nil
    if pending == "equip" and db.fishOn then
        EquipPole()
    elseif pending == "restore" and not db.fishOn then
        RestoreWeapons()
    end
end

function OnChannelStart(spellID)
    if not (db.fishOn and fishingName and spellID) then return end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if not (ok and name == fishingName) then return end
    fishingNow = true
    lastFishAt = GetTime()
    LeaseCVars()
    ApplyFishBinding()
end

function OnChannelStop()
    if not fishingNow then return end
    fishingNow = false
    reelEndedAt = GetTime()
    lastFishAt = reelEndedAt
    ReleaseCVars()
    ApplyFishBinding()
end

function InitFishing()
    if C_Spell and C_Spell.GetSpellName then
        for _, id in ipairs(FISHING_SPELL_IDS) do
            local ok, name = pcall(C_Spell.GetSpellName, id)
            if ok and type(name) == "string" and name ~= "" then
                fishingName = name
                break
            end
        end
    end
    if fishingName then
        fishButton:SetAttribute("spell", fishingName)
    else
        db.fishOn = false
    end
    ApplyFishBinding()
    UpdateAutoLoot()
    lastFishAt = GetTime()
    C_Timer.NewTicker(10, FishIdleCheck)
    if db.fishOn then
        print("|cff7fd36bWindfall|r: fishing key is ON (" .. db.fishKey .. "). /wf fish switches it off.")
    end
end

-- A small prompt that waits for the key to use.
local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
}
local MOUSE_KEYS = {
    LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3",
}
local captureFrame

function StartKeyCapture()
    if not captureFrame then
        -- Covers the whole screen so a mouse button counts wherever it is pressed.
        local c = CreateFrame("Frame", "WindfallKeyCapture", UIParent)
        c:SetAllPoints(UIParent)
        c:SetFrameStrata("DIALOG")
        local box = CreateFrame("Frame", nil, c, "BackdropTemplate")
        box:SetSize(340, 78)
        box:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        box:SetBackdropColor(0, 0, 0, 0.9)
        box:SetBackdropBorderColor(0.4, 0.7, 0.3, 1)
        c.text = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        c.text:SetPoint("CENTER")
        c.text:SetWidth(320)
        c.text:SetText("Press the key or mouse button to fish with.\n"
            .. "|cff999999Left and right click need Shift, Ctrl or Alt.\nEscape cancels.|r")

        local function Pick(key)
            local mods = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
                .. (IsShiftKeyDown() and "SHIFT-" or "")
            -- Plain left or right click would take over the camera and targeting.
            if mods == "" and (key == "BUTTON1" or key == "BUTTON2") then return end
            c:Hide()
            SetFishKey(mods .. key)
        end

        c:EnableKeyboard(true)
        c:SetScript("OnKeyDown", function(self, key)
            if MODIFIER_KEYS[key] then return end
            if key == "ESCAPE" then self:Hide() return end
            Pick(key)
        end)
        c:EnableMouse(true)
        c:SetScript("OnMouseDown", function(_, button)
            local key = MOUSE_KEYS[button]
            if not key then
                local n = type(button) == "string" and button:match("^Button(%d+)$")
                key = n and ("BUTTON" .. n)
            end
            if key then Pick(key) end
        end)
        c:EnableMouseWheel(true)
        c:SetScript("OnMouseWheel", function(_, delta)
            Pick(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
        end)
        captureFrame = c
    end
    captureFrame:Show()
end

BINDING_HEADER_WINDFALL = "Windfall"
BINDING_NAME_WINDFALL_FISHTOGGLE = "Fishing key on / off"
BINDING_NAME_WINDFALL_WINDOW = "Open or close the Windfall window"
BINDING_NAME_WINDFALL_SPARKLE = "Node sparkles on / off"

end

-- ------------------------------------------------------------- sparkles ----

-- In a block of its own: the game allows a file at most 200 locals at the top.
do

-- Makes the nearest herb, ore or fishing pool stand out, and nothing else.
-- The game's soft target picks the nearest thing you can interact with; while
-- that is a gathering node, its icon is switched on and a sparkle is drawn on
-- it. Quest objects, chests and NPCs get nothing.

local SPARKLE_COLORS = {
    herb = { 0.35, 1, 0.35 },
    ore = { 1, 0.6, 0.2 },
    fish = { 0.35, 0.75, 1 },
}
local SPARKLE_TYPES = { herb = "sparkleHerb", ore = "sparkleOre", fish = "sparkleFish" }
local GATHERMATE_TYPES = { ["Herb Gathering"] = "herb", ["Mining"] = "ore", ["Fishing"] = "fish" }

-- English names, used when GatherMate2 is not loaded to give the client's own.
local HERB_NODES = {}
for _, name in ipairs({
    "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp", "Bruiseweed",
    "Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker",
    "Wintersbite", "Firebloom", "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom",
    "Gromsblood", "Golden Sansam", "Dreamfoil", "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus",
    "Wilted Peacebloom",
}) do HERB_NODES[name] = true end

local function NodeType(name)
    local GM = LibStub and LibStub("AceAddon-3.0", true)
    GM = GM and GM:GetAddon("GatherMate2", true)
    if GM and GM.nodeIDs then
        for gmType, ours in pairs(GATHERMATE_TYPES) do
            if GM.nodeIDs[gmType] and GM.nodeIDs[gmType][name] then return ours end
        end
    end
    if HERB_NODES[name] then return "herb" end
    if name:find(" Vein$") or name:find(" Deposit$") then return "ore" end
    if name:find(" School$") or name:find(" Swarm$") or name == "Floating Wreckage" or name == "Floating Debris"
        or name == "Oil Spill" or name == "Patch of Elemental Water" then
        return "fish"
    end
    return nil
end

-- Soft targeting reaches all round you and a bit further while sparkles are
-- on, so the nearest node is picked up without facing it.
local SPARKLE_CVARS = {
    SoftTargetInteract = "3",
    SoftTargetInteractArc = "2",
    SoftTargetInteractRange = "30",
}
local sparkleLease = {}
local sparkleTicker, sparkleGUID, sparkleFrame, iconOn

local function SetCVarSafe(name, value)
    if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, name, value) end
end

local function GetCVarSafe(name)
    return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name)
end

-- The game's icon over the soft target, and the name plate the sparkle sits
-- on, are on only while the soft target is a node. Left on, every guard,
-- trainer and vendor you walk past would get a name plate or an icon too,
-- since sparkles make soft targeting reach all round you.
local NODE_ONLY_CVARS = { "SoftTargetIconGameObject", "SoftTargetIconInteract", "SoftTargetNameplateInteract" }

local function SetNodeIcon(on)
    if iconOn == on then return end
    iconOn = on
    for _, name in ipairs(NODE_ONLY_CVARS) do
        if not sparkleLease[name] then
            local current = GetCVarSafe(name)
            if current ~= nil then sparkleLease[name] = { original = current } end
        end
        if sparkleLease[name] then
            SetCVarSafe(name, on and "1" or "0")
            sparkleLease[name].ours = GetCVarSafe(name)
        end
    end
end

local function BuildSparkle()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(64, 64)
    f:SetFrameStrata("LOW")
    f.glow = f:CreateTexture(nil, "ARTWORK")
    f.glow:SetAllPoints()
    f.glow:SetTexture("Interface\\Cooldown\\star4")
    f.glow:SetBlendMode("ADD")
    f.ring = f:CreateTexture(nil, "ARTWORK")
    f.ring:SetPoint("CENTER")
    f.ring:SetSize(40, 40)
    f.ring:SetTexture("Interface\\Cooldown\\starburst")
    f.ring:SetBlendMode("ADD")
    -- Turning and pulsing, done by hand so it works on any client.
    f:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        local pulse = 0.65 + 0.35 * math.sin(self.t * 4)
        self.glow:SetAlpha(pulse)
        self.ring:SetAlpha(1.2 - pulse)
        if self.glow.SetRotation then self.glow:SetRotation(self.t * 1.5) end
        if self.ring.SetRotation then self.ring:SetRotation(-self.t) end
    end)
    f:Hide()
    return f
end

local function HideSparkle()
    if sparkleFrame then sparkleFrame:Hide() end
end

local function ShowSparkle(kind)
    local plate
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, "softinteract")
        plate = ok and p or nil
    end
    if not plate then
        HideSparkle()
        return
    end
    sparkleFrame = sparkleFrame or BuildSparkle()
    local c = SPARKLE_COLORS[kind]
    sparkleFrame.glow:SetVertexColor(c[1], c[2], c[3])
    sparkleFrame.ring:SetVertexColor(c[1], c[2], c[3])
    sparkleFrame:ClearAllPoints()
    sparkleFrame:SetPoint("CENTER", plate, "CENTER", 0, 0)
    sparkleFrame:Show()
end

local sparkleKind

-- Which kinds of node this character can gather: Herbalism, Mining and
-- Fishing, by skill line. Looked up again when skills change.
local GATHER_SKILL_LINES = { [182] = "herb", [186] = "ore", [356] = "fish" }
local canGather

local function CanGather(kind)
    if not canGather then
        canGather = {}
        if GetProfessions and GetProfessionInfo then
            for _, index in pairs({ GetProfessions() }) do
                local skillLine = select(7, GetProfessionInfo(index))
                if GATHER_SKILL_LINES[skillLine] then canGather[GATHER_SKILL_LINES[skillLine]] = true end
            end
        end
    end
    return canGather[kind]
end

function SkillsChanged()
    canGather = nil
    sparkleGUID = false -- look at the current target again
end

local function SparkleCheck()
    local guid = UnitGUID and UnitGUID("softinteract")
    if guid and issecretvalue and issecretvalue(guid) then guid = nil end
    if guid ~= sparkleGUID then
        sparkleGUID = guid
        sparkleKind = nil
        if guid then
            local name = UnitName("softinteract")
            if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
                local kind = NodeType(name)
                if kind and db[SPARKLE_TYPES[kind]] ~= false and CanGather(kind) then sparkleKind = kind end
            end
        end
        SetNodeIcon(sparkleKind ~= nil)
    end
    -- Re-placed every check: the nameplate can show up a moment late, and
    -- the game reuses nameplates.
    if sparkleKind then ShowSparkle(sparkleKind) else HideSparkle() end
end

function StopSparkles()
    if not sparkleTicker then return end
    sparkleTicker:Cancel()
    sparkleTicker = nil
    HideSparkle()
    sparkleGUID, sparkleKind, iconOn = nil, nil, nil
    -- Each setting goes back only if nothing else changed it in the meantime.
    for name, lease in pairs(sparkleLease) do
        if lease.ours == nil or GetCVarSafe(name) == lease.ours then SetCVarSafe(name, lease.original) end
        sparkleLease[name] = nil
    end
    ResetInteract()
end

-- When Windfall is done with the interact settings (the line comes in, or
-- sparkles are switched off), they go to the game's own defaults rather than
-- back to what was there before, which may be a wide setting left behind by
-- another addon. Windfall never touches them otherwise, so what other addons
-- such as EllesmereUI do is left alone.
local INTERACT_DEFAULTS = {
    SoftTargetInteractRange = "10",
    SoftTargetInteractArc = "0",
    SoftTargetIconGameObject = "0",
    SoftTargetNameplateInteract = "0",
}

function ResetInteract()
    if not db or db.interactDefault == false then return end
    if fishingNow or sparkleTicker then return end
    for name, fallback in pairs(INTERACT_DEFAULTS) do
        local current = GetCVarSafe(name)
        if current ~= nil then
            local default = C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name) or fallback
            if tonumber(current) ~= tonumber(default) then SetCVarSafe(name, default) end
        end
    end
end

function StartSparkles()
    if sparkleTicker then return end
    for name, value in pairs(SPARKLE_CVARS) do
        local current = GetCVarSafe(name)
        if current ~= nil and not sparkleLease[name] then
            SetCVarSafe(name, value)
            sparkleLease[name] = { original = current, ours = GetCVarSafe(name) }
        end
    end
    SetNodeIcon(false)
    sparkleTicker = C_Timer.NewTicker(0.2, SparkleCheck)
end

function ApplySparkles()
    if db.sparkle then StartSparkles() else StopSparkles() end
end

function Windfall_ToggleSparkles()
    if not db then return end
    db.sparkle = not db.sparkle
    ApplySparkles()
    if UpdateBarIcons then UpdateBarIcons() end
    print("|cff7fd36bWindfall|r: node sparkles " .. (db.sparkle and "on" or "off") .. ".")
    if RefreshSettings then RefreshSettings() end
end

-- Skill at which no fish get away, by zone. Below that some get away, and
-- 95 points under it you cannot fish there at all. Lure and pole bonuses
-- count. These are Classic's numbers; the three Forever differences (The
-- Barrens, Riverglades, Zephras Isle) are as measured by the OneCast addon's
-- players. Zone names are English.
local FISH_ZONES = {
    [25] = { "Dun Morogh", "Durotar", "Elwynn Forest", "Mulgore", "Teldrassil", "Tirisfal Glades", "Zephras Isle" },
    [75] = { "Stormwind City", "Ironforge", "Darnassus", "Orgrimmar", "Thunder Bluff", "Undercity",
        "Westfall", "Loch Modan", "Darkshore", "Silverpine Forest" },
    [100] = { "The Barrens" },
    [150] = { "Redridge Mountains", "Duskwood", "Wetlands", "Hillsbrad Foothills", "Ashenvale", "Stonetalon Mountains" },
    [225] = { "Stranglethorn Vale", "Arathi Highlands", "Alterac Mountains", "Swamp of Sorrows", "Dustwallow Marsh",
        "Desolace", "Thousand Needles", "Riverglades" },
    [300] = { "Tanaris", "Feralas", "The Hinterlands", "Western Plaguelands", "Un'Goro Crater", "Felwood",
        "Azshara", "Moonglade" },
    [425] = { "Eastern Plaguelands", "Winterspring", "Burning Steppes", "Silithus", "Deadwind Pass" },
}
local zoneFishLevel = {}
for level, zones in pairs(FISH_ZONES) do
    for _, zone in ipairs(zones) do zoneFishLevel[zone] = level end
end

-- One line on how many fish get away where you stand, or nil if the
-- character has no Fishing skill to go by.
function GetawayText()
    local rank, _, bonus = FishingSkill()
    if not rank then return nil end
    local skill = rank + bonus
    local zone = ZoneName()
    local level = zoneFishLevel[zone]
    if not level then
        return "|cff999999" .. zone .. ": no fishing data for this zone|r"
    elseif skill >= level then
        return zone .. ": |cff7fd36bno fish get away|r"
    elseif skill > level - 95 then
        return string.format("%s: |cffffd100about %d%% of fish get away|r", zone,
            math.floor((level - skill) / 95 * 100 + 0.5))
    end
    return string.format("%s: |cffff6060needs %d Fishing to fish here|r", zone, level - 95)
end


-- Looks at the current soft target again, after a setting changed.
function SparkleRecheck()
    sparkleGUID = false
end
end

-- ---------------------------------------------------------------- panel ----

-- The Windfall window: a standard WoW panel (portrait, title, close button,
-- inset) with tabs along the bottom, like the Character window. Levelling a
-- profession is the main tab. Each page is built by its own section; showing
-- or hiding a page shows the window on that page, so the rest of Windfall
-- needs no changes.
do
local panel, current, inset, headerRefresh, portrait
local pages = {}
local switching = false
local docked, placed, openedForDock = false, false, false
local W, H = 660, 560
local INNER_W = W - 26
local TABS = {
    { key = "route", label = "Levelling" },
    { key = "professions", label = "Recipes" },
    { key = "farming", label = "Farming" },
    { key = "settings", label = "Settings" },
}
local TAB_OF = { zones = "farming" } -- pages shown under another page's tab
PageOpeners = {}

-- The plain frame methods, for pages whose Show and Hide are replaced below.
local probe = CreateFrame("Frame")
local methods = getmetatable(probe).__index
local function Method(name)
    if type(methods) == "table" then return methods[name] end
    return methods(probe, name)
end
local rawShow, rawHide, rawIsShown = Method("Show"), Method("Hide"), Method("IsShown")

local function HasTemplate(t)
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        local ok, info = pcall(C_XMLUtil.GetTemplateInfo, t)
        return ok and info ~= nil
    end
    return true -- can't tell: the parts used are checked below
end

local function Part(obj, key)
    local v = obj and obj[key]
    if type(v) == "table" then return v end
end

local function PlacePanel()
    panel:ClearAllPoints()
    local pos = db.panelPos
    if pos then
        panel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

local function SelectTab(key)
    key = TAB_OF[key] or key
    for i, tab in ipairs(TABS) do
        if tab.key == key then
            if not (PanelTemplates_SetTab and pcall(PanelTemplates_SetTab, panel, i)) then
                for j, b in ipairs(panel.Tabs) do
                    local fs = b:GetFontString()
                    if fs then
                        if j == i then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(1, 0.82, 0) end
                    end
                end
            end
        end
    end
end

local function BuildPanel()
    local f = CreateFrame("Frame", "WindfallPanel", UIParent,
        HasTemplate("ButtonFrameTemplate") and "ButtonFrameTemplate" or nil)
    local native = Part(f, "Inset") ~= nil
        and (Part(f, "CloseButton") or Part(f, "TitleText") or Part(f, "TitleContainer")) ~= nil
    f:SetSize(W, H)
    f:SetFrameStrata("HIGH")
    if f.SetToplevel then f:SetToplevel(true) end
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not docked then
            local point, _, relPoint, x, y = self:GetPoint(1)
            db.panelPos = { point, relPoint, x, y }
        end
    end)

    if not native then
        -- Without the Blizzard art: a dark box with a close button.
        local bg = CreateFrame("Frame", nil, f, "BackdropTemplate")
        bg:SetAllPoints()
        bg:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))
        bg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        bg:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() f:Hide() end)
    end

    -- Title.
    if Part(f, "TitleText") then
        f.TitleText:SetText("Windfall")
    elseif Part(Part(f, "TitleContainer"), "TitleText") then
        f.TitleContainer.TitleText:SetText("Windfall")
    elseif native and type(f.SetTitle) == "function" then
        f:SetTitle("Windfall")
    else
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOP", 0, -8)
        t:SetText("Windfall")
    end
    portrait = Part(f, "portrait") or Part(f, "Portrait") or Part(Part(f, "PortraitContainer"), "portrait")

    -- Content area, and the strip above it for the character and profession.
    inset = Part(f, "Inset")
    if inset then
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", 4, -60)
        inset:SetPoint("BOTTOMRIGHT", -6, 6)
    else
        inset = CreateFrame("Frame", nil, f)
        inset:SetPoint("TOPLEFT", 8, -60)
        inset:SetPoint("BOTTOMRIGHT", -8, 8)
    end
    f.header = CreateFrame("Frame", nil, f)
    f.header:SetPoint("TOPLEFT", 62, -24)
    f.header:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -10, -58)

    -- Tabs along the bottom.
    local tabTemplate = (HasTemplate("PanelTabButtonTemplate") and "PanelTabButtonTemplate")
        or (HasTemplate("CharacterFrameTabButtonTemplate") and "CharacterFrameTabButtonTemplate") or nil
    f.Tabs = {}
    for i, tab in ipairs(TABS) do
        local b = CreateFrame("Button", "WindfallPanelTab" .. i, f, tabTemplate)
        b:SetID(i)
        local art = Part(b, "Left") or Part(b, "LeftActive") or Part(b, "LeftDisabled")
        if not art then
            b:SetSize(110, 26)
            local bg = b:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.12, 0.1, 0.06, 0.95)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.12)
            if not b:GetFontString() then
                local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetPoint("CENTER")
                b:SetFontString(fs)
            end
        end
        b:SetText(tab.label)
        if art and PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
        if i == 1 then
            b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, art and 2 or -2)
        else
            b:SetPoint("TOPLEFT", f.Tabs[i - 1], "TOPRIGHT", (not art or Part(b, "LeftActive")) and 3 or -15, 0)
        end
        b:SetScript("OnClick", function()
            local open = PageOpeners[tab.key]
            if open then open() end
            if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        end)
        f.Tabs[i] = b
    end
    f.numTabs = #TABS
    if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, f, #TABS) end

    f:SetScript("OnShow", function()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
    end)
    f:SetScript("OnHide", function()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "WindfallPanel") end -- Escape closes it
    f:Hide()
    return f
end

local function Select(page)
    panel = panel or BuildPanel()
    switching = true
    for other in pairs(pages) do
        if other ~= page then rawHide(other) end
    end
    switching = false
    current = page
    rawShow(page)
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, page.pageOffset or 22)
    page:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
    SelectTab(page.pageKey)
    if headerRefresh then headerRefresh(page.pageKey) end
    if not docked and not placed then
        PlacePanel()
        placed = true
    end
    rawShow(panel)
end

-- A page: a plain frame inside the window. Its Show, Hide, SetShown and
-- IsShown work on the window, so code written for separate windows still works.
function NewPage(name, label, width, key)
    panel = panel or BuildPanel()
    local f = CreateFrame("Frame", name, inset)
    f:SetSize(INNER_W, 200)
    f.pageLabel, f.pageKey = label, key
    -- Pages used to have a title of their own; some still set it.
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:Hide()
    rawHide(f)
    pages[f] = true
    f.Show = function(self) Select(self) end
    f.Hide = function(self)
        rawHide(self)
        if current == self and not switching then rawHide(panel) end
    end
    f.SetShown = function(self, show) if show then self:Show() else self:Hide() end end
    f.IsShown = function(self) return current == self and rawIsShown(panel) and true or false end
    return f
end

-- The strip above the pages, for the profession code to fill.
function PanelHeader()
    panel = panel or BuildPanel()
    return panel.header, panel
end

function SetPanelHeaderRefresh(fn)
    headerRefresh = fn
end

function SetPanelPortrait(texture)
    local t = portrait
    if not t then return end
    if SetPortraitToTexture then
        pcall(SetPortraitToTexture, t, texture)
    else
        t:SetTexture(texture)
    end
end

-- Opens the window on the page last shown (Levelling the first time), or closes it.
function TogglePanel()
    panel = panel or BuildPanel()
    if rawIsShown(panel) then
        rawHide(panel)
        return
    end
    local key = current and current.pageKey or "route"
    local open = PageOpeners[key]
    if open then open() elseif current then Select(current) end
end

-- Next to the auction house or a vendor while it is open; back to its own
-- place afterwards, and closed again if it only opened for that.
function DockPanel(target, openedForIt)
    if not (panel and target) then return end
    docked = true
    openedForDock = openedForIt or openedForDock
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", target, "TOPRIGHT", 8, 0)
end

function UndockPanel()
    if not (panel and docked) then return end
    docked = false
    PlacePanel()
    if openedForDock then rawHide(panel) end
    openedForDock = false
end
end

-- ------------------------------------------------------------------- UI ----

local function BuildFrame()
    local f = NewPage("WindfallFrame", "Farming", WIDTH, "farming")

    f.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.time:SetPoint("TOPLEFT", 10, -48)
    f.time:SetWidth(WIDTH - 20)
    f.time:SetJustifyH("LEFT")
    f.time:SetWordWrap(false)

    f.rate = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.rate:SetPoint("TOPLEFT", 10, -30)

    f.total = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.total:SetPoint("TOPRIGHT", -10, -34)

    f.rows = {}
    for i = 1, MAX_ROWS do
        local y = -FARM_TOP - (i - 1) * ROW_H
        local row = {}
        row.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", 10, y)
        row.name:SetWidth(WIDTH - 150)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.unit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.unit:SetPoint("TOPRIGHT", -78, y)
        row.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("TOPRIGHT", -10, y)
        f.rows[i] = row
    end

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT", 10, -FARM_TOP)
    f.hint:SetWidth(WIDTH - 20)
    f.hint:SetJustifyH("LEFT")

    -- Shown while the fishing key is on: how many fish get away here.
    f.getaway = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.getaway:SetWidth(WIDTH - 20)
    f.getaway:SetJustifyH("LEFT")
    f.getaway:SetWordWrap(false)

    f.toggle =CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.toggle:SetSize(60, 20)
    f.toggle:SetPoint("BOTTOMLEFT", 8, 8)
    f.toggle:SetScript("OnClick", function()
        if running then Pause() else Start() end
        Refresh()
    end)

    f.mode = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.mode:SetSize(86, 20)
    f.mode:SetPoint("LEFT", f.toggle, "RIGHT", 5, 0)
    f.mode:SetScript("OnClick", function() SetMode() end)
    f.mode:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Windfall view")
        GameTooltip:AddLine("Gathering: herbs, ore, skins and fish only.", 1, 1, 1)
        GameTooltip:AddLine("All loot: everything you loot, plus coins.", 1, 1, 1)
        GameTooltip:AddLine("Click to switch. Nothing is lost.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    f.mode:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.reset:SetSize(56, 20)
    f.reset:SetPoint("BOTTOMRIGHT", -8, 8)
    f.reset:SetText("Reset")
    f.reset:SetScript("OnClick", function() Reset(IsShiftKeyDown and IsShiftKeyDown()) end)
    f.reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset")
        GameTooltip:AddLine("Saves this session to the zone history and starts a new one.", 1, 1, 1, true)
        GameTooltip:AddLine("Shift-click: throw the session away instead.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    f.reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.zones = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.zones:SetSize(56, 20)
    f.zones:SetPoint("RIGHT", f.reset, "LEFT", -5, 0)
    f.zones:SetText("Zones")
    f.zones:SetScript("OnClick", function() ToggleHistory() end)

    return f
end

function UpdateFishIcon()
    if not frame then return end
    if UpdateBarIcons then UpdateBarIcons() end
    Refresh() -- the getaway line comes and goes with the fishing key
    RefreshSettings()
end

-- --------------------------------------------------------- zone history ----

local HISTORY_ROWS = 15
local HISTORY_WIDTH = 340

local function ShortTime(seconds)
    local minutes = math.floor((seconds or 0) / 60)
    if minutes >= 60 then
        return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
    end
    return minutes .. "m"
end

local function BuildHistoryFrame()
    local f = NewPage("WindfallHistoryFrame", "Zones", HISTORY_WIDTH, "zones")

    local function Column(template, y)
        local row = {}
        row.zone = f:CreateFontString(nil, "OVERLAY", template)
        row.zone:SetPoint("TOPLEFT", 10, y)
        row.zone:SetWidth(HISTORY_WIDTH - 190)
        row.zone:SetJustifyH("LEFT")
        row.zone:SetWordWrap(false)
        row.rate = f:CreateFontString(nil, "OVERLAY", template)
        row.rate:SetPoint("TOPRIGHT", -108, y)
        row.time = f:CreateFontString(nil, "OVERLAY", template)
        row.time:SetPoint("TOPRIGHT", -48, y)
        row.runs = f:CreateFontString(nil, "OVERLAY", template)
        row.runs:SetPoint("TOPRIGHT", -10, y)
        return row
    end

    local head = Column("GameFontDisableSmall", -32)
    head.zone:SetText("Zone")
    head.rate:SetText("Per hour")
    head.time:SetText("Time")
    head.runs:SetText("Runs")

    f.rows = {}
    for i = 1, HISTORY_ROWS do
        f.rows[i] = Column("GameFontHighlightSmall", -48 - (i - 1) * ROW_H)
    end

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetWidth(HISTORY_WIDTH - 20)
    f.hint:SetJustifyH("LEFT")

    f.mode = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.mode:SetSize(86, 20)
    f.mode:SetPoint("BOTTOMLEFT", 8, 8)
    f.mode:SetScript("OnClick", function() SetMode() end)

    f.clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.clear:SetSize(100, 20)
    f.clear:SetPoint("BOTTOMRIGHT", -8, 8)
    f.clear:SetText("Clear history")
    f.clear:SetScript("OnClick", function()
        if StaticPopup_Show then StaticPopup_Show("WINDFALL_CLEAR_HISTORY") end
    end)

    return f
end

if StaticPopupDialogs then
    StaticPopupDialogs["WINDFALL_CLEAR_HISTORY"] = {
        text = "Delete all saved Windfall zone history?",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function()
            db.history = {}
            RefreshHistory()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

-- Saved history plus the running session, for the active view.
function RefreshHistory()
    if not (historyFrame and historyFrame:IsShown()) then return end
    local f, mode = historyFrame, db.mode
    local here = ZoneName()

    local byZone = {}
    for zone, modes in pairs(db.history) do
        local h = modes[mode]
        if h then byZone[zone] = { zone = zone, time = h.time, value = h.value, runs = h.runs } end
    end
    for zone, modes in pairs(db.zones) do
        local s = modes[mode]
        if s and s.time >= MIN_ZONE_TIME then
            local e = byZone[zone] or { zone = zone, time = 0, value = 0, runs = 0 }
            e.time, e.value, e.runs = e.time + s.time, e.value + s.value, e.runs + 1
            byZone[zone] = e
        end
    end

    local list = {}
    for _, e in pairs(byZone) do
        e.rate = e.value / e.time * 3600
        list[#list + 1] = e
    end
    table.sort(list, function(a, b)
        if a.rate ~= b.rate then return a.rate > b.rate end
        return a.zone < b.zone
    end)

    f.title:SetText("|cff7fd36bWindfall|r zone history - " .. MODE_LABEL[mode])
    local shown = math.min(#list, HISTORY_ROWS)
    for i = 1, HISTORY_ROWS do
        local row, e = f.rows[i], list[i]
        if e then
            row.zone:SetText((e.zone == here and "|cff7fd36b" or "|cffffffff") .. e.zone .. "|r")
            row.rate:SetText(Money(e.rate))
            row.time:SetText(ShortTime(e.time))
            row.runs:SetText(e.runs)
        else
            row.zone:SetText("") row.rate:SetText("") row.time:SetText("") row.runs:SetText("")
        end
    end

    local hint
    if #list == 0 then
        hint = "Nothing yet for this view. A zone shows up after a minute of farming there; Reset saves the session."
    elseif #list > HISTORY_ROWS then
        hint = "+ " .. (#list - HISTORY_ROWS) .. " more zones with a lower rate."
    end
    f.hint:ClearAllPoints()
    f.hint:SetPoint("TOPLEFT", 10, -48 - shown * ROW_H - 2)
    f.hint:SetText(hint or "")
    f.mode:SetText(MODE_LABEL[mode])
    f:SetHeight(48 + shown * ROW_H + (hint and 30 or 0) + 38)
end

function ToggleHistory()
    if not historyFrame then
        historyFrame = BuildHistoryFrame()
        historyFrame:Hide()
    end
    historyFrame:SetShown(not historyFrame:IsShown())
    RefreshHistory()
end

PageOpeners.zones = function()
    historyFrame = historyFrame or BuildHistoryFrame()
    historyFrame:Show()
    RefreshHistory()
end

function Refresh()
    if not frame then return end
    local lootMode = db.mode == "loot"

    local list, total, unpriced = {}, 0, 0
    for itemID, item in pairs(db.items) do
        local count = lootMode and item.count or item.gathered
        if count > 0 then
            local price, vendor = UnitPrice(itemID)
            local value = price and price * count or 0
            if not price then unpriced = unpriced + 1 end
            total = total + value
            list[#list + 1] = {
                id = itemID, count = count, price = price, vendor = vendor, value = value,
                label = string.format("|T%s:14|t %s%s|r |cffaaaaaax%d|r", tostring(ItemIcon(itemID)),
                    QualityColor(itemID), item.name or ("item " .. itemID), count),
            }
        end
    end
    if lootMode and db.money > 0 then
        total = total + db.money
        list[#list + 1] = {
            id = 0, price = true, value = db.money, coins = true,
            label = string.format("|T%d:14|t Coins", COIN_ICON),
        }
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.id < b.id
    end)

    -- Too many kinds of loot: fold the cheapest into one last row.
    if #list > MAX_ROWS then
        local rest, restValue = 0, 0
        for i = #list, MAX_ROWS, -1 do
            rest = rest + 1
            restValue = restValue + list[i].value
            list[i] = nil
        end
        list[MAX_ROWS] = {
            id = -1, price = true, value = restValue, coins = true,
            label = string.format("|cffaaaaaa+ %d more|r", rest),
        }
    end

    local elapsed = db.elapsed
    shownMinute = math.floor(elapsed / 60)
    frame.time:SetText(MODE_LABEL[db.mode] .. " - " .. Clock(elapsed)
        .. (running and "" or "  |cffff8040paused|r"))
    if elapsed >= 30 then
        frame.rate:SetText(Money(total / elapsed * 3600) .. " |cffaaaaaa/ hour|r")
    else
        frame.rate:SetText("|cffaaaaaa-- / hour|r")
    end
    frame.total:SetText("Total " .. Money(total))

    local shown = #list
    for i = 1, MAX_ROWS do
        local row, e = frame.rows[i], list[i]
        if e then
            row.name:SetText(e.label)
            if e.coins then
                row.unit:SetText("")
            elseif e.price then
                row.unit:SetText(Money(e.price) .. (e.vendor and " |cff888888vendor|r" or ""))
            else
                row.unit:SetText("")
            end
            row.value:SetText(e.price and Money(e.value) or "|cffff6060no price|r")
        else
            row.name:SetText("") row.unit:SetText("") row.value:SetText("")
        end
    end

    local hint
    if not Auctionator then
        hint = "Auctionator is not loaded, so only vendor prices are used."
    elseif shown == 0 then
        hint = lootMode and "Loot something to start the clock."
            or "Gather a herb, ore, skin or fish to start the clock."
    elseif unpriced > 0 then
        hint = "No price: scan the auction house with Auctionator."
    end
    frame.hint:ClearAllPoints()
    frame.hint:SetPoint("TOPLEFT", 10, -FARM_TOP - shown * ROW_H)
    frame.hint:SetText(hint or "")

    local getaway = db.fishOn and GetawayText() or nil
    frame.getaway:ClearAllPoints()
    frame.getaway:SetPoint("TOPLEFT", 10, -FARM_TOP - shown * ROW_H - (hint and 26 or 0) - 2)
    frame.getaway:SetText(getaway or "")

    frame.toggle:SetText(running and "Pause" or "Start")
    frame.mode:SetText(MODE_LABEL[db.mode])
    frame:SetHeight(FARM_TOP + shown * ROW_H + (hint and 26 or 0) + (getaway and 18 or 0) + 36)
    RefreshHistory()
    if UpdateBar then UpdateBar() end
end

function Windfall_ToggleWindow()
    if not frame then return end
    TogglePanel()
end

PageOpeners.farming = function()
    frame:Show()
    Refresh()
end

-- -------------------------------------------------------- minimap button ----

-- Left-click shows or hides the window, right-click switches view, dragging
-- moves the button around the minimap edge.
local minimapButton

local function PlaceMinimapButton()
    local angle = math.rad(db.minimapAngle or 230)
    local radius = (Minimap:GetWidth() / 2) + 10
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateMinimapButton()
    if not Minimap then return end
    local b = CreateFrame("Button", "WindfallMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\AddOns\\Windfall\\Media\\icon")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then SetMode() else Windfall_ToggleWindow() end
    end)
    b:SetScript("OnEnter", function(self)
        Refresh() -- so the numbers below are current
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Windfall")
        GameTooltip:AddLine(frame.time:GetText() or "", 1, 1, 1)
        GameTooltip:AddDoubleLine(frame.rate:GetText() or "", frame.total:GetText() or "", 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine("Click: show or hide the window", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click: switch Gathering / All loot", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    minimapButton = b
    PlaceMinimapButton()
    b:SetShown(not db.minimapHidden)
end

-- ------------------------------------------------------------------ bar ----

-- A small bar that stays on screen: gold per hour and the session clock, and
-- switches for the fishing key and node sparkles. The Windfall icon opens the
-- panel; clicking the gold per hour opens the farming page.
local function BarIcon(parent, texture, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(texture)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function BuildBar()
    local b = CreateFrame("Frame", "WindfallBar", UIParent, "BackdropTemplate")
    b:SetSize(250, 26)
    b:SetFrameStrata("MEDIUM")
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0, 0, 0, 0.75)
    b:SetBackdropBorderColor(0.4, 0.7, 0.3, 1)
    local pos = db.barPos or db.pos
    if pos then
        b:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        b:SetPoint("RIGHT", UIParent, "RIGHT", -120, 0)
    end
    b:SetScript("OnDragStart", b.StartMoving)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        db.barPos = { point, relPoint, x, y }
    end)

    -- Windfall icon: the panel.
    b.menu = BarIcon(b, "Interface\\AddOns\\Windfall\\Media\\icon", 18)
    b.menu:SetPoint("RIGHT", -5, 0)
    b.menu:SetScript("OnClick", function() TogglePanel() end)
    b.menu:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Windfall")
        GameTooltip:AddLine("Farming, zones, professions, route and settings.", 1, 1, 1, true)
        GameTooltip:AddLine("Click: open or close", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Drag the bar to move it", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    -- Node sparkles on or off.
    b.sparkle = BarIcon(b, "Interface\\Icons\\INV_Misc_Flower_02", 16)
    b.sparkle:SetPoint("RIGHT", b.menu, "LEFT", -6, 0)
    b.sparkle:SetScript("OnClick", function() Windfall_ToggleSparkles() end)
    b.sparkle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Node sparkles" .. (db.sparkle and "  |cff7fd36bON|r" or "  |cff999999off|r"))
        GameTooltip:AddLine("The nearest herb, ore or fishing pool you can gather gets a sparkle.", 1, 1, 1, true)
        GameTooltip:AddLine("Click: switch on or off", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    -- Fishing key on or off; right-click picks the key.
    b.fish = BarIcon(b, FISH_ICON, 16)
    b.fish:SetPoint("RIGHT", b.sparkle, "LEFT", -6, 0)
    b.fish:SetScript("OnClick", function(_, button)
        if button == "RightButton" then StartKeyCapture() else Windfall_ToggleFishing() end
    end)
    b.fish:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Fishing key: " .. (db.fishKey or "not set")
            .. (db.fishOn and "  |cff7fd36bON|r" or "  |cff999999off|r"))
        GameTooltip:AddLine("While on, this key casts Fishing and then reels in the bobber. Off, the key is back to normal.", 1, 1, 1, true)
        local getaway = GetawayText()
        if getaway then GameTooltip:AddLine(getaway, 1, 1, 1) end
        GameTooltip:AddLine("Click: switch on or off", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click: choose the key", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    -- Gold per hour and the clock: the farming page.
    b.money = CreateFrame("Button", nil, b)
    b.money:SetPoint("LEFT", 6, 0)
    b.money:SetPoint("RIGHT", b.fish, "LEFT", -6, 0)
    b.money:SetHeight(20)
    b.money:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.rate = b.money:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.rate:SetPoint("LEFT")
    b.time = b.money:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.time:SetPoint("LEFT", b.rate, "RIGHT", 6, 0)
    b.money:SetScript("OnClick", function(_, button)
        if button == "RightButton" then SetMode() else PageOpeners.farming() end
    end)
    b.money:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Windfall - " .. MODE_LABEL[db.mode])
        GameTooltip:AddLine(frame.total:GetText() or "", 1, 1, 1)
        GameTooltip:AddLine("Click: what you have gathered", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click: switch Gathering / All loot", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b.money:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetShown(not db.barHidden)
    return b
end

function UpdateBar()
    if not (bar and frame) then return end
    local minutes = math.floor((db.elapsed or 0) / 60)
    local clock = minutes >= 60 and string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60) or (minutes .. "m")
    bar.rate:SetText((frame.rate:GetText() or ""):gsub(" |cffaaaaaa/ hour|r", "/h"))
    bar.time:SetText(clock .. (running and "" or " |cffff8040paused|r"))
end

function UpdateBarIcons()
    if not bar then return end
    bar.fish.icon:SetDesaturated(not db.fishOn)
    bar.fish:SetAlpha(db.fishOn and 1 or 0.45)
    bar.sparkle.icon:SetDesaturated(not db.sparkle)
    bar.sparkle:SetAlpha(db.sparkle and 1 or 0.45)
end

-- ---------------------------------------------------------------- slash ----

-- ------------------------------------------------------------- settings ----

local function MakeWindow(name, label, width, key)
    return NewPage(name, label, width, key)
end

local settingsFrame

-- Each row is a header, or a checkbox with either a saved key (on unless
-- switched off) or its own get and set.
local SETTINGS = {
    { header = "Fishing key" },
    { label = "Fishing key on", keyButton = true,
        tip = "While on, your fishing key casts Fishing and reels in the bobber. Off, the key is back to normal.",
        get = function() return db.fishOn end,
        set = function(value) SetFishing(value) end },
    { key = "fishEquip", label = "Equip my fishing pole, and put my weapons back after",
        tip = "Switching the fishing key on equips the best pole in your bags. Switching it off brings back the weapons you had." },
    { key = "fishLure", label = "Put a lure on when the pole has none",
        tip = "The fishing key puts on the best lure in your bags that your skill allows, before casting." },
    { key = "fishDouble", label = "Double right-click to cast",
        tip = "While the fishing key is on, two quick right-clicks on the world cast." },
    { key = "fishLoot", label = "Auto loot while the fishing key is on",
        tip = "Auto loot goes back to your own setting when the fishing key is switched off.",
        after = function() UpdateAutoLoot() end },
    { key = "fishSound", label = "Louder bobber splash while the line is out",
        tip = "Sound effects go to full and music and ambience to a quarter, until the line comes in." },
    { key = "fishSleep", label = "Switch off after 10 idle minutes, and follow the pole",
        tip = "The fishing key switches itself off after 10 minutes without fishing. Equipping a pole by hand switches it on; taking it off switches it off." },
    { header = "Gathering" },
    { label = "Sparkle on the nearest gathering node",
        tip = "The nearest herb, ore or fishing pool close by gets a sparkle and the game's gather icon. Quest objects, chests and NPCs are left alone. The game only picks up nodes within about 15 yards.",
        get = function() return db.sparkle end,
        set = function(value) db.sparkle = value ApplySparkles() if UpdateBarIcons then UpdateBarIcons() end end },
    { key = "sparkleHerb", label = "    Herbs", after = function() SparkleRecheck() end },
    { key = "sparkleOre", label = "    Ore", after = function() SparkleRecheck() end },
    { key = "sparkleFish", label = "    Fishing pools", after = function() SparkleRecheck() end },
    { key = "interactDefault", label = "Interact back to game default when Windfall is done",
        tip = "When the line comes in or sparkles are switched off, the interact key goes to the game's defaults (10 yards, in front of you) instead of what was set before. Windfall leaves it alone the rest of the time." },
    { header = "Window" },
    { label = "Show the Windfall bar",
        tip = "The small bar with your gold per hour and the fishing and sparkle switches.",
        get = function() return not db.barHidden end,
        set = function(value)
            db.barHidden = not value
            if bar then bar:SetShown(value) end
        end },
    { label = "Show the minimap button",
        get = function() return not db.minimapHidden end,
        set = function(value)
            db.minimapHidden = not value
            if minimapButton then minimapButton:SetShown(value) end
        end },
}

local function BuildSettingsFrame()
    local f = MakeWindow("WindfallSettingsFrame", "Settings", 380, "settings")
    f.checks = {}
    local y = -36
    for _, row in ipairs(SETTINGS) do
        if row.header then
            local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            head:SetPoint("TOPLEFT", 12, y - 4)
            head:SetText(row.header)
            y = y - 24
        else
            local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            check:SetSize(24, 24)
            check:SetPoint("TOPLEFT", 12, y)
            check.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
            check.label:SetText(row.label)
            check.row = row
            check:SetScript("OnClick", function(self)
                local value = self:GetChecked() and true or false
                if row.key then db[row.key] = value else row.set(value) end
                if row.after then row.after() end
                RefreshSettings()
            end)
            if row.tip then
                check:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(row.label)
                    GameTooltip:AddLine(row.tip, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                check:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            if row.keyButton then
                f.keyButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
                f.keyButton:SetSize(150, 20)
                f.keyButton:SetPoint("TOPRIGHT", -14, y - 2)
                f.keyButton:SetScript("OnClick", function() StartKeyCapture() end)
            end
            f.checks[#f.checks + 1] = check
            y = y - 24
        end
    end

    f.history = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.history:SetSize(120, 22)
    f.history:SetPoint("BOTTOMLEFT", 12, 10)
    f.history:SetText("Zone history")
    f.history:SetScript("OnClick", function() ToggleHistory() end)

    f.profs = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.profs:SetSize(120, 22)
    f.profs:SetPoint("LEFT", f.history, "RIGHT", 6, 0)
    f.profs:SetText("Professions")
    f.profs:SetScript("OnClick", function() ToggleProfessions() end)
    -- The tabs at the bottom do this now.
    f.history:Hide()
    f.profs:Hide()

    f:SetHeight(-y + 44)
    return f
end

function RefreshSettings()
    if not (settingsFrame and settingsFrame:IsShown()) then return end
    for _, check in ipairs(settingsFrame.checks) do
        local row = check.row
        local value
        if row.key then value = db[row.key] ~= false else value = row.get() end
        check:SetChecked(value and true or false)
    end
    settingsFrame.keyButton:SetText("Key: " .. (db.fishKey or "click to choose"))
end

function ToggleSettings()
    if not settingsFrame then settingsFrame = BuildSettingsFrame() end
    settingsFrame:SetShown(not settingsFrame:IsShown())
    RefreshSettings()
end

PageOpeners.settings = function()
    settingsFrame = settingsFrame or BuildSettingsFrame()
    settingsFrame:Show()
    RefreshSettings()
end

-- ---------------------------------------------------------- professions ----
local DIFFICULTY_COLOR, ReagentPrice, CraftNumbers, SKILL_CHANCE, TRAIN_SPREAD, GuessDifficulty, TrainerRecipe
local SyncLearned, SkillUpChance, PointCost, MIN_CHANCE
local RouteTarget, ROUTE_TARGETS, RebuildRoute
-- In a block of its own: the game allows a file at most 200 locals at the top.
do

-- Every character's recipes are saved when one of its profession windows
-- opens, so alts show up too once you have opened theirs. Prices are looked
-- up when the window is drawn, so they follow your latest Auctionator scan.

local AH_CUT = 0.05
local PROF_ROWS = 18
local LIST_W = 300  -- the recipe list on the Recipes tab
local DETAIL_W = 300 -- the picked recipe next to it
local PROF_WIDTH = 520
local DIFFICULTY_BY_NUMBER = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
DIFFICULTY_COLOR = {
    optimal = "|cffff8040", medium = "|cffffff00", easy = "|cff40c040", trivial = "|cff808080",
}
local DIFFICULTY_LABEL = {
    optimal = "always gives a skill point", medium = "usually gives a skill point",
    easy = "sometimes gives a skill point", trivial = "gives no skill",
}

-- The character's full name. Forever characters have a surname, which
-- UnitName gives as its second value; joined as the game's own frames show it.
local function FullName()
    local first, surname = (UnitNameUnmodified or UnitName)("player")
    if type(surname) == "string" and surname ~= "" and not (issecretvalue and issecretvalue(surname)) then
        local sep = Constants and Constants.CharacterNameSeparatorConsts
            and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
        return first .. sep .. surname
    end
    return first
end

-- Saved under full name and realm: two characters with the same first name
-- (Zivv Gg and Zivv Zniper) are kept apart.
local function CharacterKey()
    local realm = GetRealmName and GetRealmName() or ""
    return (FullName() or "?") .. "-" .. realm
end

-- Before 0.2.38 characters were saved under their first name only. That entry
-- goes to the first character of that name to log in, if its professions are
-- this character's; otherwise it stays as it was.
local function AdoptOldEntry(key, professionNames)
    local first = UnitName("player")
    local old = (first or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
    if old == key or not db.chars[old] or db.chars[key] then return end
    for name in pairs(db.chars[old].professions or {}) do
        if not professionNames[name] then return end
    end
    db.chars[key] = db.chars[old]
    db.chars[old] = nil
end

-- A recipe's reagents and what it makes, from the game. Works for recipes
-- not learned yet too. Nil if the game has nothing for it.
function ReadRecipe(recipeID, name)
    local T = C_TradeSkillUI
    local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false)
    if not (ok and schematic) then return nil end
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        local basic = not (Enum and Enum.CraftingReagentType) or slot.reagentType == Enum.CraftingReagentType.Basic
        if basic and first and first.itemID and (slot.quantityRequired or 0) > 0 then
            reagents[#reagents + 1] = { first.itemID, slot.quantityRequired }
        end
    end
    if not name then
        local info = T.GetRecipeInfo and T.GetRecipeInfo(recipeID)
        name = (info and info.name) or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID))
    end
    return {
        name = name,
        item = schematic.outputItemID,
        qty = ((schematic.quantityMin or 1) + (schematic.quantityMax or schematic.quantityMin or 1)) / 2,
        reagents = reagents,
    }
end

-- The skill line of a profession (165 for Leatherworking), from its id or,
-- failing that, by matching its name against the profession's own spell.
local PROFESSION_SPELLS = {
    [171] = 2259, [164] = 2018, [185] = 2550, [333] = 7411,
    [202] = 4036, [129] = 3273, [165] = 2108, [197] = 3908,
}

function SkillLineOf(base)
    if PROFESSION_SPELLS[base.professionID] then return base.professionID end
    if PROFESSION_SPELLS[base.parentProfessionID] then return base.parentProfessionID end
    if C_Spell and C_Spell.GetSpellName then
        for line, spell in pairs(PROFESSION_SPELLS) do
            if C_Spell.GetSpellName(spell) == base.professionName then return line end
        end
    end
end

local function SaveProfession()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetRecipeSchematic) then return end
    -- Someone else's profession (a link, a guild list, an NPC) is not yours.
    for _, check in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
        if T[check] and T[check]() then return end
    end
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    if not (base and base.professionName and base.professionName ~= "") then return end
    local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
    local skillInfo = (child and (child.maxSkillLevel or 0) > 0) and child or base

    local recipes = {}
    for _, recipeID in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(recipeID)
        if info and info.learned and not info.isRecraft and not info.isSalvageRecipe then
            local recipe = ReadRecipe(recipeID, info.name)
            if recipe then
                recipe.diff = DIFFICULTY_BY_NUMBER[info.relativeDifficulty] or info.difficulty
                recipes[recipeID] = recipe
            end
        end
    end
    if not next(recipes) then return end

    -- What the trainer has still to teach: read the reagents now, while the
    -- game has them at hand, for the levelling plan.
    local line = SkillLineOf(base)
    db.recipeData = db.recipeData or {}
    for _, entry in ipairs(line and ns.TrainerRecipes[line] or {}) do
        local spell = entry[1]
        if not entry.rank and not recipes[spell] and not db.recipeData[spell] then
            db.recipeData[spell] = ReadRecipe(spell)
        end
    end

    db.chars = db.chars or {}
    local key = CharacterKey()
    local char = db.chars[key] or { professions = {} }
    db.chars[key] = char
    local _, class = UnitClass("player")
    char.class = class
    char.name = FullName()
    char.level = UnitLevel and UnitLevel("player")
    char.professions[base.professionName] = {
        skill = skillInfo.skillLevel, max = skillInfo.maxSkillLevel, line = line,
        saved = time(), recipes = recipes,
    }
end

local professionSavePending = false
function SaveProfessionSoon()
    if professionSavePending then return end
    professionSavePending = true
    -- The list arrives in pieces; wait for it to settle.
    C_Timer.After(1, function()
        professionSavePending = false
        SaveProfession()
        if RefreshProfessions then RefreshProfessions() end
        -- The route moves on as your skill goes up.
        if RebuildRoute then RebuildRoute() end
    end)
end

-- Materials on hand, per character: the bags whenever they change, the bank
-- whenever it is open. So every character's materials are known on any other.
local BAGS = { 0, 1, 2, 3, 4 }
local bankOpen = false
local inventoryPending = false

local function BankBags()
    local bags = { BANK_CONTAINER or -1 }
    local first = (NUM_BAG_SLOTS or 4) + 1
    for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do bags[#bags + 1] = bag end
    return bags
end

local function CountContainers(bags)
    local counts = {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return counts end
    for _, bag in ipairs(bags) do
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (ok and slots) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return counts
end

local function MyCharacter()
    db.chars = db.chars or {}
    local key = CharacterKey()
    local char = db.chars[key]
    if not char then
        char = { professions = {} }
        db.chars[key] = char
    end
    local _, class = UnitClass("player")
    char.class, char.name = class or char.class, FullName() or char.name
    return char
end

function SaveInventory()
    if inventoryPending or not db then return end
    inventoryPending = true
    -- Bags change in bursts; count once they have settled.
    C_Timer.After(0.5, function()
        inventoryPending = false
        local char = MyCharacter()
        char.bags = CountContainers(BAGS)
        if bankOpen then char.bank = CountContainers(BankBags()) end
    end)
end

function SetBankOpen(open)
    bankOpen = open
    if open then SaveInventory() end
end

-- How many of an item a character has in bags and bank, how many all your
-- other characters have, and who.
local function LiveCount(itemID)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return count and count(itemID, true) or 0
end

local function SavedCount(char, itemID)
    return ((char.bags or {})[itemID] or 0) + ((char.bank or {})[itemID] or 0)
end

function HaveCount(charKey, itemID)
    local me = CharacterKey()
    local here
    if charKey == me then
        here = LiveCount(itemID)
    else
        local char = db.chars and db.chars[charKey]
        here = char and SavedCount(char, itemID) or 0
    end
    local others, who = 0, {}
    for key, char in pairs(db.chars or {}) do
        if key ~= charKey then
            local n = key == me and LiveCount(itemID) or SavedCount(char, itemID)
            if n > 0 then
                others = others + n
                who[#who + 1] = { key = key, n = n }
            end
        end
    end
    return here, others, who
end

-- This character's crafting professions that Windfall has not saved yet.
-- Opening a profession window is only allowed on a real click, so the Load
-- button opens one per click; saving then happens as for any window you open.
local function UnsavedProfessions()
    local list = {}
    if not (GetProfessions and GetProfessionInfo) then return list end
    local char = db.chars and db.chars[CharacterKey()]
    for _, index in pairs({ GetProfessions() }) do
        local name, _, _, _, _, _, skillLine = GetProfessionInfo(index)
        local saved = char and char.professions[name]
        if PROFESSION_SPELLS[skillLine] and not (saved and not saved.unloaded) then
            list[#list + 1] = { line = skillLine, name = name }
        end
    end
    return list
end

-- The character you are playing, listed as soon as you log in: its crafting
-- professions with their skill, read from the game. Their recipes come when
-- each profession window is opened once (or with Load); until then they are
-- marked as not loaded.
function NoteCharacter()
    if not (db and GetProfessions and GetProfessionInfo) then return end
    db.chars = db.chars or {}
    local key = CharacterKey()
    local names = {}
    for _, index in pairs({ GetProfessions() }) do
        local name = GetProfessionInfo(index)
        if name then names[name] = true end
    end
    AdoptOldEntry(key, names)
    local char = db.chars[key] or { professions = {} }
    local _, class = UnitClass("player")
    char.class = class
    char.name = FullName()
    char.level = UnitLevel and UnitLevel("player")
    local any = false
    for _, index in pairs({ GetProfessions() }) do
        local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
        if PROFESSION_SPELLS[skillLine] and name then
            any = true
            local prof = char.professions[name]
            if prof then
                prof.skill, prof.max, prof.line = rank or prof.skill, maxRank or prof.max, skillLine
            else
                char.professions[name] = { skill = rank, max = maxRank, line = skillLine, recipes = {}, unloaded = true }
            end
        end
    end
    if any or next(char.professions) then db.chars[key] = char end
end

local function LoadProfessions()
    local T = C_TradeSkillUI
    local nextOne = UnsavedProfessions()[1]
    if not nextOne then
        print("|cff7fd36bWindfall|r: this character's professions are all loaded.")
        return
    end
    if not (T and T.OpenTradeSkill) or (InCombatLockdown and InCombatLockdown()) then
        print("|cff7fd36bWindfall|r: open your " .. nextOne.name .. " window and it is saved.")
        return
    end
    T.OpenTradeSkill(nextOne.line)
end

-- What it costs to get one of a reagent: the cheaper of the auction house
-- and a vendor that sells it (as Auctionator saw at that vendor).
function ReagentPrice(itemID)
    local ah = AuctionPrice(itemID)
    local vendor
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetVendorPriceByItemID then
        local ok, price = pcall(api.GetVendorPriceByItemID, ADDON, itemID)
        if ok and type(price) == "number" and price > 0 then vendor = price end
    end
    if ah and vendor then return math.min(ah, vendor), vendor < ah end
    return ah or vendor, vendor ~= nil
end

-- Cost, value and profit of one craft. Value is what the result sells for
-- after the auction house cut, or what a vendor pays if that is more.
function CraftNumbers(recipe)
    local cost, missing = 0, false
    for _, r in ipairs(recipe.reagents) do
        local price = ReagentPrice(r[1])
        if price then cost = cost + price * r[2] else missing = true end
    end
    local value
    if recipe.item then
        local ah, sell = AuctionPrice(recipe.item), VendorPrice(recipe.item)
        local fromAH = ah and ah * (1 - AH_CUT)
        if fromAH or sell then value = math.max(fromAH or 0, sell or 0) * recipe.qty end
    end
    local profit = (value and not missing) and (value - cost) or nil
    return cost, value, profit, missing
end

local profFrame, profView = nil, { char = nil, prof = nil, mode = "profit", offset = 0 }
local profList = {}

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function SignedMoney(copper)
    if copper < 0 then return "|cffff6060-" .. Money(-copper) .. "|r" end
    return "|cff7fd36b" .. Money(copper) .. "|r"
end

-- Picks the character and profession to show, falling back to what exists.
local function CurrentProfession()
    local chars = db.chars or {}
    if not profView.chosen and chars[CharacterKey()] then profView.char = CharacterKey() end
    if not chars[profView.char] then
        profView.char = chars[CharacterKey()] and CharacterKey() or SortedKeys(chars)[1]
    end
    local char = chars[profView.char]
    if not char then return nil end
    if not char.professions[profView.prof] then profView.prof = SortedKeys(char.professions)[1] end
    return char, char.professions[profView.prof]
end

local function ShortName(key)
    local char = db.chars and db.chars[key]
    if char and char.name then return char.name end
    return (key or ""):match("^(.-)%-") or key
end

-- A character's name, with the realm added when another saved character
-- has the same name.
local function DisplayName(key)
    local name = ShortName(key)
    for other in pairs(db.chars or {}) do
        if other ~= key and ShortName(other) == name then
            local realm = (key or ""):match("^.-%-(.+)$")
            return realm and (name .. " |cff999999(" .. realm .. ")|r") or name
        end
    end
    return name
end

local function ClassColored(char, key)
    local c = char and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.class]
    local name = DisplayName(key)
    return c and string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) or name
end

local function BuildProfitList(prof)
    local list = {}
    for recipeID, recipe in pairs(prof.recipes) do
        local cost, value, profit, missing = CraftNumbers(recipe)
        list[#list + 1] = { id = recipeID, recipe = recipe, cost = cost, value = value,
            profit = profit, missing = missing }
    end
    -- Best profit first; recipes that cannot be priced go last.
    table.sort(list, function(a, b)
        if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
        if a.profit and a.profit ~= b.profit then return a.profit > b.profit end
        return (a.recipe.name or "") < (b.recipe.name or "")
    end)
    return list
end

-- Levelling plan. Recipes you know come with their real colour from the
-- game. For recipes you can train but have not, the colour is a guess from
-- how far past their unlock skill you are, since the game only says once you
-- know them. A craft that sells covers part of its own cost; orange gives a
-- point every time, yellow and green less often.
SKILL_CHANCE = { optimal = 1, medium = 0.75, easy = 0.25 }
local RANK_CAP = { Journeyman = 150, Expert = 225, Artisan = 300 }
TRAIN_SPREAD = 5      -- skill points a trained recipe's price is spread over
local PLAN_CHOICES = 8      -- recipes listed under "best way up"
local PLAN_UNLOCKS = 6      -- recipes listed under "coming up"

function GuessDifficulty(unlockAt, skill)
    local gap = skill - unlockAt
    if gap < 10 then return "optimal" elseif gap < 25 then return "medium" elseif gap < 40 then return "easy" end
    return "trivial"
end

-- Chance that one craft gives a skill point, and the recipe's colour, at a
-- skill. Uses the game's own yellow and grey levels where Windfall has them
-- (Data/SkillUps.lua): a point every time until yellow, then less in a
-- straight line down to nothing at grey. Without them, a guess from the
-- recipe's unlock skill.
function SkillUpChance(spell, unlock, skill)
    if unlock and skill < unlock then return 0, nil end
    local t = ns.SkillUps and ns.SkillUps[spell]
    if t then
        local yellow, grey = t[1], t[2]
        if skill >= grey then return 0, "trivial" end
        if skill < yellow then return 1, "optimal" end
        local diff = skill < (yellow + grey) / 2 and "medium" or "easy"
        return (grey - skill) / (grey - yellow), diff
    end
    local diff = GuessDifficulty(unlock or skill, skill)
    return SKILL_CHANCE[diff] or 0, diff
end

-- What a skill point costs with a recipe. What the craft sells for comes off,
-- but levelling never counts as earning (that made low-chance crafts look
-- good), and every craft carries a little effort (a tenth of its materials),
-- so a sure point beats many tries.
MIN_CHANCE = 0.5        -- below this, a recipe is only used when nothing better is left
local EFFORT = 0.1

function PointCost(cost, value, chance)
    if not chance or chance <= 0 then return nil end
    return (math.max(cost - (value or 0), 0) + cost * EFFORT) / chance
end

function TrainerRecipe(entry)
    local data = db.recipeData and db.recipeData[entry[1]]
    return {
        name = (data and data.name) or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry[1]))
            or ("recipe " .. entry[1]),
        item = (data and data.item) or entry[4],
        qty = (data and data.qty) or 1,
        reagents = (data and data.reagents) or {},
        noReagents = not data,
    }
end

-- Trainer recipes this character has learned since its profession window was
-- last read: the game knows them as spells, so they count as known right away,
-- with a guessed colour until the profession window says better.
function SyncLearned(prof, charKey)
    if not (prof and prof.line) or charKey ~= CharacterKey() then return false end
    local char = db.chars and db.chars[charKey]
    if char and UnitLevel then char.level = UnitLevel("player") end
    -- Skill and cap as the game has them now: training a rank or a skill-up
    -- shows here without opening the profession window.
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ GetProfessions() }) do
            local _, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
            if skillLine == prof.line and rank then
                prof.skill, prof.max = rank, maxRank or prof.max
            end
        end
    end
    if not IsPlayerSpell then return false end
    local added = false
    for _, entry in ipairs(ns.TrainerRecipes[prof.line] or {}) do
        local spell = entry[1]
        if not entry.rank and not prof.recipes[spell] and IsPlayerSpell(spell) then
            local recipe = TrainerRecipe(entry)
            recipe.diff = select(2, SkillUpChance(spell, entry[2], prof.skill or 1)) or "trivial"
            recipe.noReagents = nil
            prof.recipes[spell] = recipe
            added = true
        end
    end
    return added
end

local function BuildPlan(prof, char)
    local skill = prof.skill or 0
    local trainer = prof.line and ns.TrainerRecipes[prof.line] or {}
    local choices = {}
    local unlockAt = {}
    for _, entry in ipairs(trainer) do
        if not entry.rank then unlockAt[entry[1]] = entry[2] end
    end
    for recipeID, recipe in pairs(prof.recipes) do
        local chance
        if ns.SkillUps and ns.SkillUps[recipeID] then
            chance = SkillUpChance(recipeID, nil, skill)
        else
            chance = SKILL_CHANCE[recipe.diff] -- the game's colour, no exact numbers
        end
        if chance and chance > 0 then
            choices[#choices + 1] = { id = recipeID, recipe = recipe, train = 0, chance = chance }
        end
    end
    for _, entry in ipairs(trainer) do
        if not entry.rank and entry[2] <= skill and not prof.recipes[entry[1]] then
            local chance, diff = SkillUpChance(entry[1], entry[2], skill)
            if chance > 0 then
                local recipe = TrainerRecipe(entry)
                recipe.diff = diff
                choices[#choices + 1] = { id = entry[1], recipe = recipe, train = entry[3], chance = chance,
                    guess = not (ns.SkillUps and ns.SkillUps[entry[1]]) }
            end
        end
    end
    for _, e in ipairs(choices) do
        e.cost, e.value, e.profit, e.missing = CraftNumbers(e.recipe)
        e.missing = e.missing or e.recipe.noReagents
        if not e.missing then
            e.perPoint = PointCost(e.cost, e.value, e.chance) + e.train / TRAIN_SPREAD
        end
    end
    table.sort(choices, function(a, b)
        if (a.perPoint ~= nil) ~= (b.perPoint ~= nil) then return a.perPoint ~= nil end
        local aSure, bSure = a.chance >= MIN_CHANCE, b.chance >= MIN_CHANCE
        if aSure ~= bSure then return aSure end
        if a.perPoint and a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
        return (a.recipe.name or "") < (b.recipe.name or "")
    end)

    local list = {}
    -- The next rank, once it is the thing holding you back.
    for _, entry in ipairs(trainer) do
        if entry.rank and (RANK_CAP[entry.rank] or 0) > (prof.max or 0) then
            local needLevel = entry[4] > 0 and (char.level or 0) < entry[4]
            list[#list + 1] = { kind = "rank", entry = entry, ready = skill >= entry[2] and not needLevel,
                needLevel = needLevel and entry[4] }
            break
        end
    end
    list[#list + 1] = { kind = "header", text = "Best way up from " .. skill }
    if not choices[1] then
        list[#list + 1] = { kind = "note", text = "Nothing you know or can train gives skill right now." }
    end
    for i = 1, math.min(#choices, PLAN_CHOICES) do list[#list + 1] = choices[i] end

    local unlocks = {}
    for _, entry in ipairs(trainer) do
        if not entry.rank and entry[2] > skill and not prof.recipes[entry[1]] then
            unlocks[#unlocks + 1] = entry
        end
    end
    if unlocks[1] then
        list[#list + 1] = { kind = "header", text = "Coming up at the trainer" }
        for i = 1, math.min(#unlocks, PLAN_UNLOCKS) do
            local entry = unlocks[i]
            list[#list + 1] = { kind = "unlock", entry = entry, recipe = TrainerRecipe(entry) }
        end
    end
    return list
end

local function BuildProfList(prof, char)
    if profView.mode == "plan" then return BuildPlan(prof, char) end
    return BuildProfitList(prof)
end

local function RecipeTooltip(row)
    local e = row.entry
    if not (e and e.recipe) then return end
    e.cost, e.value, e.profit, e.missing = CraftNumbers(e.recipe)
    local recipe = e.recipe
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine((DIFFICULTY_COLOR[recipe.diff] or "") .. (recipe.name or "?") .. "|r")
    if DIFFICULTY_LABEL[recipe.diff] then
        GameTooltip:AddLine(DIFFICULTY_LABEL[recipe.diff] .. (e.guess and " (a guess until you learn it)" or ""), 0.7, 0.7, 0.7, true)
    end
    if e.kind == "unlock" then
        GameTooltip:AddLine(string.format("The trainer teaches it from skill %d for %s.", e.entry[2], Money(e.entry[3])), 1, 1, 1, true)
    elseif (e.train or 0) > 0 then
        GameTooltip:AddLine("Not learned yet: the trainer teaches it for " .. Money(e.train) .. ".", 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    if recipe.noReagents then
        GameTooltip:AddLine("Open your profession window once to load its reagents.", 1, 0.5, 0.5, true)
    end
    for _, r in ipairs(recipe.reagents) do
        local price, fromVendor = ReagentPrice(r[1])
        local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r[1])) or ("item " .. r[1])
        GameTooltip:AddDoubleLine(string.format("%dx %s", r[2], name),
            price and (Money(price * r[2]) .. (fromVendor and " |cff888888vendor|r" or "")) or "|cffff6060no price|r",
            1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Cost", Money(e.cost) .. (e.missing and " |cffff6060+ unpriced|r" or ""), 1, 0.82, 0, 1, 1, 1)
    if e.value then
        GameTooltip:AddDoubleLine("Sells for", Money(e.value) .. (recipe.qty ~= 1 and string.format(" (%gx)", recipe.qty) or ""),
            1, 0.82, 0, 1, 1, 1)
    elseif not recipe.item then
        GameTooltip:AddLine("Makes no item to sell (an enchant or similar).", 0.7, 0.7, 0.7, true)
    end
    if e.profit then GameTooltip:AddDoubleLine("Profit", SignedMoney(e.profit), 1, 0.82, 0, 1, 1, 1) end
    GameTooltip:AddLine("Sale value is after the 5% auction house cut.", 0.5, 0.5, 0.5, true)
    if recipe.reagents[1] then GameTooltip:AddLine("Click: shopping list for it", 0.5, 0.5, 0.5) end
    GameTooltip:Show()
end

-- How many times a character can make a recipe from what it holds.
function CanMake(charKey, recipe)
    local n
    for _, r in ipairs(recipe.reagents or {}) do
        local here = HaveCount(charKey, r[1])
        local can = math.floor(here / r[2])
        n = n and math.min(n, can) or can
    end
    return n or 0
end

local function WhoHas(who)
    table.sort(who, function(a, b) return a.n > b.n end)
    local parts = {}
    for i = 1, math.min(#who, 3) do parts[#parts + 1] = string.format("%s %d", ShortName(who[i].key), who[i].n) end
    if #who > 3 then parts[#parts + 1] = "..." end
    return table.concat(parts, ", ")
end

function ShowRecipeDetail(f, prof)
    local d = f.detail
    local e
    for _, x in ipairs(profList) do
        if x.id == profView.selected then e = x end
    end
    e = e or profList[1]
    if not (e and e.recipe) then d:Hide() return end
    profView.selected = e.id
    d:Show()
    local recipe = e.recipe
    local icon = recipe.item and ItemIcon(recipe.item)
        or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.id)) or 134400
    d.icon:SetTexture(icon)
    d.name:SetText((DIFFICULTY_COLOR[recipe.diff] or "|cffffffff") .. (recipe.name or "?") .. "|r")
    local chance = ns.SkillUps and ns.SkillUps[e.id] and SkillUpChance(e.id, nil, prof.skill or 0)
    local skillText = chance and (chance >= 1 and "always gives a skill point"
        or chance > 0 and string.format("%d%% chance of a skill point", math.floor(chance * 100 + 0.5))
        or "gives no skill") or (DIFFICULTY_LABEL[recipe.diff] or "")
    d.sub:SetText((recipe.qty and recipe.qty ~= 1 and string.format("Makes %g. ", recipe.qty) or "") .. skillText)
    for i, line in ipairs(d.reagents) do
        local r = recipe.reagents[i]
        if r then
            local here, others, who = HaveCount(profView.char, r[1])
            line:SetText(string.format("|T%s:16|t %s", tostring(ItemIcon(r[1])),
                (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r[1])) or ("item " .. r[1])))
            line.count:SetText(string.format("%s%d|r / %d", here >= r[2] and "|cff7fd36b" or "|cffff6060", here, r[2]))
            line.alts:SetText(others > 0 and ("on other characters: " .. WhoHas(who)) or "")
            line:Show() line.count:Show() line.alts:Show()
        else
            line:Hide() line.count:Hide() line.alts:Hide()
        end
    end
    local shown = math.min(#recipe.reagents, #d.reagents)
    d.money:ClearAllPoints()
    d.money:SetPoint("TOPLEFT", 0, -76 - shown * 30)
    local can = CanMake(profView.char, recipe)
    d.money:SetText(string.format("Cost: %s%s\nSells for: %s\nProfit: %s\n\n%s",
        Money(e.cost), e.missing and " |cffff6060+ unpriced|r" or "",
        e.value and Money(e.value) or "|cff888888-|r",
        e.profit and SignedMoney(e.profit) or "|cff888888?|r",
        can > 0 and string.format("|cff7fd36b%s can make %d.|r", ShortName(profView.char), can)
            or string.format("|cff999999%s has not got the reagents.|r", ShortName(profView.char))))
end

-- The recipes that earn the most, for a maxed profession's Levelling tab.
function TopProfit(prof, n)
    local list, out = BuildProfitList(prof), {}
    for _, e in ipairs(list) do
        if e.profit and e.profit > 0 and #out < n then out[#out + 1] = e end
    end
    return out
end

local function BuildProfessionsFrame()
    local f = MakeWindow("WindfallProfessionsFrame", "Recipes", PROF_WIDTH, "professions")
    f:SetHeight(84 + PROF_ROWS * ROW_H + 40)
    f.pageOffset = 52 -- the character and profession are picked in the window's header

    f.charButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.charButton:SetSize(150, 20)
    f.charButton:SetPoint("TOPLEFT", 10, -32)
    f.charButton:SetScript("OnClick", function()
        local keys = SortedKeys(db.chars)
        for i, k in ipairs(keys) do
            if k == profView.char then profView.char = keys[i % #keys + 1] break end
        end
        profView.prof, profView.offset = nil, 0
        RefreshProfessions()
    end)

    f.profButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.profButton:SetSize(130, 20)
    f.profButton:SetPoint("LEFT", f.charButton, "RIGHT", 6, 0)
    f.profButton:SetScript("OnClick", function()
        local char = CurrentProfession()
        local keys = SortedKeys(char and char.professions)
        for i, k in ipairs(keys) do
            if k == profView.prof then profView.prof = keys[i % #keys + 1] break end
        end
        profView.offset = 0
        RefreshProfessions()
    end)

    f.modeButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.modeButton:SetSize(130, 20)
    f.modeButton:SetPoint("LEFT", f.profButton, "RIGHT", 6, 0)
    f.modeButton:SetScript("OnClick", function()
        profView.mode = profView.mode == "profit" and "plan" or "profit"
        profView.offset = 0
        RefreshProfessions()
    end)

    f.skill = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.skill:SetPoint("TOPRIGHT", -14, -36)

    -- The list on the left (name and profit), the picked recipe on the right.
    local function Column(row, template)
        row.name = f:CreateFontString(nil, "OVERLAY", template)
        row.name:SetWidth(LIST_W - 90)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.cost = f:CreateFontString(nil, "OVERLAY", template)
        row.value = f:CreateFontString(nil, "OVERLAY", template)
        row.profit = f:CreateFontString(nil, "OVERLAY", template)
        row.cost:Hide()
        row.value:Hide()
    end
    local function Place(row, y)
        row.name:SetPoint("TOPLEFT", 12, y)
        row.profit:SetPoint("TOPRIGHT", f, "TOPLEFT", LIST_W, y)
    end
    f.head = {}
    Column(f.head, "GameFontDisableSmall")
    Place(f.head, -62)
    f.head.name:SetText("Recipe")

    f.rows = {}
    for i = 1, PROF_ROWS do
        local y = -78 - (i - 1) * ROW_H
        local row = CreateFrame("Button", nil, f)
        row:SetPoint("TOPLEFT", 8, y + 2)
        row:SetSize(LIST_W - 4, ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(self)
            if self.entry and self.entry.id then
                profView.selected = self.entry.id
                RefreshProfessions()
            end
        end)

        Column(row, "GameFontHighlightSmall")
        Place(row, y)
        f.rows[i] = row
    end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #profList - PROF_ROWS)
        profView.offset = math.max(0, math.min(maxOffset, profView.offset - delta * 3))
        RefreshProfessions()
    end)

    -- The picked recipe, like the right side of the profession window.
    local d = CreateFrame("Frame", nil, f)
    d:SetPoint("TOPLEFT", LIST_W + 14, -60)
    d:SetSize(DETAIL_W, 420)
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(36, 36)
    d.icon:SetPoint("TOPLEFT", 0, 0)
    d.name = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 8, -1)
    d.name:SetWidth(DETAIL_W - 46)
    d.name:SetJustifyH("LEFT")
    d.sub = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -3)
    d.sub:SetWidth(DETAIL_W - 46)
    d.sub:SetJustifyH("LEFT")
    d.reagentHead = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.reagentHead:SetPoint("TOPLEFT", 0, -50)
    d.reagentHead:SetText("Reagents")
    d.reagents = {}
    for i = 1, 8 do
        local line = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", 4, -68 - (i - 1) * 30)
        line:SetWidth(DETAIL_W - 70)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        line.count = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.count:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, -68 - (i - 1) * 30)
        line.alts = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        line.alts:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 18, -2)
        line.alts:SetWidth(DETAIL_W - 22)
        line.alts:SetJustifyH("LEFT")
        line.alts:SetWordWrap(false)
        d.reagents[i] = line
    end
    d.money = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.money:SetJustifyH("LEFT")
    d.money:SetWidth(DETAIL_W)
    d.money:SetSpacing(3)
    f.detail = d

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", 12, 14)
    f.hint:SetWidth(PROF_WIDTH - 250)

    f.route = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.route:SetSize(110, 20)
    f.route:SetPoint("BOTTOMRIGHT", -126, 10)
    f.route:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.route:SetScript("OnClick", function(_, button)
        local _, prof = CurrentProfession()
        if not prof then return end
        local target = profView.target or RouteTarget(prof.skill or 1)
        if button == "RightButton" then
            -- Next target above your skill, round again after 300.
            local nextTarget
            for _, t in ipairs(ROUTE_TARGETS) do
                if t > target and t > (prof.skill or 1) then nextTarget = t break end
            end
            profView.target = nextTarget or RouteTarget(prof.skill or 1)
            RefreshProfessions()
        else
            ShowRoute(prof, profView.prof, target, profView.char)
        end
    end)
    f.route:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Levelling route")
        GameTooltip:AddLine("Every step and all the materials from your skill up to the target, with Buy buttons at the auction house.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-click: change the target", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    f.route:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.hint:SetJustifyH("LEFT")

    f.forget = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.forget:SetSize(110, 20)
    f.forget:SetPoint("BOTTOMRIGHT", -10, 10)
    f.forget:SetText("Forget this")
    -- Shift-click only, so a slip next to Route does not wipe anything.
    f.forget:SetScript("OnClick", function()
        if IsShiftKeyDown and IsShiftKeyDown() and StaticPopup_Show then
            StaticPopup_Show("WINDFALL_FORGET_PROFESSION")
        end
    end)
    f.forget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Forget this profession")
        GameTooltip:AddLine("Shift-click to remove this character's saved profession from Windfall. Opening the profession window again brings it back.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.forget:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Shown when this character has nothing saved yet.
    f.load = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.load:SetSize(160, 24)
    f.load:SetPoint("CENTER", 0, 0)
    f.load:SetText("Load my professions")
    f.load:SetScript("OnClick", function() LoadProfessions() end)
    -- Above the recipe rows, which cover the middle of the window.
    f.load:SetFrameLevel((f:GetFrameLevel() or 1) + 10)
    -- The window's header picks the character and profession now.
    for _, old in ipairs({ f.charButton, f.profButton, f.modeButton, f.skill, f.route, f.forget }) do old:Hide() end
    return f
end

if StaticPopupDialogs then
    StaticPopupDialogs["WINDFALL_FORGET_PROFESSION"] = {
        text = "Forget this character's saved profession in Windfall?",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function()
            local char = db.chars and db.chars[profView.char]
            if char then
                char.professions[profView.prof or ""] = nil
                if not next(char.professions) then db.chars[profView.char] = nil end
            end
            profView.prof, profView.offset = nil, 0
            RefreshProfessions()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

function RefreshProfessions()
    if not (profFrame and profFrame:IsShown()) then return end
    local f = profFrame
    local char, prof = CurrentProfession()
    f.modeButton:SetText(profView.mode == "profit" and "Best profit" or "Levelling plan")
    f.head.profit:SetText(profView.mode == "profit" and "Profit" or "Per point")
    if not prof then
        profList = {}
        f.charButton:SetText("No characters")
        f.profButton:SetText("-")
        f.skill:SetText("")
        for _, row in ipairs(f.rows) do
            row.entry = nil
            row:EnableMouse(false)
            row.name:SetText("") row.cost:SetText("") row.value:SetText("") row.profit:SetText("")
        end
        local pending = UnsavedProfessions()[1]
        f.hint:SetText(pending and "Click Load, or open a profession window on any character, and it is saved here."
            or "This character has no crafting profession. Open a profession window on another character and it is saved here.")
        f.load:ClearAllPoints()
        f.load:SetPoint("CENTER", 0, 0)
        f.load:SetSize(180, 24)
        f.load:SetText(pending and ("Load " .. pending.name) or "")
        f.load:SetShown(pending ~= nil)
        f.forget:Hide()
        f.route:Hide()
        return
    end
    -- A profession of this character still to load: a small Load button.
    local pending = UnsavedProfessions()[1]
    f.load:ClearAllPoints()
    f.load:SetPoint("BOTTOMRIGHT", -10, 10)
    f.load:SetSize(150, 20)
    f.load:SetText(pending and ("Load " .. pending.name) or "")
    f.load:SetShown(pending ~= nil)
    f.hint:SetWidth(PROF_WIDTH - (pending and 180 or 30))
    if profView.target and profView.target <= (prof.skill or 1) then profView.target = nil end
    f.route:SetText("Route to " .. (profView.target or RouteTarget(prof.skill or 1)))
    f.route:Hide()
    f.charButton:SetText(ClassColored(char, profView.char))
    f.profButton:SetText(profView.prof)
    f.skill:SetText(string.format("Skill %d / %d", prof.skill or 0, prof.max or 0))

    SyncLearned(prof, profView.char)
    profView.mode = "profit" -- the levelling plan lives on the Levelling tab now
    profList = BuildProfList(prof, char)
    if RefreshHeader then RefreshHeader() end
    profView.offset = math.max(0, math.min(profView.offset, #profList - PROF_ROWS))
    for i, row in ipairs(f.rows) do
        local e = profList[i + profView.offset]
        row.entry = e
        -- Only rows with a recipe take the mouse.
        row:EnableMouse(e ~= nil and e.recipe ~= nil)
        row.name:SetText("") row.cost:SetText("") row.value:SetText("") row.profit:SetText("")
        if not e then
            -- empty row
        elseif e.kind == "header" then
            row.name:SetText("|cffffd100" .. e.text .. "|r")
        elseif e.kind == "note" then
            row.name:SetText("|cff888888" .. e.text .. "|r")
        elseif e.kind == "rank" then
            local entry = e.entry
            local text = string.format("Train %s at skill %d for %s", entry.rank, entry[2], Money(entry[3]))
            if entry[5] ~= "trainer" then
                text = string.format("%s comes from a %s at skill %d", entry.rank, entry[5] or "?", entry[2])
            end
            if e.needLevel then text = text .. string.format(" (needs level %d)", e.needLevel) end
            row.name:SetText((e.ready and "|cff7fd36b" or "|cffffffff") .. text .. "|r")
        elseif e.kind == "unlock" then
            row.name:SetText(string.format("|cff888888%d|r  %s", e.entry[2], e.recipe.name or "?"))
            row.cost:SetText("|cff888888train|r " .. Money(e.entry[3]))
        else
            local train = ((e.train or 0) > 0 and " |cff888888(train)|r" or "")
                .. ((e.chance and e.chance < 1) and string.format(" |cff888888%d%%|r", math.floor(e.chance * 100 + 0.5)) or "")
            local can = CanMake(profView.char, e.recipe)
            row.name:SetText((DIFFICULTY_COLOR[e.recipe.diff] or "|cffffffff") .. (e.recipe.name or "?") .. "|r"
                .. (can > 0 and string.format(" |cffffffff(%d)|r", can) or "") .. train)
            if e.missing and e.cost == 0 then
                row.cost:SetText("|cff888888?|r")
            else
                row.cost:SetText(Money(e.cost) .. (e.missing and "|cffff6060*|r" or ""))
            end
            row.value:SetText(e.value and Money(e.value) or (e.recipe.item and "|cff888888-|r" or "|cff888888no item|r"))
            if profView.mode == "profit" then
                row.profit:SetText(e.profit and SignedMoney(e.profit) or "|cff888888?|r")
            elseif not e.perPoint then
                row.profit:SetText("|cff888888?|r")
            elseif e.perPoint <= 0 then
                row.profit:SetText("|cff7fd36bearns " .. Money(-e.perPoint) .. "|r")
            else
                row.profit:SetText(Money(e.perPoint))
            end
        end
    end

    ShowRecipeDetail(f, prof)

    local age = math.floor((time() - (prof.saved or time())) / 86400)
    local hint = (age >= 1 and string.format("Saved %d day%s ago. ", age, age == 1 and "" or "s") or "")

        .. "* = a reagent has no price."
        .. (#profList > PROF_ROWS and " Scroll for more." or "")
    if prof.unloaded then
        hint = "Not loaded yet: open " .. (profView.prof or "this profession") .. " once (or click Load) so Windfall can read its recipes."
    end
    f.hint:SetText(hint)
end

function ToggleProfessions()
    NoteCharacter()
    if not profFrame then profFrame = BuildProfessionsFrame() end
    profFrame:SetShown(not profFrame:IsShown())
    if profFrame:IsShown() then
        profView.char, profView.prof = nil, nil
        -- Open on the profession window you have open, if any.
        local base = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
        if base and base.professionName then
            profView.char, profView.prof = CharacterKey(), base.professionName
        end
        profView.offset = 0
    end
    RefreshProfessions()
end

PageOpeners.professions = function()
    if not (profFrame and profFrame:IsShown()) then ToggleProfessions() end
end

-- The window's header: which character, which profession, and its skill.
local PROFESSION_ICONS = {
    [165] = "Interface\\Icons\\Trade_LeatherWorking", [197] = "Interface\\Icons\\Trade_Tailoring",
    [171] = "Interface\\Icons\\Trade_Alchemy", [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [333] = "Interface\\Icons\\Trade_Engraving", [202] = "Interface\\Icons\\Trade_Engineering",
    [185] = "Interface\\Icons\\INV_Misc_Food_15", [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
}
local MAX_PROF_ICONS = 6
local header, headerPanel, charMenu

local function ProfessionIcon(prof)
    return PROFESSION_ICONS[prof and prof.line] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function CurrentSelection()
    local char, prof = CurrentProfession()
    return char, prof, profView
end

function CharacterKeyNow()
    return CharacterKey()
end

-- Picks a character and profession and shows it on the open page.
local function Choose(charKey, profName)
    profView.char, profView.prof, profView.offset, profView.target = charKey, profName, 0, nil
    profView.chosen = true -- picked by hand: stay on it
    CurrentProfession()
    if headerPanel and headerPanel:IsShown() then
        if WindfallShoppingFrame and WindfallShoppingFrame:IsShown() then
            PageOpeners.route()
        else
            RefreshProfessions()
            RefreshHeader()
        end
    end
end

local function ProfessionSummary(char)
    local parts = {}
    for _, name in ipairs(SortedKeys(char.professions)) do
        parts[#parts + 1] = string.format("%s %d", name, char.professions[name].skill or 0)
    end
    return table.concat(parts, ", ")
end

local function ToggleCharMenu(anchor)
    if charMenu and charMenu:IsShown() then charMenu:Hide() return end
    if not charMenu then
        charMenu = CreateFrame("Frame", "WindfallCharMenu", anchor, "BackdropTemplate")
        charMenu:SetFrameStrata("DIALOG")
        charMenu:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        charMenu:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
        charMenu.rows = {}
        if UISpecialFrames then table.insert(UISpecialFrames, "WindfallCharMenu") end
    end
    charMenu:ClearAllPoints()
    charMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    -- This character first, then the others.
    local keys = SortedKeys(db.chars)
    table.sort(keys, function(x, y)
        if (x == CharacterKey()) ~= (y == CharacterKey()) then return x == CharacterKey() end
        return x < y
    end)
    for i, key in ipairs(keys) do
        local row = charMenu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, charMenu)
            row:SetSize(330, 18)
            row:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 18)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 4, 0)
            row.text:SetWidth(322)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row:SetScript("OnClick", function(self)
                if IsShiftKeyDown and IsShiftKeyDown() then
                    if StaticPopup_Show then StaticPopup_Show("WINDFALL_FORGET_CHARACTER", DisplayName(self.key), nil, self.key) end
                    return
                end
                charMenu:Hide()
                local char = db.chars[self.key]
                local current = (self.key == profView.char) and profView.prof
                Choose(self.key, (char and char.professions[current or ""]) and current or SortedKeys(char and char.professions)[1])
            end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(DisplayName(self.key))
                GameTooltip:AddLine("Shift-click: forget this character in Windfall.", 0.6, 0.6, 0.6, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            charMenu.rows[i] = row
        end
        local char = db.chars[key]
        row.key = key
        row.text:SetText(ClassColored(char, key) .. "   |cff999999" .. ProfessionSummary(char) .. "|r")
        row:Show()
    end
    for i = #keys + 1, #charMenu.rows do charMenu.rows[i]:Hide() end
    charMenu:SetSize(346, 16 + math.max(1, #keys) * 18)
    charMenu:Show()
end

if StaticPopupDialogs then
    StaticPopupDialogs["WINDFALL_FORGET_CHARACTER"] = {
        text = "Forget %s in Windfall? Opening their profession windows brings them back.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(_, key)
            if db.chars then db.chars[key] = nil end
            if charMenu then charMenu:Hide() end
            if profView.char == key then profView.char, profView.prof = nil, nil end
            Choose(profView.char, profView.prof)
            RefreshHeader()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

local function BuildHeader()
    header, headerPanel = PanelHeader()
    -- Character picker.
    header.char = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    header.char:SetSize(200, 22)
    header.char:SetPoint("LEFT", 0, 0)
    header.char:SetScript("OnClick", function(self) ToggleCharMenu(self) end)
    header.char:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Character")
        GameTooltip:AddLine("Pick any of your characters to see their professions.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    header.char:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Profession icons for that character.
    header.icons = {}
    for i = 1, MAX_PROF_ICONS do
        local b = CreateFrame("Button", nil, header)
        b:SetSize(28, 28)
        b:SetPoint("LEFT", header.char, "RIGHT", 8 + (i - 1) * 32, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.ring = b:CreateTexture(nil, "OVERLAY")
        b.ring:SetPoint("TOPLEFT", -6, 6)
        b.ring:SetPoint("BOTTOMRIGHT", 6, -6)
        b.ring:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b.ring:SetBlendMode("ADD")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function(self) Choose(profView.char, self.name) end)
        b:SetScript("OnEnter", function(self)
            local char = db.chars and db.chars[profView.char]
            local prof = char and char.professions[self.name]
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(self.name)
            if prof then GameTooltip:AddLine(string.format("Skill %d / %d", prof.skill or 0, prof.max or 0), 1, 1, 1) end
            if prof and prof.unloaded then
                GameTooltip:AddLine("Not loaded yet: open this profession once (or click Load) so Windfall can read its recipes.", 1, 0.6, 0.3, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        header.icons[i] = b
    end
    -- Skill bar.
    header.bar = CreateFrame("StatusBar", nil, header)
    header.bar:SetSize(190, 16)
    header.bar:SetPoint("RIGHT", -2, 0)
    header.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    header.bar:SetStatusBarColor(0.1, 0.5, 0.15)
    header.bar.bg = header.bar:CreateTexture(nil, "BACKGROUND")
    header.bar.bg:SetAllPoints()
    header.bar.bg:SetColorTexture(0, 0, 0, 0.6)
    header.bar.text = header.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.bar.text:SetPoint("CENTER")
    -- On the farming and settings tabs: a line of text instead.
    header.info = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header.info:SetPoint("LEFT", 0, 0)
end

function RefreshHeader(key)
    if not header then BuildHeader() end
    key = key or header.key
    header.key = key
    local profPage = key == "route" or key == "professions"
    header.char:SetShown(profPage)
    header.bar:SetShown(profPage)
    header.info:SetShown(not profPage)
    for _, b in ipairs(header.icons) do b:Hide() end
    if not profPage then
        if key == "settings" then
            header.info:SetText("Settings")
            SetPanelPortrait("Interface\\Icons\\INV_Misc_Gear_01")
        else
            header.info:SetText((frame and frame.rate:GetText() or "") .. "   " .. (frame and frame.total:GetText() or ""))
            SetPanelPortrait("Interface\\AddOns\\Windfall\\Media\\icon")
        end
        return
    end
    local char, prof = CurrentProfession()
    if not char then
        header.char:SetText("No characters")
        header.bar:Hide()
        SetPanelPortrait("Interface\\AddOns\\Windfall\\Media\\icon")
        return
    end
    header.char:SetText(ClassColored(char, profView.char))
    for i, name in ipairs(SortedKeys(char.professions)) do
        local b = header.icons[i]
        if b then
            b.name = name
            b.icon:SetTexture(ProfessionIcon(char.professions[name]))
            b.icon:SetDesaturated(char.professions[name].unloaded and true or false)
            b.ring:SetShown(name == profView.prof)
            b:Show()
        end
    end
    if prof then
        header.bar:SetMinMaxValues(0, math.max(prof.max or 1, 1))
        header.bar:SetValue(prof.skill or 0)
        header.bar.text:SetText(string.format("%s %d / %d", profView.prof, prof.skill or 0, prof.max or 0))
        SetPanelPortrait(ProfessionIcon(prof))
    end
end

SetPanelHeaderRefresh(function(key) RefreshHeader(key) end)
end

-- Route and shopping list, in a block of their own (the 200-locals limit).
do
-- Levelling route: the plan played forward from your skill to a target, one
-- skill point at a time, always taking the cheapest recipe per point. Recipe
-- colours along the way are guessed from each recipe's unlock skill, so the
-- craft counts are an estimate; the plan itself recalculates as you level.
local RANK_AT = { { 50, "Journeyman", 150 }, { 125, "Expert", 225 }, { 200, "Artisan", 300 } }
ROUTE_TARGETS = { 75, 150, 225, 300 }

function RouteTarget(skill)
    for _, t in ipairs(ROUTE_TARGETS) do
        if t > skill then return t end
    end
    return 300
end

local function BuildRoute(prof, target, charLevel)
    local skill = prof.skill or 1
    local trainer = prof.line and ns.TrainerRecipes[prof.line] or {}
    -- Level each rank needs, and where it comes from, from the trainer data.
    local rankNeeds = {}
    for _, entry in ipairs(trainer) do
        if entry.rank then rankNeeds[entry.rank] = { level = entry[4] or 0, how = entry[5], skill = entry[2] } end
    end
    -- Recipes with the game's own yellow and grey levels use those. For the
    -- rest, the colour the game shows now places them for the guess.
    local guessBack = { optimal = 0, medium = 10, easy = 25, trivial = 40 }

    local pool = {}
    for id, recipe in pairs(prof.recipes) do
        local exact = ns.SkillUps and ns.SkillUps[id]
        pool[#pool + 1] = { id = id, recipe = recipe, train = 0,
            unlock = exact and 0 or (skill - (guessBack[recipe.diff] or 40)) }
    end
    for _, entry in ipairs(trainer) do
        if not entry.rank and not prof.recipes[entry[1]] and entry[2] < target then
            pool[#pool + 1] = { id = entry[1], recipe = TrainerRecipe(entry), train = entry[3], unlock = entry[2] }
        end
    end
    for _, p in ipairs(pool) do
        local cost, value, _, missing = CraftNumbers(p.recipe)
        p.cost, p.value = cost, value or 0
        p.usable = not missing and not p.recipe.noReagents and p.recipe.reagents[1] ~= nil
    end

    local steps, crafts, trained, gaps = {}, {}, {}, {}
    local spread = {} -- per recipe: how much the number of crafts can vary with luck
    local current
    local cap = prof.max or 0
    local blocked
    for level = skill, target - 1 do
        -- The next rank, from the skill it can be trained at; ranks already
        -- trained (your cap is already that high) are skipped. A rank your
        -- character is too low for waits: level on up to the cap first.
        for _, r in ipairs(RANK_AT) do
            -- Where the rank opens and how you get it come from the data (Cooking
            -- and First Aid get Expert from a book and Artisan from a quest).
            local needs = rankNeeds[r[2]] or { level = 0 }
            if level >= (needs.skill or r[1]) and r[3] > cap and r[3] <= cap + 75 then
                local tooLow = (charLevel or 0) < needs.level
                if not tooLow then
                    steps[#steps + 1] = { rank = r[2], at = level, how = needs.how }
                    current = nil
                    cap = r[3]
                elseif level >= cap then
                    blocked = { rank = r[2], at = level, needLevel = needs.level, how = needs.how }
                end
            end
        end
        if blocked then
            steps[#steps + 1] = blocked
            break
        end
        -- The cheapest point among recipes with a good chance; a poor chance
        -- only when nothing better is left at this skill.
        local best, bestScore, bestChance, bestSure
        for _, p in ipairs(pool) do
            if p.usable and p.unlock <= level then
                local chance = SkillUpChance(p.id, p.unlock, level)
                if chance > 0 then
                    local score = PointCost(p.cost, p.value, chance) + (trained[p.id] and 0 or p.train / TRAIN_SPREAD)
                    local sure = chance >= MIN_CHANCE
                    if not best or (sure and not bestSure) or (sure == bestSure and score < bestScore) then
                        best, bestScore, bestChance, bestSure = p, score, chance, sure
                    end
                end
            end
        end
        if not best then
            gaps[#gaps + 1] = level
            current = nil
        else
            trained[best.id] = true
            crafts[best.id] = (crafts[best.id] or 0) + 1 / bestChance
            -- Tries for one point vary (a geometric spread): (1 - chance) / chance^2.
            spread[best.id] = (spread[best.id] or 0) + (1 - bestChance) / (bestChance * bestChance)
            if current and current.p == best then
                current.to = level + 1
                current.crafts = current.crafts + 1 / bestChance
            else
                current = { p = best, from = level, to = level + 1, crafts = 1 / bestChance }
                steps[#steps + 1] = current
            end
        end
    end

    -- Materials for every craft, rounded up per recipe, plus a spare for bad
    -- luck on yellow and green crafts: one standard deviation, enough about
    -- five times out of six. Orange crafts never miss and get none.
    local need, order, trainCost = {}, {}, 0
    for _, p in ipairs(pool) do
        local n = crafts[p.id]
        if n then
            n = math.ceil(n + math.sqrt(spread[p.id] or 0) - 0.001)
            if p.train > 0 then trainCost = trainCost + p.train end
            for _, r in ipairs(p.recipe.reagents) do
                if not need[r[1]] then order[#order + 1] = r[1] end
                need[r[1]] = (need[r[1]] or 0) + r[2] * n
            end
        end
    end
    local items = {}
    for _, id in ipairs(order) do items[#items + 1] = { id = id, need = need[id] } end
    return steps, items, trainCost, gaps
end

-- Shopping list window: what to buy, less what is in your bags. Next to the
-- auction house it gets a Buy button per item.
local shopFrame
local shop = { title = "", lines = {}, items = {}, crafts = 5 }
local SHOP_STEP_ROWS = 8
local SHOP_ROWS = 10
local SHOP_WIDTH = 520
local ahOpen = false
local merchantOpen, merchantItems = false, {} -- the vendor window, and what it sells
local ScanMerchant, ToBuy
local RefreshShoppingList, DockToAuctionHouse, RankAction

local function BagCountOf(itemID)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return count and count(itemID) or 0
end

local function ItemName(itemID)
    return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ("item " .. itemID)
end

-- ------------------------------------------------------- auction house ------

-- The Show button opens an item's buy page in the game's own auction house
-- window, with the amount you still need filled in. You press Buy Now there
-- yourself; Windfall never buys anything.
local AH = C_AuctionHouse
local showing                   -- the item last shown: { id, qty }

local function Status(text)
    if shopFrame then shopFrame.status:SetText(text or "") end
end

local function StopBuying(text)
    showing = nil
    Status(text)
end

-- Fills in the amount on the buy page. The game resets it once the listings
-- arrive, so this runs again then.
local function SetBuyQuantity()
    local ahFrame = _G.AuctionHouseFrame
    local display = ahFrame and ahFrame.CommoditiesBuyFrame and ahFrame.CommoditiesBuyFrame.BuyDisplay
    if not (showing and display and display:IsShown()) then return end
    local qty = showing.qty
    if display.SetQuantitySelected and pcall(display.SetQuantitySelected, display, qty) then return end
    local input = display.QuantityInput
    if input and input.SetQuantity and pcall(input.SetQuantity, input, qty) then return end
    local box = input and input.InputBox
    if box and box.SetNumber then
        box:SetNumber(qty)
        local onChanged = box:GetScript("OnTextChanged")
        if onChanged then pcall(onChanged, box, true) end
    end
end

-- Is the auction house on some item's buy page right now?
local function OnBuyPage()
    local ahFrame = _G.AuctionHouseFrame
    for _, key in ipairs({ "CommoditiesBuyFrame", "ItemBuyFrame" }) do
        local page = ahFrame and ahFrame[key]
        if type(page) == "table" and page.IsShown and page:IsShown() then return true end
    end
    return false
end

-- Back to the Buy tab's list, as clicking the tab does. Asking for a new item
-- straight from another item's page can leave the auction house searching.
local function BackToBuyTab()
    local tab = _G.AuctionHouseFrameBuyTab
    if tab and tab.Click then pcall(tab.Click, tab) end
end

-- The auction house takes one request at a time; asking while it is busy
-- leaves it searching.
local function AuctionHouseReady()
    return not (AH and AH.IsThrottledMessageSystemReady) or AH.IsThrottledMessageSystemReady()
end

local function OpenBuyPage()
    local ahFrame = _G.AuctionHouseFrame
    if not (showing and ahFrame and ahFrame.SelectBrowseResult and AH and AH.MakeItemKey) then return false end
    local itemKey = AH.MakeItemKey(showing.id)
    -- The game needs to know the item first; if not, it says so with an event.
    if AH.GetItemKeyInfo and not AH.GetItemKeyInfo(itemKey) then return false end
    if not AuctionHouseReady() then
        showing.waiting = true -- opened when the auction house says it is ready
        return false
    end
    showing.waiting = false
    local ok = pcall(ahFrame.SelectBrowseResult, ahFrame, { itemKey = itemKey, minPrice = 0, totalQuantity = 0 })
    if not ok then return false end
    showing.opened, showing.listed = GetTime(), false
    C_Timer.After(0.3, SetBuyQuantity)
    -- Still no listings after a few seconds: start over once, as changing tab does.
    local mine = showing
    C_Timer.After(4, function()
        if showing == mine and not mine.listed and not mine.retried and ahOpen then
            mine.retried = true
            BackToBuyTab()
            C_Timer.After(0.5, function()
                if showing == mine and OpenBuyPage() then
                    Status(string.format("Showing %s: buy %d in the auction house.", ItemName(mine.id), mine.qty))
                end
            end)
        end
    end)
    return true
end

local function ShowInAuctionHouse(itemID, qty)
    if not ahOpen then return end
    showing = { id = itemID, qty = qty }
    local function Open()
        if OpenBuyPage() then
            Status(string.format("Showing %s: buy %d in the auction house.", ItemName(itemID), qty))
        elseif showing and showing.waiting then
            Status("Waiting for the auction house to be ready for " .. ItemName(itemID) .. "...")
        else
            Status("Looking up " .. ItemName(itemID) .. "...")
        end
    end
    -- From another item's page, back to the list first.
    if OnBuyPage() then
        BackToBuyTab()
        C_Timer.After(0.3, Open)
    else
        Open()
    end
end

local function OnAuctionEvent(event, ...)
    if event == "AUCTION_HOUSE_SHOW" then
        ahOpen = true
        -- Next to the auction house, but only with something left to buy.
        local anything
        for _, item in ipairs(shop.items) do
            if item.need * (shop.single and shop.crafts or 1) > BagCountOf(item.id) then anything = true end
        end
        if anything and shopFrame then
            local already = shopFrame:IsShown()
            shopFrame:Show()
            -- The auction house frame is shown just after this event.
            C_Timer.After(0, function() DockToAuctionHouse(not already) end)
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen = false
        StopBuying()
        UndockPanel()
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        merchantOpen = true
        ScanMerchant()
        -- Next to the vendor, when it sells something still to buy.
        local wanted
        for _, item in ipairs(shop.items) do
            if merchantItems[item.id] and ToBuy(item) > 0 then wanted = true end
        end
        if event == "MERCHANT_SHOW" and wanted and shopFrame then
            local already = shopFrame:IsShown()
            shopFrame:Show()
            if _G.MerchantFrame then DockPanel(_G.MerchantFrame, not already) end
        end
    elseif event == "NEW_RECIPE_LEARNED" or event == "LEARNED_SPELL_IN_TAB" or event == "TRAINER_UPDATE"
        or event == "SKILL_LINES_CHANGED" then
        -- Learned a recipe or a rank at the trainer: look again in a moment,
        -- once the game has it.
        C_Timer.After(0.3, function()
            if RebuildRoute then RebuildRoute() end
            if RefreshProfessions then RefreshProfessions() end
        end)
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        merchantItems = {}
        UndockPanel()
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
        local itemID = ...
        if showing and itemID == showing.id and OpenBuyPage() then
            Status(string.format("Showing %s: buy %d in the auction house.", ItemName(itemID), showing.qty))
        end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local itemID = ...
        if showing and itemID == showing.id then
            showing.listed = true
            C_Timer.After(0, SetBuyQuantity)
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemKey = ...
        if showing and itemKey and itemKey.itemID == showing.id then showing.listed = true end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        -- Waiting to open an item: the auction house is free now.
        if showing and showing.waiting and OpenBuyPage() then
            Status(string.format("Showing %s: buy %d in the auction house.", ItemName(showing.id), showing.qty))
        end
    end
    if RefreshShoppingList then RefreshShoppingList() end
end

-- -------------------------------------------------------------- vendor ------

-- At a vendor, what it sells from the list can be bought straight away.

function ScanMerchant()
    merchantItems = {}
    if not (merchantOpen and GetMerchantNumItems and GetMerchantItemID) then return end
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(i)
        if id then merchantItems[id] = i end
    end
end

local function MerchantPrice(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then return info.price, info.stackCount or 1 end
    elseif GetMerchantItemInfo then
        local _, _, price, stackCount = GetMerchantItemInfo(index)
        return price, stackCount or 1
    end
end

-- Buys qty of an item from the open vendor, in as few purchases as it allows.
local function BuyFromVendor(itemID, qty)
    local index = merchantItems[itemID]
    if not (merchantOpen and index and qty > 0) then return 0 end
    local price, stackCount = MerchantPrice(index)
    stackCount = math.max(1, stackCount or 1)
    local cost = price and math.ceil(qty / stackCount) * price or 0
    if GetMoney and cost > GetMoney() then
        Status("|cffff6060Not enough money for " .. qty .. " " .. ItemName(itemID) .. " (" .. Money(cost) .. ").|r")
        return 0
    end
    local maxStack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(index)) or qty
    local left = qty
    while left > 0 do
        local n = math.min(left, math.max(1, maxStack))
        BuyMerchantItem(index, n)
        left = left - n
    end
    return cost
end

-- What the route's character holds (bags and bank; saved for other characters).
local function HereCount(itemID)
    if shop.route and HaveCount then return (HaveCount(shop.route.char, itemID)) end
    return BagCountOf(itemID)
end

function ToBuy(item)
    local need = item.need * (shop.single and shop.crafts or 1)
    return math.max(0, need - HereCount(item.id))
end

local function BuyAllHere()
    local spent, count = 0, 0
    for _, item in ipairs(shop.items) do
        local buy = ToBuy(item)
        if buy > 0 and merchantItems[item.id] then
            local cost = BuyFromVendor(item.id, buy)
            if cost > 0 then spent, count = spent + cost, count + 1 end
        end
    end
    if count > 0 then Status("Bought everything on the list this vendor sells, for " .. Money(spent) .. ".") end
end

-- ------------------------------------------------------------ crafting ------

-- The route's current step, crafted from this window. Opening the profession
-- and crafting both happen on your click, as the game requires.
local function RouteProfession()
    local r = shop.route
    local char = r and db.chars and db.chars[r.char]
    return char and char.professions[r.name], r
end

local function CraftableCount(recipe)
    local n
    for _, rg in ipairs(recipe.reagents) do
        local can = math.floor(BagCountOf(rg[1]) / rg[2])
        n = n and math.min(n, can) or can
    end
    return n or 0
end

local function ProfessionIsOpen(line)
    local T = C_TradeSkillUI
    if not (T and T.IsTradeSkillReady and T.IsTradeSkillReady()) then return false end
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    return base and SkillLineOf(base) == line
end

local function CraftNow()
    local now = shop.now
    local prof = RouteProfession()
    local T = C_TradeSkillUI
    -- Not read yet: this click opens the profession window, which saves it.
    if now and now.load and prof then
        if T and T.OpenTradeSkill then T.OpenTradeSkill(prof.line) end
        Status("Opened " .. shop.route.name .. ". Its route appears in a moment.")
        return
    end
    if not (now and now.p and prof) then return end
    if not ProfessionIsOpen(prof.line) then
        if T and T.OpenTradeSkill then T.OpenTradeSkill(prof.line) end
        Status("Opened " .. shop.route.name .. ". Click Craft again.")
        return
    end
    local count = math.min(now.crafts, CraftableCount(now.p.recipe))
    if count < 1 then return end
    T.CraftRecipe(now.p.id, count)
    Status(string.format("Crafting %d %s...", count, now.p.recipe.name or "?"))
end

-- ------------------------------------------------------------ window ------

function RefreshShoppingList()
    if not (shopFrame and shopFrame:IsShown()) then return end
    local f = shopFrame
    f.title2:SetText(shop.title)
    f.target:SetShown(not shop.single and shop.route ~= nil)
    if shop.route then f.target:SetText("Plan to " .. shop.route.target) end
    f.crafts:SetShown(shop.single)
    f.minus:SetShown(shop.single)
    f.plus:SetShown(shop.single)
    if shop.single then f.crafts:SetText(shop.crafts .. " crafts") end

    -- The step to do now (routes only).
    local now, prof = shop.now, RouteProfession()
    local nowShown = not shop.single and now ~= nil
    f.now:SetShown(nowShown)
    f.craft:Hide()
    if nowShown and now.load then
        if now.mine then
            f.now:SetText("|cffffd100Now:|r open " .. (shop.route and shop.route.name or "the profession")
                .. " once, so Windfall can read its recipes and plan your route.")
            f.craft:SetText("Load " .. (shop.route and shop.route.name or ""))
            f.craft:SetEnabled(true)
            f.craft:Show()
        else
            f.now:SetText("|cffffd100Now:|r log in on this character and open " .. (shop.route and shop.route.name or "the profession")
                .. " once, so Windfall can read its recipes.")
        end
    elseif nowShown and now.rank and now.needLevel then
        f.now:SetText(string.format("|cffff6060Capped at %d.|r %s needs level %d, so the route goes on from there.",
            now.at, now.rank, now.needLevel))
    elseif nowShown and now.rank then
        f.now:SetText(string.format("|cffffd100Now:|r %s (skill %d).", RankAction(now.rank, now.how), now.at))
    elseif nowShown and now.p then
        local recipe = now.p.recipe
        local known = prof and prof.recipes[now.p.id]
        local name = (DIFFICULTY_COLOR[known and known.diff or recipe.diff] or "") .. (recipe.name or "?") .. "|r"
        if not known then
            f.now:SetText(string.format("|cffffd100Now:|r learn %s at the trainer (%s), then craft %d.",
                name, Money(now.p.train or 0), now.crafts))
        else
            local can = math.min(now.crafts, CraftableCount(recipe))
            f.now:SetText(string.format("|cffffd100Now:|r %s x%d  |cff888888(skill %d-%d)|r%s", name, now.crafts, now.from, now.to,
                recipe.item and "" or "\n|cff888888After Craft, click the item to enchant.|r"))
            f.craft:SetText(can > 0 and ("Craft " .. can) or "Need materials")
            f.craft:SetEnabled(can > 0)
            f.craft:Show()
        end
    elseif nowShown and now.gap then
        f.now:SetText(string.format("|cffff6060No priced recipe from %d.|r Scan the auction house with Auctionator, then come back to this tab.", now.gap))
    elseif nowShown and now.maxed then
        f.now:SetText("|cff7fd36b" .. (shop.route and shop.route.name or "") .. " is maxed.|r Best earners at today's prices "
            .. "(the Recipes tab has them all):")
    elseif nowShown then
        f.now:SetText("|cff7fd36bDone: you reached " .. (shop.route and shop.route.target or "") .. ".|r")
    end

    local lineTop = nowShown and -84 or -56
    for i, row in ipairs(f.lines) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 14, lineTop - (i - 1) * 14)
        row:SetText(shop.lines[i] or "")
    end
    local top = lineTop - 2 - #shop.lines * 14
    f.matHead:ClearAllPoints()
    f.matHead:SetPoint("TOPLEFT", 12, top - 4)

    local total, missing, anyHere = 0, false, false
    -- Everything counts in the total, also what does not fit in the rows.
    for i = #f.rows + 1, #shop.items do
        local item = shop.items[i]
        local buy = math.max(0, item.need * (shop.single and shop.crafts or 1) - HereCount(item.id))
        local price = ReagentPrice(item.id)
        if buy > 0 then
            if price then total = total + price * buy else missing = true end
        end
    end
    local hidden = math.max(0, #shop.items - #f.rows)
    for i, row in ipairs(f.rows) do
        local item = shop.items[i]
        local y = top - 22 - (i - 1) * 20
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, y)
        if item then
            local need = item.need * (shop.single and shop.crafts or 1)
            local have, others = HereCount(item.id), 0
            if shop.route and HaveCount then _, others = HaveCount(shop.route.char, item.id) end
            local buy = math.max(0, need - have)
            local price, fromVendor = ReagentPrice(item.id)
            row.name:SetText(string.format("|T%s:14|t %s", tostring(ItemIcon(item.id)), ItemName(item.id)))
            row.need:SetText(string.format("%d |cff888888(%d here%s)|r", need, have,
                others > 0 and string.format(", %d on others", others) or ""))
            if buy == 0 then
                row.total:SetText("|cff7fd36bhave all|r")
            elseif price then
                total = total + price * buy
                row.total:SetText(buy .. " for " .. Money(price * buy) .. (fromVendor and " |cff888888vendor|r" or ""))
            else
                missing = true
                row.total:SetText(buy .. " |cffff6060no price|r")
            end
            -- At a vendor that sells it: Buy. At the auction house: Show.
            if merchantOpen and merchantItems[item.id] and buy > 0 then
                row.vendor = true
                row.buy:SetText("Buy " .. buy)
                row.buy:Show()
                anyHere = true
            else
                row.vendor = false
                row.buy:SetShown(ahOpen and buy > 0 and not (fromVendor and price))
                row.buy:SetText((showing and showing.id == item.id) and "|cff7fd36bShown|r" or "Show")
            end
            row.item, row.toBuy = item.id, buy
            row:Show()
        else
            row:Hide()
        end
    end
    f.sum:SetText("Left to buy: " .. Money(total) .. (missing and " |cffff6060+ unpriced|r" or "")
        .. (hidden > 0 and string.format("  |cff999999(and %d more material%s, buy them as the route gets there)|r",
            hidden, hidden == 1 and "" or "s") or ""))
    f.buyAll:SetShown(anyHere)
end

local function BuildShoppingFrame()
    local f = MakeWindow("WindfallShoppingFrame", "Route", SHOP_WIDTH, "route")
    f.title2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title2:SetPoint("TOPLEFT", 12, -34)
    f.title2:SetWidth(SHOP_WIDTH - 150)
    f.title2:SetJustifyH("LEFT")
    f.title2:SetWordWrap(false)

    local function Step(label, delta, x)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(28, 20)
        b:SetPoint("TOPRIGHT", x, -30)
        b:SetText(label)
        b:SetScript("OnClick", function()
            local step = IsShiftKeyDown and IsShiftKeyDown() and 10 or 1
            shop.crafts = math.max(1, shop.crafts + delta * step)
            RefreshShoppingList()
        end)
        return b
    end
    f.plus = Step("+", 1, -12)
    f.crafts = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.crafts:SetPoint("TOPRIGHT", -46, -35)
    f.minus = Step("-", -1, -108)

    -- How far the route goes: the next skill cap, or click for further.
    f.target = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.target:SetSize(110, 20)
    f.target:SetPoint("TOPRIGHT", -12, -30)
    f.target:SetScript("OnClick", function()
        local _, prof, view = CurrentSelection()
        if not prof then return end
        local skill, now = prof.skill or 1, view.target or RouteTarget(prof.skill or 1)
        local nextTarget
        for _, t in ipairs(ROUTE_TARGETS) do
            if t > now and t > skill then nextTarget = t break end
        end
        view.target = nextTarget or RouteTarget(skill)
        PageOpeners.route()
    end)
    f.target:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("How far to plan")
        GameTooltip:AddLine("Click for the next target: 75, 150, 225 or 300.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.target:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.now = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.now:SetPoint("TOPLEFT", 14, -60)
    f.now:SetWidth(SHOP_WIDTH - 160)
    f.now:SetJustifyH("LEFT")
    f.craft = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.craft:SetSize(130, 22)
    f.craft:SetPoint("TOPRIGHT", -12, -54)
    f.craft:SetScript("OnClick", function() CraftNow() end)

    f.lines = {}
    for i = 1, SHOP_STEP_ROWS do
        local line = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetWidth(SHOP_WIDTH - 28)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        f.lines[i] = line
    end
    f.matHead = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.matHead:SetText("Materials")

    f.rows = {}
    for i = 1, SHOP_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(SHOP_WIDTH - 16, 20)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 4, 0)
        row.name:SetWidth(170)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.need = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.need:SetPoint("LEFT", 178, 0)
        row.total = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.total:SetPoint("RIGHT", -74, 0)
        row.buy = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.buy:SetSize(66, 18)
        row.buy:SetPoint("RIGHT", -2, 0)
        row.buy:SetScript("OnClick", function()
            if row.vendor then
                local cost = BuyFromVendor(row.item, row.toBuy)
                if cost > 0 then Status("Bought " .. row.toBuy .. " " .. ItemName(row.item) .. " for " .. Money(cost) .. ".") end
            else
                ShowInAuctionHouse(row.item, row.toBuy)
            end
        end)
        f.rows[i] = row
    end

    f.sum = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.sum:SetPoint("BOTTOMLEFT", 12, 34)
    f.buyAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.buyAll:SetSize(130, 22)
    f.buyAll:SetPoint("BOTTOMRIGHT", -10, 28)
    f.buyAll:SetText("Buy all here")
    f.buyAll:SetScript("OnClick", function() BuyAllHere() end)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 12, 12)
    f.status:SetWidth(SHOP_WIDTH - 24)
    f.status:SetJustifyH("LEFT")

    f:SetScript("OnHide", function() StopBuying() end)
    return f
end

-- Next to the auction house, when it is open.
function DockToAuctionHouse(openedForIt)
    local ahFrame = _G.AuctionHouseFrame
    if shopFrame and ahFrame and ahFrame:IsShown() then DockPanel(ahFrame, openedForIt) end
end

local function OpenShopping()
    shopFrame = shopFrame or BuildShoppingFrame()
    StopBuying()
    -- Opened while already at the auction house: the "opened" event has gone by.
    local ahFrame = _G.AuctionHouseFrame
    ahOpen = ahFrame and ahFrame:IsShown() and true or false
    if ahOpen then DockToAuctionHouse() end
    merchantOpen = _G.MerchantFrame and _G.MerchantFrame:IsShown() and true or false
    ScanMerchant()
    shopFrame:Show()
    RefreshShoppingList()
end

-- The Levelling tab: the route for the character and profession picked in
-- the header, up to the next skill cap (or the target picked on the page).
PageOpeners.route = function()
    local _, prof, view = CurrentSelection()
    if not prof then
        PageOpeners.professions() -- nothing saved yet: the Recipes tab has the Load button
        return
    end
    local target = view.target or RouteTarget(prof.skill or 1)
    if shop.single or not shop.route or shop.route.char ~= view.char or shop.route.name ~= view.prof
        or shop.route.target ~= target then
        ShowRoute(prof, view.prof, target, view.char)
    else
        shopFrame = shopFrame or BuildShoppingFrame()
        shopFrame:Show()
        RefreshShoppingList()
    end
end

-- Listens from the start, so the auction house opening is never missed.
local auctionEvents = CreateFrame("Frame")
auctionEvents:SetScript("OnEvent", function(_, event, ...)
    if event == "BAG_UPDATE_DELAYED" then
        if RefreshShoppingList then RefreshShoppingList() end
    else
        OnAuctionEvent(event, ...)
    end
end)
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "ITEM_KEY_ITEM_INFO_RECEIVED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED",
    "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_TAB", "TRAINER_UPDATE", "SKILL_LINES_CHANGED" }) do
    pcall(auctionEvents.RegisterEvent, auctionEvents, event)
end

-- One recipe, a number of crafts.
function ShowShoppingList(recipe)
    shop.single, shop.lines, shop.route, shop.now = true, {}, nil, nil
    shop.title = (DIFFICULTY_COLOR[recipe.diff] or "|cffffffff") .. (recipe.name or "?") .. "|r"
    shop.items = {}
    for _, r in ipairs(recipe.reagents) do shop.items[#shop.items + 1] = { id = r[1], need = r[2] } end
    OpenShopping()
end

-- What to do for a rank, by where it comes from.
function RankAction(rank, how)
    if how == "vendor" then return "buy the " .. rank .. " book from a vendor" end
    if how == "quest" then return "do the " .. rank .. " quest" end
    return "train " .. rank .. " at a trainer"
end

-- A whole route, up to target. Remembered, so it can move on as you level.
local function FillRoute(keepStatus)
    local prof, r = RouteProfession()
    if not prof then return end
    SyncLearned(prof, r.char)
    if prof.unloaded then
        shop.single = false
        shop.title = string.format("%s %d to %d", r.name, prof.skill or 1, r.target)
        shop.lines, shop.items = {}, {}
        shop.now = { load = true, line = prof.line, mine = r.char == (db.chars and CharacterKeyNow and CharacterKeyNow()) }
        return
    end
    local char = db.chars and db.chars[r.char]
    local steps, items, trainCost, gaps = BuildRoute(prof, r.target, char and char.level)
    shop.single = false
    shop.title = string.format("%s %d to %d", r.name, prof.skill or 1, r.target)
    shop.lines = {}
    shop.now = nil
    for _, st in ipairs(steps) do
        if not shop.now then
            if st.rank then
                shop.now = { rank = st.rank, at = st.at, needLevel = st.needLevel, how = st.how }
            else
                shop.now = { p = st.p, crafts = math.ceil(st.crafts - 0.001), from = st.from, to = st.to }
            end
        end
        if #shop.lines < SHOP_STEP_ROWS - 1 then
            if st.rank and st.needLevel then
                shop.lines[#shop.lines + 1] = string.format("|cffff6060%d: capped until level %d for %s|r",
                    st.at, st.needLevel, st.rank)
            elseif st.rank then
                shop.lines[#shop.lines + 1] = string.format("|cffffd100%d: %s|r", st.at, RankAction(st.rank, st.how))
            else
                shop.lines[#shop.lines + 1] = string.format("%d-%d: %s%s|r x%d%s", st.from, st.to,
                    DIFFICULTY_COLOR[select(2, SkillUpChance(st.p.id, st.p.unlock, st.from)) or ""] or "", st.p.recipe.name or "?",
                    math.ceil(st.crafts - 0.001), (st.p.train > 0 and " |cff888888(train)|r" or "")
                    -- More than two crafts per point on average: nothing better was left here.
                    .. (st.crafts > 2 * (st.to - st.from) and " |cffff6060low chance|r" or ""))
            end
        end
    end
    -- Nothing to do: either the target is reached, or no recipe has prices yet.
    if not shop.now then
        shop.now = (prof.skill or 0) >= r.target and { finished = true, maxed = (prof.skill or 0) >= 300 }
            or { gap = gaps[1] or prof.skill or 1 }
    end
    -- Nothing left to level: the recipes that earn the most instead.
    if shop.now.finished then
        shop.lines, shop.items = {}, {}
        local top = TopProfit and TopProfit(prof, SHOP_STEP_ROWS) or {}
        for _, e in ipairs(top) do
            shop.lines[#shop.lines + 1] = string.format("%s%s|r  |cff7fd36b+%s|r a craft", DIFFICULTY_COLOR[e.recipe.diff] or "",
                e.recipe.name or "?", Money(e.profit))
        end
        if not top[1] then shop.lines[1] = "|cff999999Nothing earns at the current auction prices.|r" end
    end
    if #steps > #shop.lines then shop.lines[#shop.lines + 1] = "|cff888888... and more steps|r" end
    if gaps[1] then
        -- Added below the steps (or in place of the last one when the list is full).
        local at = math.min(#shop.lines + 1, SHOP_STEP_ROWS)
        shop.lines[at] = string.format("|cffff6060No priced recipe from %d. Scan the auction house.|r", gaps[1])
    end
    shop.items = items
    if not keepStatus and trainCost > 0 then
        Status("Trainer recipes on this route: " .. Money(trainCost) .. ". Materials include a spare for unlucky skill-ups.")
    end
end

function ShowRoute(prof, profName, target, charKey)
    shop.route = { char = charKey, name = profName, target = target }
    OpenShopping()
    FillRoute()
    RefreshShoppingList()
end

function RebuildRoute()
    if shop.single or not shop.route or not (shopFrame and shopFrame:IsShown()) then return end
    FillRoute(true)
    RefreshShoppingList()
end
end

local FISH_OPTIONS = {
    equip = { key = "fishEquip", label = "auto-equip fishing pole" },
    doubleclick = { key = "fishDouble", label = "double right-click to cast" },
    autoloot = { key = "fishLoot", label = "auto loot while the fishing key is on" },
    sleep = { key = "fishSleep", label = "sleep after 10 minutes and follow the pole" },
}

SLASH_WINDFALL1 = "/windfall"
SLASH_WINDFALL2 = "/wf"
SlashCmdList["WINDFALL"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local fishKey = msg:match("^fishkey%s*(.*)$")
    if fishKey then
        if fishKey == "" then StartKeyCapture() else SetFishKey(fishKey) end
    elseif msg == "fish" or msg == "fishing" then
        Windfall_ToggleFishing()
    elseif FISH_OPTIONS[msg] then
        local option = FISH_OPTIONS[msg]
        db[option.key] = db[option.key] == false
        if option.key == "fishLoot" then UpdateAutoLoot() end
        print("|cff7fd36bWindfall|r: " .. option.label .. " is " .. (db[option.key] and "on" or "off") .. ".")
        RefreshSettings()
    elseif msg == "options" or msg == "settings" or msg == "config" then
        ToggleSettings()
    elseif msg == "lure" or msg == "lures" then
        db.fishLure = db.fishLure == false
        print("|cff7fd36bWindfall|r: putting lures on with the fishing key is " .. (db.fishLure and "on" or "off") .. ".")
    elseif msg == "fishsound" then
        db.fishSound = db.fishSound == false
        print("|cff7fd36bWindfall|r: bobber sound boost " .. (db.fishSound and "on" or "off") .. ".")
    elseif msg == "start" then
        Start() Refresh()
    elseif msg == "pause" or msg == "stop" then
        Pause() Refresh()
    elseif msg == "reset" then
        Reset()
    elseif msg == "gather" or msg == "loot" or msg == "mode" then
        SetMode(msg)
        print("|cff7fd36bWindfall|r: showing " .. MODE_LABEL[db.mode]:lower() .. ".")
    elseif msg == "history" or msg == "zones" then
        ToggleHistory()
    elseif msg == "discard" then
        Reset(true)
    elseif msg == "prof" or msg == "profs" or msg == "professions" then
        ToggleProfessions()
    elseif msg == "sparkle" or msg == "sparkles" then
        Windfall_ToggleSparkles()
    elseif msg == "minimap" then
        db.minimapHidden = not db.minimapHidden
        if minimapButton then minimapButton:SetShown(not db.minimapHidden) end
        print("|cff7fd36bWindfall|r: minimap button " .. (db.minimapHidden and "hidden" or "shown") .. ".")
    elseif msg == "" or msg == "show" or msg == "hide" or msg == "toggle" then
        Windfall_ToggleWindow()
    else
        print("|cff7fd36bWindfall|r: /wf (show or hide), /wf settings, /wf zones (zone history), /wf gather, /wf loot, /wf start, /wf pause, /wf reset (save and start over), /wf discard, /wf fish (fishing key on or off), /wf fishkey (choose the key), /wf sparkle (node sparkles on or off), /wf prof (professions)")
    end
end

-- --------------------------------------------------------------- events ----

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("CHAT_MSG_MONEY")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
pcall(events.RegisterEvent, events, "BANKFRAME_OPENED")
pcall(events.RegisterEvent, events, "BANKFRAME_CLOSED")
pcall(events.RegisterEvent, events, "PLAYERBANKSLOTS_CHANGED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pcall(events.RegisterEvent, events, "SKILL_LINES_CHANGED") -- may not exist on every client
pcall(events.RegisterEvent, events, "TRADE_SKILL_SHOW")
pcall(events.RegisterEvent, events, "TRADE_SKILL_LIST_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        WindfallDB = WindfallDB or {}
        db = WindfallDB
        db.items = db.items or {}
        db.elapsed = db.elapsed or 0
        db.money = db.money or 0
        db.zones = db.zones or {}
        db.history = db.history or {}
        db.sparkleRange = nil -- the range button of 0.2.14 is gone
        if db.mode ~= "loot" then db.mode = "gather" end
        -- Sessions saved by 0.1.0 only ever held gathered herbs.
        for _, item in pairs(db.items) do
            if item.gathered == nil then item.gathered = item.count end
        end
    elseif event == "PLAYER_LOGIN" then
        frame = BuildFrame()
        bar = BuildBar()
        Refresh()
        CreateMinimapButton()
        InitFishing()
        NoteCharacter()
        SaveInventory()
        if db.sparkle then StartSparkles() end
        UpdateFishIcon()
        C_Timer.NewTicker(1, Tick)
    elseif event == "PLAYER_LOGOUT" then
        Pause()
        ReleaseCVars()
        UpdateAutoLoot(true)
        StopSparkles()
    elseif not db then
        return
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        OnChannelStart(arg3)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        OnChannelStop()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnded()
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYERBANKSLOTS_CHANGED" then
        SaveInventory()
    elseif event == "BANKFRAME_OPENED" then
        SetBankOpen(true)
    elseif event == "BANKFRAME_CLOSED" then
        SetBankOpen(false)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if arg1 == 16 then OnMainHandChanged() end
        if db.fishOn then Refresh() end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
        SaveProfessionSoon()
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "SKILL_LINES_CHANGED" then
        if event == "SKILL_LINES_CHANGED" then
            SkillsChanged()
            NoteCharacter()
        end
        -- Zone, skill and lure all change the getaway line.
        if db.fishOn and frame then Refresh() end
    elseif event == "CHAT_MSG_LOOT" then
        OnLootMessage(arg1)
    elseif event == "CHAT_MSG_MONEY" then
        OnMoneyMessage(arg1)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellSucceeded(arg3)
        OnLureCastSucceeded(arg3)
    elseif event == "UNIT_SPELLCAST_START" then
        OnLureCastStart(arg3)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        OnLureCastEnded()
    elseif event == "LOOT_OPENED" then
        OnLootOpened()
    elseif event == "LOOT_CLOSED" then
        OnLootClosed()
    end
end)
