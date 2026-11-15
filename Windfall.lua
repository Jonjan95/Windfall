-- Windfall: tracks what you loot, values it with Auctionator's scanned prices
-- and shows gold per hour for the current farming session.
--
-- Two views of the same session:
--   gather  only what came from herbalism, mining, skinning and fishing
--   loot    everything you loot, plus looted coins

local ADDON = "Windfall"
local MAX_ROWS = 14
local WIDTH = 290
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
local ToggleProfessions, RefreshProfessions

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
    if math.floor(db.elapsed / 60) ~= shownMinute and frame and frame:IsShown() then
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

-- One key for fishing, switched on and off at will. While it is on, the key
-- is taken over: a press casts Fishing, and while the line is out the same
-- key interacts with the bobber instead. Switched off, the key does whatever
-- it normally does. Every cast and every reel is still one key press.

local FISHING_SPELL_IDS = { 7620, 131474, 131476 }
local FISH_ICON = "Interface\\Icons\\Trade_Fishing"
local fishingName
local fishingNow = false    -- a Fishing channel is running
local reelEndedAt = 0       -- when the line last came in
local bindOwner = CreateFrame("Frame")
local bindPending = false   -- a binding change is waiting for combat to end
local UpdateFishIcon, StartKeyCapture

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
local function ReleaseCVars()
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
local function FishingSkill()
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

local function OnLureCastStart(spellID)
    if lureBySpell[spellID] then
        lureCasting, lureCastingAt = true, GetTime()
        lureTried = nil
    end
end

local function OnLureCastSucceeded(spellID)
    local lure = lureBySpell[spellID]
    if not lure then return end
    lureCasting = false
    lureAppliedAt = GetTime()
    lureBelievedUntil = lureAppliedAt + lure.minutes * 60
    lureFailures = {}
end

local function OnLureCastEnded()
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

local function UpdateAutoLoot(forceOff)
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
local function SetFishing(on, keepGear)
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

local function SetFishKey(key)
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

local function OnMainHandChanged()
    if db.fishSleep == false then return end
    local pole = MainHandIsPole()
    if pole and not db.fishOn and db.fishKey and fishingName then
        SetFishing(true)
    elseif not pole and db.fishOn and not gearPending then
        SetFishing(false, true)
    end
end

local function OnCombatEnded()
    if bindPending then ApplyFishBinding() end
    local pending = gearPending
    gearPending = nil
    if pending == "equip" and db.fishOn then
        EquipPole()
    elseif pending == "restore" and not db.fishOn then
        RestoreWeapons()
    end
end

local function OnChannelStart(spellID)
    if not (db.fishOn and fishingName and spellID) then return end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if not (ok and name == fishingName) then return end
    fishingNow = true
    lastFishAt = GetTime()
    LeaseCVars()
    ApplyFishBinding()
end

local function OnChannelStop()
    if not fishingNow then return end
    fishingNow = false
    reelEndedAt = GetTime()
    lastFishAt = reelEndedAt
    ReleaseCVars()
    ApplyFishBinding()
end

local function InitFishing()
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
BINDING_NAME_WINDFALL_WINDOW = "Show or hide the window"
BINDING_NAME_WINDFALL_SPARKLE = "Node sparkles on / off"

-- ------------------------------------------------------------- sparkles ----

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

local function SkillsChanged()
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

local function StopSparkles()
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

local function StartSparkles()
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

local function ApplySparkles()
    if db.sparkle then StartSparkles() else StopSparkles() end
end

function Windfall_ToggleSparkles()
    if not db then return end
    db.sparkle = not db.sparkle
    ApplySparkles()
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
local function GetawayText()
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

-- ------------------------------------------------------------------- UI ----

