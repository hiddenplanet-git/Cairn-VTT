# Cairn Board

A small, self-hosted play-by-post message board for running
[Cairn](https://cairnrpg.com/first-edition/cairn-srd/) (First Edition) games.
It's one Python file (`app.py`), built to run comfortably on a Raspberry Pi
in Docker. All game state is stored in one SQLite file in `data/`. SQLite is
built into Python, so there's no database server to run.

Players make a character with the SRD creation tables, post to a shared feed,
roll dice, and keep their sheets up to date. The DM gets a dashboard to post,
whisper, manage every character, and share table documents.

## Features

**For players**
- **Character creation wizard.** Rolls background, traits, trinket, attributes (3d6 each, one swap allowed), HP and gold, all server-side. Players pick or roll a gear package.
- **Character sheet.**
  - HP, armor and gold edit inline.
  - The 10-slot inventory has a free "pocket" slot, encumbrance warnings, and DM-assigned containers (cart, mule, porter…).
  - Temporary conditions from the DM adjust attributes without changing the base scores.
- **Message feed.**
  - Posts support `*bold*`, `"italic dialogue"` and `@Character` mentions with autocomplete.
  - Players can whisper to the DM.
  - New posts and edits arrive live, with no reload.
  - Posts can be edited or deleted for 5 minutes after sending. A post with rolls can still be edited but never deleted.
- **Dice.** The server rolls d4–d100 and keeps the results, so they can't be faked in the browser. A single d20 can be tagged as a save against STR, DEX or WIL, and the server decides success.
- **Private notes, logins and docs.**
  - Each character has a private notes page.
  - Each character gets a generated username and password.
  - Players can open any documents the DM has shared.
- **Mobile layout.** Phones get Feed / Post / Sheet tabs.

**For the DM**
- **Posting.** Post as the DM, or whisper to a single character. DM rolls can carry a +/- modifier.
- **Players pop-out.**
  - The roster has quick HP/STR nudges.
  - A full editor covers stats, inventory, containers, conditions, background and gear.
  - The DM can mark a character dead or revive them, delete characters, and look up or reset player logins.
- **Edit protection.** If a player and the DM edit the same part of a sheet at once, the later save is refused rather than silently overwriting.
- **Scene name.** Set the scene name shown as the title for everyone.
- **Table documents.**
  - Upload PDFs, images, Markdown, text, HTML, Word files, spreadsheets and more (up to 25 MB each).
  - Each document can be kept DM-only or shared with players.
  - Files can also be dropped straight into `data/documents/`.
- **Backups.** Download a one-click zip of the whole game and import it again later. The current game is auto-saved before every import, so an import can be undone.
- **Activity log.** An append-only log in the database records every change.
- **Rate limits.** Failed logins, posts and rolls are rate-limited.

## Project layout

```
cairnapp/
    app.py                 the whole app (templates are inline)
    requirements.txt       Flask and waitress
    Dockerfile             builds the image: code only, no data or secrets
    docker-compose.yml     runs it: port, .env, PUID/PGID, ./data mount
    .dockerignore          keeps data/, .env and old copies out of the image
    .gitignore
    .env                   real secrets; never committed or copied into the image
    .env.example           template with blank values
    README.md
    data/                  the only folder the app writes to
        documents/         table documents (content; upload or drop files in)
        backups/           automatic saves taken before each import
        cairn.db (+ -wal, -shm)    game state + activity log (SQLite, created at runtime)
        legacy-json/       old JSON files, moved here once imported
```

Everything the game needs to survive a rebuild is in `data/`. The image holds
only `app.py` and its dependencies.

## Configuration

All settings are environment variables, kept in `.env` (copy
`.env.example`). Docker Compose passes them in with `env_file`; a plain
`python3 app.py` run reads the same `.env` itself. Real environment variables
override `.env`.

| Variable | Required | Purpose |
|---|---|---|
| `CAIRN_SECRET_KEY` | **yes** | Signs session cookies. Keep it stable, or everyone is logged out. Generate with `python3 -c "import secrets; print(secrets.token_hex(32))"`. |
| `CAIRN_DM_PASSWORD` | **yes** | The DM login password. |
| `PUID` / `PGID` | Docker only (default `1000`) | Host user and group the container runs as. They must own `data/`. Use the output of `id -u` / `id -g`. |
| `TZ` | no (default UTC) | Time zone for timestamps, e.g. `America/New_York`. |
| `CAIRN_BEHIND_PROXY` | no (off) | Set to `1` only when a reverse proxy sits in front (see below). |
| `CAIRN_DATA_DIR` | no | Where game state is saved. Default `data/` next to `app.py`; the Dockerfile sets `/app/data`. |
| `CAIRN_HOST` / `CAIRN_PORT` | no (`0.0.0.0` / `5000`) | Only used by `python3 app.py`, not by waitress. |

The app **refuses to start** if `CAIRN_SECRET_KEY` or `CAIRN_DM_PASSWORD` is
missing or blank. There are no built-in fallbacks.

Gameplay limits sit as constants near the top of `app.py`. These include
message length, the post edit window, rate limits, inventory slots and upload
sizes.

## Running with Docker (Raspberry Pi)

1. **Copy the whole folder to the Pi, including hidden dotfiles.** Use
   `scp -r cairnapp pi@raspberrypi:` rather than `scp cairnapp/*`: the `*`
   (and some GUI copy tools) skip `.env` and `.dockerignore`, and compose then
   fails with `env file ... not found`. Keep only one copy of the project per
   host, so you always know which `data/` folder is in use.

2. **Set up `.env`** (skip `cp` if you copied a `.env` across):

   ```bash
   cd cairnapp
   cp .env.example .env
   python3 -c "import secrets; print(secrets.token_hex(32))"
   nano .env
   ```

   Paste the key into `CAIRN_SECRET_KEY`, set `CAIRN_DM_PASSWORD`, and set
   `PUID` / `PGID` to the output of `id -u` / `id -g`. Then `chmod 600 .env`.

3. **Give that user the data folder.** From the folder that holds
   `docker-compose.yml`:

   ```bash
   mkdir -p data
   sudo chown -R "$(id -u):$(id -g)" data && chmod -R u+rwX data
   ```

   `chown` alone doesn't add write permission, and files copied from Windows
   can arrive without it, hence the `chmod`.

4. **Start it:**

   ```bash
   docker compose up -d --build
   docker compose logs -f
   ```

   The first lines should be `[cairn] data directory: /app/data` and
   `[cairn] database: /app/data/cairn.db`. The board is
   at `http://<pi-address>:5000`; the DM dashboard at `/dm`.

5. **After editing `.env` or `docker-compose.yml`**, run
   `docker compose up -d --force-recreate`, not `docker compose restart`.
   `env_file` and `user:` are only applied when the container is created.

**Updating:** replace `app.py`, then `docker compose up -d --build`. `data/`
is untouched.

## Running without Docker

You need Python 3.9 or newer.

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env      # then fill in the two required values
python3 app.py            # Flask's dev server, for local use
```

Or run it the way the container does:

```bash
python3 -m waitress --host=0.0.0.0 --port=5000 --threads=8 app:app
```

Open `http://localhost:5000` to create a character and
`http://localhost:5000/dm` for the DM dashboard. Players on the same network
use the host's LAN address, such as `http://192.168.1.50:5000`. Game state is
saved in `data/` next to `app.py`.

## Data and backups

All game state lives in one SQLite database, `data/cairn.db`, created on
first start. The table documents stay ordinary files in `data/documents/`.

| Path in `data/` | Written by | Holds |
|---|---|---|
| `cairn.db` | every change | Everything: posts (including whispers), characters and their logins, scene name, DM notes, the document index, and the activity log |
| `cairn.db-wal`, `cairn.db-shm` | SQLite | SQLite's working files. They belong to `cairn.db`; never delete or copy one without the others |
| `documents/` | DM uploads, or you dropping files in | The table documents themselves |
| `backups/` | Import Backup | Automatic zip snapshots of the game, saved before each import (newest 10 kept) |
| `legacy-json/` | first start after upgrading | The old JSON files and `Activity Log.txt`, moved here after being imported (see below) |

Inside the database:

| Table | Holds |
|---|---|
| `posts` | One row per post. The whole post is JSON in `data`; `seq`, author, whisper target etc. are copied into columns for querying |
| `characters` | One row per character, likewise: whole sheet in `data`, plus `username`, `name`, `dead` |
| `documents` | One row per table document: file name, title, shared with players or not |
| `activity_log` | Append-only audit trail of every player and DM action (`ts`, `actor`, `action`, `details`) |
| `meta` | Scene name, DM notes, schema version and the backup-import epoch |
| `client_map` | Legacy browser links from before logins; empties itself over time |

Every save is one transaction, so a crash or power cut leaves the database
either fully before or fully after a change. If the database is damaged, or
was written by a newer `app.py`, the app **refuses to start** rather than
touch it.

You can browse it with `sqlite3 data/cairn.db` or DB Browser for SQLite, even
while the app is running. Don't edit it while the app is running: the app
keeps the game in memory and would overwrite your change.

**Backing up.** **Download Backup** on the DM dashboard gives a zip of
readable JSON files, the activity log as text, and every table document. It's
the same format the app used before it switched to SQLite, so old and new
backups both import. Copying `data/` works too, but only while the app is
stopped (`docker compose stop`): a copy of a live database can miss its newest
changes.

**Reset** to a fresh game: stop the container and move `cairn.db`,
`cairn.db-wal` and `cairn.db-shm` out of `data/` (keep them until you're
sure). Leave `documents/` in place to keep the documents; they're picked up
again, DM-only, on the next page load.

**Upgrading from the JSON version.** On the first start after upgrading, any
`Characters.json`, `Hidden Message Board.json`, `Scene.json`, `DMNotes.json`,
`Documents.json` and `Activity Log.txt` in `data/` are imported in one go,
then moved into `data/legacy-json/<date-time>/`. Nothing is deleted. If one of
them is damaged, the app refuses to start and imports nothing. Once you're
happy the game looks right, you can delete `legacy-json/`.

**Moving an existing game in:** download a backup from the old board and use
**Import Backup** on the new one. Or stop the container, copy the old
install's JSON files and `documents` folder into `data/` (with no `cairn.db`
there yet), fix ownership, and start; they're imported as above.

