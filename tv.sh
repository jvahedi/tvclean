#!/usr/bin/env bash
# tvclean — reversible debloat for Android/Google TV over adb, grouped by concept.
# Everything that changes the TV is dry-run unless --yes is passed.
# Bash 3.2 compatible (stock macOS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SNAPS="$ROOT/snapshots"
LOG="$ROOT/applied.log"
[ -f "$ROOT/config.env" ] && . "$ROOT/config.env"
ADB_SERIAL="${ADB_SERIAL:-}"
PRIVATE_DNS_HOST="${PRIVATE_DNS_HOST:-}"

die()  { echo "error: $*" >&2; exit 1; }
info() { echo "-- $*"; }

# ---------- device ----------

pick_device() {
  [ -n "$ADB_SERIAL" ] && return
  local devs
  devs=$(adb devices | awk 'NR>1 && $2=="device"{print $1}')
  [ -z "$devs" ] && die "no adb device. Run: ./tv.sh connect"
  # adb auto-connects paired TVs by their mDNS name, which survives port changes;
  # the same TV then also shows up as ip:port. Prefer the mDNS serial.
  local mdns; mdns=$(echo "$devs" | grep '_adb-tls-connect' || true)
  [ -n "$mdns" ] && [ "$(echo "$mdns" | wc -l | tr -d ' ')" = 1 ] && devs="$mdns"
  [ "$(echo "$devs" | wc -l | tr -d ' ')" -gt 1 ] && die "several devices; set ADB_SERIAL in config.env:
$devs"
  ADB_SERIAL="$devs"
}
S() { adb -s "$ADB_SERIAL" shell "$@" | tr -d '\r'; }

cmd_connect() { # find the TV via mDNS and adb connect
  # Wireless debugging uses a random port; find it via mDNS.
  local target
  target=$(adb mdns services 2>/dev/null | awk '/_adb-tls-connect/{print $NF; exit}')
  if [ -z "$target" ] && command -v dns-sd >/dev/null; then
    local inst host port ip
    inst=$( (dns-sd -B _adb-tls-connect._tcp local. & p=$!; sleep 3; kill $p) 2>/dev/null | awk '/ Add /{print $NF; exit}')
    [ -n "$inst" ] || die "no TV advertising wireless debugging. Is it on, and was the TV paired? (adb pair ip:port code)"
    read -r host port < <( (dns-sd -L "$inst" _adb-tls-connect._tcp local. & p=$!; sleep 3; kill $p) 2>/dev/null \
      | sed -nE 's/.*reached at ([^:]+)\.:([0-9]+).*/\1 \2/p' | head -1)
    ip=$( (dns-sd -G v4 "$host" & p=$!; sleep 2; kill $p) 2>/dev/null | grep -Eo '([0-9]+\.){3}[0-9]+' | tail -1)
    target="$ip:$port"
  fi
  [ -n "$target" ] || die "could not find the TV"
  adb connect "$target"
  info "set ADB_SERIAL=$target in config.env if you have more than one device"
}

# ---------- lists ----------

