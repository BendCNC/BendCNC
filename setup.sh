#!/usr/bin/env bash
# BendCNC one-step setup for Linux (Debian/Ubuntu/Armbian) and macOS.
# Installs Python 3 + shapely/numpy/networkx and Node.js for CAD import.
set -euo pipefail
cd "$(dirname "$0")"

echo "== BendCNC setup =="
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip python3-venv nodejs
elif command -v brew >/dev/null 2>&1; then
    brew install python node
fi

command -v python3 >/dev/null || { echo "python3 not found"; exit 1; }
command -v node >/dev/null || { echo "node not found"; exit 1; }

# Private runtime inside the planner; the app adds it to PYTHONPATH automatically.
[ -d .git ] && git submodule update --init --recursive
python3 -m pip install --target sequence-planner/runtime/python shapely numpy networkx
PYTHONPATH=sequence-planner/runtime/python python3 -c "import shapely, numpy, networkx; print('shapely', shapely.__version__)"
echo "node $(node --version)"
echo "Setup complete. CAD import and sequence planning are ready."
