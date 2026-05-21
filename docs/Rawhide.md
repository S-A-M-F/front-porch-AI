# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements

- 🖥️ **Pseudo-Remote backend** — A new backend option that runs KoboldCPP locally on your machine while exposing it through an OpenAI-compatible API. This gives you the strengths of local models (no API costs, full control) combined with the flexibility of remote-style prompting and generation. The integration is now complete and stable after the initial build issues.
- 🔄 **Auto-updater for Rawhide** — Nightly builds now correctly detect newer Rawhide releases and offer in-app updates on all platforms. The asset lookup, version comparison (date-based for `rawhide.YYYYMMDD.SHA`), and display strings were fixed so older nightlies will see and install newer ones.
