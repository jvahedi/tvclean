#!/bin/bash
# tap.sh "Exact text" — tap the first on-screen node with that text
S=$(adb devices | awk '/_adb-tls-connect/{print $1}')
adb -s $S shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
b=$(adb -s $S shell cat /sdcard/ui.xml | tr '>' '\n' | grep -F "text=\"$1\"" | head -1 | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | grep -oE '[0-9]+' | paste -sd' ' -)
[ -n "$b" ] || { echo "no '$1'"; exit 1; }
set -- $b; adb -s $S shell input tap $(( ($1+$3)/2 )) $(( ($2+$4)/2 ))
