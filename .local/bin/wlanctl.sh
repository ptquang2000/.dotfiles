#!bin/bash

OFFSET=6

device=$(iwctl device list | grep on | awk '{ print $2 }' -)
iwctl station $device scan
available_networks=$(iwctl station $device get-networks | grep -U psk | head -n $OFFSET | awk -F"psk" '{ print $1 }')

echo "$available_networks"

exit 0

