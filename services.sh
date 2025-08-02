#!/bin/bash

echo Enable services
systemctl enable --now systemd-resolved
systemctl enable --now reflector.service
systemctl --user enable --now waybar.service