## Running behind a reverse proxy (HTTPS)

To serve the board over HTTPS with Caddy or nginx, point the proxy at port
5000. Then set `CAIRN_BEHIND_PROXY=1` in `.env` and
`docker compose up -d --force-recreate`. This makes per-IP login limits see
each player's real address instead of the proxy's. Don't set it without a
proxy, because then anyone could fake their address.

If the proxy runs on the same machine, you can bind the container to
localhost only with `"127.0.0.1:5000:5000"` in `docker-compose.yml`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `env file ... not found` | `.env` didn't copy over (dotfiles skipped) or isn't next to `docker-compose.yml`. |
| Container keeps restarting | Run `docker compose logs`. "is not set" means a required variable is missing from `.env`. "Cannot write to the data directory" means `./data` isn't owned/writable by `PUID:PGID` (step 3). "Cannot read …cairn.db" means a damaged database; "Cannot read …json" a damaged old JSON file being imported. |
| Permission denied on `/app/data` although you ran `chown` | You fixed a different copy of the project. `docker inspect cairn-board` → `Binds` shows the folder actually mounted; fix that one, including `chmod -R u+rwX`. |
| `.env` change has no effect | Use `docker compose up -d --force-recreate`, not `restart`. |
| Everyone logged out after a restart | `CAIRN_SECRET_KEY` changed. |
| Page won't load from another device | Use `http://` and the Pi's LAN IP, and check the firewall. |
| "Address already in use" on a Mac | macOS AirPlay Receiver uses port 5000. Map another port, such as `"8000:5000"`. |

## Credits

Character creation tables are from the Cairn First Edition SRD by Yochai
Gal, licensed CC-BY-SA 4.0. The **Rules** and **Bestiary** buttons link to
[cairnrpg.com](https://cairnrpg.com).
