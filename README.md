<img src="docs/icon-512.png" width="96" align="right" alt="Windfall icon">

# Windfall

A World of Warcraft Forever addon that shows what your farming is worth: the value of what you gather or loot, priced with Auctionator's scans, and your gold per hour. It also has a one-button fishing key you can switch on and off.

## Gold per hour

- **Two views:** *Gathering* counts only herbs, ore, skins and fish (mob loot does not pull your rate down). *All loot* counts everything you loot, plus coins. Switch with the button in the window or a right-click on the minimap button; nothing is lost when you switch.
- **Prices:** Auctionator's last scanned price, or the vendor price when that is higher or the item was never scanned.
- **Calm numbers:** the window redraws when you loot something or once a minute.
- **Zone history:** Reset saves the session per zone. The Zones window ranks zones by gold per hour, so you can tell which spot is worth farming.

## Professions

The anvil icon in the title bar (or `/wf prof`) opens a window with every recipe a character knows: what the reagents cost (the cheaper of the auction house and a vendor), what the result sells for after the 5% auction house cut, and the profit. The *Levelling plan* lists the cheapest way up from your current skill, mixing the recipes you know with the ones the trainer can teach you now, and shows the next rank and the recipes that unlock next. Click a recipe for a shopping list: what to buy for a number of crafts, less what is in your bags. *Route to 150* (right-click for another target) works out every step up to the target and all the materials for it. At the auction house the shopping list docks next to it with a Show button per material: it opens that item's page in the auction house with the amount you still need filled in, and you press Buy Now there. At a vendor that sells something on the list, it gets a Buy button (and *Buy all here*) instead. A route also shows the step to do now with a Craft button, and moves on as your skill goes up. Recipes are saved when you open a profession window, on every character, so alts show up too.

Trainer recipe data comes from **What's Training?** by Sveng (MIT licence, see `Data/THIRD_PARTY.md`); `tools/import_recipes.py` rebuilds it.

## Node sparkles

Switched on in the settings, the nearest herb, ore vein or fishing pool close by gets a sparkle and the game's gather icon. Quest objects, chests and NPCs get nothing. Each kind can be switched off on its own.

When Windfall is done with the interact key (the line comes in, or sparkles are switched off), it puts it back to the game's defaults: 10 yards, in front of you. The rest of the time it leaves the interact settings alone, so other addons can set them as they like. This is a setting too.

## Fishing key

- **One key:** while on, a press casts Fishing and the next press reels in the bobber. Off, the key does whatever it normally does. Keyboard keys, mouse buttons and the wheel all work.
- **Lures:** puts the best lure your skill allows on the pole when it has none.
- **Pole:** equips your best fishing pole when you switch on, and puts your weapons back when you switch off.
- **Louder splash:** sound effects to full and music and ambience to a quarter while the line is out.
- **Also:** double right-click to cast, auto loot while fishing, switches off after 10 idle minutes, and a line telling you how many fish get away in the zone you are in.

Every option is a checkbox in the settings window (the gear icon in the title bar).

## Commands

| Command | What it does |
|---|---|
| `/wf` | Show or hide the window |
| `/wf settings` | Settings window |
| `/wf zones` | Zone history |
| `/wf gather`, `/wf loot` | Switch view |
| `/wf start`, `/wf pause` | Start or pause the clock |
| `/wf reset` | Save the session to the zone history and start over (`/wf discard` throws it away) |
| `/wf fish` | Fishing key on or off |
| `/wf fishkey` | Choose the fishing key |
| `/wf sparkle` | Node sparkles on or off |
| `/wf prof` | Professions window |

Key bindings for the fishing switch, node sparkles and the window are under Options > Keybindings > AddOns > Windfall.

## Development

- `tools/sim_test.py` runs the addon against a stubbed game API and prints a simulated session.
- `tools/make_icon.py` draws `Media/icon.tga` and `docs/icon-512.png`.
