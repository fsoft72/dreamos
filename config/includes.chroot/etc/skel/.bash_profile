# Read the standard profile first (it sources ~/.bashrc).
[ -f "$HOME/.profile" ] && . "$HOME/.profile"

# Start the graphical session automatically on the first VT only.
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
