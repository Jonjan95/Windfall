# Changelog

All changes to Windfall, newest first. After an update, type `/reload` in game (or restart the game when the notes say so).

## [0.2.53] - 2026-11-16

- **Enchanting: the plan knows about rods.** An enchant needs one particular rod (Runed Copper, Silver, Golden, Truesilver or Arcanite Rod) in your bags, and the plan did not look at that, so it could stop at a recipe you had no rod for. Now a recipe whose rod you do not have is only planned when the rod can be made at that skill, and then making the rod comes first as its own step (*Runed Silver Rod x1*), with its materials on the shopping list. A rod you already have, in bags or bank, is never made again.
  - Which rod a recipe needs comes from the game where it says so, otherwise from the skill the recipe is learned at (the last rod before it).

## [0.2.52] - 2026-11-16

- **The levelling plan holds still.** The plan used to be worked out from scratch every time your bags or skill changed, so buying materials or a price moving could change the recipes, and with them the shopping list (it could ask for more of what you had just bought). Now the plan is saved per character and profession: which recipe each skill point is made with. While you level and shop it stays exactly as it is, and the shopping list only counts down.
  - It is only worked out again for points it has no recipe for: a further goal, or a recipe that turned grey sooner than expected.
  - **New plan** (Levelling tab and shopping list) works the whole plan out again from current prices and what you have, for example after a new auction house scan.
- **Level to 75 / 150 / 225 / 300** replaces the *Plan to ...* button, on the Levelling tab and on the shopping list. The goal picked is lit and remembered per profession. Going further adds to the plan; what was already planned stays.
- The shopping list names the character in its title when it is for another character.

## [0.2.51] - 2026-11-16

- **Fix: the levelling route uses what you already bought.** The route is planned again at every skill-up, and it priced every craft as if all its materials still had to be bought. So after a price moved or you learned a new recipe, it could switch halfway to something you had not bought for (Small Silk Pack, needing Heavy Leather, at 134 Tailoring). Materials in your bags and bank now count as already paid for: the route uses them up first and only then goes for the cheapest new materials. A material the auction house has no price for is fine too, as long as you have it.

## [0.2.50] - 2026-11-16

- **Shopping list as a drawer.** At the auction house and at vendors a small Windfall tab sits on the window's right edge. Click it to pull the shopping list out beside the window and click again to push it back in; it stays as you left it the next time. No second window opens by itself any more.
  - It lists what the route of the profession picked in Windfall still needs: have / need, what is left to buy and its cost.
  - *Show* at the auction house, *Buy* at a vendor that sells it, and *Buy all here*. Materials that are cheaper from a vendor say *Vendor* at the auction house.
  - *Plan to 150 / 225 / 300* extends the list.
  - *Shopping list* on the Levelling tab opens the same drawer beside the profession window.
- **Fix: Show after buying.** After buying something at the auction house, the next *Show* left the auction house on the old item's page without searching, until you closed and reopened it. Windfall went back to the list by clicking the Buy tab, but the auction house keeps that tab disabled while you are on an item's page. It now goes back the way the page's own Back button does, so every *Show* searches.

## [0.2.49] - 2026-11-16

- **Farming tab:** the farming mode button and its two sliders no longer sit on top of the node sparkle switches. Everything under the zones is one column now: node sparkles, then farming mode with *Map terrain* and *Map size*, then the button. *Clear* moved up next to the zones' title, and the zone list shows the best 6.

## [0.2.48] - 2026-11-16

- **Farming mode: the map's terrain can show.** A *Map terrain* slider on the Farming tab (or `/wf hud terrain 30`) fades the map itself in behind the dots, from 0 (only the dots, as before) to 100 (the whole map), so you can find your way by roads, mountains and water. With a minimap skin, its borders, buttons and text stay hidden while the mode is on.
- A *Map size* slider sits next to it (the same as `/wf hud 70`).

## [0.2.47] - 2026-11-16

- **Farming mode: hold Alt to point at a dot.** While Alt is held the overlay takes the mouse, so pointing at a node dot shows the game's tooltip with what it is. Let go and every click and mouseover goes through to the world again. (Not in combat: the game does not let addons change the minimap then.)
- **Names beside nodes.** GatherMate2's nodes on the overlay have their name written beside them, so you can tell a Dreamfoil spot from a Plaguebloom spot without pointing. `/wf hud names` switches the names off or on. The game's own live dots cannot be named (addons are not told where they are); a live dot on a named spot is that herb.
- GatherMate2's pins on the overlay no longer take clicks, except while Alt is held (for their tooltip and menu).

