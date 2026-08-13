#!/bin/sh
set -eu

python_path=/opt/homebrew/opt/python@3.12/bin/python3.12
temporary_runtime=$(mktemp -d)
trap 'rm -rf "$temporary_runtime"' EXIT INT TERM

"$python_path" -m venv "$temporary_runtime/venv"
"$temporary_runtime/venv/bin/python" -m pip install -r Runtime/Synapse/requirements.in
"$temporary_runtime/venv/bin/python" -m pip freeze --all | LC_ALL=C sort > Runtime/Synapse/requirements.lock
