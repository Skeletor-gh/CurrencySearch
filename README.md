## Currency Search

A lightweight World of Warcraft add-on that adds a search box to the currency pane.

### What this branch now includes

This branch consolidates the latest stability improvements that were added in recent updates:

- Safer filtering behavior while currency transfer mode is active.
- Deferred UI/provider mutations during combat lockdown and transfer states.
- Better Token UI load/install timing to avoid protected-function errors.
- More resilient transfer-state detection across legacy and newer Token UI APIs.
- A conservative safety mode that disables filtering on clients with account-currency transfer APIs to avoid tainting protected transfer actions.

### Compatibility notes

Currency Search avoids direct frame mutations during sensitive UI states and restores Blizzard's original data provider when needed, which improves coexistence with other add-ons that also interact with the currency frame.

On modern Retail clients where Blizzard exposes account-currency transfer APIs, Currency Search now refuses to install its list filtering hook and prints a one-time chat notice. This is intentional to prevent `ADDON_ACTION_FORBIDDEN` taint during protected transfer operations.
