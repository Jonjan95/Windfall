# Runs Windfall.lua against a stubbed WoW API and prints what a simulated
# session looks like: gathering, loot, zone history, fishing key, lures,
# sound boost, gear swap and the settings window. Read the output by eye.
#
# Usage: python -I tools/sim_test.py <dir with lupa> Windfall.lua
# (the lupa package lives in JumpCounter-dev/tools/pylib on this machine)
import sys
sys.path.insert(0, sys.argv[1])
import lupa.lua51 as l51
rt = l51.LuaRuntime()
rt.execute(r'''
now = 0
function GetTime() return now end
function print() end
zone="Eastern Plaguelands" function GetRealZoneText() return zone end
StaticPopupDialogs={} function StaticPopup_Show(n) if n == 'WINDFALL_FORGET_PROFESSION' then forgetShown = true return end StaticPopupDialogs[n].OnAccept() end
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
GOLD_AMOUNT = "%d Gold" SILVER_AMOUNT = "%d Silver" COPPER_AMOUNT = "%d Copper"
SlashCmdList = {}
binds = {} cvars = {SoftTargetInteract="0", SoftTargetInteractArc="0", SoftTargetInteractRange="10"} combat = false
function InCombatLockdown() return combat end
function ClearOverrideBindings() binds = {} end
function SetOverrideBinding(_,_,key,cmd) binds[key]=cmd end
function SetOverrideBindingClick(_,_,key,btn) binds[key]="CLICK "..btn end
C_CVar = { GetCVar=function(n) return cvars[n] end, SetCVar=function(n,v) cvars[n]=v end }
shiftDown = false
function IsAltKeyDown() return false end function IsControlKeyDown() return false end function IsShiftKeyDown() return shiftDown end
local function widget()
  local w = {shown=true}
  return setmetatable(w, {__index=function(t,k)
    if k=="IsShown" then return function(s) return s.shown end end
    if k=="Hide" then return function(s) s.shown=false; if rawget(s,"isSparkle") then sparkleShown=false end end end
    if k=="SetFrameStrata" then return function(s,v) if v=="LOW" then rawset(s,"isSparkle",true) end end end
    if k=="SetShown" then return function(s,v) s.shown=v and true or false end end
    if k=="Show" then return function(s) s.shown=true; if rawget(s,"isSparkle") then sparkleShown=true end end end
    if k=="CreateFontString" or k=="CreateTexture" then return function() return widget() end end
    if k=="GetText" then return function(s) return s.text end end
    if k=="GetWidth" then return function() return 140 end end
    if k=="SetScript" then return function(s,ev,fn) s["on"..ev]=fn end end
    if k=="SetText" then return function(s,x) s.text=x; sets=(sets or 0)+1 end end
    if k=="SetAttribute" then return function(s,a,v) s.attr=rawget(s,"attr") or {}; s.attr[a]=v end end
    if k=="HookScript" then return function(s,ev,fn) rawset(s,"on"..ev,fn) end end
    if k=="SetChecked" then return function(s,v) s.checked=v end end
    if k=="GetChecked" then return function(s) return s.checked end end
    if k=="GetStringHeight" then return function() return 300 end end
    if k=="AddLine" then return function(s,t) tipLines[#tipLines+1]=tostring(t) end end
    if k=="AddDoubleLine" then return function(s,a,b) tipLines[#tipLines+1]=tostring(a).." = "..tostring(b) end end
    if k=="SetEnabled" then return function(s,v) s.enabled=v end end
    if k=="SetDesaturated" then return function(s,v) s.desat=v end end
    if k=="SetHeight" then return function(s,x) s.h=x end end
    return function() end
  end})
end
UIParent = widget() Minimap = widget() GameTooltip = widget()
handlers = {}
function CreateFrame(kind, name)
  local f = widget()
  if name then _G[name]=f end
  local mt = getmetatable(f); local idx = mt.__index
  mt.__index = function(t,k)
    if k=="SetScript" then return function(s,ev,fn) rawset(s,"on"..ev,fn) if ev=="OnEvent" then handlers[#handlers+1]=fn end end end
    return idx(t,k)
  end
  return f
end
C_Timer = { NewTicker=function(_,fn) tick=fn end }
C_Spell = { GetSpellName=function(id) local n={[2366]="Herb Gathering",[2575]="Mining",[8613]="Skinning",[7620]="Fishing",[133]="Fireball"} return n[id] end }
local sub = {[13466]=9,[10620]=7,[8170]=6}
local vend = {[6238]=80,[2589]=13,[4306]=150,[7909]=2500}
C_Item = {
  GetItemInfoInstant=function(id) if sub[id] then return id,"","","",134215,7,sub[id] end return id,"","","",1,4,1 end,
  GetItemInfo=function(id) return "n",nil,1,1,1,"","",1,"",1,vend[id] end,
}
bags = {} mainhand = nil enchant = nil
function GetInventoryItemID() return mainhand end
function GetWeaponEnchantInfo() if enchant then return true, enchant end return false end
C_Item.GetItemCount = function(id) return bags[id] or 0 end
do local old = C_Item.GetItemInfoInstant
  C_Item.GetItemInfoInstant = function(id) if id == 6256 then return id,"","","",1,2,20 end return old(id) end end
offhand = nil containers = {} timers = {}
function GetInventoryItemID(_, slot) if slot == 17 then return offhand end return mainhand end
function GetInventoryItemLink(_, slot) local id = GetInventoryItemID(nil, slot) return id and ("link:"..id) or nil end
C_Container = { GetContainerNumSlots=function(b) return containers[b] and #containers[b] or 0 end,
  GetContainerItemID=function(b,s) return containers[b] and containers[b][s] end }
C_Item.EquipItemByName = function(item, slot)
  local id = tonumber(tostring(item):match("%d+"))
  if slot == 17 then offhand = id else mainhand = id; if id == 6256 then offhand = nil end end
end
C_Timer.After = function(d, fn) timers[#timers+1] = fn end
function runTimers() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
C_Timer.NewTicker = function(d, fn) if d == 1 then tick = fn else idle = fn end end
WorldFrame = { HookScript=function(_, ev, fn) worldMouseDown = fn end }
cvars.autoLootDefault = "0"
skill = nil faction = "Alliance" UISpecialFrames = {}
gatherProfs = { 182, 186 } -- Herbalism, Mining
function GetProfessions() return gatherProfs[1] and 101 or nil, gatherProfs[2] and 102 or nil, nil, skill and 1 or nil end
function GetProfessionInfo(i) if i == 1 then return "Fishing", 1, skill[1], skill[2], 0, 0, 356, skill[3] end local line = gatherProfs[i - 100]; return (profNames and profNames[line]) or "Gathering", 1, 1, 300, 0, 0, line, 0 end
function UnitFactionGroup() return faction end
soft = nil plateMissing = false sparkleShown = false
function UnitGUID(u) if u == "softinteract" and soft then return soft.guid end end
do local oldUnitName = UnitName
  function UnitName(u) if u == "softinteract" then return soft and soft.name end if oldUnitName then return oldUnitName(u) end end end
C_NamePlate = { GetNamePlateForUnit=function(u) if u == "softinteract" and soft and not plateMissing then return UIParent end end }
do local oldNT = C_Timer.NewTicker
  C_Timer.NewTicker = function(d, fn) if d == 0.2 then sparkleTick = fn; return { Cancel=function() sparkleTick = function() end end } end return oldNT(d, fn) end end
player = "Jonis" class = "PALADIN" trade = nil linked = false tipLines = {}
do local oldUN = UnitName
  function UnitName(u) if u == "player" then return player end return oldUN(u) end end
function GetRealmName() return "Realm" end
function time() return 1763200000 end
function UnitClass() return class, class end
playerLevel = 60
function UnitLevel() return playerLevel end
RAID_CLASS_COLORS = { PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
Enum = { CraftingReagentType = { Basic = 0 } }
C_TradeSkillUI = {
  IsTradeSkillLinked = function() return linked end,
  OpenTradeSkill = function(line) openedLines[#openedLines+1] = line end,
  CloseTradeSkill = function() closedTrade = true end,
  IsTradeSkillReady = function() return tradeReady end,
  CraftRecipe = function(id, n) craftedRecipe, craftedCount = id, n end,
  GetBaseProfessionInfo = function() return trade and { professionName = trade.name, professionID = trade.id, skillLevel = trade.skill, maxSkillLevel = trade.max } end,
  GetAllRecipeIDs = function() local t = {} for id in pairs(trade.recipes) do t[#t+1] = id end return t end,
  GetRecipeInfo = function(id) local r = trade.recipes[id]; if not r then return nil end return { name = r.name, learned = r.learned ~= false and not r.unlearned, relativeDifficulty = r.rd } end,
  GetRecipeSchematic = function(id) local r = trade.recipes[id]; if not r then return nil end local slots = {}
    for _, g in ipairs(r.reagents) do slots[#slots+1] = { reagentType = 0, quantityRequired = g[2], reagents = { { itemID = g[1] } } } end
    return { outputItemID = r.item, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = slots } end,
}
C_Item.GetItemNameByID = function(id) return "item"..id end
ahResults = {} lastSearch = nil startedQty = nil confirmedQty = nil
C_AuctionHouse = {
  MakeItemKey = function(id) return { itemID = id } end,
  SendSearchQuery = function(key) lastSearch = key.itemID end,
  GetNumCommoditySearchResults = function(id) return #(ahResults[id] or {}) end,
  GetCommoditySearchResultInfo = function(id, i) return ahResults[id][i] end,
  StartCommoditiesPurchase = function(id, qty) startedQty = qty end,
  ConfirmCommoditiesPurchase = function(id, qty) confirmedQty = qty end,
  CancelCommoditiesPurchase = function() end,
}
knownSpells = {}
function IsPlayerSpell(id) return knownSpells[id] == true end
merchant = {} buys = {} tradeReady = false craftedRecipe = nil craftedCount = nil openedLines = {}
function GetMerchantNumItems() return #merchant end
function GetMerchantItemID(i) return merchant[i] end
function GetMerchantItemMaxStack() return 20 end
C_MerchantFrame = { GetItemInfo = function(i) return { price = 10, stackCount = 1 } end }
function BuyMerchantItem(i, n) buys[#buys+1] = n; bags[merchant[i]] = (bags[merchant[i]] or 0) + n end
function GetMoney() return 1000000 end
Auctionator = { API = { v1 = { GetVendorPriceByItemID=function(_, id) if id == 2320 or id == 3371 then return 10 elseif id == 4289 then return 50 end end, GetAuctionPriceByItemID=function(caller,id)
  local p={[2318]=30,[783]=20,[2302]=60,[2304]=45,[2303]=150,[4237]=130,[4231]=40,[4306]=100,[4305]=600,[2996]=50,[2320]=30,[2447]=20,[765]=15,[3371]=40,[118]=500,[13466]=2840,[10620]=4000,[8170]=900,[7909]=30000,[4306]=100} return p[id] end } } }
''')
import os
_ns = rt.eval('{}')
_load = rt.eval('function(src, name) return assert(loadstring(src, name)) end')
for _path in [os.path.join(os.path.dirname(os.path.abspath(sys.argv[2])), 'Data', n) for n in ('Recipes.lua', 'SkillUps.lua')] + [sys.argv[2]]:
    _load(open(_path, encoding='utf-8').read(), '=' + os.path.basename(_path))('Windfall', _ns)