groups() { ls "$ROOT"/groups/*.txt | xargs -n1 basename | sed 's/\.txt$//'; }
group_file() {
  local f="$ROOT/groups/$1.txt"
  [ -f "$f" ] || die "no group '$1'. Groups: $(groups | paste -sd' ' -)"
  echo "$f"
}
# "package risk" lines from a group file (strip comments/blank lines)
group_entries() { sed -e 's/#.*//' "$(group_file "$1")" | awk 'NF{print $1, ($2==""?"safe":$2)}'; }
protect_re() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$ROOT/protect.txt" | awk 'NF' | paste -sd'|' -; }
is_protected() { echo "$1" | grep -Eq "$(protect_re)"; }

pkg_state() { # enabled | disabled | missing
  local p="$1"
  if ! S pm list packages | grep -qx "package:$p"; then echo missing
  elif S pm list packages -d | grep -qx "package:$p"; then echo disabled
  else echo enabled; fi
}
is_running() { S pidof "$1" >/dev/null 2>&1 || S ps -A -o NAME | grep -q "^$1\(:\|$\)"; }

# ---------- snapshot / diff ----------

cmd_snapshot() { # read-only: save packages, settings, home, processes to snapshots/
  pick_device
  local build dir
  build=$(S getprop ro.build.version.incremental)
  dir="$SNAPS/$(date +%Y%m%d-%H%M%S)_${build:-unknown}"
  mkdir -p "$dir"
  S getprop > "$dir/props.txt"
  S pm list packages    | sed 's/package://' | sort > "$dir/.all"
  S pm list packages -d | sed 's/package://' | sort > "$dir/.dis"
  S pm list packages -s | sed 's/package://' | sort > "$dir/.sys"
  # pkg <TAB> enabled|disabled <TAB> system|user
  while read -r p; do
    st=enabled; grep -qx "$p" "$dir/.dis" && st=disabled
    ty=user;    grep -qx "$p" "$dir/.sys" && ty=system
    printf '%s\t%s\t%s\n' "$p" "$st" "$ty"
  done < "$dir/.all" > "$dir/packages.tsv"
  rm -f "$dir"/.all "$dir"/.dis "$dir"/.sys
  S settings list global > "$dir/settings-global.txt"
  S settings list secure > "$dir/settings-secure.txt"
  S cmd package resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN | tail -1 > "$dir/home.txt"
  S ps -A -o NAME | sort -u > "$dir/running.txt"
  info "snapshot: $dir"
  info "$(wc -l < "$dir/packages.tsv" | tr -d ' ') packages, $(grep -c $'\tdisabled' "$dir/packages.tsv" || true) disabled, build $build"
  echo "$dir"
}

cmd_diff() { # diff [old] [new]  — defaults to the two most recent snapshots
  local a="${1:-}" b="${2:-}"
  if [ -z "$a" ]; then
    a=$(ls -d "$SNAPS"/*/ 2>/dev/null | sort | tail -2 | head -1); b=$(ls -d "$SNAPS"/*/ | sort | tail -1)
  fi
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ] || die "need two snapshots"
  a="${a%/}"; b="${b%/}"
  echo "old: $(basename "$a")"; echo "new: $(basename "$b")"
  local fa fb
  fa=$(grep ro.build.fingerprint "$a/props.txt"); fb=$(grep ro.build.fingerprint "$b/props.txt")
  [ "$fa" = "$fb" ] && echo "build: unchanged" || { echo "build CHANGED:"; echo "  $fa"; echo "  $fb"; }
  echo; echo "== new packages (review these — updates add things)"
  comm -13 <(cut -f1 "$a/packages.tsv") <(cut -f1 "$b/packages.tsv") | sed 's/^/  + /'
  echo "== removed packages"
  comm -23 <(cut -f1 "$a/packages.tsv") <(cut -f1 "$b/packages.tsv") | sed 's/^/  - /'
  echo "== state changes"
  join -t $'\t' <(cut -f1,2 "$a/packages.tsv") <(cut -f1,2 "$b/packages.tsv") | awk -F'\t' '$2!=$3{print "  "$1": "$2" -> "$3}'
  echo "== home: $(cat "$a/home.txt") -> $(cat "$b/home.txt")"
  echo "== private_dns: $(grep -h '^private_dns_mode' "$a/settings-global.txt" || echo unset) -> $(grep -h '^private_dns_mode' "$b/settings-global.txt" || echo unset)"
}

# ---------- apply / verify / restore ----------

