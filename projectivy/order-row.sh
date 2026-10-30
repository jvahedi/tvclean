#!/bin/bash
# Projectivy: put the TV Apps row in ORDER (by tile name) via each tile's Reorder action.
S=$(adb devices | awk '/_adb-tls-connect/{print $1}')
ORDER=("Netflix" "Paramount+" "Prime Video" "HBO Max" "SmartTube" "Apple TV" "Disney+" "STARZ" "Hulu")
k(){ adb -s $S shell input keyevent "$@"; }
dump(){ adb -s $S shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb -s $S shell cat /sdcard/ui.xml | tr '>' '\n'; }
foc(){ dump | grep 'focused="true"' | grep -oE 'content-desc="[^"]+"' | head -1 | cut -d'"' -f2; }
start(){ for i in $(seq 1 15); do f=$(foc); case "$f" in "TV Apps"|Reorder|Settings) k KEYCODE_DPAD_RIGHT; sleep 0.2; return;; esac; k KEYCODE_DPAD_LEFT; sleep 0.1; done; }
readrow(){ start; ROW=""; prev=""; for i in $(seq 1 12); do f=$(foc); [ "$f" = "$prev" ] && break; ROW="$ROW$f"$'\n'; prev="$f"; k KEYCODE_DPAD_RIGHT; sleep 0.1; done; }
idx(){ printf '%s' "$ROW" | grep -nxF "$1" | cut -d: -f1 | head -1; }
readrow; echo "before:"; printf "%s" "$ROW" | paste -sd"|" -
for i in "${!ORDER[@]}"; do
  want="${ORDER[$i]}"; c=$(idx "$want"); [ -z "$c" ] && { echo "missing $want"; continue; }
  cur=$((c-1)); n=$((cur - i)); [ $n -eq 0 ] && continue
  dir=LEFT; [ $n -lt 0 ] && { dir=RIGHT; n=$((-n)); }   # a tile that must go right moves in one step
  start; keys=""; for j in $(seq 1 $cur); do keys="$keys KEYCODE_DPAD_RIGHT"; done; [ -n "$keys" ] && k $keys; sleep 0.3
  f=$(foc); [ "$f" = "$want" ] || { echo "focus $f != $want, abort"; exit 1; }
  k --longpress KEYCODE_DPAD_CENTER; sleep 0.5
  adb -s $S shell input swipe 1600 900 1600 300 150; sleep 0.3
  b=$(dump | grep -E 'text="Reorder"' | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1 | grep -oE '[0-9]+' | paste -sd' ' -)
  [ -n "$b" ] || { echo "no Reorder"; k KEYCODE_BACK; exit 1; }
  set -- $b; adb -s $S shell input tap $(( ($1+$3)/2 )) $(( ($2+$4)/2 )); sleep 0.6
  for j in $(seq 1 $n); do k KEYCODE_DPAD_$dir; sleep 0.25; done; k KEYCODE_DPAD_CENTER; sleep 0.3
  ROW=$(printf '%s' "$ROW" | awk -v w="$want" -v i=$i '$0!=w{a[n++]=$0} END{for(j=0;j<n;j++){if(j==i)print w; print a[j]} if(i>=n)print w}')$'\n'
  echo "moved $want $dir $n"
done
readrow; echo "after:"; printf "%s" "$ROW" | paste -sd"|" -