local function BuildFrame()
    local f = CreateFrame("Frame", "WindfallFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 100)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.8)
    f:SetBackdropBorderColor(0.4, 0.7, 0.3, 1)

    local pos = db.pos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -120, 0)
    end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        db.pos = { point, relPoint, x, y }
    end)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -9)
    f.title:SetText("|cff7fd36bWindfall|r")

    f.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.time:SetPoint("LEFT", f.title, "RIGHT", 8, 0)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function() f:Hide() db.hidden = true end)

    -- Fishing key switch: lit while the key is taken over for fishing.
    f.fish = CreateFrame("Button", nil, f)
    f.fish:SetSize(18, 18)
    f.fish:SetPoint("TOPRIGHT", -28, -6)
    f.fish:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.fish.icon = f.fish:CreateTexture(nil, "ARTWORK")
    f.fish.icon:SetAllPoints()
    f.fish.icon:SetTexture(FISH_ICON)
    f.fish.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.fish:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            StartKeyCapture()
        else
            Windfall_ToggleFishing()
        end
    end)

    -- Settings.
    f.gear = CreateFrame("Button", nil, f)
    f.gear:SetSize(18, 18)
    f.gear:SetPoint("RIGHT", f.fish, "LEFT", -4, 0)
    f.gear.icon = f.gear:CreateTexture(nil, "ARTWORK")
    f.gear.icon:SetAllPoints()
    f.gear.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    f.gear:SetScript("OnClick", function() ToggleSettings() end)
    f.gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Windfall settings")
        GameTooltip:Show()
    end)
    f.gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Professions.
    f.prof = CreateFrame("Button", nil, f)
    f.prof:SetSize(18, 18)
    f.prof:SetPoint("RIGHT", f.gear, "LEFT", -4, 0)
    f.prof.icon = f.prof:CreateTexture(nil, "ARTWORK")
    f.prof.icon:SetAllPoints()
    f.prof.icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
    f.prof.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.prof:SetScript("OnClick", function() ToggleProfessions() end)
    f.prof:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Professions")
        GameTooltip:AddLine("What your characters can craft, and what it earns or costs.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.prof:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.fish:SetScript("OnEnter", function(self)
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
    f.fish:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.time:SetPoint("RIGHT", f.prof, "LEFT", -4, 0)
    f.time:SetJustifyH("LEFT")
    f.time:SetWordWrap(false)

    f.rate =f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.rate:SetPoint("TOPLEFT", 10, -30)

    f.total = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.total:SetPoint("TOPRIGHT", -10, -34)

    f.rows = {}
    for i = 1, MAX_ROWS do
        local y = -54 - (i - 1) * ROW_H
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
    f.hint:SetPoint("TOPLEFT", 10, -54)
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
    frame.fish.icon:SetDesaturated(not db.fishOn)
    frame.fish:SetAlpha(db.fishOn and 1 or 0.45)
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
    local f = CreateFrame("Frame", "WindfallHistoryFrame", UIParent, "BackdropTemplate")
    f:SetSize(HISTORY_WIDTH, 120)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetBackdropBorderColor(0.4, 0.7, 0.3, 1)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -9)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function() f:Hide() end)

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
    frame.hint:SetPoint("TOPLEFT", 10, -54 - shown * ROW_H)
    frame.hint:SetText(hint or "")

    local getaway = db.fishOn and GetawayText() or nil
    frame.getaway:ClearAllPoints()
    frame.getaway:SetPoint("TOPLEFT", 10, -54 - shown * ROW_H - (hint and 26 or 0) - 2)
    frame.getaway:SetText(getaway or "")

    frame.toggle:SetText(running and "Pause" or "Start")
    frame.mode:SetText(MODE_LABEL[db.mode])
    frame:SetHeight(54 + shown * ROW_H + (hint and 26 or 0) + (getaway and 18 or 0) + 36)
    RefreshHistory()
end

function Windfall_ToggleWindow()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
        db.hidden = true
    else
        frame:Show()
        db.hidden = false
        Refresh()
    end
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

-- ---------------------------------------------------------------- slash ----

-- ------------------------------------------------------------- settings ----