cmd_apply() { # apply <group> [--only pkg] [--yes] — safe packages only; "test" ones need --only
  local group="${1:-}"; shift || true
  [ -n "$group" ] || die "usage: apply <group> [--only pkg] [--yes]. Groups: $(groups | paste -sd' ' -)"
  local yes=0 only=""
  while [ $# -gt 0 ]; do case "$1" in
    --yes) yes=1;; --only) only="$2"; shift;; *) die "unknown arg $1";; esac; shift; done
  group_file "$group" >/dev/null   # dies here, not inside a subshell
  pick_device

  local entries pkgs skipped=""
  entries=$(group_entries "$group")
  if [ -n "$only" ]; then
    echo "$entries" | awk '{print $1}' | grep -qx "$only" || die "$only is not in group $group"
    pkgs="$only"
  else
    pkgs=$(echo "$entries" | awk '$2=="safe"{print $1}')
    skipped=$(echo "$entries" | awk '$2!="safe"{print $1}')
  fi

  if echo "$pkgs" | grep -qx com.google.android.apps.tv.launcherx; then
    # Only a user-installed app counts: system HOME handlers (setup wizard, settings
    # fallback) are not usable home screens.
    local alt
    alt=$(comm -12 \
      <(S cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME \
          | grep -oE '^[[:space:]]*[a-zA-Z0-9_.]+/' | tr -d ' /' | sort -u) \
      <(S pm list packages -3 -e | sed 's/package://' | sort))
    [ -n "$alt" ] || die "no user-installed replacement launcher. Install one (e.g. Projectivy) first."
    info "replacement launcher(s): $alt"
  fi

  [ $yes = 1 ] && cmd_snapshot >/dev/null
  echo "$group — $([ $yes = 1 ] && echo APPLYING || echo 'dry run, pass --yes to apply')"
  local p st
  for p in $pkgs; do
    if is_protected "$p"; then echo "  REFUSED  $p (matches protect.txt)"; continue; fi
    st=$(pkg_state "$p")
    case "$st" in
      missing)  echo "  skip     $p (not installed)";;
      disabled) echo "  ok       $p (already disabled)";;
      enabled)
        if [ $yes = 1 ]; then
          if out=$(S pm disable-user --user 0 "$p" 2>&1); then
            echo "  DISABLED $p"; printf '%s\tdisable\t%s\t%s\n' "$(date +%FT%T)" "$p" "$group" >> "$LOG"
          else
            echo "  FAILED   $p: $out"
          fi
        else echo "  would disable  $p"; fi;;
    esac
  done
  for p in $skipped; do echo "  test     $p — not included; one at a time: --only $p"; done
}

cmd_verify() { # every package ever disabled via apply should still be disabled and not running
  pick_device
  [ -f "$LOG" ] || { info "nothing applied yet"; return 0; }
  local bad=0 p st run
  echo "build: $(S getprop ro.build.fingerprint)"
  for p in $(awk -F'\t' '$2=="disable"{print $3}' "$LOG" | sort -u); do
    # skip ones later restored
    if awk -F'\t' -v p="$p" '$3==p{last=$2} END{exit last=="enable"?0:1}' "$LOG"; then continue; fi
    st=$(pkg_state "$p"); run=""; is_running "$p" && run=" (RUNNING)"
    case "$st" in
      disabled) echo "  ok        $p$run";;
      missing)  echo "  gone      $p";;
      *)        echo "  RE-ENABLED $p$run"; bad=1;;
    esac
  done
  echo "private dns: $(S settings get global private_dns_mode) $(S settings get global private_dns_specifier)"
  echo "home: $(home_state)"
  [ $bad = 0 ] && info "all good" || { info "something was re-enabled (update?). Re-run: ./tv.sh reapply --yes"; return 1; }
}

cmd_reapply() { # re-disable everything in applied.log (after an update turned things back on)
  local yes=0; [ "${1:-}" = --yes ] && yes=1
  pick_device
  [ -f "$LOG" ] || die "nothing applied yet"
  local p
  for p in $(awk -F'\t' '{last[$3]=$2} END{for(p in last) if(last[p]=="disable") print p}' "$LOG" | sort); do
    is_protected "$p" && { echo "  REFUSED  $p"; continue; }
    if [ "$(pkg_state "$p")" = enabled ]; then
      if [ $yes = 1 ]; then S pm disable-user --user 0 "$p" >/dev/null && echo "  DISABLED $p"
      else echo "  would disable  $p"; fi
    fi
  done
  [ $yes = 1 ] || echo "(dry run, pass --yes)"
}

