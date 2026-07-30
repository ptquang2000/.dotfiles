-- ################
-- ### MONITORS ###
-- ################

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- ###################
-- ### MY PROGRAMS ###
-- ###################

local terminal = "ghostty"
local menu = 'bemenu-run --fn "CaskaydiaCove Nerd Font" --hp 6 w'
local browser = "zen-browser"

-- #############################
-- ### ENVIRONMENT VARIABLES ###
-- #############################

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("GTK_THEME", "Adwaita:dark")
hl.env("GTK2_RC_FILES", "/usr/share/themes/Adwaita-dark/gtk-2.0/gtkrc")
hl.env("QT_STYLE_OVERRIDE", "Adwaita-Dark")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")

-- #################
-- ### AUTOSTART ###
-- #################

hl.on("hyprland.start", function()
	hl.exec_cmd("fcitx5 -d -r")
	hl.exec_cmd("hypridle")
	hl.exec_cmd("hyprpaper")
	hl.exec_cmd("hyprpolkitagent")
	hl.exec_cmd("mako")
	hl.exec_cmd("waybar")
	hl.exec_cmd([[gsettings set org.gnome.desktop.interface gtk-theme "Adwaita:Dark"]])
	hl.exec_cmd([[gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark']])
	hl.exec_cmd("mkdir -p " .. os.getenv("HOME") .. "/Work")
	hl.exec_cmd("mkdir -p " .. os.getenv("HOME") .. "/Downloads")
	hl.exec_cmd("mkdir -p " .. os.getenv("HOME") .. "/Pictures/Screenshots")
	hl.exec_cmd("warp-taskbar")
	hl.exec_cmd("sioyek")
	hl.exec_cmd("ghostty")
	hl.exec_cmd("zen-browser")
end)

-- #####################
-- ### LOOK AND FEEL ###
-- #####################

hl.config({
	general = {
		gaps_in = 0,
		gaps_out = 0,
		border_size = 0,
		col = {
			active_border = { colors = { "rgb(1d2021)" }, angle = 45 },
			inactive_border = "rgb(1d2021)",
		},
		resize_on_border = true,
		allow_tearing = false,
		layout = "dwindle",
	},
})

hl.config({
	decoration = {
		rounding = 0,
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		shadow = {
			enabled = true,
			range = 4,
			color = "rgba(1a1a1aee)",
			render_power = 3,
		},
		blur = {
			enabled = true,
			size = 8,
			passes = 2,
			vibrancy = 0.1696,
		},
	},
})

hl.config({
	animations = {
		enabled = false,
	},
})

hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 7, bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7, bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 7, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "default" })

hl.config({
	dwindle = {
		preserve_split = true,
		force_split = 2,
	},
})

hl.config({
	master = {
		new_status = "master",
	},
})

hl.config({
	misc = {
		force_default_wallpaper = 0,
		disable_hyprland_logo = true,
	},
})

-- #############
-- ### INPUT ###
-- #############

hl.config({
	input = {
		kb_layout = "us",
		kb_variant = "",
		kb_model = "",
		kb_options = "",
		kb_rules = "",
		follow_mouse = 1,
		accel_profile = "adaptive",
		sensitivity = 0,
		touchpad = {
			natural_scroll = false,
		},
	},
})

hl.device({
	name = "epic-mouse-v1",
	sensitivity = -0.5,
})

-- ###################
-- ### KEYBINDINGS ###
-- ###################

local mainMod = "ALT"

hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd("systemctl poweroff"))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exit())
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu))

hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
	local k = i % 10
	hl.bind(mainMod .. " + " .. k, hl.dsp.focus({ workspace = i }))
end

for i = 1, 10 do
	local k = i % 10
	hl.bind(mainMod .. " + SHIFT + " .. k, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

local wpvol =
	[[export volume=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print ($2 * 100) / 1}' | bc) && notify-send -t 1000 -a 'wp-vol' -h int:value:$volume "Volume: ${volume}%"]]

hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5% && " .. wpvol),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5% && " .. wpvol),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioMute",
	hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioMicMute",
	hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"),
	{ locked = true, repeating = true }
)

-- Screenshot
hl.bind(
	mainMod .. " + SHIFT + S",
	hl.dsp.exec_cmd(
		[[export sspath="${HOME}/Pictures/Screenshots/$(date +'%Y%m%d_%H%M%S_grim.png')" && grim -g "$(slurp)" $sspath && sioyek --new-window $sspath]]
	)
)

-- ##############################
-- ### WINDOWS AND WORKSPACES ###
-- ##############################

hl.window_rule({ match = { class = "^(zen)$" }, workspace = "1" })
hl.window_rule({ match = { class = "^(com.mitchellh.ghostty)$" }, workspace = "2" })
hl.window_rule({ match = { class = "^(org.pwmt.zathura)$" }, workspace = "2" })
hl.window_rule({ match = { class = "^(sioyek)$" }, workspace = "3" })
hl.window_rule({ match = { class = "^(Waydroid)$" }, workspace = "4" })

hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

hl.window_rule({ match = { title = "^([Pp]icture[\\-\\s]in[\\-\\s][Pp]icture)$" }, float = true })
hl.window_rule({ match = { title = "^([Pp]icture[\\-\\s]in[\\-\\s][Pp]icture)$" }, pin = true })

hl.window_rule({ match = { class = "^(mpv)$" }, float = true })
hl.window_rule({ match = { class = "^(mpv)$" }, content = "none" })
