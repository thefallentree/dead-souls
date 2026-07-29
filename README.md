# The Dead Souls 3.8.6 with FluffOS v2019

## Current status

- [X] : Boots.
- [X] : works under Websocket.
- [X] : Don't require special configs from FluffOS 2019.
- [ ] : No warning or errors

Verified live with the shipped `config.deadsouls` as-is and this repo's
own `driver/` submodule build (`./build.sh && ./run.sh`, no `-DPACKAGE_UIDS`
override needed beyond what build.sh already sets): zero fatal errors
through the full boot log, and a full registration -> auto-wiz creator
promotion -> look/score/quit playthrough. The `driver/` submodule is kept
tracking latest fluffos/fluffos master; as of the current pin this
surfaces ~600 real compile-time warnings across the mudlib (redeclared
globals, an illegal `nosave` on a function, argument-count mismatches
against earlier declarations, etc. -- all pre-existing in the lib, just
not previously flagged) that a much older driver build didn't catch.
None of them are fatal -- boot and the full playthrough above are both
clean -- but they're real and worth someone's attention; not fixed here
so this note doesn't go stale. A GitHub Pages WASM demo is also set up
(`.github/workflows/pages.yml`) using the shared prebuilt fluffos/fluffos
WASM release rather than this repo's own driver build; see that
workflow's and `scripts/pack_for_web.sh`'s comments for the one feature
gap that trades off (the in-game creator code editor needs the modern
`ed_start`/`ed_cmd` efuns, which aren't in the shared WASM release's
driver build -- native `build.sh`/`run.sh` is unaffected and remains the
right way to do in-game LPC development).

## How to test and contribute

```
git clone --recurse-submodules https://github.com/fluffos/dead-souls.git
cd dead-souls
./build.sh
./run.sh
```

Connect to http://localhost:5555 and play!

## Admin

1. Edit ```lib/secure/cfg/groups.cfg``` and replace ```sunyc``` with the lower-case name of your admin character you will create below.
2. Connect via web browser to http://localhost:5555 or via mudclient to localhost port 6666.
3. Select Creator instead of player.
4. Set your character name to match the name you used above.
5. Enjoy!

Alternatively, this mudlib has AUTO_WIZ enabled: during registration
(after picking a race) it will ask directly whether you want to be a
player or a creator, no `groups.cfg` edit needed.

## Screenshot

![image](https://user-images.githubusercontent.com/1256464/71966839-2f444180-31b7-11ea-8cd4-f2fdf5f0cec7.png)

## Contribution

Send PR to fix stuff!