local function MakeWindow(name, title, width)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, 200)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetBackdropBorderColor(0.4, 0.7, 0.3, 1)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText("|cff7fd36bWindfall|r " .. title)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function() f:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames, name) end -- Escape closes it
    f:Hide()
    return f
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
        set = function(value) db.sparkle = value ApplySparkles() end },
    { key = "sparkleHerb", label = "    Herbs", after = function() sparkleGUID = false end },
    { key = "sparkleOre", label = "    Ore", after = function() sparkleGUID = false end },
    { key = "sparkleFish", label = "    Fishing pools", after = function() sparkleGUID = false end },
    { key = "interactDefault", label = "Interact back to game default when Windfall is done",
        tip = "When the line comes in or sparkles are switched off, the interact key goes to the game's defaults (10 yards, in front of you) instead of what was set before. Windfall leaves it alone the rest of the time." },
    { header = "Window" },
    { label = "Show the Windfall window",
        get = function() return frame:IsShown() end,
        set = function(value) if value ~= frame:IsShown() then Windfall_ToggleWindow() end end },
    { label = "Show the minimap button",
        get = function() return not db.minimapHidden end,
        set = function(value)
            db.minimapHidden = not value
            if minimapButton then minimapButton:SetShown(value) end
        end },
}

local function BuildSettingsFrame()
    local f = MakeWindow("WindfallSettingsFrame", "settings", 380)
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

-- ---------------------------------------------------------- professions ----

-- Every character's recipes are saved when one of its profession windows
-- opens, so alts show up too once you have opened theirs. Prices are looked
-- up when the window is drawn, so they follow your latest Auctionator scan.

local AH_CUT = 0.05
local PROF_ROWS = 18
local PROF_WIDTH = 520
local DIFFICULTY_BY_NUMBER = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
local DIFFICULTY_COLOR = {
    optimal = "|cffff8040", medium = "|cffffff00", easy = "|cff40c040", trivial = "|cff808080",
}
local DIFFICULTY_LABEL = {
    optimal = "always gives a skill point", medium = "usually gives a skill point",
    easy = "sometimes gives a skill point", trivial = "gives no skill",
}

local function CharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName and GetRealmName() or ""
    return (name or "?") .. "-" .. realm
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
            local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false)
            if ok and schematic then
                local reagents = {}
                for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
                    local first = slot.reagents and slot.reagents[1]
                    local basic = not (Enum and Enum.CraftingReagentType) or slot.reagentType == Enum.CraftingReagentType.Basic
                    if basic and first and first.itemID and (slot.quantityRequired or 0) > 0 then
                        reagents[#reagents + 1] = { first.itemID, slot.quantityRequired }
                    end
                end
                local difficulty = DIFFICULTY_BY_NUMBER[info.relativeDifficulty] or info.difficulty
                recipes[recipeID] = {
                    name = info.name,
                    item = schematic.outputItemID,
                    qty = ((schematic.quantityMin or 1) + (schematic.quantityMax or schematic.quantityMin or 1)) / 2,
                    diff = difficulty,
                    reagents = reagents,
                }
            end
        end
    end
    if not next(recipes) then return end

    db.chars = db.chars or {}
    local key = CharacterKey()
    local char = db.chars[key] or { professions = {} }
    db.chars[key] = char
    local _, class = UnitClass("player")
    char.class = class
    char.professions[base.professionName] = {
        skill = skillInfo.skillLevel, max = skillInfo.maxSkillLevel,
        saved = time(), recipes = recipes,
    }
end

local professionSavePending = false
local function SaveProfessionSoon()
    if professionSavePending then return end
    professionSavePending = true
    -- The list arrives in pieces; wait for it to settle.
    C_Timer.After(1, function()
        professionSavePending = false
        SaveProfession()
        if RefreshProfessions then RefreshProfessions() end
    end)
end

-- What it costs to get one of a reagent: the cheaper of the auction house
-- and a vendor that sells it (as Auctionator saw at that vendor).
local function ReagentPrice(itemID)
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
local function CraftNumbers(recipe)
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
    if not chars[profView.char] then
        profView.char = chars[CharacterKey()] and CharacterKey() or SortedKeys(chars)[1]
    end
    local char = chars[profView.char]
    if not char then return nil end
    if not char.professions[profView.prof] then profView.prof = SortedKeys(char.professions)[1] end
    return char, char.professions[profView.prof]
end

local function ShortName(key)
    return (key or ""):match("^(.-)%-") or key
end

local function ClassColored(char, key)
    local c = char and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.class]
    return c and string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, ShortName(key)) or ShortName(key)