## [0.2.46] - 2026-11-16

- **Farming mode stays centred.** With a minimap skin (EllesmereUI), the map was pushed off to the side: the skin clamps the minimap to the screen with margins and puts it back in its own place and size. While farming mode is on, the minimap is no longer clamped and the skin's attempts to move, resize or show it do nothing; its position is also checked continuously. Switching the mode off hands the map back to the skin, which restores its own look.
- **Round overlay** with a minimap skin that uses a square map: the dots show in a circle around you while the mode is on, and the square map comes back afterwards.

## [0.2.45] - 2026-11-16

- **Farming mode:** the minimap, large and see-through in the middle of the screen, so herb and ore dots show around your character instead of up in the corner. The terrain is invisible, the map turns with you and lets every click through, and GatherMate2's remembered nodes move onto it. Switching it off puts the minimap back exactly as it was.
  - Switch it with the map icon on the bar, the *Farming mode* button on the Farming tab, `/wf hud`, or a key binding (Options > Keybindings > AddOns > Windfall).
  - `/wf hud 70` sets its size in percent of the screen's height (40 to 100, 80 to start with).
  - The game does not let addons move the minimap in combat, so switching waits until combat ends.

## [0.2.44] - 2026-11-16

- **Levelling guides for Herbalism, Mining, Skinning and Fishing.** Gathering professions now sit with the crafting ones in the header and in the character menu, for every character. On the Levelling tab they show a guide instead of a route:
  - the stretches of skill, with the one you are in marked and the ranks to train on the way
  - what to pick, mine or skin in each stretch, coloured by what it gives at your skill (a point every time, most times, now and then, or none)
  - the zones to find it in
  - for Fishing, the waters by the skill at which no fish get away, with the Expert book and the Artisan quest
- The skill levels and zones are Classic's. On Recipes a gathering profession without recipes says so.
- **Fix:** a levelling route that crossed a rank (Journeyman at 50, Expert at 125, Artisan at 200, or the First Aid and Cooking book and quest) threw an error in the profession window instead of showing the step.
- First Aid's route is tested with its Expert book step.

## [0.2.43] - 2026-11-16

- **Five tabs that never change:** Recipes, Levelling, Make money, Farming and Fishing sit under the profession window whatever you are looking at. (Fishing is there when the character you are on fishes.) The header's character and profession icons show on Recipes and Levelling, where they apply; Fishing and Farming are no longer icons among the professions.
- **Every profession on your account in one menu.** The character button lists each character with its professions under it. Click a profession to go straight to it; click a name for that character. Shift-click a name to forget the character.
- **Make money:** every recipe of every character that sells for more than its materials cost, best profit first, with who makes it, what it costs and sells for, and how many can be made from what that character holds. Search it, or tick *Only what can be made now*. Click a row to open the recipe on its character. A recipe several characters know is listed once.
- **Levelling:** *Plan to 150 / 225 / 300* and *Shopping list* sit under the route. A profession Windfall has not read yet gets a *Read its recipes* button.
- **Farming** shows the session and your best zones side by side, with the node sparkle switches under the zones.
- **Fixes for tabs misbehaving:**
  - Windfall no longer hides the game's own pages while it shows; they stay as they are underneath, invisible. Hiding them made the window close itself when a profession closed or changed, and brought back stale pages on top of each other when you left Windfall.
  - Create for a profession that is not the open one opens it and comes straight back to Windfall.
  - Leaving Windfall and coming back keeps the tab you were on.

## [0.2.42] - 2026-11-15

- **One Fishing, one Farming.** The header now holds your crafting professions, then **Fishing**, then **Farming**, the same on every character:
  - **Farming** has **Session** and **Zones**. Session shows gold per hour, the clock, the total, your gathering skills, what you have looted, and switches for herb, ore and fishing pool sparkles.
  - **Fishing** has only fishing: the fishing key and its options, how many fish get away where you are, and the fishing pool sparkle. If the character has Camping recipes (Fish Bowl), a **Recipes** tab shows them.
  - Herbalism, Mining and Skinning no longer each open a copy of the same session; their skills are on Farming's Session page.
- **Opens on the character you are playing**, every time the window opens. Picking another character still works until you close it.
- The title and the round portrait now show Windfall's profession instead of the game's own.
- Fishing no longer shows up twice (once as a question mark).
- Tooltips in the header open below it instead of over the title.

## [0.2.41] - 2026-11-15

