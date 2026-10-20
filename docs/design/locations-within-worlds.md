# Locations within Worlds

Status: **approved plan, not started.** Source: the Discord enhancement
thread "Support Locations as a finer-grain entity within Worlds" (Oct 2026)
and the follow-up on overloading lorebooks.

## 1. The ask

Authors build one detailed World (a town, a planet) and many places inside
it: town hall, academy, church, tea rooms. Every place has its own
description and lorebook. All of them share the parent's lorebook,
description and climate. Picking a place as the Setting of a chat should
bring the whole bundle: place prose, place lore, parent lore, parent
weather, without copying any of it into every place.

In one line: **a Location is a sub-World that inherits from its parent.**

Three concerns from the thread that this plan answers:

- **Budget.** The Setting block is always injected and budget-capped. A
  chain must not cost more than one world does today.
- **Depth.** Do locations have sub-locations? "It escalates quickly."
- **Transitions.** Moving between places mid-chat, including climate.

Plus two requirements that came out of review:

- A world must be able to hold several locales with **different climates**
  (Earth with its continents).
- **Overloading lorebooks**: a teacup in a palace and a teacup in a
  commoner's house trigger on the same key but read differently. The more
  specific place should win without the author copying worlds or toggling
  entries by hand.

## 2. What exists today

The UI already calls a World a **place**. A chat has place slots:

| Slot | Count | Owns |
|------|-------|------|
| Setting | 0..1 | weather and climate, the "Setting — where you are" prose, place traits |
| Lore | 0..N | lorebook entries only; never weather, never prose |

Where it lives:

- Model `lib/models/world.dart` (`World`), `lib/models/chat_place_slots.dart`
  (`ChatPlaceSlots`, `primaryWorldAllowsClimate`).
- Tables `Worlds`, `ChatWorlds` in `lib/database/database.tables.features.dart`;
  queries in `database.queries.worlds.dart`. Schema is v60.
- `lib/services/world_repository.dart` (cache, save, import, export,
  `resolveWorld`), `lib/services/world_store/`.
- Chat wiring `lib/services/chat/chat_service_wiring_injection.dart`
  (`_chatPlaceSlots`, `setChatPlaceSlots`, `setChatClimate`);
  `_worldDefaultBiome` in `chat_service_wiring_injection_leaves.dart`;
  weather gate in `chat_service_accessors_living.dart`.
- Prompt `lib/services/chat/prompt_injection/world_injection.dart`
  (`buildWorldInjection`, 600-char soft cap, trait lines beat description),
  called from `chat_service_generation_plan.dart` with the Setting only.
- Lore `lib/services/chat/lorebook_collection.dart` (`collectLoreEntryRefs`:
  chat book → group book → chat worlds → character books) and
  `lorebook_injector.dart` (SillyTavern inclusion groups: of the active
  members of a group exactly one injects, chosen sticky → prioritize →
  match score → seeded random).
- Clock judge `lib/services/chat/time_service/scene_time_evaluator.dart`:
  one post-reply model call reporting minutes, new day, days skipped and
  posture, tool call first then JSON text floor.
- Scene Guests: `cast_detector.dart` finds a named side character in the
  narration, `pendingGuestDetection` surfaces `SceneGuestDetectedDialog`,
  accept runs `SceneGuestFactory` and mints a lite card. The web snapshot
  carries the same flag.
- Desktop UI: Places sidebar `lib/ui/chat_components/sidebar/story_tools/
  chat_places_panel*.dart`; editor `lib/ui/pages/world_management/`;
  cards `lib/ui/pages/worlds/world_place_card.dart`; group wizard and group
  settings pick template `groups.world_ids`.
- Web: `web_ui/src/components/ChatPlacesSection.tsx`,
  `web_ui/src/pages/WorldsPage.tsx`; relay `lib/services/web/facade/
  world_facade.dart` + `routes/world_routes.dart` (`/api/worlds*`,
  `/api/chat/places`, `/api/chat/climate`).
- Portable format `lib/models/fp_world_package.dart` (`.fpworld` v1; the
  `lorebooks` array is already reserved for multi-book). The Stoop shares
  the same envelope.
- Tests: `test/services/chat/chat_places_primary_lore_test.dart`,
  `world_injection_test.dart`, `world_climate_injection_test.dart`,
  `test/services/world_repository_test.dart`,
  `integration_test/worlds_management_test.dart`, `WorldsPage.*.test.tsx`.

What the author can already do: one climate-off world per place attached
as Lore, the town as Setting. That gives the lore union but not the place's
own prose in the Setting block, not a one-tap bundle switch, and not a
library that reads as "town → its places".

## 3. Design: a Location is a World with a parent

No second entity, table, editor, relay or file format. One nullable
column, `worlds.parent_world_id`, and everything else is derived.

- A **Location** is a `World` whose `parentWorldId` is set.
- **Climate is inherited by default and may be owned.** A location with
  climate off takes weather, biome and place traits from the nearest
  climate-enabled ancestor. A location may switch its own climate on and
  becomes the climate author for itself and its descendants. So Earth can
  be a climate-off root carrying shared lore, each continent a child with
  its own biome, and each city under a continent inherits that continent.