cmd_restore() { # restore [pkg] [--yes] — re-enable what apply disabled (or one package)
  local yes=0 one=""
  while [ $# -gt 0 ]; do case "$1" in --yes) yes=1;; *) one="$1";; esac; shift; done
  pick_device
  local pkgs
  if [ -n "$one" ]; then pkgs="$one"
  else
    [ -f "$LOG" ] || die "nothing to restore"
    pkgs=$(awk -F'\t' '{last[$3]=$2} END{for(p in last) if(last[p]=="disable") print p}' "$LOG" | sort)
  fi
  local p
  for p in $pkgs; do
    if [ $yes = 1 ]; then
      S pm enable --user 0 "$p" >/dev/null && echo "  ENABLED  $p" \
        && printf '%s\tenable\t%s\t-\n' "$(date +%FT%T)" "$p" >> "$LOG"
    else echo "  would enable  $p"; fi
  done
  [ $yes = 1 ] || echo "(dry run, pass --yes). DNS is separate: ./tv.sh dns off --yes"
}

cmd_dns() { # dns status | on [--yes] | off [--yes]
  pick_device
  local action="${1:-status}" yes=0; [ "${2:-}" = --yes ] && yes=1
  case "$action" in
    status) echo "mode=$(S settings get global private_dns_mode) host=$(S settings get global private_dns_specifier)";;
    on)
      [ -n "$PRIVATE_DNS_HOST" ] || die "set PRIVATE_DNS_HOST in config.env"
      if [ $yes = 1 ]; then
        S settings put global private_dns_specifier "$PRIVATE_DNS_HOST"
        S settings put global private_dns_mode hostname
        printf '%s\tdns-on\t%s\t1\n' "$(date +%FT%T)" "$PRIVATE_DNS_HOST" >> "$LOG"; cmd_dns status
      else echo "would set private DNS to $PRIVATE_DNS_HOST (pass --yes)"; fi;;
    off)
      if [ $yes = 1 ]; then
        S settings put global private_dns_mode off
        printf '%s\tdns-off\t-\t1\n' "$(date +%FT%T)" >> "$LOG"; cmd_dns status
      else echo "would turn private DNS off (pass --yes)"; fi;;
    *) die "dns status|on|off";;
  esac
}

# Google TV ignores set-home-activity, so Projectivy takes over Home through its
# accessibility service ("Override current launcher"). Google TV stays installed.
PROJECTIVY_A11Y=com.spocky.projengmenu/.services.ProjectivyAccessibilityService
a11y_list() { S settings get secure enabled_accessibility_services | sed 's/^null$//'; }
home_state() {
  if a11y_list | tr ':' '\n' | grep -qx "$PROJECTIVY_A11Y"; then echo "projectivy (override on; Google TV kept)"
  else echo "google-tv"; fi
}

cmd_home() { # home status | projectivy [--yes] | google [--yes] — switch home screen
  pick_device
  local action="${1:-status}" yes=0 cur new; [ "${2:-}" = --yes ] && yes=1
  cur=$(a11y_list)
  case "$action" in
    status) echo "home: $(home_state)";;
    projectivy)
      S pm list packages | grep -qx package:com.spocky.projengmenu || die "Projectivy not installed"
      new=$(printf '%s\n%s\n' "$cur" "$PROJECTIVY_A11Y" | tr ':' '\n' | awk 'NF && !seen[$0]++' | paste -sd: -)
      if [ $yes = 1 ]; then
        S settings put secure enabled_accessibility_services "$new"; S settings put secure accessibility_enabled 1
        printf '%s\thome\tprojectivy\t-\n' "$(date +%FT%T)" >> "$LOG"; cmd_home status
      else echo "would enable Projectivy override (pass --yes)"; fi;;
    google)
      new=$(echo "$cur" | tr ':' '\n' | grep -vx "$PROJECTIVY_A11Y" | awk NF | paste -sd: -)
      if [ $yes = 1 ]; then
        if [ -n "$new" ]; then S settings put secure enabled_accessibility_services "$new"
        else S settings delete secure enabled_accessibility_services >/dev/null; S settings put secure accessibility_enabled 0; fi
        printf '%s\thome\tgoogle-tv\t-\n' "$(date +%FT%T)" >> "$LOG"; cmd_home status
      else echo "would turn off Projectivy override, Google TV home returns (pass --yes)"; fi;;
    *) die "home status|projectivy|google";;
  esac
}

cmd_show() { # show every group with live state
  pick_device
  local g p risk st
  for g in $(groups); do
    echo "== $g"
    while read -r p risk; do
      st=$(pkg_state "$p" </dev/null); is_running "$p" </dev/null && st="$st, running"
      printf '  %-38s %-5s %s\n' "$p" "$risk" "$st"
    done <<< "$(group_entries "$g")"
  done
  echo "== dns"; echo "  $(cmd_dns status)"
}

usage() { sed -n 's/^cmd_\([a-z]*\)() *{ *#* *\(.*\)/  \1  \2/p' "$0"; }

case "${1:-}" in
  connect|snapshot|diff|apply|verify|reapply|restore|dns|home|show) c="$1"; shift; "cmd_$c" "$@";;
  *) echo "usage: ./tv.sh <command>"; usage; exit 1;;
esac
