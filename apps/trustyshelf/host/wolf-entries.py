"""Write the (T)rustyShelf app into every account profile of Wolf's config.toml.

Each profile gets: the image, the host's TrustyShelf.AppImage (read-only), the first-start seeds (settings without
accounts, the box-art database), the shared caches (unpacked (T)rustyShelf, umu's runtime), the emulator and game folders,
and the PC games: the shared PC games folder and the account's own folder (Prefixes, Games = its own copies, Home = the
home its Linux games get, Citron's data in it too), all at their host paths, so Wine prefixes and game settings work
the same on the host and in every account. TRUSTYSHELF_PC tells (T)rustyShelf which folders are the account's (startup-app.sh
puts them in its settings at every start).
A few mounts of the account's Heroic app that lay a shared folder over part of a game (a game's mods, its saves in
Documents) are carried over, moved to where (T)rustyShelf has that game; nothing of Heroic's own is mounted.
Proton gets the permissions it needs. Old (T)rustyShelf entries are replaced; everything else in the file is checked to be
unchanged.

What's particular to a machine (its accounts and folders) comes from a site file: copy site.example.json to site.json
(git ignores it) and fill it in.

Usage (edit config.toml only while nobody is streaming; restart Wolf afterwards):
    python3 -I wolf-entries.py site.json /etc/wolf/cfg/config.toml /tmp/config.toml.new
    cp /etc/wolf/cfg/config.toml /etc/wolf/cfg/config.toml.bak && cp /tmp/config.toml.new /etc/wolf/cfg/config.toml
"""
import json
import os
import re
import sys
import tomllib

SITE, SRC, DST = sys.argv[1], sys.argv[2], sys.argv[3]
site = json.load(open(SITE, encoding="utf-8"))
ACCOUNTS = site["accounts"]                    # Wolf profile id -> the account's own folder on the host
TRUSTYSHELF, PC = site["trustyshelf"], site["pcGames"]
APPIMAGE = site.get("appImage") or TRUSTYSHELF + "/TrustyShelf.AppImage"  # the AppImage (its file can have any name)  # (T)rustyShelf's folder (AppImage, Library...), the shared PC games
GAME_DIRS = site.get("gameDirs", [])           # read-only, at the same paths (emulator games)
EMULATOR_DIRS = site.get("emulatorDirs", [])   # their AppImages are linked into ~/Applications
PROTON_DIR = site.get("protonDir", "")         # the host's Proton builds (compatibilitytools.d)
EXTRA = site.get("mounts", [])                 # anything else every account gets ("src:dst:mode")
for p in [TRUSTYSHELF, PC, *ACCOUNTS.values(), *GAME_DIRS]:
    assert os.path.isabs(p), f"not an absolute path in {SITE}: {p}"

q = repr  # (a TOML literal string: single quotes, as Python writes them; paths here have none)
BLOCK = """
    [[profiles.apps]]
    icon_png_path = '/etc/wolf/icons/trustyshelf.png'
    start_virtual_compositor = true
    title = '(T)rustyShelf'

        [profiles.apps.runner]
        base_create_json = \'\'\'{
  "HostConfig": {
    "IpcMode": "host",
    "Privileged": false,
    "CapAdd": ["SYS_ADMIN", "SYS_NICE", "SYS_PTRACE", "NET_RAW", "MKNOD", "NET_ADMIN"],
    "SecurityOpt": ["seccomp=unconfined", "apparmor=unconfined"],
    "Ulimits": [{"Name": "nofile", "Hard": 10240, "Soft": 10240}],
    "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
  }
}
\'\'\'
        devices = []
        env = [
            'GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*',{env}
            'SDL_GAMECONTROLLERCONFIG=0500a8394c050000e60c000011810000,Wolf controller,platform:Linux,crc:39a8,a:b0,b:b1,x:b3,y:b2,back:b8,start:b9,leftstick:b11,rightstick:b12,leftshoulder:b4,rightshoulder:b5,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a3,righty:a4,lefttrigger:+a2,righttrigger:a5,'
        ]
        image = 'trustyshelf:latest'
        mounts = [{mounts}
        ]
        name = 'WolfTrustyShelf'
        ports = []
        type = 'docker'
"""