print(rt.eval(r'''(function()
  local ev = handlers[#handlers]
  local out = {}
  local f
  local function L(id,n,c) ev(nil,"CHAT_MSG_LOOT","You receive loot: |cffffffff|Hitem:"..id.."::::::::60:::::|h["..n.."]|h|r"..(c and ("x"..c) or "")..".") end
  local function dump(tag)
    out[#out+1] = "## "..tag..": "..f.time.text.." | "..f.rate.text.." | "..f.total.text.." | hint="..tostring(f.hint.text)
    for i=1,6 do if f.rows[i].name.text ~= "" then out[#out+1] = "   "..f.rows[i].name.text.." | "..f.rows[i].unit.text.." | "..f.rows[i].value.text end end
  end
  ev(nil,"ADDON_LOADED","Windfall"); ev(nil,"PLAYER_LOGIN"); f = WindfallFrame
  -- gather mode, clock stopped: mob loot and coins are ignored
  L(2589,"Linen Cloth",2); ev(nil,"CHAT_MSG_MONEY","You loot 3 Silver, 20 Copper")
  dump("ignored before start")
  L(13466,"Plaguebloom",3)                       -- herb by subclass, starts clock
  L(2589,"Linen Cloth",2)                        -- recorded, hidden in gather view
  ev(nil,"UNIT_SPELLCAST_SUCCEEDED","player","x",2575); ev(nil,"LOOT_OPENED")
  L(10620,"Thorium Ore",2); L(7909,"Aquamarine")  -- gem from the node counts as gathered
  ev(nil,"LOOT_CLOSED"); now = 10
  ev(nil,"UNIT_SPELLCAST_SUCCEEDED","player","x",133); ev(nil,"LOOT_OPENED")
  L(4306,"Silk Cloth",4); ev(nil,"CHAT_MSG_MONEY","You loot 1 Gold, 3 Silver, 20 Copper"); ev(nil,"LOOT_CLOSED")
  local before = sets
  for t=11,59 do now=t; tick() end
  out[#out+1] = "redraws during 49 idle seconds: "..(sets-before)
  now = 1800; tick()
  dump("gather")
  SlashCmdList.WINDFALL("loot"); dump("loot")
  SlashCmdList.WINDFALL("mode"); out[#out+1] = "mode back to "..WindfallDB.mode
  local b = WindfallMinimapButton; b.onOnEnter(b); b.onOnClick(b,"RightButton"); out[#out+1]="minimap right-click -> "..WindfallDB.mode
  b.onOnClick(b,"LeftButton"); out[#out+1]="minimap left-click -> window shown: "..tostring(f:IsShown())
  -- zone history
  local function hist(tag)
    local h = WindfallHistoryFrame
    out[#out+1] = "## history "..tag..": "..h.title.text.." | hint="..tostring(h.hint.text)
    for i=1,4 do if h.rows[i].zone.text ~= "" then out[#out+1] = "   "..h.rows[i].zone.text.." | "..h.rows[i].rate.text.." | "..h.rows[i].time.text.." | "..h.rows[i].runs.text end end
  end
  if not f:IsShown() then b.onOnClick(b,"LeftButton") end
  SlashCmdList.WINDFALL("gather"); SlashCmdList.WINDFALL("zones")
  hist("live session, gather")
  SlashCmdList.WINDFALL("reset")
  out[#out+1] = "after reset: "..f.total.text.." "..f.time.text
  hist("saved, gather")
  -- second run: 20 min in EPL, then 30 s passing through WPL, then 10 min in Winterspring
  now = 5000; L(13466,"Plaguebloom",10); now = 6200; tick()
  zone = "Western Plaguelands"; now = 6230; tick()
  zone = "Winterspring"; L(10620,"Thorium Ore",5); now = 6830; tick()
  hist("second run live, gather")
  SlashCmdList.WINDFALL("loot"); hist("loot view")
  SlashCmdList.WINDFALL("gather"); SlashCmdList.WINDFALL("discard"); hist("after discard")
  WindfallHistoryFrame.clear.onOnClick(); hist("after clear")
  -- fishing key
  local function bind() return tostring(binds.F) end
  out[#out+1] = "## fishing: start binding="..bind()
  SlashCmdList.WINDFALL("fish")                     -- no key yet: opens the prompt
  out[#out+1] = "prompt shown: "..tostring(WindfallKeyCapture and WindfallKeyCapture:IsShown())
  WindfallKeyCapture.onOnKeyDown(WindfallKeyCapture, "LSHIFT")
  WindfallKeyCapture.onOnKeyDown(WindfallKeyCapture, "F")
  out[#out+1] = "key picked: "..tostring(WindfallDB.fishKey).." on="..tostring(WindfallDB.fishOn).." binding="..bind().." spell="..tostring(WindfallFishButton.attr.spell)
  ev(nil,"UNIT_SPELLCAST_CHANNEL_START","player","x",133)
  out[#out+1] = "other channel: binding="..bind()
  ev(nil,"UNIT_SPELLCAST_CHANNEL_START","player","x",7620)
  out[#out+1] = "line out: binding="..bind().." SoftTargetInteract="..cvars.SoftTargetInteract
  now = now + 10; ev(nil,"UNIT_SPELLCAST_CHANNEL_STOP","player","x",7620)
  out[#out+1] = "line in: binding="..bind().." SoftTargetInteract="..cvars.SoftTargetInteract
  WindfallFishButton.onPreClick(WindfallFishButton, "LeftButton", false)
  out[#out+1] = "key-up right after reel: type="..tostring(WindfallFishButton.attr.type)
  WindfallFishButton.onPostClick(WindfallFishButton)
  WindfallFishButton.onPreClick(WindfallFishButton, "LeftButton", true)
  out[#out+1] = "next press: type="..tostring(WindfallFishButton.attr.type)
  combat = true; SlashCmdList.WINDFALL("fish")
  out[#out+1] = "off in combat: on="..tostring(WindfallDB.fishOn).." binding="..bind()
  combat = false; ev(nil,"PLAYER_REGEN_ENABLED")
  out[#out+1] = "combat over: binding="..bind()
  SlashCmdList.WINDFALL("fishkey shift-g")
  out[#out+1] = "fishkey shift-g: key="..WindfallDB.fishKey.." binding="..tostring(binds["SHIFT-G"])
  -- mouse buttons in the key prompt
  local cap = WindfallKeyCapture
  local function try(fn, arg, label)
    SlashCmdList.WINDFALL("fishkey"); cap[fn](cap, arg)
    out[#out+1] = "prompt "..label.." -> key="..WindfallDB.fishKey.." binding="..tostring(binds[WindfallDB.fishKey]).." prompt open="..tostring(cap:IsShown())
  end
  try("onOnMouseDown", "Button4", "Button4")
  try("onOnMouseDown", "MiddleButton", "MiddleButton")
  try("onOnMouseDown", "Button12", "Button12")
  try("onOnMouseDown", "LeftButton", "plain LeftButton (refused)")
  try("onOnMouseWheel", 1, "wheel up")
  try("onOnKeyDown", "ESCAPE", "Escape (cancel)")
  -- bobber sound boost
  local function snd() return "sfx="..cvars.Sound_SFXVolume.." enabled="..cvars.Sound_EnableSFX.." music="..cvars.Sound_MusicVolume.." ambience="..cvars.Sound_AmbienceVolume end
  cvars.Sound_SFXVolume="0.3" cvars.Sound_EnableSFX="0" cvars.Sound_MusicVolume="0.4" cvars.Sound_AmbienceVolume="0.6"
  out[#out+1] = "sound before: "..snd()
  ev(nil,"UNIT_SPELLCAST_CHANNEL_START","player","x",7620); out[#out+1] = "sound line out: "..snd()
  ev(nil,"UNIT_SPELLCAST_CHANNEL_STOP","player","x",7620); out[#out+1] = "sound line in: "..snd()
  ev(nil,"UNIT_SPELLCAST_CHANNEL_START","player","x",7620); cvars.Sound_MusicVolume="0.8"
  ev(nil,"UNIT_SPELLCAST_CHANNEL_STOP","player","x",7620); out[#out+1] = "music changed by you mid-cast is kept: "..snd()
  SlashCmdList.WINDFALL("fishsound")
  ev(nil,"UNIT_SPELLCAST_CHANNEL_START","player","x",7620); out[#out+1] = "boost off, line out: "..snd().." interact="..cvars.SoftTargetInteract
  ev(nil,"UNIT_SPELLCAST_CHANNEL_STOP","player","x",7620)
  -- lures
  local B = WindfallFishButton
  local function press(label)
    B.attr.type = "spell"; B.attr.macrotext = nil
    B.onPreClick(B, "LeftButton", true)
    local t, m = tostring(B.attr.type), B.attr.macrotext
    out[#out+1] = "lure: "..label.." -> "..t..(m and (" ["..m:gsub("\n"," ; ").."]") or "")
    B.onPostClick(B)
  end
  now = now + 100
  press("no pole in main hand")
  mainhand = 6256
  press("pole, no lures in bags")
  bags[6529] = 3; bags[6532] = 1
  press("pole, lures in bags (best is Bright Baubles)")
  ev(nil,"UNIT_SPELLCAST_START","player","x",8090)
  press("while the lure is going on")
  ev(nil,"UNIT_SPELLCAST_SUCCEEDED","player","x",8090); ev(nil,"UNIT_SPELLCAST_STOP","player","x",8090)
  bags[6532] = 0
  press("lure just applied")
  now = now + 598
  press("2 s of lure left")
  now = now + 2; press("(retry after no cast started)")
  now = now + 2; press("(second failure: Shiny Bauble skipped)")
  enchant = 300000
  press("game reports 5 min of lure on the pole")
  enchant = nil; SlashCmdList.WINDFALL("lure"); bags[6532] = 2
  press("auto lures switched off")
  SlashCmdList.WINDFALL("lure")
  -- auto-equip, auto loot, sleep/wake, double-click
  local function st(label)
    out[#out+1] = "four: "..label.." -> on="..tostring(WindfallDB.fishOn).." mainhand="..tostring(mainhand).." offhand="..tostring(offhand).." autoLoot="..cvars.autoLootDefault.." BUTTON2="..tostring(binds.BUTTON2)
  end
  if WindfallDB.fishOn then SlashCmdList.WINDFALL("fish") end
  mainhand = 111; offhand = 222; containers = { [0] = { 6256, 2589 }, [1] = { 999 } }; cvars.autoLootDefault = "0"
  st("start: sword and shield, pole in bags, fishing off")
  SlashCmdList.WINDFALL("fish"); st("fishing switched on")
  -- double right-click
  now = now + 5; worldMouseDown(nil, "RightButton"); st("one right-click")
  now = now + 0.2; worldMouseDown(nil, "RightButton"); st("second right-click within 0.4 s")
  B.attr.type = "spell"; B.onPreClick(B, "LeftButton", false); out[#out+1] = "four: mouse-up casts: type="..tostring(B.attr.type); B.onPostClick(B); st("after that click")
  -- sleep after 10 idle minutes
  now = now + 590; idle(); st("9 min 50 s idle")
  now = now + 20; idle(); now = now + 1; runTimers(); st("over 10 min idle: asleep, weapons back")
  -- wake by equipping the pole by hand, sleep by taking it off
  mainhand = 6256; offhand = nil; ev(nil, "PLAYER_EQUIPMENT_CHANGED", 16, true); st("pole equipped by hand")
  mainhand = 111; ev(nil, "PLAYER_EQUIPMENT_CHANGED", 16, true); st("pole taken off by hand")
  -- combat: gear waits
  combat = true; SlashCmdList.WINDFALL("fish"); st("switched on in combat")
  combat = false; ev(nil, "PLAYER_REGEN_ENABLED"); st("combat over")
  SlashCmdList.WINDFALL("autoloot"); st("auto loot option off")
  SlashCmdList.WINDFALL("autoloot"); SlashCmdList.WINDFALL("fish"); now = now + 1; runTimers(); st("fishing switched off")
  -- settings window and fishing guide
  SlashCmdList.WINDFALL("settings")
  local sf = WindfallSettingsFrame
  local function checks()
    local t = {}
    for _, c in ipairs(sf.checks) do t[#t+1] = (c.checked and "[x] " or "[ ] ")..c.label.text end
    return table.concat(t, "\n      ")
  end
  out[#out+1] = "settings shown="..tostring(sf:IsShown()).." keyButton="..tostring(sf.keyButton.text).." height="..tostring(sf.h).."\n      "..checks()
  local function click(i, v) local c = sf.checks[i]; c.checked = v; c.onOnClick(c) end
  click(2, false); click(5, false); click(1, true)
  out[#out+1] = "after clicks: fishEquip="..tostring(WindfallDB.fishEquip).." fishLoot="..tostring(WindfallDB.fishLoot).." fishOn="..tostring(WindfallDB.fishOn).." mainhand="..tostring(mainhand).." autoLoot="..cvars.autoLootDefault
  click(9, false); out[#out+1] = "minimap hidden="..tostring(WindfallDB.minimapHidden).." button shown="..tostring(WindfallMinimapButton:IsShown())
  click(9, true); click(2, true); click(5, true); click(1, false)
  out[#out+1] = "settings after restore:\n      "..checks()
  skill = {75, 75, 0}; zone = "Eastern Plaguelands"; faction = "Alliance"
  skill = {130, 150, 75}; zone = "Stranglethorn Vale"; faction = "Horde"
  -- getaway line
  local function ga(label) out[#out+1] = "getaway: "..label.." -> '"..tostring(f.getaway.text).."' height="..tostring(f.h) end
  if not f:IsShown() then SlashCmdList.WINDFALL("") end
  skill = {75, 75, 0}; zone = "Stormwind City"
  ga("fishing key off")
  SlashCmdList.WINDFALL("fish"); ga("key on, 75 in Stormwind")
  zone = "The Barrens"; ev(nil, "ZONE_CHANGED_NEW_AREA"); ga("75 in The Barrens")
  skill = {75, 75, 50}; ev(nil, "SKILL_LINES_CHANGED"); ga("75+50 lure in The Barrens")
  zone = "Eastern Plaguelands"; ev(nil, "ZONE_CHANGED_NEW_AREA"); ga("in Eastern Plaguelands")
  zone = "Gilneas"; ev(nil, "ZONE_CHANGED_NEW_AREA"); ga("zone without data")
  skill = nil; ev(nil, "SKILL_LINES_CHANGED"); ga("no Fishing skill")
  SlashCmdList.WINDFALL("fish"); ga("key off again")
  -- node sparkles
  local function sp(label)
    local fr = sparkleShown and "sparkle shown" or "no sparkle"
    out[#out+1] = "sparkle: "..label.." -> "..fr.." icon="..tostring(cvars.SoftTargetIconGameObject).." interact="..tostring(cvars.SoftTargetInteract).." range="..tostring(cvars.SoftTargetInteractRange).." plates="..tostring(cvars.SoftTargetNameplateInteract).." npcIcon="..tostring(cvars.SoftTargetIconInteract)
  end
  cvars.SoftTargetInteract = "0"; cvars.SoftTargetInteractRange = "10"; cvars.SoftTargetIconGameObject = "0"; cvars.SoftTargetNameplateInteract = "0"; cvars.SoftTargetInteractArc = "0"; cvars.SoftTargetIconInteract = "1"
  sp("sparkles off by default")
  SlashCmdList.WINDFALL("sparkle"); sparkleTick(); sp("switched on, nothing near")
  soft = { guid = "GameObject-1", name = "Plaguebloom" }; sparkleTick(); sp("Plaguebloom nearby")
  soft = { guid = "GameObject-2", name = "Rich Thorium Vein" }; sparkleTick(); sp("Rich Thorium Vein (by name rule)")
  soft = { guid = "Creature-3", name = "Scourge Champion" }; sparkleTick(); sp("quest mob")
  soft = { guid = "GameObject-4", name = "Sturdy Locked Chest" }; sparkleTick(); sp("chest")
  soft = { guid = "GameObject-5", name = "Stonescale Eel Swarm" }; sparkleTick(); sp("fishing pool, no Fishing skill")
  skill = {100, 150, 0}; ev(nil, "SKILL_LINES_CHANGED"); sparkleTick(); sp("fishing pool, Fishing learned")
  SlashCmdList.WINDFALL("settings"); local sf2 = WindfallSettingsFrame
  for _, c in ipairs(sf2.checks) do if c.label.text == "    Fishing pools" then c.checked = false; c.onOnClick(c) end end
  sparkleTick(); sp("fishing pools unticked")
  soft = { guid = "GameObject-6", name = "Peacebloom" }; plateMissing = true; sparkleTick(); sp("herb, nameplate not there yet")
  plateMissing = false; sparkleTick(); sp("nameplate appears")
  gatherProfs = { 186 }; ev(nil, "SKILL_LINES_CHANGED"); sparkleTick(); sp("same herb, Herbalism unlearned")
  soft = { guid = "GameObject-7", name = "Truesilver Deposit" }; sparkleTick(); sp("ore, Mining known")
  gatherProfs = { 182, 186 }; ev(nil, "SKILL_LINES_CHANGED")
  soft = nil; sparkleTick(); sp("walked away")
  SlashCmdList.WINDFALL("sparkle"); sp("switched off: settings restored")
  -- interact defaults
  local function it(label)
    out[#out+1] = "interact: "..label.." -> range="..tostring(cvars.SoftTargetInteractRange).." arc="..tostring(cvars.SoftTargetInteractArc).." icon="..tostring(cvars.SoftTargetIconGameObject)
  end
  cvars.SoftTargetInteractRange = "60"; cvars.SoftTargetInteractArc = "2"; cvars.SoftTargetIconGameObject = "1"
  it("set by another addon")
  ev(nil, "PLAYER_LOGOUT"); it("logout without using Windfall: untouched")
  if WindfallDB.fishOn then SlashCmdList.WINDFALL("fish") end
  SlashCmdList.WINDFALL("fish"); it("fishing key on, line not out yet: untouched")
  ev(nil,"UNIT_SPELLCAST_CHANNEL_START","player","x",7620); it("line out")
  ev(nil,"UNIT_SPELLCAST_CHANNEL_STOP","player","x",7620); it("line in: game default")
  cvars.SoftTargetInteractRange = "60"; cvars.SoftTargetInteractArc = "2"
  it("another addon sets it again")
  SlashCmdList.WINDFALL("fish"); it("fishing key off: untouched")
  SlashCmdList.WINDFALL("sparkle"); it("sparkles on")
  SlashCmdList.WINDFALL("sparkle"); it("sparkles off: game default")
  local sf3 = WindfallSettingsFrame
  for _, c in ipairs(sf3.checks) do if c.label.text:find("^Interact back") then c.checked = false; c.onOnClick(c) end end
  cvars.SoftTargetInteractRange = "60"
  SlashCmdList.WINDFALL("sparkle"); SlashCmdList.WINDFALL("sparkle")
  it("option off: back to what was there (60)")
  -- professions
  local function pw(label)
    local P = WindfallProfessionsFrame
    out[#out+1] = "prof: "..label.." -> ["..tostring(P.charButton.text).."] ["..tostring(P.profButton.text).."] ["..tostring(P.modeButton.text).."] "..tostring(P.skill.text).." | hint: "..tostring(P.hint.text)
    out[#out+1] = "      "..P.head.name.text.." | "..P.head.cost.text.." | "..P.head.value.text.." | "..tostring(P.head.profit.text)
    for i = 1, 5 do local r = P.rows[i]; if r.name.text ~= "" then out[#out+1] = "      "..r.name.text.." | "..r.cost.text.." | "..r.value.text.." | "..r.profit.text end end
  end
  SlashCmdList.WINDFALL("prof"); pw("before any profession window")
  player = "Jonis"; class = "PALADIN"
  trade = { name = "Tailoring", skill = 120, max = 150, recipes = {
    [101] = { name = "Bolt of Silk Cloth", item = 4305, rd = 0, reagents = { {4306, 4} } },
    [102] = { name = "Brown Linen Robe", item = 6238, rd = 3, reagents = { {2996, 3}, {2320, 1} } },
    [103] = { name = "Runed Copper Rod", item = nil, rd = 1, reagents = { {10940, 1} } },
    [104] = { name = "Not learned", item = 1, rd = 0, learned = false, reagents = {} },
  } }
  ev(nil, "TRADE_SKILL_SHOW"); runTimers()
  pw("tailoring saved, profit view")
  local P = WindfallProfessionsFrame
  P.modeButton.onOnClick(P.modeButton); pw("skill-up view")
  P.rows[1].onOnEnter(P.rows[1]); out[#out+1] = "      tooltip lines: "..table.concat(tipLines, " / ")
  player = "Altie"; class = "MAGE"
  trade = { name = "Alchemy", skill = 60, max = 75, recipes = {
    [201] = { name = "Minor Healing Potion", item = 118, rd = 2, reagents = { {2447, 1}, {765, 1}, {3371, 1} } },
  } }
  ev(nil, "TRADE_SKILL_LIST_UPDATE"); runTimers()
  P.modeButton.onOnClick(P.modeButton)
  P.charButton.onOnClick(P.charButton); pw("cycled to the other character")
  P.charButton.onOnClick(P.charButton); pw("cycled again")
  linked = true; trade = { name = "Engineering", skill = 300, max = 300, recipes = { [301] = { name = "Linked", item = 1, rd = 0, reagents = {} } } }
  ev(nil, "TRADE_SKILL_SHOW"); runTimers(); linked = false
  local n = 0; for _ in pairs(WindfallDB.chars["Altie-Realm"].professions) do n = n + 1 end
  out[#out+1] = "prof: someone else's linked profession saved? Altie professions="..n.." engineering="..tostring(WindfallDB.chars["Altie-Realm"].professions.Engineering ~= nil)
  StaticPopupDialogs.WINDFALL_FORGET_PROFESSION.OnAccept(); pw("forgot the shown one")
  -- levelling plan
  player = "Huntie"; class = "HUNTER"; playerLevel = 10
  bags[2318] = 12; bags[2320] = 0
  trade = { name = "Leatherworking", id = 165, skill = 30, max = 75, recipes = {
    [2881] = { name = "Light Leather", item = 2318, rd = 3, reagents = { {783, 3} } },
    [2149] = { name = "Handstitched Leather Boots", item = 2302, rd = 2, reagents = { {2318, 2}, {2320, 1} } },
    [2152] = { name = "Light Armor Kit", item = 2304, rd = 1, reagents = { {2318, 1} } },
    [2153] = { name = "Handstitched Leather Pants", item = 2303, rd = 1, unlearned = true, reagents = { {2318, 4}, {2320, 1} } },
    [3753] = { name = "Handstitched Leather Belt", item = 4237, rd = 0, unlearned = true, reagents = { {2318, 6}, {2320, 1} } },
    [3816] = { name = "Cured Light Hide", item = 4231, rd = 0, unlearned = true, reagents = { {783, 1}, {4289, 1} } },
  } }
  ev(nil, "TRADE_SKILL_SHOW"); runTimers()
  local P = WindfallProfessionsFrame
  if not P:IsShown() then SlashCmdList.WINDFALL("prof") end
  profPick = function() end
  while P.profButton.text ~= "Leatherworking" or not tostring(P.charButton.text):find("Huntie") do
    if not tostring(P.charButton.text):find("Huntie") then P.charButton.onOnClick(P.charButton) else P.profButton.onOnClick(P.profButton) end
  end
  if P.modeButton.text ~= "Levelling plan" then P.modeButton.onOnClick(P.modeButton) end
  out[#out+1] = "plan: ["..tostring(P.charButton.text).."] ["..P.profButton.text.."] ["..P.modeButton.text.."] "..P.skill.text.." | "..tostring(P.hint.text)
  for i = 1, 18 do local r = P.rows[i]; if r.name.text ~= "" then out[#out+1] = "      "..r.name.text.." | "..r.cost.text.." | "..r.value.text.." | "..r.profit.text end end
  local saved = WindfallDB.recipeData or {}
  local n = 0; for _ in pairs(saved) do n = n + 1 end
  out[#out+1] = "plan: trainer recipes with reagents saved: "..n
  -- route and auction house buying
  local P = WindfallProfessionsFrame
  out[#out+1] = "route: button '"..tostring(P.route.text).."' shown="..tostring(P.route:IsShown())
  P.route.onOnClick(P.route, "LeftButton")
  local S = WindfallShoppingFrame
  local function sh(label)
    out[#out+1] = "route: "..label.." -> "..tostring(S.title2.text).." | "..tostring(S.sum.text).." | status: "..tostring(S.status.text)
    for i = 1, 8 do local t = S.lines[i].text; if t and t ~= "" then out[#out+1] = "      step "..t end end
    for i = 1, 6 do local r = S.rows[i]; if r:IsShown() then out[#out+1] = "      mat "..r.name.text.." | "..r.need.text.." | "..r.total.text.." | buy="..(r.buy:IsShown() and r.buy.text or "-") end end
  end
  sh("route opened, not at the AH")
  if not P:IsShown() then SlashCmdList.WINDFALL("prof") end -- one page at a time: back to Professions
  P.route.onOnClick(P.route, "RightButton"); out[#out+1] = "route: right-click target -> "..P.route.text
  -- events go to every addon frame, as in the game
  ev2 = function(_, e, ...) for _, h in ipairs(handlers) do h(nil, e, ...) end end
  -- the auction house is already open when the route is opened (the case from the screenshot)
  AuctionHouseFrame = CreateFrame("Frame"); AuctionHouseFrame.shown = true
  S:Hide(); P.route.onOnClick(P.route, "LeftButton")
  local row; for i = 1, 6 do if S.rows[i]:IsShown() and S.rows[i].buy:IsShown() then row = S.rows[i] break end end
  sh("AH open")
  -- Show opens the item's buy page in the game's auction house window
  local display = CreateFrame("Frame"); display.shown = true
  display.SetQuantitySelected = false -- not every client has it
  display.QuantityInput = { SetQuantity = function(_, n) shownQty = n end }
  AuctionHouseFrame.CommoditiesBuyFrame = { BuyDisplay = display }
  AuctionHouseFrame.SelectBrowseResult = function(_, r) selected = r.itemKey.itemID end
  knownKeys = {}
  C_AuctionHouse.GetItemKeyInfo = function(key) return knownKeys[key.itemID] end
  row.buy.onOnClick(row.buy); runTimers()
  out[#out+1] = "ah: item not known yet -> selected="..tostring(selected).." status: "..tostring(S.status.text)
  knownKeys[row.item] = { isCommodity = true }
  ev2(S, "ITEM_KEY_ITEM_INFO_RECEIVED", row.item); runTimers()
  out[#out+1] = "ah: item info arrived -> selected="..tostring(selected).." quantity filled="..tostring(shownQty).." button="..row.buy.text.." status: "..tostring(S.status.text)
  shownQty = nil; ev2(S, "COMMODITY_SEARCH_RESULTS_UPDATED", row.item); runTimers()
  out[#out+1] = "ah: listings arrived, amount filled again="..tostring(shownQty)
  out[#out+1] = "ah: anything bought by Windfall? started="..tostring(startedQty).." confirmed="..tostring(confirmedQty)
  -- a second item while still on the first item's buy page, with a busy auction house
  local cbf = CreateFrame("Frame"); cbf.shown = true; cbf.BuyDisplay = display
  AuctionHouseFrame.CommoditiesBuyFrame = cbf
  tabClicks = 0; AuctionHouseFrameBuyTab = { Click = function() tabClicks = tabClicks + 1; cbf.shown = false end }
  ahReady = false; C_AuctionHouse.IsThrottledMessageSystemReady = function() return ahReady end
  selected = nil; knownKeys[2320] = { isCommodity = true }
  local row2; for i = 1, 6 do if S.rows[i]:IsShown() and S.rows[i].item ~= row.item and S.rows[i].buy:IsShown() then row2 = S.rows[i] break end end
  if not row2 then row2 = row; out[#out+1] = "ah: (only one row to show, reusing it)" end
  row2.buy.onOnClick(row2.buy); runTimers()
  out[#out+1] = "ah: second item, busy auction house -> tab clicks="..tabClicks.." selected="..tostring(selected).." status: "..tostring(S.status.text)
  ahReady = true; ev2(S, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  out[#out+1] = "ah: auction house ready -> selected="..tostring(selected).." status: "..tostring(S.status.text)
  -- no listings arrive: one retry after 4 s
  selected = nil; runTimers(); runTimers()
  out[#out+1] = "ah: no listings came -> retried, tab clicks="..tabClicks.." selected again="..tostring(selected)
  ev2(S, "AUCTION_HOUSE_CLOSED"); sh("AH closed")
  -- vendor buying and crafting from the route window
  local S = WindfallShoppingFrame
  local function g(label)
    out[#out+1] = "guide: "..label.." -> now: "..tostring(S.now:IsShown() and S.now.text).." | craft: "..(S.craft:IsShown() and tostring(S.craft.text) or "-").." | buy all: "..tostring(S.buyAll:IsShown()).." | status: "..tostring(S.status.text)
    for i = 1, 6 do local r = S.rows[i]; if r:IsShown() then out[#out+1] = "      mat "..r.name.text.." | "..r.need.text.." | buy="..(r.buy:IsShown() and r.buy.text or "-") end end
  end
  g("route open")
  -- at a vendor that sells Coarse Thread (2320), 10c each, up to 20 per purchase
  merchant = { 2320 }; MerchantFrame = CreateFrame("Frame"); MerchantFrame.shown = true; buys = {}
  ev2(S, "MERCHANT_SHOW"); g("at the thread vendor")
  S.buyAll.onOnClick(S.buyAll); ev2(S, "BAG_UPDATE_DELAYED")
  out[#out+1] = "guide: vendor purchases "..table.concat(buys, ",").." -> thread in bags "..tostring(bags[2320])
  g("after Buy all here")
  ev2(S, "MERCHANT_CLOSED"); MerchantFrame.shown = false
  -- craft: profession window not open yet, then open
  bags[2318] = 200; ev2(S, "BAG_UPDATE_DELAYED"); g("leather in bags")
  tradeReady = false; S.craft.onOnClick(S.craft)
  out[#out+1] = "guide: first Craft click opened skill line "..tostring(openedLines[#openedLines]).." crafted="..tostring(craftedRecipe)
  tradeReady = true; S.craft.onOnClick(S.craft)
  out[#out+1] = "guide: second Craft click crafted recipe "..tostring(craftedRecipe).." x"..tostring(craftedCount).." | status: "..tostring(S.status.text)
  -- skill goes up: the route moves on
  trade.skill = 40; ev(nil, "TRADE_SKILL_LIST_UPDATE"); runTimers(); g("skill went up to 40")
  -- learned at the trainer while the window is open (profession window not opened since)
  knownSpells[2153] = true; bags[2320] = 100
  ev2(S, "NEW_RECIPE_LEARNED", 2153); runTimers(); g("learned Handstitched Leather Pants at the trainer")
  -- at 50 with cap 75, then journeyman trained (cap 150), read live from the game
  gatherProfs = { 165 }; profNames = { [165] = "Leatherworking" }; lwRank, lwMax = 50, 75
  local oldGPI = GetProfessionInfo
  GetProfessionInfo = function(i) if i == 101 then return "Leatherworking", 1, lwRank, lwMax, 0, 0, 165, 0 end return oldGPI(i) end
  ev2(S, "SKILL_LINES_CHANGED"); runTimers(); g("skill 50, cap 75")
  lwMax = 150; ev2(S, "SKILL_LINES_CHANGED"); runTimers(); g("journeyman trained, cap 150")
  -- level 10 at skill 120, cap 150, route to 225: too low for Expert
  lwRank, lwMax = 120, 150; playerLevel = 10
  trade.skill, trade.max = 120, 150
  trade.recipes[3768] = { name = "Hillman's Shoulders", item = 4251, rd = 0, reagents = { {2318, 4}, {2320, 1} } }
  trade.recipes[3779] = { name = "Barbaric Belt", item = 4264, rd = 0, reagents = { {2318, 6}, {2320, 2} } }
  ev(nil, "TRADE_SKILL_LIST_UPDATE"); runTimers()
  local PF = WindfallProfessionsFrame
  if not PF:IsShown() then SlashCmdList.WINDFALL("prof") end
  if PF.modeButton.text ~= "Levelling plan" then PF.modeButton.onOnClick(PF.modeButton) end
  ev2(S, "SKILL_LINES_CHANGED"); runTimers()
  PF.route.onOnClick(PF.route, "RightButton"); PF.route.onOnClick(PF.route, "LeftButton")
  local function steps(label) out[#out+1] = "rank: "..label.." -> "..tostring(S.title2.text).." | now: "..tostring(S.now.text); for i = 1, 8 do local t = S.lines[i].text; if t and t ~= "" then out[#out+1] = "      step "..t end end end
  steps("level 10, too low for Expert")
  playerLevel = 20; ev2(S, "SKILL_LINES_CHANGED"); runTimers(); steps("level 20")
  -- cooking book rank: Expert comes from a vendor book at 125
  trade = { name = "Cooking", id = 185, skill = 125, max = 150, recipes = {
    [2541] = { name = "Coyote Steak", item = 2684, rd = 1, reagents = { {2673, 1} } } } }
  ev(nil, "TRADE_SKILL_LIST_UPDATE"); runTimers()
  local PF2 = WindfallProfessionsFrame
  if not PF2:IsShown() then SlashCmdList.WINDFALL("prof") end
  while PF2.profButton.text ~= "Cooking" do PF2.profButton.onOnClick(PF2.profButton) end
  PF2.route.onOnClick(PF2.route, "LeftButton")
  out[#out+1] = "cook: "..tostring(S.title2.text).." | now: "..tostring(S.now.text)
  for i = 1, 4 do local t = S.lines[i].text; if t and t ~= "" then out[#out+1] = "      step "..t end end
  GetProfessionInfo = oldGPI; gatherProfs = { 182, 186 }
  -- forget needs shift, load brings it back
  local P = WindfallProfessionsFrame
  if not P:IsShown() then SlashCmdList.WINDFALL("prof") end -- one page at a time: back to Professions
  P.forget.onOnClick(P.forget)
  out[#out+1] = "load: plain click on Forget -> popup shown? "..tostring(forgetShown == true).." char="..tostring(P.charButton.text)
  shiftDown = true; P.forget.onOnClick(P.forget); shiftDown = false
  out[#out+1] = "load: shift-click on Forget -> popup shown? "..tostring(forgetShown == true)
  for k in pairs(WindfallDB.chars) do WindfallDB.chars[k] = nil end
  RefreshForTest = true; P.modeButton.onOnClick(P.modeButton); P.modeButton.onOnClick(P.modeButton)
  out[#out+1] = "load: everything forgotten -> ["..tostring(P.charButton.text).."] load button shown="..tostring(P.load:IsShown()).." hint="..tostring(P.hint.text)
  gatherProfs = { 165, 197 }; openedLines = {}; profNames = { [165] = "Leatherworking", [197] = "Tailoring" }
  P.modeButton.onOnClick(P.modeButton); P.modeButton.onOnClick(P.modeButton)
  out[#out+1] = "load: two professions, none saved -> button '"..tostring(P.load.text).."'"
  P.load.onOnClick(P.load)
  out[#out+1] = "load: click opened skill lines "..table.concat(openedLines, ",").." closed="..tostring(closedTrade).." timers waiting="..#timers
  ev(nil, "TRADE_SKILL_SHOW"); runTimers()
  out[#out+1] = "load: Leatherworking saved -> ["..tostring(P.charButton.text).."] ["..tostring(P.profButton.text).."] load button shown="..tostring(P.load:IsShown()).." '"..tostring(P.load.text).."'"
  -- the bar and the panel (Huntie has Leatherworking and Cooking saved)
  trade = { name = "Leatherworking", id = 165, skill = 120, max = 150, recipes = {
    [3768] = { name = "Hillman's Shoulders", item = 4251, rd = 0, reagents = { {2318, 4}, {2320, 1} } } } }
  ev(nil, "TRADE_SKILL_LIST_UPDATE"); runTimers()
  local B, PN = WindfallBar, WindfallPanel
  local function pn(label)
    local cur = "none"
    for _, n in ipairs({ "WindfallFrame", "WindfallHistoryFrame", "WindfallProfessionsFrame", "WindfallShoppingFrame", "WindfallSettingsFrame" }) do
      if _G[n] and _G[n]:IsShown() then cur = n end
    end
    out[#out+1] = "panel: "..label.." -> panel shown="..tostring(PN.shown).." page="..cur
  end
  out[#out+1] = "bar: rate='"..tostring(B.rate.text).."' time='"..tostring(B.time.text).."' fish dim="..tostring(B.fish.icon.desat).." sparkle dim="..tostring(B.sparkle.icon.desat)
  if PN.shown then B.menu.onOnClick(B.menu) end
  pn("closed")
  B.menu.onOnClick(B.menu); pn("Windfall icon on the bar")
  WindfallFrame.zones.onOnClick(WindfallFrame.zones); pn("Zones button on the Farming tab")
  PN.Tabs[4].onOnClick(PN.Tabs[4]); pn("tab: Settings")
  PN.Tabs[2].onOnClick(PN.Tabs[2]); pn("tab: Recipes")
  PN.Tabs[1].onOnClick(PN.Tabs[1]); pn("tab: Levelling")
  local H = PN.header
  local names = {}; for _, b in ipairs(H.icons) do if b:IsShown() then names[#names+1] = b.name end end
  out[#out+1] = "header: char="..tostring(H.char.text).." icons="..table.concat(names, ",").." bar='"..tostring(H.bar.text.text).."' route="..tostring(WindfallShoppingFrame.title2.text)
  for _, b in ipairs(H.icons) do if b.name == "Leatherworking" then b.onOnClick(b) end end
  out[#out+1] = "header: picked Leatherworking -> bar='"..tostring(H.bar.text.text).."' route="..tostring(WindfallShoppingFrame.title2.text).." target button="..tostring(WindfallShoppingFrame.target.text)
  WindfallShoppingFrame.target.onOnClick(WindfallShoppingFrame.target)
  out[#out+1] = "header: target clicked -> route="..tostring(WindfallShoppingFrame.title2.text).." target button="..tostring(WindfallShoppingFrame.target.text)
  H.char.onOnClick(H.char)
  local rows = {}; for _, r in ipairs(WindfallCharMenu.rows) do if r:IsShown() then rows[#rows+1] = r.text.text end end
  out[#out+1] = "header: character menu -> "..table.concat(rows, " || ")
  WindfallCharMenu:Hide()
  -- a second Huntie on another realm
  WindfallDB.chars["Huntie-Other Realm"] = { class = "HUNTER", professions = { Tailoring = { skill = 40, max = 75, recipes = {} } } }
  WindfallCharMenu:Hide(); H.char.onOnClick(H.char)
  rows = {}; for _, r in ipairs(WindfallCharMenu.rows) do if r:IsShown() then rows[#rows+1] = r.text.text end end
  out[#out+1] = "header: two Hunties -> "..table.concat(rows, " || ").." | button="..tostring(H.char.text)
  WindfallCharMenu:Hide(); WindfallDB.chars["Huntie-Other Realm"] = nil
  B.money.onOnClick(B.money, "LeftButton"); pn("gold per hour on the bar")
  B.menu.onOnClick(B.menu); pn("Windfall icon again")
  -- at a vendor with the panel closed: it opens next to the vendor, and closes again after
  merchant = { 2320 }; MerchantFrame.shown = true; bags[2320] = 0
  ev2(nil, "MERCHANT_SHOW"); pn("vendor opens (route has thread to buy)")
  ev2(nil, "MERCHANT_CLOSED"); MerchantFrame.shown = false; pn("vendor closes")
  B.sparkle.onOnClick(B.sparkle); out[#out+1] = "bar: sparkle click -> sparkle="..tostring(WindfallDB.sparkle).." dim="..tostring(B.sparkle.icon.desat)
  B.sparkle.onOnClick(B.sparkle)
  -- logging in on a new character (a priest with Enchanting and Tailoring, nothing opened yet)
  player = "Jonjan"; class = "PRIEST"; playerLevel = 8
  gatherProfs = { 333, 197 }; profNames = { [333] = "Enchanting", [197] = "Tailoring" }
  local oldGPI2 = GetProfessionInfo
  GetProfessionInfo = function(i) local line = gatherProfs[i - 100]; if line then return profNames[line], 1, line == 333 and 12 or 30, 75, 0, 0, line, 0 end return oldGPI2(i) end
  ev(nil, "SKILL_LINES_CHANGED"); runTimers()
  local c = WindfallDB.chars["Jonjan-Realm"]
  out[#out+1] = "priest: listed at login -> "..tostring(c ~= nil).." professions: "..(c and ((c.professions.Enchanting and "Enchanting "..c.professions.Enchanting.skill.." unloaded="..tostring(c.professions.Enchanting.unloaded)) or "-") or "-")
  if WindfallPanel.shown then WindfallBar.menu.onOnClick(WindfallBar.menu) end
  WindfallBar.menu.onOnClick(WindfallBar.menu)
  local H2 = WindfallPanel.header
  local S2 = WindfallShoppingFrame
  -- this test session has picked Huntie by hand earlier; pick the priest the same way
  H2.char.onOnClick(H2.char)
  for _, r in ipairs(WindfallCharMenu.rows) do if r:IsShown() and r.key == "Jonjan-Realm" then r.onOnClick(r) end end
  local icons = {}; for _, b in ipairs(H2.icons) do if b:IsShown() then icons[#icons+1] = b.name..(b.icon.desat and "(grey)" or "") end end
  out[#out+1] = "priest: window -> char="..tostring(H2.char.text).." icons="..table.concat(icons, ",").." route="..tostring(S2.title2.text).." now="..tostring(S2.now.text).." button="..(S2.craft:IsShown() and tostring(S2.craft.text) or "-")
  openedLines = {}; S2.craft.onOnClick(S2.craft)
  out[#out+1] = "priest: Load clicked -> opened skill line "..tostring(openedLines[#openedLines]).." | "..tostring(S2.status.text)
  trade = { name = "Enchanting", id = 333, skill = 12, max = 75, recipes = {
    [7421] = { name = "Runed Copper Rod", item = 6218, rd = 0, reagents = { {2840, 1}, {10940, 1} } } } }
  ev(nil, "TRADE_SKILL_SHOW"); runTimers()
  out[#out+1] = "priest: after the window opened -> route="..tostring(S2.title2.text).." now="..tostring(S2.now.text).." unloaded="..tostring(WindfallDB.chars["Jonjan-Realm"].professions.Enchanting.unloaded)
  GetProfessionInfo = oldGPI2; player = "Huntie"; class = "HUNTER"
  return table.concat(out, "\n")
end)()''').replace("|cffffd700g|r","g").replace("|cffc7c7cfs|r","s").replace("|cffeda55fc|r","c"))
