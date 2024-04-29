#!/usr/bin/env bash

filename=screenshot-$(date +"%Y%m%d-%H-%M-%S")
ext=.png
dest=~/pictures/
if [ ! -d $dest_path ]; then
	mkdir $dest
fi
if [ -f $dest_path$filename ]; then
	filename=$filename.1
fi
filepath=$dest$filename$ext
maim -s --hidecursor $filepath
mupdf $filepath