def block(pid):
    u = ACCOUNTS[pid]
    pc = {"gamesDir": PC, "userGamesDir": u + "/Games", "prefixDir": u + "/Prefixes", "homeDir": u + "/Home"}
    env = [*(["TRUSTYSHELF_EMULATOR_DIRS=" + ":".join(EMULATOR_DIRS)] if EMULATOR_DIRS else []), "TRUSTYSHELF_PC=" + json.dumps(pc, ensure_ascii=False)]
    mounts = [
        f"{APPIMAGE}:/opt/trustyshelf/TrustyShelf.AppImage:ro",
        "/etc/wolf/trustyshelf/seed-config.json:/opt/trustyshelf/seed/config.json:ro",
        f"{TRUSTYSHELF}/Library:{TRUSTYSHELF}/Library:rw",
        f"{TRUSTYSHELF}/Guides:{TRUSTYSHELF}/Guides:rw",
        f"{TRUSTYSHELF}/Magazines:{TRUSTYSHELF}/Magazines:rw",
        f"{TRUSTYSHELF}/Songs:/home/retro/TrustyShelf/Songs:ro",
        f"{TRUSTYSHELF}/Custom themes:/home/retro/TrustyShelf/Custom themes:ro",
        f"{TRUSTYSHELF}/tools/runtimes:/home/retro/TrustyShelf/tools/runtimes:ro",
        *[f"{d}:{d}:ro" for d in GAME_DIRS],
        f"{PC}:{PC}:rw",
        f"{u}:{u}:rw",
        f"{u}/Home/.local/share/citron:/home/retro/.local/share/citron:rw",
        f"{u}/Home/.config/citron:/home/retro/.config/citron:rw",
        *EXTRA,
        "/etc/wolf/trustyshelf/umu:/home/retro/.local/share/umu:rw",
        "/etc/wolf/trustyshelf/app-cache:/var/cache/trustyshelf:rw",
        "/etc/wolf/trustyshelf/boxart-cache:/opt/trustyshelf/seed/boxart-cache:ro",
        "/run/udev/data:/run/udev/data:ro",
        "/usr/share/steam:/usr/share/steam:ro",
        *([f"{PROTON_DIR}:/home/retro/.steam/root/compatibilitytools.d:ro"] if PROTON_DIR else []),
        *carried(pid, u),
    ]
    mounts = list(dict.fromkeys(mounts))
    return (BLOCK.replace("{env}", "".join("\n            " + q(e) + "," for e in env))
            .replace("{mounts}", ",".join("\n            " + q(m) for m in mounts)))


# The account's Heroic mounts that lay a shared folder over part of a game, moved to where (T)rustyShelf has it:
#   .../Heroic/Prefixes/<prefix>/...  -> <account>/Prefixes/<prefix>/...   (e.g. a game's mods inside its prefix)
#   .../Heroic/<game>/<inside>        -> <account>/Games/<game>/<inside>   when the account has its own copy (its mods)
#   /home/retro/Documents/...         -> kept, and also in <account>/Home/Documents (where its Linux games look)
HEROIC_GAMES, RETRO = "/home/retro/Games/Heroic/", "/home/retro"


def carried(pid, u):
    out = []
    for prof in stripped["profiles"]:
        if prof["id"] != pid:
            continue
        for a in prof.get("apps", []):
            if a.get("title") != "Heroic":
                continue
            for m in a["runner"]["mounts"]:
                src, dst, *mode = m.split(":")
                mode = ":".join(mode) or "rw"
                if dst.startswith(RETRO + "/Documents/"):
                    out += [f"{src}:{dst}:{mode}", f"{src}:{u}/Home{dst[len(RETRO):]}:{mode}"]
                elif dst.startswith(HEROIC_GAMES + "Prefixes/"):
                    out.append(f"{src}:{u}/Prefixes/{dst[len(HEROIC_GAMES + 'Prefixes/'):]}:{mode}")
                elif dst.startswith(HEROIC_GAMES):
                    game, _, inside = dst[len(HEROIC_GAMES):].partition("/")
                    if inside and os.path.isdir(f"{u}/Games/{game}"):
                        out.append(f"{src}:{u}/Games/{game}/{inside}:{mode}")
    return out


