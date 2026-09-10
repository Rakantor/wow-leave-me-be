# Leave Me Be development notes

## Project

Leave Me Be is a standalone World of Warcraft: Midnight addon that filters
incoming player whispers. The current targets are retail patches 12.0.7 and
12.1; guard any API that only exists on one of them.

## References

- WoW addon API documentation:
  https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
- Reference implementation and product behavior:
  https://github.com/funkydude/BadBoy_Levels
- CurseForge automatic packaging:
  https://support.curseforge.com/support/solutions/articles/9000197281-automatic-packaging

Check the API documentation before introducing or changing WoW API calls.
BadBoy_Levels may be used to understand behavior and design patterns, but do
not copy its code without first checking its license and attribution
requirements.

## Conventions

- Keep `## Interface` in `LeaveMeBe.toc` aligned with the target retail client.
- Keep the addon standalone unless a dependency is intentionally introduced.
- Put persistent user preferences in `LeaveMeBeDB`.
- Store filtered whisper history in the separate `LeaveMeBeLog` SavedVariable.
  Log entries are append-only unless a future retention policy is explicitly
  requested. An entry's `timestamp` is when the whisper arrived, and an
  optional `reason` explains a non-standard entry (currently only
  `level-check-interrupted`).
- Keep chat event filters free of side effects because WoW can invoke a filter
  once for every chat frame showing the event.
- Guard chat payloads with `issecretvalue` before comparing, transforming, or
  using them as table keys; Midnight can mark chat values secret during
  messaging lockdown.
- Every automatic reply must begin with the immutable prefix
  `Leave Me Be (Addon):`. Hide its local `CHAT_MSG_WHISPER_INFORM` echo and
  never auto-reply to another message bearing that prefix, to avoid loops.
  Rate-limit automatic replies to once per sender every 60 seconds.
- Allowlist and blocklist keys are lowercased with all spaces removed, so
  matching ignores both case and spacing. The stored value is the spelling the
  player entered, purely so the settings list can show it back to them; older
  entries hold `true`, so test membership with `~= nil` rather than `== true`.
  A bare `name` entry matches that character on every realm; a `name-realm`
  entry matches only that realm, including when a same-realm whisper arrives
  without the suffix.
- `blockAllWhispers` is the main filtering toggle. Explicit blocklist entries
  are still blocked when it is off; friends, guild, group, contacts, and the
  allowlist are exceptions when it is on.
- Premade Group Finder automation is opt-in. It enables blocking after the
  player appears to own an active listing as home-group leader (or solo owner)
  for one second. Keep this settling delay: accepting an invite can briefly
  report an active listing before the home-group roster arrives. Blocking is
  disabled after a fixed 15-second grace period. Relisting cancels the pending
  disable. It must not disable a blocking state that automation did not enable,
  and turning automation off must hand back a blocking state that it did enable.
- The level exception defaults to enabled with `minimumLevel = 42`. Unknown
  levels are resolved asynchronously through a temporary character-friend
  entry marked `LeaveMeBe:level-check`; remove that entry after resolving or
  timing out, and do not log or auto-reply until the result is known. The one
  exception is logout, which ends every lookup in flight: log those whispers
  with `reason = "level-check-interrupted"` and send no reply.
- Resolved levels are cached per session. A level at or above the minimum
  never expires (levels only rise); a lower level expires after 60 seconds so
  a level-up can be discovered, and a failed lookup is retried after 30
  seconds. The live friends list always takes precedence over the cache.
- A character friend can only be added on our own realm or a connected one,
  and only while the friends list has room, so do not start a level lookup
  that cannot succeed. Treat an unresolvable level as "no exception applies"
  rather than hiding the whisper until the lookup times out. `ERR_FRIEND_LIST_FULL`
  is the only signal the client gives for a failed add; give up on the checks
  in flight without caching a level so they can be retried once a slot frees.
  Character friends can also be unavailable altogether (12.1 without the
  legacy friend system); then no lookup can start, and the addon explains
  this once per session, as it does for a full list.
- Hide only the system messages the automatic friend add or remove produces,
  matched by exact text for that friend's name, never every system message
  in a time window. The add-side window must cover the whole lookup timeout
  because the add is confirmed asynchronously.
- Whisper popouts (`whisperMode` popout or popout-and-inline) are opened by
  Blizzard before message filters run. `ChatWindows.lua` closes a window that
  was opened for a filtered whisper and is still empty, and reopens one when a
  deferred whisper is replayed after its level resolves. Never close a window
  that already holds messages or that was not opened for the filtered event.
- Keep the automatic reply editor on the main settings page. Keep allowlist
  and blocklist management in their own canvas subcategories.
- Prefer local functions and the addon namespace (`local _, LMB = ...`) over
  new globals.
- Verify all Lua against WoW's Lua runtime; do not assume newer standard-Lua
  features are available.
- Keep `## Version` in `LeaveMeBe.toc` release-ready. Run `./release.sh` to
  create and push the matching annotated Git tag. Only committed changes are
  included in a release.