- **Everything Windfall does is now in the game's profession window.** The Windfall tab's header shows every profession of the character you pick, and the tabs under the window change with it:
  - **Crafting** (Tailoring, Alchemy…): **Recipes** and **Levelling**, as before.
  - **Herbalism, Mining and Skinning:** **Session** shows gold per hour, time, total and what you have gathered with prices, with Start/Pause, Gathering/All loot, Reset and a sparkle switch for that kind of node. **Zones** ranks zones by gold per hour, with Clear history.
  - **Fishing:** Session and Zones, plus **Fishing** with the fishing key, all its options and how many fish get away here.
  - A character without a gathering profession gets **Farming** in its header for the same pages.
  - The few general settings (node sparkles, interact back to default, show the bar) are under the gear at the top right.
- **Opening it:** the Windfall icon on the bar, the key binding and `/wf` open the profession window on Windfall (or close it). Clicking the gold per hour on the bar opens the Session page. `/wf prof`, `/wf session`, `/wf zones` and `/wf settings` open those pages. Gathering and fishing skills are saved for every character too.
- **Removed:** the separate Windfall window and the minimap button. The shopping list stays: it docks next to the auction house or a vendor when there is something to buy there, and *Shopping list* on the Levelling page opens it beside the profession window.

## [0.2.40] - 2026-11-15

- **Cleaner Windfall page in the profession window:**
  - The window's own pages (like the overview's skill bars) no longer show through. They come back when you click one of the game's tabs.
  - **Recipes** and **Levelling** are tabs under the window, like the game's own.
  - The header has a character button with a drop-down arrow in the class colour, framed profession icons (hover for skill), and a framed skill bar that fills the rest of the row.
  - The recipe list sits in its own box with a scroll bar. Categories collapse with +/-; while you search, every category stays open.
  - The recipe shows its reagents in two columns with have/need on the icon (red when short) and what other characters hold. Below them: To craft, Sells for, Profit and Skill-up, then Create All and Create.
- **Reagents for every recipe.** Recipes counted as learned before their profession window was read showed no reagents (and a cost of 0). Windfall now reads them from the game.

## [0.2.39] - 2026-11-15

- **Windfall inside the game's profession window.** A Windfall tab now sits with the profession tabs on the right side of the profession window. Click it and the window shows Windfall's page in the window's own layout:
  - the recipe list grouped into the game's categories, with search and how many you can make
  - the picked recipe with its reagents (what you have and need, and what your other characters hold), cost, profit and skill-up chance, plus Create and Create All
  - at the top, a character button (full names) and that character's profession icons with the skill bar, so you can switch between any character's professions without leaving the window
  - **Recipes** and **Levelling** views; Levelling lists the route step by step
- It opens on the profession you were looking at; click any of the game's profession tabs to go back. Create works for the character you are on; other characters' recipes are for looking. *Shopping list* opens the Windfall window's Levelling tab with the Show and Buy buttons.
- Recipes now remember their category from the profession window (open each profession once to fill it in).

## [0.2.38] - 2026-11-15

- **Full character names.** Forever characters have a surname, and Windfall now uses the whole name ("Zivv Gg", "Zivv Zniper") everywhere. Characters with the same first name used to share one save; now each has its own. An old save under just the first name goes to the first character of that name to log in, if its professions match.
- **Your whole account in one place.** Every character's bags are saved as they change, and its bank whenever you open it. Wherever Windfall counts materials it uses the character you are looking at, and also shows what your other characters hold.
- **Recipes tab like the profession window:** the recipe list on the left (with how many you can make), and the picked recipe on the right: its reagents with how many that character has and needs, what your other characters have, cost, sale value, profit, and its skill-up chance. Look at any character's professions from any character.
- **A maxed profession's Levelling tab** now lists the recipes that earn the most at today's prices, instead of only saying it is done.
- The shopping list's counts include the bank, and show what is on other characters.

## [0.2.37] - 2026-11-15

- **Every character shows up as soon as you log in**, with its crafting professions and skill, and the window opens on the character you are playing. Professions whose recipes Windfall has not read yet have a grey icon.
- **Load from the Levelling tab:** for a profession not read yet, the Levelling tab says so and its button reads *Load Enchanting* (for example). One click opens the profession window; its route appears straight after.
- When no recipe can be planned yet because nothing has a price, the Levelling tab now says to scan the auction house, instead of "Done".

## [0.2.36] - 2026-11-15

- **Nothing runs off the bottom of the window any more.** Every tab now fills the window, so "Left to buy" and the status line stay at its bottom, also when you plan further.
- **Characters with the same name are told apart:** the character list adds the realm when two of your saved characters share a name. They were always saved separately; now you can see which is which.
- **All materials count in "Left to buy"**, also when a long route needs more than fit in the list, and the line says how many more there are.

