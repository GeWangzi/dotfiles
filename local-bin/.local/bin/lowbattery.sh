#!/bin/bash

BAT=$(cat /sys/class/power_supply/BAT0/capacity)
STATUS=$(cat /sys/class/power_supply/BAT0/status)
STATEFILE="$HOME/.cache/lowbattery.last"

# Only care if discharging
[ "$STATUS" = "Discharging" ] || { rm -f "$STATEFILE"; exit 0; }

# Thresholds
if [ "$BAT" -le 5 ]; then LEVEL=5
elif [ "$BAT" -le 10 ]; then LEVEL=10
elif [ "$BAT" -le 15 ]; then LEVEL=15
else rm -f "$STATEFILE"; exit 0
fi

# Prevent repeat notifications
LAST=$(cat "$STATEFILE" 2>/dev/null || echo "")
[ "$LAST" = "$LEVEL" ] && exit 0

echo "$LEVEL" > "$STATEFILE"

notify-send -u critical "Low Battery" "Battery is at ${BAT}%"
