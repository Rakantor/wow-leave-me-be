# Leave Me Be

Leave Me Be is a whisper filter for World of Warcraft: Midnight.

## Features

- Block unwanted player whispers without showing them in chat.
- Automatically enable blocking while leading a listed Premade Group Finder
  group.
- Send blocked players a customizable automatic reply.
- Allow friends, guild members, group members, and players above a chosen
  level.
- Manage personal allowlists and blocklists.
- Save filtered messages for later reference.

## Installation and settings

Place the `LeaveMeBe` folder in:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

Configure the addon under **Options → AddOns → Leave Me Be**.

## Commands

```text
/lmb                         Show all commands
/lmb status                  Show the current state
/lmb on|off                  Turn whisper blocking on or off
/lmb allow <name>            Add a player to the allowlist
/lmb unallow <name>          Remove a player from the allowlist
/lmb block <name>            Add a player to the blocklist
/lmb unblock <name>          Remove a player from the blocklist
/lmb reply <message>         Change the automatic reply
/lmb reply reset             Restore the default reply
```

## Inspiration

Leave Me Be was inspired by
[BadBoy_Levels](https://github.com/funkydude/BadBoy_Levels).
