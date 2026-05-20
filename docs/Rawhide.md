# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements

- 🖼️ **Changing a character's avatar image** — Fixed a crash ("Error updating character: FileSystemException … Read-only file system, errno = 30") that occurred when replacing a character's avatar via the full editor page on macOS (and would affect packaged builds on other platforms too). The editor was storing only the filename (basename) instead of the full absolute path before calling through to the PNG writer. The repository now defensively resolves any relative path before filesystem I/O, and the editor follows the documented "keep full paths in-memory" convention (the simpler popup editor was already correct). A stray PNG in the project root on dev machines was the silent symptom of the same bug.

- 🛠️ **Story generation stability** — Fixed crashes when LLMs return numeric fields as doubles (`1.0`) instead of ints. Affects beats, scenes, acts, lore entries, and top-level project data. Includes 16 new unit tests. (Backported from PR #31)
