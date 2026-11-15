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
StaticPopupDialogs={} function StaticPopup_Show(n) StaticPopupDialogs[n].OnAccept() end
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
function IsAltKeyDown() return false end function IsControlKeyDown() return false end function IsShiftKeyDown() return false end
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
local vend = {[2589]=13,[4306]=150,[7909]=2500}
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
function GetProfessions() return nil, nil, nil, skill and 1 or nil end
function GetProfessionInfo() return "Fishing", 1, skill[1], skill[2], 0, 0, 356, skill[3] end
function UnitFactionGroup() return faction end
soft = nil plateMissing = false sparkleShown = false
function UnitGUID(u) if u == "softinteract" and soft then return soft.guid end end
do local oldUnitName = UnitName
  function UnitName(u) if u == "softinteract" then return soft and soft.name end if oldUnitName then return oldUnitName(u) end end end
C_NamePlate = { GetNamePlateForUnit=function(u) if u == "softinteract" and soft and not plateMissing then return UIParent end end }
do local oldNT = C_Timer.NewTicker
  C_Timer.NewTicker = function(d, fn) if d == 0.2 then sparkleTick = fn; return { Cancel=function() sparkleTick = function() end end } end return oldNT(d, fn) end end
Auctionator = { API = { v1 = { GetAuctionPriceByItemID=function(caller,id)
  local p={[13466]=2840,[10620]=4000,[8170]=900,[7909]=30000,[4306]=100} return p[id] end } } }
''')
rt.execute(open(sys.argv[2], encoding="utf-8").read())
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
    out[#out+1] = "sparkle: "..label.." -> "..fr.." icon="..tostring(cvars.SoftTargetIconGameObject).." interact="..tostring(cvars.SoftTargetInteract).." range="..tostring(cvars.SoftTargetInteractRange).." plates="..tostring(cvars.SoftTargetNameplateInteract)
  end
  cvars.SoftTargetInteract = "0"; cvars.SoftTargetInteractRange = "10"; cvars.SoftTargetIconGameObject = "0"; cvars.SoftTargetNameplateInteract = "0"; cvars.SoftTargetInteractArc = "0"
  sp("sparkles off by default")
  SlashCmdList.WINDFALL("sparkle"); sparkleTick(); sp("switched on, nothing near")
  soft = { guid = "GameObject-1", name = "Plaguebloom" }; sparkleTick(); sp("Plaguebloom nearby")
  soft = { guid = "GameObject-2", name = "Rich Thorium Vein" }; sparkleTick(); sp("Rich Thorium Vein (by name rule)")
  soft = { guid = "Creature-3", name = "Scourge Champion" }; sparkleTick(); sp("quest mob")
  soft = { guid = "GameObject-4", name = "Sturdy Locked Chest" }; sparkleTick(); sp("chest")
  soft = { guid = "GameObject-5", name = "Stonescale Eel Swarm" }; sparkleTick(); sp("fishing pool")
  SlashCmdList.WINDFALL("settings"); local sf2 = WindfallSettingsFrame
  for _, c in ipairs(sf2.checks) do if c.label.text == "    Fishing pools" then c.checked = false; c.onOnClick(c) end end
  sparkleTick(); sp("fishing pools unticked")
  soft = { guid = "GameObject-6", name = "Peacebloom" }; plateMissing = true; sparkleTick(); sp("herb, nameplate not there yet")
  plateMissing = false; sparkleTick(); sp("nameplate appears")
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
  return table.concat(out, "\n")
end)()''').replace("|cffffd700g|r","g").replace("|cffc7c7cfs|r","s").replace("|cffeda55fc|r","c"))
