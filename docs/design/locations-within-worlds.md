# Locations within Worlds — exploration and plan

Status: **proposal, not started.** Source: the Discord enhancement thread
"Support Locations as a finer-grain entity within Worlds" (Oct 2026).

## 1. What was asked

The requester builds one detailed World (a town) and many places inside it
(town hall, academy, church, tea rooms …). Each place has its own description
and lorebook; all of them share the town's lorebook, description and climate.
They want to use a *place* as the Setting of a group chat and have it pull in
its World's weather, description and lore without copying that material into
every place.

In their words: **a Location is a sub-World that inherits from its parent
World.**

The maintainer's concerns in the thread, which the plan must answer:

- Budgets: the Setting block is a budget-capped always-injected description;
  a 3-tier (location → world) chain makes it longer.
- Sub-locations: "it escalates quickly" — does a location get children?
- Transitions: moving between places mid-chat, especially when climate
  changes.

## 2. What exists today (read before touching anything)

Terminology: the UI already calls a World a **place**. One chat has place
*slots*:

| Slot | Count | Owns |
|------|-------|------|
| Setting (Primary) | 0..1 | weather/climate, the "Setting — where you are" prose, place traits |
| Lore | 0..N | lorebook entries only; never weather, never prose |

Where that lives:

- Model: `lib/models/world.dart` (`World`: name, description, lorebook,
  biomeId/biomeJson, climateEnabled, injectDescription, placeTraits,
  coverImage, sourceId). `lib/models/chat_place_slots.dart`
  (`ChatPlaceSlots`, `primaryWorldAllowsClimate`).
- Storage: `Worlds` and `ChatWorlds` tables in
  `lib/database/database.tables.features.dart`; queries in
  `lib/database/database.queries.worlds.dart`. `chat_worlds.is_primary`
  marks the Setting. Schema is at v60 (`AppDatabase.schemaVersion`).
- Repository: `lib/services/world_repository.dart` (cache, save/import/export,
  `resolveWorld(idOrName)`) + `lib/services/world_store/`.
- Chat wiring: `lib/services/chat/chat_service_wiring_injection.dart`
  loads slots into `_chatPlaceSlots`, `setChatPlaceSlots`, `setChatClimate`.
  `chat_service_wiring_injection_leaves.dart` `_worldDefaultBiome` reads the
  Setting's biome. `chat_service_accessors_living.dart` gates weather on
  `primaryWorldAllowsClimate(primary)`.
- Prompt: `lib/services/chat/prompt_injection/world_injection.dart`
  `buildWorldInjection([primary])` — 600-char soft cap, trait lines beat
  description under pressure. Called from `chat_service_generation_plan.dart`
  with **only the Setting**.
- Lore: `lib/services/chat/lorebook_collection.dart` `collectLoreEntryRefs`
  enumerates chat book → group book → `chatWorldIds` (Setting first, then
  Lore) → character books + character `worldNames`.
- Desktop UI: Places sidebar `lib/ui/chat_components/sidebar/story_tools/
  chat_places_panel*.dart`; World editor `lib/ui/pages/world_management/`;
  cards `lib/ui/pages/worlds/world_place_card.dart`; group wizard / group
  settings pick template `groups.world_ids`.
- Web: `web_ui/src/components/ChatPlacesSection.tsx`,
  `web_ui/src/pages/WorldsPage.tsx`, `WorldCard.tsx`; relay
  `lib/services/web/facade/world_facade.dart` + `routes/world_routes.dart`
  (`/api/worlds*`, `/api/chat/places`, `/api/chat/climate`).
- Portable format: `lib/models/fp_world_package.dart` (`.fpworld`, format
  version 1, `lorebooks` array already reserved for multi-book). Stoop
  shares the same envelope (`stoop_world_share.dart`).
- Tests: `test/services/chat/chat_places_primary_lore_test.dart`,
  `world_injection_test.dart`, `world_climate_injection_test.dart`,
  `test/services/world_repository_test.dart`,
  `integration_test/worlds_management_test.dart`, web
  `WorldsPage.*.test.tsx`, sweep route `/worlds`.

### What the requester can already do, and why it is not enough

