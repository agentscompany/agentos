# AgentOS

The computer behind the bots of [AgentsCompany](https://agentscompany.ai): a minimal Debian 13 with a lightweight
desktop (TigerVNC + openbox + picom), Chromium, a terminal and a file manager, shown in the app through noVNC.

Prebuilt image for arm64 and amd64: `ghcr.io/agentscompany/agentos:<version>`. Every `vYYYY.MM.N` tag publishes a
new version (see `.github/workflows/publish.yml`); the AgentsCompany daemon pins the version it uses.

## Contract with the daemon (`acd`)

Breaking changes here require a new version and a daemon update.

**Startup:** `pc-start` (as root) sets the uid of the `ac` user to `AC_UID` (the owner of the mounted folders),
prepares the home directory and starts the desktop as `ac` (`pc-desktop`).

| Variable | Purpose |
|---|---|
| `AC_UID` | uid of the `ac` user (501 on a Mac, usually 1000 on Linux) |
| `VNC_PW` | VNC password (up to 8 characters) |
| `AC_TINT` | initial background color (`#rrggbb`) |
| `AC_OPEN_URL` | during a CLI login: where `xdg-open` sends the link (opens in the user's browser) |

- Port **6080**: noVNC (`/core/rfb.js` answers once the desktop is ready).
- User **`ac`** with passwordless sudo; home at `/home/ac` (a persistent volume: CLIs and logins live there).
- The bots' CLIs are not part of the image: the daemon installs them on demand into the home directory, using the
  official installers.

**The `pc` command** (what bots use on screen, through `company pc …`):

    pc screenshot [file]       pc click X Y [button]    pc double X Y     pc move X Y
    pc type text               pc key ctrl+l            pc scroll X Y N   pc tint #rrggbb
    pc open url|terminal|files     pc open --as <profile> <#rrggbb> [url]   (Chromium in the bot's profile and color)

## Building locally

    docker build -t agentos .
