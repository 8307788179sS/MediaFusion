# MediaFusion on Android (Termux) — local Stremio addon

Run MediaFusion as a **local, token-less Stremio addon** on an Android phone or
tablet. No account, no payment, no server in the cloud — it runs on the device.

## What you need first

1. **Termux** — install from **F-Droid** (not the Play Store; that version is old).
2. **Stremio** — install the Stremio app on the same device.

## Install (one time)

Open **Termux** and run:

```bash
pkg install -y git
git clone https://github.com/8307788179sS/MediaFusion.git
cd MediaFusion
bash deployment/termux/install.sh
```

The installer handles everything:

- installs PostgreSQL, Redis, the Rust toolchain and Python
- applies the local-mode patches (live search on, addon installs cleanly)
- builds the backend with **native-tls** and a low-memory profile
- starts the API (`:8000`) behind a small manifest proxy (`:8001`)

> ⚠️ The first build takes **20–40 minutes** and the device gets warm — keep it
> **plugged in** and the screen on. This happens only once.

## Add it in Stremio

On the **same device**, in Stremio → **Add-ons** → paste:

```
http://127.0.0.1:8001/manifest.json
```

Install it, open a movie or series, and scroll to the **MediaFusion Local**
streams. For faster playback pick **720p/1080p** with **more seeders** (👤).

## Restart later / after reboot

```bash
bash ~/mf-run.sh &
```

For automatic start on boot, install the **Termux:Boot** app (F-Droid) and open
it once — the installer already placed the boot script in `~/.termux/boot/`.

## Good to know

- MediaFusion streams are **torrents (P2P)**, so playback starts slower than a
  direct-stream addon. That is the nature of torrents, not a bug.
- For instant, direct playback use a direct-stream addon instead; MediaFusion is
  best as a **large fallback library** with many qualities and languages.
- Everything is local to the device. Other devices on the same WiFi can use
  `http://<device-LAN-IP>:8001/manifest.json`.
