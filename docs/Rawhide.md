# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements

- 🛠️ **Story generation stability** — Fixed crashes when LLMs return numeric fields as doubles (`1.0`) instead of ints. Affects beats, scenes, acts, lore entries, and top-level project data. Includes 16 new unit tests. (Backported from PR #31)