## [0.2.35] - 2026-11-15

**A real WoW window, with professions first.**

- **The Windfall window** now looks like the game's own windows: portrait, title, close button and tabs along the bottom, like the Character window. The portrait shows the profession you are looking at.
- **Pick any character and profession** at the top: the character button lists everyone you have saved with their professions, the icons next to it switch profession, and a skill bar shows where you are.
- **Tabs:** *Levelling* (the route for the picked profession, opening straight on it, with *Plan to 150* to plan further), *Recipes* (cost, sale value and profit), *Farming* (gold per hour, with your zones behind the Zones button) and *Settings*.
- **Less to find your way through:** the cycle buttons, the separate plan view and the shopping list from clicking a recipe are gone; the Levelling tab does all of it. Shift-click a character in the character list to forget it.

## [0.2.34] - 2026-11-15

**One bar and one panel instead of many windows.**

- **The bar** stays on screen with your gold per hour and session time, a fish switch for the fishing key, a flower switch for node sparkles, and the Windfall icon. Drag it where you like.
- **The panel** replaces the separate windows. The Windfall icon, the minimap button or `/wf` opens it on the page you used last, and the menu along its top switches between Farming, Zones, Professions, Route and Settings.
- **At the auction house or a vendor** the panel docks next to it on the Route page when there is something there to buy, and goes back to its own spot afterwards (closing again if it only opened for that).
- **Every crafting profession:** Cooking and First Aid get their Expert rank from a vendor book and Artisan from a quest, and the route now says so instead of "train". Enchanting crafts remind you to click the item to enchant.
- "No priced recipe" no longer hides the route's last step.
- The bar and the panel start where they like the first time; move them once and they stay.

## [0.2.33] - 2026-11-15

- **Enough materials for unlucky skill-ups.** Yellow and green crafts give a point only some of the time, and the route used to buy for the average number of crafts, so about half the time you ran short. It now adds a spare worked out from each step's chance, enough about five times out of six. Orange crafts never miss and get no spare.

## [0.2.32] - 2026-11-15

- **Ranks you are too low for no longer stop the route.** When a rank needs a higher character level (Expert needs level 20), the route keeps you crafting up to your current skill cap and then says how far you are capped and why. Once you reach the level, the "train" step appears where it should.

## [0.2.31] - 2026-11-15

- **Show no longer leaves the auction house stuck searching.** When you Show the next material while the auction house is still on the last one's page, Windfall first goes back to the Buy tab, as changing tab by hand did. If the auction house is busy it waits until it is ready, and if the listings still do not come it starts over once by itself.

## [0.2.30] - 2026-11-15

- **The route no longer stops at a rank you have already trained.** It reads your skill and skill cap straight from the game, so training Journeyman (or any skill-up) moves the route on right away, without opening the profession window.

## [0.2.29] - 2026-11-15

- **Accurate skill-up chances.** Windfall now knows when every trainer recipe turns yellow and grey, taken from the game's own recipe data for Forever. A recipe gives a point every time while orange, then less and less until it goes grey, and the plan shows that chance (for example "Light Leather 50%").
- **The route no longer favours low-chance crafts.** A skill point's cost is what the craft costs after resale, divided by the chance, plus a little effort per craft. Selling a craft never makes levelling count as earning money, which used to make green recipes look good. Recipes with at least a 50% chance come first, and a step that can only be done with low chances says "low chance".

## [0.2.28] - 2026-11-15

- **Learning a recipe updates the route straight away.** When you learn a recipe or a rank at the trainer, the route and the levelling plan notice it at once, so the Craft button shows while you are still at the trainer. Before, they only knew after you opened the profession window again.

## [0.2.27] - 2026-11-15

- **Buy from vendors:** with a shopping list open at a vendor that sells something on it (Coarse Thread, for example), that row gets a Buy button for exactly what you still need, and *Buy all here* buys everything the vendor has on your list. The list docks next to the vendor window.
- **Craft from the route:** a route now shows the step to do now at the top, e.g. "Light Armor Kit x14", with a Craft button. The first click opens your profession window if it is closed, the next crafts as many as your bags allow. As your skill goes up the route moves on to the next step by itself, and tells you when to visit the trainer for a new recipe or rank.

## [0.2.26] - 2026-11-15

- **Show instead of Buy:** at the auction house, a material's Show button now opens its page in the auction house itself, with the amount you still need filled in. You look at the listings and press Buy Now there. Windfall no longer buys anything on its own.

## [0.2.25] - 2026-11-15