A climate-off World per place, attached as a Lore place, plus the town as
the Setting, gives the lore union today. It does **not** give:

- a place's *own* description in the Setting prose (Lore places inject no
  prose);
- one-click switching of the whole bundle (town climate + town lore + place
  lore + place prose) as one Setting;
- a library that reads as "Bletchfield → its places" instead of a flat list
  of N+1 worlds.

## 3. Design decision: a Location is a World with a parent

Do **not** add a second entity, table, editor, relay, or package format.
Add one nullable column, `worlds.parent_world_id`, and derive everything
else:

- A **Location** is a `World` row whose `parentWorldId` is non-null.
- A location **always** has `climateEnabled = false` in its own row. It
  never authors climate. Weather, biome and place traits come from the
  nearest climate-enabled ancestor. (This is the "sub-World inherits" rule
  and it sidesteps the transition problem for climate inside one world: the
  climate does not change when you walk from the church to the tea rooms.)
- Depth: allow a parent chain, but **cap at two levels below the root in
  the UI** (town → building → room). The engine walks the chain to the
  root regardless; the UI refuses to make a child of a depth-2 location.
  The maintainer asked whether sub-locations should exist; answer is "yes,
  shallow", and the cap is a UI rule so the schema never needs to change.
- Cycles: the save path rejects a parent that is the world itself or any
  of its descendants.

### Resolution rules (the engine's contract)

Given the chat's Setting slot holds world `S`:

1. **Chain** = `[S, parent(S), parent(parent(S)) …]` up to the root, deduped.
2. **Climate / weather / traits** = the first climate-enabled world in the
   chain. Empty ⇒ weather off, exactly as today for a lore-only Setting.
   `primaryWorldAllowsClimate` gains the chain; `_worldDefaultBiome` reads
   the same world. The custom-climate dropdown option id stays
   `world:<id of the climate author>`.
3. **Setting prose** = `buildWorldInjection(chain)`, **leaf first**. The
   existing budget code already handles a list; the location's own
   description wins the budget, the town's gets truncated. Budget answer
   for the maintainer: the cap stays at 600 chars total, so a 3-tier chain
   costs no more than today's one-world Setting; authors see the truncation
   in the preview (see §5 UI).
4. **Lore** = chain books in leaf-first order, then the Lore slot books.
   `collectLoreEntryRefs` already dedupes worlds by id, so a town attached
   as both an ancestor and an explicit Lore place enumerates once.
5. **Lore slot** places may also be locations; they contribute their own
   book **and their ancestors' books** (a lore place "Bletchmore Academy"
   should bring Bletchfield's lore too). Still no prose, still no weather.

### Transitions

Phase 1 ships only the switch that exists today: replace the Setting. The
existing demote-on-replace behaviour (old Setting goes to the top of Lore)
is right for places: move from the church to the tea rooms and the church's
book stays in play as lore for the rest of the scene. A climate change on
transition only happens when the new Setting resolves to a *different*
climate author, which is the cross-world case the maintainer said is
already hard and is out of scope here. The biome-span machinery
(`setChatClimate`, `ChatBiomeSpans`) already records a mid-chat changeover
from "today" onward; a Setting swap that changes the climate author should
call it with the new author's biome so earlier story days keep their
weather. That is one call in `setChatPlaceSlots`, guarded by "climate
author actually changed".

Automatic transit from narration ("they walk to the academy") is **not** in
this plan.

## 4. Data and portability

- Schema v61: `ALTER TABLE worlds ADD COLUMN parent_world_id TEXT NULL`.
  Additive; no backfill. Repair ladder entry so a rerun is idempotent
  (`test/database/repair_covers_ladder_columns_test.dart` pattern).
- Deleting a parent: children are **re-rooted** (their `parent_world_id`
  set null, `climateEnabled` left false) and the user is told how many.
  Never cascade-delete lore the user wrote.
- `.fpworld` stays format 1 and gains an additive `locations: [ … ]`
  array on the root world's envelope, each item a world envelope minus
  climate. Import creates child rows with fresh ids and `sourceId`
  provenance. Older apps ignore the key and import the town alone
  (mixed-fleet rule). Exporting a location on its own exports its root
  with only that branch.
