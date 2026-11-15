# Changelog

All changes to Windfall, newest first. After an update, type `/reload` in game (or restart the game when the notes say so).

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
