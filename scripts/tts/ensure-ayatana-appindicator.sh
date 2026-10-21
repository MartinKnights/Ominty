#!/usr/bin/env bash
# Provision the Ayatana AppIndicator typelib for piper-indicator without root.
#
# piper-indicator publishes its tray icon over StatusNotifierItem on Wayland,
# which needs the AyatanaAppIndicator3 GObject typelib.  On systems where
# gir1.2-ayatanaappindicator3-0.1 is not installed and sudo is unavailable,
# this script extracts the .debs into a user-local prefix and prints the
# environment needed to use them.
#
# piper-indicator already re-execs itself with these variables when the prefix
# exists, so no shell configuration is required.
#
# The permanent, system-wide fix is:
#   sudo apt install gir1.2-ayatanaappindicator3-0.1 libayatana-appindicator3-1

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local/opt/ayatana-appindicator}"
MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null \
    || echo "$(dpkg --print-architecture)-linux-gnu")"
LIBDIR="$PREFIX/usr/lib/$MULTIARCH"
TYPELIB="$LIBDIR/girepository-1.0/AyatanaAppIndicator3-0.1.typelib"
SYS_TYPELIB="/usr/lib/$MULTIARCH/girepository-1.0/AyatanaAppIndicator3-0.1.typelib"

if [[ -f "$SYS_TYPELIB" ]]; then
    echo "AyatanaAppIndicator3 typelib already installed system-wide:"
    echo "  $SYS_TYPELIB"
    exit 0
fi

if [[ -f "$TYPELIB" ]]; then
    echo "User-local typelib already provisioned:"
    echo "  $TYPELIB"
else
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    echo "Downloading packages (no root required)..."
    (
        cd "$tmp"
        apt-get download \
            gir1.2-ayatanaappindicator3-0.1 \
            libayatana-appindicator3-1
    )

    echo "Extracting into $PREFIX ..."
    mkdir -p "$PREFIX"
    for deb in "$tmp"/*.deb; do
        dpkg-deb -x "$deb" "$PREFIX"
    done

    if [[ ! -f "$TYPELIB" ]]; then
        echo "error: typelib not found after extraction: $TYPELIB" >&2
        exit 1
    fi
    echo "Provisioned: $TYPELIB"
fi

cat <<EOF

Environment used by piper-indicator's self-reexec block:
  export LD_LIBRARY_PATH="$LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
  export GI_TYPELIB_PATH="$LIBDIR/girepository-1.0\${GI_TYPELIB_PATH:+:\$GI_TYPELIB_PATH}"

Verify:
  GI_TYPELIB_PATH="$LIBDIR/girepository-1.0" \\
  LD_LIBRARY_PATH="$LIBDIR" \\
  python3 -c "import gi; gi.require_version('AyatanaAppIndicator3','0.1'); from gi.repository import AyatanaAppIndicator3; print('ok')"
EOF
