#!/bin/bash
# Projectivy: hide every tile in the TV Apps row except KEEP. Run with Projectivy home on screen.
# Hide every tile in Projectivy's TV Apps row except favorites. Only taps a node whose text is exactly "Hide".
S=$(adb devices | awk '/_adb-tls-connect/{print $1}')
KEEP='^(Netflix|Paramount\+|Prime Video|HBO Max|YouTube|Apple TV|Disney\+|STARZ|Hulu)$'
k(){ adb -s $S shell input keyevent "$@"; }
dump(){ adb -s $S shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb -s $S shell cat /sdcard/ui.xml | tr '>' '\n'; }
focused(){ dump | grep 'focused="true"' | grep -oE 'content-desc="[^"]+"' | head -1 | cut -d'"' -f2 | sed 's/&amp;/\&/g'; }
k KEYCODE_BACK; sleep 0.3; k KEYCODE_HOME; sleep 1
# go to the row start: step left until the sidebar header has focus, then one right
for i in $(seq 1 60); do case "$(focused)" in "TV Apps"|Reorder|Settings) break;; esac; k KEYCODE_DPAD_LEFT; sleep 0.1; done
k KEYCODE_DPAD_RIGHT; sleep 0.3
last=""
for n in $(seq 1 80); do
  d=$(focused)
  if [ -z "$d" ]; then echo "no focus, stop"; break; fi
  if echo "$d" | grep -qE "$KEEP"; then
    if [ "$d" = "$last" ]; then echo "end of row"; break; fi
    last="$d"; echo "keep  $d"; k KEYCODE_DPAD_RIGHT; sleep 0.35; continue
  fi
  k --longpress KEYCODE_DPAD_CENTER; sleep 0.8
  adb -s $S shell input swipe 1600 900 1600 300 250; sleep 0.5
  x=$(dump)
  title=$(echo "$x" | grep -oE 'text="[^"]+"[^/]*bounds="\[1[23][0-9]{2},(8[0-9]|9[0-9]|1[0-9]{2})\]' | head -1 | cut -d'"' -f2 | sed 's/&amp;/\&/g')
  b=$(echo "$x" | grep -E 'text="Hide"' | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1 | grep -oE '[0-9]+' | paste -sd' ' -)
  if [ -z "$b" ]; then echo "no Hide for $d, abort"; k KEYCODE_BACK; break; fi
  set -- $b; tx=$(( ($1+$3)/2 )); ty=$(( ($2+$4)/2 ))
  adb -s $S shell input tap $tx $ty; sleep 0.7
  # a confirm dialog or the menu may remain; back out if menu still open
  echo "$(dump)" | grep -q 'text="Visibility"' && k KEYCODE_BACK && sleep 0.3
  echo "HIDE  $d"
done
