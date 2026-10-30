# tvclean

Reversible debloat for Android / Google TV over adb. Built for a Sony Bravia 8
(K-65XR80, Google TV 14), but the group files are the only Sony-specific part.

- Nothing is uninstalled — packages are `pm disable-user`'d and come back with `restore`.
- Every command that changes the TV is a **dry run unless you pass `--yes`**.
- `protect.txt` is a hard deny-list; `apply` refuses anything matching it.
- Every change is recorded in `applied.log`, which `verify`, `reapply` and `restore` read.
- Factory reset undoes everything.

## Setup (once per TV)

1. TV: Settings → System → About → click *Android TV OS build* 7×.
   Then Developer options → **Wireless debugging** on → *Pair device with pairing code*.
2. Mac: `brew install --cask android-platform-tools`, then `adb pair <ip>:<pair-port> <code>`.
3. `cp config.env.example config.env` and fill in `PRIVATE_DNS_HOST` if using DNS.
4. `./tv.sh connect` (after reboots the port changes; paired TVs usually auto-reconnect).

## Groups

Grouped by concept. Each package also has a **risk** tag:
`safe` = included when you apply the group; `test` = skipped unless you name it with
`--only`, then use the TV for a day before the next one.

| Group | What | How |
|---|---|---|
| **settings** | Sony/Google privacy toggles | by hand — checklist below |
| **dns** | Private DNS (NextDNS/AdGuard) blocks trackers + ads network-wide | `./tv.sh dns on --yes` |
| **tracking** (`groups/tracking.txt`) | Samba TV ACR, Sony IDD, crash/feedback upload; *test:* fingerprinter, adservices | `./tv.sh apply tracking --yes` |
| **bloatware** (`groups/bloatware.txt`) | store demo, Sony promos, Sony Select | `./tv.sh apply bloatware --yes` |
| **home** (`groups/home.txt`) | stock Google TV home screen (*test*) | install Projectivy, then `./tv.sh apply home --only com.google.android.apps.tv.launcherx --yes` — refuses without a user-installed launcher |
| **replacements** (`groups/replacements.md`) | Projectivy, SmartTube, uninstall unused FAST apps | by hand |

To add a package: put it in the right group file as `package  safe|test  # what it is`.

### Settings checklist (remote)
Menu paths are for the Bravia 8 on build 603100. Re-check after updates; updates can bring
back consent prompts or a new ad ID.

| Setting | Path | Last checked 2026-10-30 |
|---|---|---|
| Samba Interactive TV | Settings → System → Samba Interactive TV | already **off**; its services still ran → also disable the package (`tracking`) |
| Google usage & diagnostics | Settings → Privacy → Usage & diagnostics | already **off** |
| Advertising ID | Settings → Privacy → Ads → Delete advertising ID | **deleted**. "Get new advertising ID" now shows — don't press it |
| Gemini personal results | Settings → Privacy → Voice Assistant (Gemini for TV) | already **off** |
| Ambient screensaver | Settings → System → Ambient Screensaver → Settings | source is Art Gallery, no personal data — nothing to do |
| Sony data collection | `am start -n com.sony.dtv.privacypolicy/.MainActivity` | it's a whole-policy accept/decline, which may break Sony online features — left alone; the IDD agent package is disabled instead |

Not changed (your call): *Hands-free mic ("Hey Google")* is **on** — the mic is always
listening for the wake word. *Location → Scanning always available* is **on**.

Driving the TV from the Mac: `adb shell input keyevent KEYCODE_DPAD_DOWN` (…`_CENTER`,
`_BACK`, `_HOME`), `adb shell input tap X Y` (1920×1080), `adb exec-out screencap -p > s.png`,
`adb shell uiautomator dump` to find what's focused.

### DNS lists
Perflyst *SmartTV*, HaGeZi *Native Tracker* lists, plus one general ad list. Watch the
NextDNS log for a day and allow any Sony update domains that get blocked.

## After a firmware update

```bash
./tv.sh snapshot        # new snapshot of the updated TV
./tv.sh diff            # vs the previous one: build change, NEW packages, state changes
./tv.sh verify          # did the update re-enable anything?
./tv.sh reapply --yes   # if so, disable it again
```

Read the *new packages* section of `diff` — updates are where new trackers show up. Add
anything worth disabling to a group file (with a risk tag and comment) and apply it.

## Commands

```
./tv.sh show                       live state of every group package + DNS
./tv.sh snapshot                   read-only backup into snapshots/
./tv.sh diff [old] [new]           compare snapshots (default: last two)
./tv.sh apply <group> [--only pkg] [--yes]
./tv.sh verify                     everything applied still disabled?
./tv.sh reapply [--yes]            re-disable after an update
./tv.sh restore [pkg] [--yes]      re-enable everything applied (or one package)
./tv.sh dns status|on|off [--yes]
```

## Adapting to another TV

Copy the folder, run `snapshot`, and edit the group files. Keep `protect.txt` strict — for a
new brand, add its panel, update, tuner and settings packages before applying anything.
