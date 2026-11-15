# Changelog

All changes to Windfall, newest first. After an update, type `/reload` in game (or restart the game when the notes say so).

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
