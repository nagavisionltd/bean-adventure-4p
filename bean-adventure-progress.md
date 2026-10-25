# Bean Adventure — progress log

**Updated:** 2026-10-25
**Working build:** `bean-adventure-4p.html`
**Status:** playable first-zone prototype; local changes are not in a Git checkout.

## What is in the build

- Four distinct hero picks (Knight / Fire, Mage / Ice, Rogue / Lightning, Brute / Earth), with one-of-each party selection.
- Shared 2.5D road combat, co-op party camera, character-specific elemental magic, melee combos, heavy attacks, dodge, enemies, ambush sections and a boss/level progression loop.
- Keyboard and up-to-four-controller support through the browser Gamepad API. This standalone HTML build does not require the optional localhost pad bridge.
- HUD for level/road progress, encounter status, player health and XP, plus a controller-friendly hero select overlay.
- Changing outdoor environments, roadside foliage, smashable crates, ambient debris and particle feedback.

## Latest verification (2026-10-25)

- Extracted the inline game script from the deliverable HTML and ran `node --check` plus Node VM parsing — **pass**; no illegal top-level `return` or other syntax errors.
- Reloaded the actual file in Chrome; title screen, Three.js canvas and hero-select screen initialized successfully — **pass**.
- Exercised title → hero select → campaign map → mission briefing → gameplay — **pass**.
- Spawned the first road encounter and exercised a melee combo; the target took damage and was stunned — **pass**.
- Exercised pause/resume, stage report/reward, and progression through Verdant Crossing → Mothership Wilds → Cinder Crown — **pass**.
- Checked the biome scene state: forest rain/foliage, alien-world environment, and lava hazards all initialized; shop presented all three demo upgrades — **pass**.
- Checked the runtime error probe throughout the flow — no errors recorded. The current standalone build made **zero** requests to `127.0.0.1:8777/pads`; its controller fallback uses the browser Gamepad API, so a stopped local bridge cannot cause the reported connection-refused message.
- Left the game at the title screen in Chrome for hands-on play.

## Known caveats / next work

- This is a targeted campaign smoke test, not a complete four-player run. Level-clear rewards/progression were exercised through the in-page test hook, not by defeating each boss in ordinary combat; a full combat play-through remains to be done.
- No visual screenshot review was performed; verification used the live DOM, game state, syntax parser and runtime error probe.
- The local game directory does not yet have Git metadata; publication to GitHub is still pending repository visibility/authentication setup.
