---
description: How to synchronize brain artifacts across devices
---

# Synchronizing Brain Artifacts

When you pull this repository on a new machine (Linux/macOS), you'll want to move the brain artifacts to the local system path so Antigravity can use them.

## To System Path (After Pulling)

Run this command to copy files from the repo to your local brain directory:

```bash
# On Linux/macOS
mkdir -p ~/.gemini/antigravity/brain/885ed0f0-ab29-4cc4-a0bf-296905e78dc7
cp -r .antigravity/brain/885ed0f0-ab29-4cc4-a0bf-296905e78dc7/* ~/.gemini/antigravity/brain/885ed0f0-ab29-4cc4-a0bf-296905e78dc7/
```

## To Repository (Before Pushing)

If you've made progress on another machine, copy it back to the repo before committing:

```bash
# On Linux/macOS
cp -r ~/.gemini/antigravity/brain/885ed0f0-ab29-4cc4-a0bf-296905e78dc7/* .antigravity/brain/885ed0f0-ab29-4cc4-a0bf-296905e78dc7/
```

> [!TIP]
> Always ensure you have the latest conversation ID folder matched up.
