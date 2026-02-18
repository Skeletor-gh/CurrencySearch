## Currency Search

A lightweight World of Warcraft add-on that adds a search box to the currency pane.

### What this branch now includes

This branch consolidates the latest stability improvements that were added in recent updates:

- Safer filtering behavior while currency transfer mode is active.
- Deferred UI/provider mutations during combat lockdown and transfer states.
- Better Token UI load/install timing to avoid protected-function errors.
- More resilient transfer-state detection across legacy and newer Token UI APIs.
- A default strict mode that conservatively disables filtering install on clients exposing account-currency transfer APIs.
- An optional compatibility mode that keeps install/filter enabled with transfer/combat mutation guards.

### Compatibility notes

Currency Search avoids direct frame mutations during sensitive UI states and restores Blizzard's original data provider when needed, which improves coexistence with other add-ons that also interact with the currency frame.

Currency Search now stores a mode in `CurrencySearchDB.mode`:

- `strict` (default): conservative behavior that blocks install/filter on clients exposing account-currency transfer APIs.
- `compat`: allows install/filter while retaining transfer/combat runtime guards.

Use `/currencysearch mode strict` or `/currencysearch mode compat` to switch modes at runtime. Enabling compatibility mode prints an explicit warning about increased taint risk (including potential `ADDON_ACTION_FORBIDDEN` during transfer UI interactions).
