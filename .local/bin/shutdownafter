#!/bin/bash

pattern=$1
if [ -z "${pattern}" ]; then
	echo missing expr
	exit 0
fi

result=$(ps -e | grep -i $pattern) 
while [ ! -z "${result}" ]; do
	echo found "$result"
	sleep 3
	result=$(ps -e | grep -i $pattern)
done

echo proc $pattern has finished or not found
systemctl poweroff
exit 0

