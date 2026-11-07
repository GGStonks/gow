---
title: Boxshelf
---

# Boxshelf

![Boxshelf](assets/icon.png)

Boxshelf is a TV-style launcher for emulators, Steam and media apps: a shelf of
game boxes you browse with a controller. This image runs it as a Wolf app, one
Boxshelf per Wolf profile.

## How it works

- **Compositor:** Boxshelf runs inside a nested KWin (Wayland, with Xwayland),
  not Sway or gamescope. Boxshelf needs a stacking window manager: it keeps
  itself on top, fades in and out, and covers a game while it closes. KWin
  behaves like a Plasma desktop does. Boxshelf itself uses X11 for the same
  reason.
- **Session:** Boxshelf is KWin's only session. Quitting Boxshelf (quick menu,
  then Power, then Exit) closes the stream.
- **Emulators:** built on `base-emu`, so Dolphin, Cemu, PCSX2, RPCS3 and
  RetroArch are in the image. At start the AppImages are linked into
  `~/Applications`, where Boxshelf finds them. Folders listed in
  `BOXSHELF_EMULATOR_DIRS` (separated by `:`) are linked too.
- **The app:** the image doesn't contain Boxshelf. Wolf mounts the host's
  `Boxshelf.AppImage` read-only at `/opt/boxshelf/Boxshelf.AppImage`, so every
  profile runs the same build as the host (an official release from
  sassiestrhihno/boxshelf-beta or a build of your own), and updating it on the
  host updates every profile. It's unpacked once per version into
  `/etc/wolf/boxshelf/app-cache` (shared by every profile) and started from
  there, instead of being unpacked into `/tmp` on every start.

## PC games (Epic, Windows games)

Boxshelf's Linux PC support (Settings, then PC games) shows every folder of the
PC games folder as a game: a Linux one runs as it is, a Windows one through
Wine or Proton. It also shows the whole Epic library through legendary, with
uninstalled games greyed out. The image adds `legendary`, `umu-run` (pinned,
checksum-verified releases) and Ubuntu's Wine (32 and 64 bit). The Proton
builds come from the host's `compatibilitytools.d` and `/usr/share/steam`.

For example (`host/site.json` names the real folders):

| Folder | What |
|---|---|
| `/srv/games/PC` | the PC games every account shares |
| `/srv/games/accounts/<name>/Prefixes` | the account's Wine prefixes, one per game, named after it |
| `/srv/games/accounts/<name>/Games` | the account's own copies (a folder with the same name wins over the shared one) |
| `/srv/games/accounts/<name>/Home` | the home the account's Linux games get: their saves and settings, Citron's data |

They're mounted at the same paths as on the host, so prefixes and settings work
the same everywhere. `BOXSHELF_PC` in the Wolf entry names the account's folders.
Each account keeps its own Epic sign-in in `~/Boxshelf/data/legendary`, and its
own programs and Wine settings per game (`pc.programs`, `pc.run`) in Boxshelf's
settings. The umu runtime (about 0.5 GB) is downloaded once into
`/etc/wolf/boxshelf/umu` and shared by every profile.

These need extra container permissions: `SYS_ADMIN`,
unconfined seccomp and AppArmor (the Steam Linux Runtime uses bubblewrap), and
10240 open files (esync).

## What lives where: the image or the AppImage

The image only provides the place Boxshelf runs in. Everything Boxshelf does
(its shelves, settings, PC games, Epic support, covers, the Exit
button) comes from the host's `Boxshelf.AppImage`. Replace that file and the
next Boxshelf session in Wolf runs the new version: no image rebuild, no
config change. A session that's already open keeps its version until it's
closed. Each new version is unpacked once, about 0.5 s on its first start.

The image and the Wolf entry provide what Boxshelf finds around it:

- KWin, Xwayland and the libraries Electron needs
- `legendary`, `umu-run` and Wine
- the emulators from `base-emu`
- the start-up script: settings seed, the account's PC folders, box-art seed, emulator links
- the launch wrapper: Chromium flags, the file dialog's size, the unpack cache
- the mounts: games, the account's folder, Proton builds, caches

These only need changing when a new Boxshelf feature needs something new from
outside the AppImage, such as another tool or another folder.

`host/wolf-entries.py` writes the Boxshelf entry into every account profile of
Wolf's `config.toml` (the accounts and folders come from `host/site.json`; copy
`host/site.example.json`), with the account's folders and the few mounts of its
Heroic app that lay a shared folder over part of a game (mods, saves). Run
it, then restart Wolf, while nobody is streaming.

## Each profile's data

Wolf gives each profile its own home (`/etc/wolf/profile-data/<profile>/WolfBoxshelf`).
Boxshelf keeps its settings, history and caches in `~/Boxshelf` there.

On a profile's first start its settings are copied from a seed made on the
host, `/etc/wolf/boxshelf/seed-config.json`. The seed is the host's Boxshelf
settings without its accounts (RetroAchievements, ScreenScraper, API keys) and
with Steam turned off (there's no Steam in this image). Each profile can sign in
to its own accounts in Boxshelf's settings.

Shared between all profiles (see `assets/wolf.config.toml`):

| What | Access |
|---|---|
| The art library, guides and magazines | read-write |
| Songs and custom themes | read-only |
| The Switch game folders | read-only, at the same paths as on the host |
| The PC games folder | read-write (Epic games install there) |
| The account's own folder (`/srv/games/accounts/<name>`) | read-write, that account only |

## Building

```sh
docker build \
  --build-arg BASE_APP_IMAGE=ghcr.io/games-on-whales/base-emu:edge \
  -t boxshelf:latest apps/boxshelf/build
```

Then refresh the seed (`/etc/wolf/boxshelf/seed-config.json`: the host's
Boxshelf settings without its accounts, see above) and copy `assets/icon.png`
to `/etc/wolf/icons/boxshelf.png`.
