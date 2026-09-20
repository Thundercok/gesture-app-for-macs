#!/usr/bin/env bash
# Quick launcher for GestureFlow

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSPACE_DIR="$( cd "$DIR/.." && pwd )"

VENV_PYTHON="$WORKSPACE_DIR/.venv/bin/python"

if [ ! -f "$VENV_PYTHON" ]; then
    echo "Creating virtualenv..."
    python3 -m venv "$WORKSPACE_DIR/.venv"
    source "$WORKSPACE_DIR/.venv/bin/activate"
    pip install opencv-python mediapipe pyobjc-framework-Quartz pyobjc-framework-Vision pyobjc-framework-Cocoa pyyaml numpy
fi

export MPLCONFIGDIR=/tmp

echo "Starting GestureFlow with HUD..."
"$VENV_PYTHON" "$DIR/main.py" "$@"
