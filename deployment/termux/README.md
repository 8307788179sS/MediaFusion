# MediaFusion — token-less local addon on Termux (WiFi/LAN)

Run MediaFusion as a **local Stremio addon** on an Android tablet/phone via Termux,
reachable from any device on the **same WiFi**, with **no token** in the manifest URL.

## Why "no token" already works

The Rust backend exposes **public, token-less routes** out of the box:

| Route                              | Purpose                          |
|------------------------------------|----------------------------------|
| `GET /manifest.json`               | manifest with `UserData::default` |
| `GET /stream/movie/{id}`           | public movie streams             |
| `GET /stream/series/{id}`          | public series streams            |
| `GET /stream/tv/{id}`              | public live-TV streams           |
| `GET /catalog/...`, `/meta/...`    | public catalog + metadata        |

So you install the **plain** URL (no `secret_str` path segment):

```
http://<tablet-LAN-IP>:8000/manifest.json
```

No code change is needed for token-less use — these routes already exist in
`backend/src/routes/*` and are wired in `backend/src/routes/mod.rs`.

## Setup

On the tablet, in Termux:

```bash
pkg install -y git
git clone https://github.com/8307788179sS/MediaFusion.git
cd MediaFusion
bash deployment/termux/setup-local.sh
```

The script installs PostgreSQL + Redis + Rust, creates the database, applies
migrations, builds `mediafusion-api`, and runs it bound to `0.0.0.0:8000`.

Then, in **Stremio on the same WiFi**, add the addon:

```
http://<tablet-LAN-IP>:8000/manifest.json
```

(The script prints your detected LAN IP when it starts.)

### Useful overrides

```bash
LAN_IP=192.168.1.43 STREAM_RS_PORT=8000 bash deployment/termux/setup-local.sh
```

Keep the device awake while streaming:

```bash
termux-wake-lock
```

## Honest limitations (read these)

1. **Public mode = non-debrid streams only.** Debrid providers (Real-Debrid,
   AllDebrid, Torbox…) need *their* account keys — a token-less manifest cannot
   provide them. For debrid you must use a configured `/{secret_str}/manifest.json`.
2. **Content is not built in.** Streams appear only once the database is populated
   by scrapers/indexers (Prowlarr/Jackett/Torrentio/etc.). A fresh DB returns empty
   results. Configure indexers via the `/configure` page or the worker jobs.
3. **Torrent playback** needs a Stremio build / external player that can handle the
   stream type on Android.
4. **First build is slow.** Compiling a large Rust project on a tablet can take a
   long time and significant RAM. A `--release` binary is produced once, then reused.
5. **LAN only.** This binds to your private network. Do **not** expose port 8000 to
   the public internet without auth in front of it.

## Required environment (set automatically by the script)

| Var              | Default                                                        |
|------------------|----------------------------------------------------------------|
| `SECRET_KEY`     | random 32-char string (any string works; padded to 32 bytes)   |
| `POSTGRES_URI`   | `postgresql://mediafusion:mediafusion@127.0.0.1:5432/mediafusion` |
| `REDIS_URL`      | `redis://127.0.0.1:6379`                                        |
| `STREAM_RS_PORT` | `8000`                                                          |
| `HOST_URL`       | `http://<LAN-IP>:8000`                                          |