end

local function BuildProfList(prof)
    local list = {}
    for recipeID, recipe in pairs(prof.recipes) do
        local cost, value, profit, missing = CraftNumbers(recipe)
        local skillUp = recipe.diff ~= "trivial"
        if profView.mode == "profit" or skillUp then
            list[#list + 1] = { id = recipeID, recipe = recipe, cost = cost, value = value,
                profit = profit, missing = missing }
        end
    end
    if profView.mode == "profit" then
        -- Best profit first; recipes that cannot be priced go last.
        table.sort(list, function(a, b)
            if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
            if a.profit and a.profit ~= b.profit then return a.profit > b.profit end
            return (a.recipe.name or "") < (b.recipe.name or "")
        end)
    else
        -- Skill-up: what a point costs. A craft that sells covers part of
        -- its own cost; orange counts fully, yellow and green less.
        local chance = { optimal = 1, medium = 0.75, easy = 0.25 }
        for _, e in ipairs(list) do
            if not e.missing then
                -- Below zero: the craft sells for more than it costs.
                local net = e.cost - (e.value or 0)
                e.perPoint = net / (chance[e.recipe.diff] or 0.25)
            end
        end
        table.sort(list, function(a, b)
            if (a.perPoint ~= nil) ~= (b.perPoint ~= nil) then return a.perPoint ~= nil end
            if a.perPoint and a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
            return (a.recipe.name or "") < (b.recipe.name or "")
        end)
    end
    return list
end

local function RecipeTooltip(row)
    local e = row.entry
    if not e then return end
    local recipe = e.recipe
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine((DIFFICULTY_COLOR[recipe.diff] or "") .. (recipe.name or "?") .. "|r")
    if DIFFICULTY_LABEL[recipe.diff] then GameTooltip:AddLine(DIFFICULTY_LABEL[recipe.diff], 0.7, 0.7, 0.7) end
    GameTooltip:AddLine(" ")
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
    GameTooltip:Show()
end