text = open(SRC, encoding="utf-8").read()
# drop the (T)rustyShelf blocks written before (each from its [[profiles.apps]] line to its type line)
# (and the Boxshelf blocks from before the rename to (T)rustyShelf)
text = re.sub(r"\n    \[\[profiles\.apps\]\]\n    icon_png_path = '/etc/wolf/icons/(?:trustyshelf|boxshelf)\.png'\n.*?\n        type = 'docker'\n", "\n", text, flags=re.S)
assert "WolfTrustyShelf" not in text and "WolfBoxshelf" not in text, "an old (T)rustyShelf / Boxshelf block is still there"
stripped = tomllib.loads(text)
lines = text.split("\n")
# Where each profile section ends: just before the next [[profiles]], or EOF
starts = [i for i, l in enumerate(lines) if l.strip() == "[[profiles]]"]
ids = {}
for s in starts:
    pid = lines[s + 1].split("=", 1)[1].strip().strip("'\"")
    ids[pid] = s
missing = [p for p in ACCOUNTS if p not in ids]
assert not missing, f"no such profiles in {SRC}: {missing}"
ends = {}
for pid, s in ids.items():
    nxt = [x for x in starts if x > s]
    ends[pid] = nxt[0] if nxt else len(lines)

for pid in sorted(ACCOUNTS, key=lambda p: ends[p], reverse=True):  # bottom-up keeps indexes valid
    at = ends[pid]
    while at > 0 and lines[at - 1].strip() == "":
        at -= 1
    # the profile's trailing blank lines are replaced (one blank line before the next profile), so running this again
    # gives the same file
    end = ends[pid]
    lines[at:end] = block(pid).rstrip("\n").split("\n") + ([""] if end < len(lines) else [])

out = "\n".join(lines)
out = out.replace("icon_png_path = '/etc/wolf/kde/assets/icon.png'",
                  "icon_png_path = '/etc/wolf/icons/kde.png'")
if not out.endswith("\n"):
    out += "\n"

after = tomllib.loads(out)
before = stripped  # compare against the config without the old (T)rustyShelf blocks

# Verify: the only differences are one new (T)rustyShelf app per account and the KDE icon path
assert before.keys() == after.keys(), "top-level tables changed"
for k in before:
    if k != "profiles":
        assert before[k] == after[k], f"{k} changed"
for pb, pa in zip(before["profiles"], after["profiles"]):
    apps_b, apps_a = pb.get("apps", []), pa.get("apps", [])
    extra = [a for a in apps_a if a.get("title") == "(T)rustyShelf"]
    if pb["id"] in ACCOUNTS:
        assert len(extra) == 1 and len(apps_a) == len(apps_b) + 1, pb["id"]
        mounts = extra[0]["runner"]["mounts"]
        assert not any("WolfHeroic" in m or ".config/heroic" in m for m in mounts), pb["id"]  # nothing of Heroic's own
        assert any(m.startswith(f"{ACCOUNTS[pb['id']]}:") for m in mounts), pb["id"]
    else:
        assert not extra and apps_a == apps_b, pb["id"]
    for ab, aa in zip(apps_b, apps_a[: len(apps_b)]):
        if ab.get("title") == "Desktop (KDE Plasma)":
            ab = dict(ab, icon_png_path="/etc/wolf/icons/kde.png")
        assert ab == aa, f"{pb['id']}: {ab.get('title')} changed"
    assert {k: v for k, v in pb.items() if k != "apps"} == {k: v for k, v in pa.items() if k != "apps"}

open(DST, "w", encoding="utf-8").write(out)
print("ok:", {p["id"]: [a["title"] for a in p.get("apps", [])][-2:] for p in after["profiles"]})