- Stoop: same envelope, so a shared WORLD card carries its locations for
  free. No new endpoint. Relay list/detail DTOs gain `parentWorldId` and
  `locationCount` (additive).
- Group template `groups.world_ids` and character `world_names` keep
  accepting any world id, location or not.

## 5. UI (desktop and web in the same PR, per parity law)

**Worlds library**

- Cards group by root: a root card shows a small "N places" chip; tapping
  the chip expands the children under it (indent, smaller card). Flat list
  stays for users with no locations.
- World editor gains, in the basics section, a **"Part of"** picker
  (none / any root or depth-1 world, excluding self and descendants). When
  set, the climate section collapses to one line: "Climate comes from
  <parent> (<biome>)". Place traits collapse the same way.
- New-location affordance on a root card: "+ Add a place inside".
- Setting prose preview under the description field shows what
  `buildWorldInjection(chain)` would emit at the 600 cap, so authors see
  the truncation the maintainer worried about.

**Places sidebar / web ChatPlacesSection**

- Setting card shows the breadcrumb ("Tea Rooms · Bletchfield") and the
  climate author's name in the climate line ("Weather from Bletchfield").
- Attach picker lists roots with their children indented; picking a child
  is the same `setChatPlaceSlots` call.
- Group wizard / group settings "Linked Worlds" pickers get the same
  indented list (no new behaviour).

**Rendered text rule:** the breadcrumb separator and labels are plain
strings; no enum names leak.

## 6. Delivery plan (one PR per row, each independently shippable)

| # | Slice | Touches | Guard that goes red first |
|---|-------|---------|---------------------------|
| 1 | Model + schema + resolver | `world.dart` (`parentWorldId`), `WorldRepository.chainFor(id)` / `climateAuthorFor(id)`, v61 migration, repair ladder, cycle check in `_saveWorld` | `world_repository_test.dart`: chain resolution, cycle refusal, re-root on parent delete; `repair_covers_ladder_columns_test` |
| 2 | Engine | `primaryWorldAllowsClimate` → chain; `_worldDefaultBiome`; `buildWorldInjection(chain)` leaf-first; `collectLoreEntryRefs` expands ancestors for Setting **and** Lore slots; biome span on author change in `setChatPlaceSlots` | `chat_places_primary_lore_test`: location Setting gets parent weather; lore-only root keeps weather off; `world_injection_test`: leaf wins budget; `lorebook_scanner_test`/`lorebook_speaker_inherit_test`: ancestor books enumerate once; group twin asserted in the same test |
| 3 | Desktop UI | editor "Part of" picker + collapsed climate, library grouping, Places breadcrumb, pickers | `integration_test/worlds_management_test.dart`: create town, create place inside it, attach place, see "Weather from <town>"; `layout_sweep` at 400/1440 |
| 4 | Web + relay | facade DTOs, `/api/worlds` save accepts `parentWorldId`, `WorldsPage` picker + grouping, `ChatPlacesSection` breadcrumb | `WorldsPage.*.test.tsx` for the picker; journey in `web_ui/e2e/journeys.spec.ts` (town → place → attach) |
| 5 | Portability | `.fpworld` `locations[]` export/import, Stoop share rides along, Rawhide notes | `world_repository_test` import group: round-trip keeps children, old envelope still imports |

Path-complete matrix for slice 2: generation ✓, Continue (reads the same
slots, no change), regen/swipe (slots are per chat, not per message, no
change), 1:1 ↔ group (slots are session-scoped for both; test both),
desktop ↔ web (slice 4). RAG / Journal / Growth / Pockets: N/A, no
world input.

## 7. Open questions for the maintainer

1. Depth cap of two below the root (town → building → room): fine, or
   keep it to one?
2. On Setting swap between two places under the same town, should the
   old place be demoted to Lore (today's behaviour) or dropped? Plan says
   demote.
3. Should a location be allowed to **override** the parent climate (a
   greenhouse in a tundra)? Plan says no in phase 1; the column shape
   allows it later by letting a child set `climateEnabled = true`, which
   then makes it the climate author for itself and its descendants.
4. Does the Stoop need a "place inside" badge on WORLD cards, or is the
   envelope ride-along enough for now?
