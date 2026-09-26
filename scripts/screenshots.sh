#!/usr/bin/env bash
# Drives the demo build through the rider flow on an emulator and saves screenshots to shots/.
set -u
PKG=com.bucks.app; mkdir -p shots; n=0
tap() { for _ in 1 2 3 4 5 6 7 8; do
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1
    if xy=$(python3 scripts/ui_find.py "$1" < /tmp/ui.xml); then adb shell input tap $xy; sleep 1.5; return 0; fi; sleep 1
  done; echo "::warning::not found on screen: $1"; return 1; }
type_in() { tap "$1" && adb shell input text "$2" && adb shell input keyevent 111; sleep 1; }
shot() { n=$((n+1)); f=$(printf "shots/%02d_%s.png" $n "$1"); adb exec-out screencap -p > "$f"; echo "saved $f"; }

adb install -r app/build/outputs/apk/debug/app-debug.apk
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS; do adb shell pm grant $PKG android.permission.$p || true; done
adb emu geo fix 77.5938 12.9250   # Jayanagar, Bengaluru
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null; sleep 6
shot welcome
tap "Get started";                      shot sign_in
type_in "@edit" 9876543210; tap "Send code"; sleep 1
type_in "@edit" 1234;                   shot otp
tap "Verify"; sleep 1
type_in "@edit" "Deepa"; tap "Continue"; shot profile_area
tap "Continue"; tap "Finish"; sleep 8;  shot home
tap "Services"; sleep 5;                shot services
tap "Pay"; sleep 0.5;                   shot locked_service
tap "Taxi"; sleep 2; tap "MG Road";     shot destination
tap "Confirm"; sleep 3;                 shot choose_vehicle
tap "Confirm"; sleep 4;                 shot pickup
tap "Confirm pick-up"; sleep 1;         shot confirm_booking
tap "Confirm"; sleep 2;                 shot finding_rider
sleep 5;                                shot rider_found
sleep 9;                                shot rider_arrived
ls -la shots
