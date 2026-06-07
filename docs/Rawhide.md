# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent Improvements

- 📦 **MacOS Notarization Fixed** — Mac builds should actually pass Apple's notarization Gatekeeper now! We've completely overhauled the CI pipeline to generate a proper, fully signed and stapled `.pkg` installer instead of a `.dmg`.
- 🚧 **Auto-Updater Notice** — Please note that the in-app macOS auto-updater is temporarily broken by the `.pkg` switch. It will be fully repaired after the upcoming major refactoring is completed.