- **Depth** is capped at two levels below the root in the UI (town →
  building → room). The engine walks any chain to the root; the editor
  refuses to make a child of a depth-2 location. The schema never needs to
  change if the cap moves.
- **Cycles** are rejected on save (a parent may not be the world itself or
  any descendant). **Deleting a parent re-roots its children** (parent
  cleared, climate left as it was) and tells the user how many. Lore the
  user wrote is never cascade-deleted.

### Resolution rules (the engine's contract)

With world `S` in the Setting slot:

1. **Chain** = `[S, parent(S), …]` up to the root, deduped by id.
2. **Climate, weather, traits** = the first climate-enabled world in the
   chain. None ⇒ weather off, exactly as a lore-only Setting today. The
   custom-climate dropdown id stays `world:<id of the climate author>`.
3. **Setting prose** = `buildWorldInjection(chain)`, leaf first, under the
   same 600-char cap. The location's own description wins the budget and
   the town's is truncated. A three-tier chain costs no more tokens than a
   single world does now. The editor shows the preview (see §5).
4. **Lore** = chain books leaf first, then the Lore slot books. Existing
   dedupe by world id means a town attached both as ancestor and as an
   explicit Lore place enumerates once.
5. **Lore slot places may be locations** and bring their ancestors' books
   too. Still no prose, still no weather.

### Overloading: nearest place wins its inclusion group

`LoreEntryRef` gains a specificity rank set by `collectLoreEntryRefs`: the
Setting leaf is 0, its parent 1, and so on; Lore-slot places and character
books rank behind the whole chain. `_pickGroupWinner` checks that rank
right after the sticky check. Among members from chain worlds the nearest
place wins; the existing prioritize, scoring and random steps still break
ties at the same rank.

Authoring: put both "teacup" entries in inclusion group `teacup`. The
palace version injects whenever the palace or a room inside it is the
Setting. An ungrouped entry behaves exactly as today, and the group field
already round-trips through import and export, so the change is
nonbreaking.

Held back: implicit shadowing by identical keys with no group label. Zero
authoring, but it would silently hide a town entry meant to add detail. If
wanted later it is a per-location switch, never a default.

### Transitions

**Manual, always available.** Replace the Setting from the Places sidebar
or the web Places section. The Setting card's breadcrumb becomes a
dropdown of reachable places (self, parents, siblings, children) so a
by-hand move is one tap. Today's demote-on-replace stays: the old place
goes to the top of Lore, so its book remains live for the rest of the
scene. When the swap changes the climate author, `setChatPlaceSlots`
records a biome span from the current story day, so earlier days keep
their weather. That is the same `ChatBiomeSpans` machinery the climate
dropdown uses now.

**Suggested, confirmed by the user.** No new model call. The clock judge
gains one field, `scene_place`, whose only legal values are the ids of the
reachable places plus `same`. The field is sent only when Passage of Time
is on, the per-chat switch "Suggest scene moves" (default off) is on, and
the Setting has relatives; otherwise the prompt is unchanged. The rubric
mirrors the days rule: report a move only when the reply narrates
arriving; a plan or a mention is not a move; missing or unparseable means
`same`. The service never applies the answer. It sets `pendingPlaceMove`
and the chat page shows a dialog in the Scene Guest style: "The model
thinks the scene has moved to the Tea Rooms. Move there?" with Move and
Stay. Move runs the manual path above. Stay remembers that place as
declined until the Setting next changes, so it does not nag. Because the
user confirms, a move is a user action: no undo chip, no per-message
rewind stamp, no Continue or one-shot special case. Web gets the flag
through the chat snapshot and shows the same dialog. One scene place per
chat in both 1:1 and group; split parties are out of scope. Director and
AFK turns do not run the clock judge and never move the scene.

### Minted places

The same field gains one more legal value, `new`, carried with a name and
a one-line descriptor, the same pair `DetectedCharacter` uses. It fires
only when the reply narrates arriving at a **named** place that is not in
the reachable list; an unnamed side street never qualifies. The dialog
offers Add and move, Just add, Ignore. Ignored names are remembered per
chat. Nothing is minted until the tap.

`PlaceFactory` sits beside `SceneGuestFactory`. Inputs: the name, the
descriptor, the narration lines where the place was portrayed, and the
parent chain's description and lore. Output: a child World under the
current Setting (or its parent when the depth cap is hit) with a short
description sized to the Setting budget, three to five lore entries, climate
inherited, and a `model-made` provenance marker. Where a parent entry
shares keys with a minted entry, the factory puts the new entry into that
inclusion group, so the palace teacup is written as the palace's version.
Persisted through `WorldRepository.saveWorld`, so name collisions, cycle
checks, export and the Stoop envelope behave as for a hand-made place.

Transport: the **eval transport** (native tool call first, then the JSON
text floor), not the World-from-Wiki tools gate, so a local KoboldCpp model
can mint. Guardrails: a separate per-chat switch "Let the model add
places" (default off), never climate on the fly, entry count capped, and a
`model-made` filter with bulk delete in the Worlds library.