local function BuildProfessionsFrame()
    local f = MakeWindow("WindfallProfessionsFrame", "professions", PROF_WIDTH)
    f:SetHeight(84 + PROF_ROWS * ROW_H + 40)

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
        profView.mode = profView.mode == "profit" and "skill" or "profit"
        profView.offset = 0
        RefreshProfessions()
    end)

    f.skill = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.skill:SetPoint("TOPRIGHT", -14, -36)

    local function Column(row, template)
        row.name = f:CreateFontString(nil, "OVERLAY", template)
        row.name:SetWidth(PROF_WIDTH - 290)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.cost = f:CreateFontString(nil, "OVERLAY", template)
        row.value = f:CreateFontString(nil, "OVERLAY", template)
        row.profit = f:CreateFontString(nil, "OVERLAY", template)
    end
    local function Place(row, y)
        row.name:SetPoint("TOPLEFT", 12, y)
        row.cost:SetPoint("TOPRIGHT", -196, y)
        row.value:SetPoint("TOPRIGHT", -104, y)
        row.profit:SetPoint("TOPRIGHT", -14, y)
    end
    f.head = {}
    Column(f.head, "GameFontDisableSmall")
    Place(f.head, -62)
    f.head.name:SetText("Recipe")
    f.head.cost:SetText("Cost")
    f.head.value:SetText("Sells for")

    f.rows = {}
    for i = 1, PROF_ROWS do
        local y = -78 - (i - 1) * ROW_H
        local row = CreateFrame("Button", nil, f)
        row:SetPoint("TOPLEFT", 8, y + 2)
        row:SetSize(PROF_WIDTH - 16, ROW_H)
        row:SetScript("OnEnter", RecipeTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", 12, 14)
    f.hint:SetWidth(PROF_WIDTH - 130)
    f.hint:SetJustifyH("LEFT")

    f.forget = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.forget:SetSize(110, 20)
    f.forget:SetPoint("BOTTOMRIGHT", -10, 10)
    f.forget:SetText("Forget this")
    f.forget:SetScript("OnClick", function()
        if StaticPopup_Show then StaticPopup_Show("WINDFALL_FORGET_PROFESSION") end
    end)
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
    f.modeButton:SetText(profView.mode == "profit" and "Best profit" or "Cheapest skill-up")
    f.head.profit:SetText(profView.mode == "profit" and "Profit" or "Per point")
    if not prof then
        profList = {}
        f.charButton:SetText("No characters")
        f.profButton:SetText("-")
        f.skill:SetText("")
        for _, row in ipairs(f.rows) do
            row.entry = nil
            row.name:SetText("") row.cost:SetText("") row.value:SetText("") row.profit:SetText("")
        end
        f.hint:SetText("Open a profession window on any character and it is saved here.")
        f.forget:Hide()
        return
    end
    f.forget:Show()
    f.charButton:SetText(ClassColored(char, profView.char))
    f.profButton:SetText(profView.prof)
    f.skill:SetText(string.format("Skill %d / %d", prof.skill or 0, prof.max or 0))

    profList = BuildProfList(prof)
    profView.offset = math.max(0, math.min(profView.offset, #profList - PROF_ROWS))
    for i, row in ipairs(f.rows) do
        local e = profList[i + profView.offset]
        row.entry = e
        if e then
            row.name:SetText((DIFFICULTY_COLOR[e.recipe.diff] or "|cffffffff") .. (e.recipe.name or "?") .. "|r")
            if e.missing and e.cost == 0 then
                row.cost:SetText("|cff888888?|r")
            else
                row.cost:SetText(Money(e.cost) .. (e.missing and "|cffff6060*|r" or ""))
            end
            row.value:SetText(e.value and Money(e.value) or (e.recipe.item and "|cff888888-|r" or "|cff888888no item|r"))
            if profView.mode == "profit" then
                row.profit:SetText(e.profit and SignedMoney(e.profit) or "|cff888888?|r")
            else
                if not e.perPoint then
                    row.profit:SetText("|cff888888?|r")
                elseif e.perPoint <= 0 then
                    row.profit:SetText("|cff7fd36bearns " .. Money(-e.perPoint) .. "|r")
                else
                    row.profit:SetText(Money(e.perPoint))
                end
            end
        else
            row.name:SetText("") row.cost:SetText("") row.value:SetText("") row.profit:SetText("")
        end
    end

    local age = math.floor((time() - (prof.saved or time())) / 86400)
    local hint = (age >= 1 and string.format("Saved %d day%s ago. ", age, age == 1 and "" or "s") or "")
        .. (profView.mode == "skill" and "Orange, yellow and green recipes, by what a skill point costs. " or "")
        .. "* = a reagent has no price."
        .. (#profList > PROF_ROWS and " Scroll for more." or "")
    f.hint:SetText(hint)
end

function ToggleProfessions()
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
        if db.hidden then frame:Hide() end
        Refresh()
        CreateMinimapButton()
        InitFishing()
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
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if arg1 == 16 then OnMainHandChanged() end
        if db.fishOn then Refresh() end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
        SaveProfessionSoon()
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "SKILL_LINES_CHANGED" then
        if event == "SKILL_LINES_CHANGED" then SkillsChanged() end
        -- Zone, skill and lure all change the getaway line.
        if db.fishOn and frame and frame:IsShown() then Refresh() end
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
