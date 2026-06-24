# What's New

These notes feed the in-app "Update Available" dialog for stable releases on `main`.

## Highlights

- 🔌 **Character creation now works on local KoboldCpp** — On the native KoboldCpp backend the AI Character Creator (and the Realism Engine's behind-the-scenes evaluations) could come back empty or run away repeating itself, so characters generated blank or garbled. Front Porch now talks to KoboldCpp through its chat API, so the model gets its proper instruct template and generates reliably — exactly like the cloud / oMLX backends. Making characters and running Realism on a local model just works again.

- 🎨 **Generate character avatars on the local backend too** — In the Creator's Review step, "Generate Avatar" was hidden whenever your chat model was KoboldCpp — a leftover from when KoboldCpp was mistakenly treated as the image source. Avatars actually come from the image generator you pick in Image Studio (Draw Things / A1111 / a remote API), which is independent of your chat model — so generating one now works no matter which LLM backend you're on.

- 🖼️ **Image Studio: typing no longer comes out backwards** — In the custom image generator, typing into the Prompt and Negative Prompt fields inserted each character at the *start*, so your prompt ended up reversed. Fixed — text goes in the right direction, and editing mid-prompt keeps the cursor where you put it.

- 🧹 **Cleaner large-model loading** — Loading a big-vocabulary model no longer floods the log with GGUF parsing errors, and the app reads those models' architecture correctly now, so VRAM and layer estimates are a touch more accurate.

For the complete list, see the GitHub release notes.
