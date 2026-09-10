Run from the repository root with Lua 5.1:

```sh
lua5.1 tests/run.lua
```

The suite loads the addon into a fresh environment per test, with simulated
events, timers, friends, and chat windows. It checks filtering decisions,
lookup failures and cleanup, cache expiry, contacts, reply suppression,
popouts, logout logging, and automation ownership. Tests are excluded from
the packaged addon.

These tests cannot reproduce WoW's native taint and secret-value machinery.
In-client verification should cover inline, separate-tab, and combined
whispers, ordinary whispers during an automatic reply, and `/reload` during
a pending level check. Check that existing conversation tabs remain open and
that chat continues working during messaging lockdown.
