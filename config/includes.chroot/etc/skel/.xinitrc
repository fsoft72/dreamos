#!/bin/sh
# startx entry point: launch the Openbox session under a D-Bus session
# bus (GTK4 and OpusDM expect one). Openbox then runs
# /etc/xdg/openbox/autostart, which starts opusdm-hub as the desktop
# shell.
exec dbus-run-session -- openbox-session
