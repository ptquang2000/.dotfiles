#!/usr/bin/env bash

# Terminate already running bar instances
# If all your bars have ipc enabled, you can use 
polybar-msg cmd quit
# Otherwise you can use the nuclear option:
# killall -q polybar

# Launch bar1 and bar2
echo "---" | tee -a /tmp/polybar_dock.log /tmp/polybar_status.log
polybar dock 2>&1 | tee -a /tmp/polybar_dock.log & disown
polybar status 2>&1 | tee -a /tmp/polybar_status.log & disown

echo "Bars launched..."
