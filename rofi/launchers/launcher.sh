#!/usr/bin/env bash

## Author : Aditya Shakya (adi1090x)
## Github : @adi1090x

dir="$HOME/.config/rofi/launchers"
theme='style'

## Run
rofi \
    -show drun \
    -theme ${dir}/${theme}.rasi \
    -matching fuzzy