## 4. Data and portability

- Schema v61: `ALTER TABLE worlds ADD COLUMN parent_world_id TEXT NULL`.
  Additive, no backfill, repair-ladder entry so a rerun is idempotent.
- `.fpworld` stays format 1 and gains an additive `locations: [ … ]` array
  on the root envelope, each item a world envelope with its own
  `climate_enabled` (inherit or own). Import creates child rows with fresh
  ids and `sourceId` provenance. Older apps ignore the key and import the
  root alone. Exporting a location alone exports its root with that branch.
- Stoop: same envelope, so a shared WORLD card carries locations. Relay
  list and detail DTOs gain `parentWorldId`, `locationCount`,
  `climateAuthorId` (additive).
- `groups.world_ids` and character `world_names` keep accepting any world
  id, location or not.

## 5. UI (desktop and web in the same slice, parity law)

**Worlds library.** Cards group by root; a root card shows an "N places"
chip that expands the children indented beneath it. Flat list is unchanged
for users with no locations. Root card action: "Add a place inside".
Filter: "model-made", with bulk delete.

**World editor.** Basics gains a **Part of** picker (none, or any root or
depth-1 world excluding self and descendants). With a parent set, the
climate section offers "Inherit from <parent> (<biome>)" or "Own climate";
the existing climate editor shows under "Own". A Setting-prose preview
under the description shows what the chain emits at the 600 cap.

**Places sidebar / web ChatPlacesSection.** Setting card shows the
breadcrumb ("Tea Rooms · Bletchfield") as the move dropdown and names the
climate author ("Weather from Bletchfield"). Attach picker lists roots with
children indented. Group wizard and group settings pickers get the same
indented list. Two per-chat switches under the panel: "Suggest scene moves"
and "Let the model add places".

**Dialogs.** `PlaceMoveDialog` in the `SceneGuestDetectedDialog` style, via
`showWarmDialog`, for both the move and the mint offers; web twin on the
chat page. Rendered text is plain strings; no enum names leak.

## 6. Delivery: seven PRs in strict order, each shippable alone

| # | Slice | Depends on | Guard that goes red first |
|---|-------|-----------|---------------------------|
| 1 | Model + schema v61 + `chainFor` / `climateAuthorFor` on the repository, cycle check, re-root on delete | — | `world_repository_test`: chain, cycle refusal, re-root; `repair_covers_ladder_columns_test` |
| 2 | Engine: chain climate (own or inherited), leaf-first prose, chain lore for Setting and Lore slots, specificity rank + nearest-wins group rule, biome span on author change | 1 | `chat_places_primary_lore_test`: location Setting gets ancestor weather, lore-only root keeps weather off, continent-level climates differ, grouped teacup flips with the Setting (1:1 and group); `world_injection_test`: leaf wins budget; `lorebook_scanner_test`: ancestor books enumerate once |
| 3 | Desktop UI: Part of picker, inherit-or-own climate, grouped library, breadcrumb dropdown, prose preview | 2 | `integration_test/worlds_management_test`: make a town, make a place inside, attach, see "Weather from <town>", move by dropdown; `layout_sweep` at 400 and 1440 |
| 4 | Web + relay twins of 3 | 3 | `WorldsPage.*.test.tsx` for the picker; journey in `web_ui/e2e/journeys.spec.ts` |
| 5 | `.fpworld` `locations[]`, Stoop ride-along, Rawhide notes | 1 | `world_repository_test` import group: round-trip keeps children, old envelope still imports |
| 6 | Confirmed scene moves: `scene_place` on the clock judge, `pendingPlaceMove`, dialog, declined memory, both shells | 2, 3, 4 | scene-time evaluator test: arrival sets the flag without changing slots, a plan does not, Move swaps and demotes, Stay is not re-offered until the Setting changes; dialog widget test; web journey |
| 7 | Minted places: `new` value, `PlaceFactory`, `model-made` marker, library filter + bulk delete, both shells | 6 | pure test of the tool payload decoder; the mint itself in the E2E journey (real model, no stub) |

Slices 1 to 5 are a complete, useful V1 on their own. If 6 or 7 slip,
nothing ships half-wired. Slice 7 carries the one real open risk, the
quality of minted lore on small local models, which is why it has its own
switch, default off.

Path-complete matrix for slice 2: generation ✓; Continue reads the same
slots, no change; regen/swipe: slots are per chat, not per message, no
change; 1:1 ↔ group: slots are session-scoped for both, both asserted;
desktop ↔ web in slice 4. RAG, Journal, Growth, Pockets: N/A, no world
input. Slices 6 and 7 add no per-message state because the user confirms.

## 7. Decisions taken

- Depth cap two below the root, UI-enforced.
- Setting swap demotes the old place to Lore (today's behaviour).
- A location may own its climate; inheritance is the default.
- A climate-off root as Setting means weather off, as a lore-only world
  does today.
- No implicit key shadowing in V1.
- No automatic travel without confirmation.
