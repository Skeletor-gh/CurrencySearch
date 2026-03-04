CurrencySearch

CurrencySearch is a World of Warcraft addon for the 12.x API (Midnight era) that adds a lightweight search box to the currency tab.

Features
- Adds a small inline search box to the currency tab UI.
- Filters visible currency rows in real time while typing.
- Includes an embedded clear button through WoW's standard `SearchBoxTemplate`.
- Enabled by default when the addon loads.
- Keeps functionality minimal and scoped to the currency pane.

Commands
- `/cs on` or `/cs enable` to enable CurrencySearch.
- `/cs off` or `/cs disable` to disable CurrencySearch.
- `/cs` to print help.

Behavior details
- When disabled, the search box is hidden and any active filter text is cleared.
- When enabled, the search box appears when the currency pane is available.
- Headers are kept visible during filtering so category context remains readable.

Installation
1. Place the `CurrencySearch` folder in your `World of Warcraft/_retail_/Interface/AddOns/` directory.
2. Ensure both `CurrencySearch.toc` and `CurrencySearch.lua` are inside that folder.
3. Launch or reload WoW and enable the addon from the AddOns list if needed.

Notes
- The addon does not add an options panel.
- The addon avoids replacing Blizzard functions and uses hooks/events for updates.
- If Blizzard significantly changes currency frame internals in future patches, minor adjustments may be required.