- **Load no longer causes an "action blocked" error.** The game only lets an addon open a profession window on a real click, so the Load button now opens one profession per click ("Load Leatherworking", then "Load Tailoring") and leaves the window open for you to close. It also shows next to Route while a profession of this character is still to load.

## [0.2.24] - 2026-11-15

- **Load my professions can be clicked now.** The empty recipe rows lay on top of it.

## [0.2.23] - 2026-11-15

- **Load my professions:** when a character has nothing saved, the Professions window shows a button that opens each of its crafting professions in turn, saves them and closes the window again. No need to open them by hand.
- **Forget this now needs Shift-click,** so a slip next to the Route button no longer removes a profession.

## [0.2.22] - 2026-11-15

- **Buy buttons now show when you open a shopping list at the auction house.** Before, they only showed if the list was already open when you walked up to it. The list also docks next to the auction house either way.
- The shopping list is wider, so long prices no longer run into the amounts.

## [0.2.21] - 2026-11-15

- **Levelling route:** in the Professions window's levelling plan, *Route to 150* (right-click for another target) works out every step from your skill to the target - which recipe, roughly how many crafts, where to train the next rank - and adds up all the materials, less what is in your bags. The craft counts are an estimate.
- **Buy at the auction house:** with a shopping list open, it docks next to the auction house and every material gets a Buy button. Click Buy to find the item, click again to buy the amount you still need at the cheapest prices, then Confirm once the auction house has told you the real total. Nothing is spent before Confirm. Things a vendor sells cheaper get no Buy button.

## [0.2.20] - 2026-11-15

- **Levelling plan** in the Professions window (the mode button): the cheapest way up from your current skill. It mixes the recipes you know with the ones the trainer can teach you now, ranks them by what a skill point costs (a craft that sells pays for part of itself), and shows the trainer's price. Below that: the next rank to train and what the trainer teaches next. Recipe colours for recipes you have not learned are a guess until you learn them.
- **Shopping list:** click a recipe in the Professions window for what to buy for a number of crafts, less what is in your bags, with prices. It updates as your bags fill.
- Recipe data for Forever's trainers comes from the What's Training? addon by Sveng (MIT licence).

## [0.2.19] - 2026-11-15

- **Sparkles only on what you can gather:** herbs need Herbalism, ore needs Mining and fishing pools need Fishing. A character without the profession gets no sparkle or icon for those nodes. Learning a profession counts straight away.

## [0.2.18] - 2026-11-15

- **No more icons over trainers and vendors while sparkles are on.** Sparkles make soft targeting reach all round you, so every nearby NPC got the game's interact icon. That icon is now off while sparkles are on, unless the nearest thing is a node, and comes back when you switch sparkles off.

## [0.2.17] - 2026-11-15

- **Professions:** a new window (the anvil icon in the title bar, or `/wf prof`) shows every recipe a character knows with what the reagents cost, what the result sells for after the auction house cut, and the profit. Switch to *Cheapest skill-up* to see which orange, yellow and green recipes level the profession for the least gold. Open each profession window once on every character, and your alts show up too. No pop-ups.

## [0.2.16] - 2026-11-15

- **No more name plates on guards and vendors while sparkles are on.** The name plate the sparkle sits on is now switched on only while the nearest thing is a herb, ore vein or fishing pool.

## [0.2.15] - 2026-11-15

The first release on CurseForge. **Restart the game once** after installing, so the icon and key bindings load.

- **Gold per hour** for what you gather or loot, priced with Auctionator's scans (or the vendor price when that is higher). Two views: *Gathering* counts only herbs, ore, skins and fish, so killing mobs on the way does not pull your rate down; *All loot* counts everything plus coins.
- **Zone history:** Reset saves the session per zone, and the Zones window ranks your zones by gold per hour.
- **One-button fishing key** you switch on and off. On, it casts and reels in; off, the key works as normal. Keyboard keys, mouse buttons and the wheel all work.
- **Fishing helpers,** each a checkbox in the settings: put a lure on when the pole has none, equip the pole and put your weapons back after, a louder bobber splash, double right-click to cast, auto loot while fishing, and switching off after 10 idle minutes. While fishing, the window shows how many fish get away in the zone you are in.
- **Node sparkles:** the nearest herb, ore vein or fishing pool gets a sparkle. Quest objects, chests and NPCs are left alone. The game only picks up nodes within about 15 yards.
- **Interact back to normal:** when the line comes in or sparkles are switched off, the interact key goes back to the game's default range.
- **Settings window** (the gear icon in the title bar), a minimap button and key bindings under Options > Keybindings > AddOns > Windfall.
