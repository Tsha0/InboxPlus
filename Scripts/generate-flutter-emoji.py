#!/usr/bin/env python3
"""Export the retained app's emoji catalog for every Flutter platform."""

import argparse
import json
from pathlib import Path
import subprocess


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
arguments = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/InboxPlusUI/ReactionPicker.swift').read_text()
start = source.index('enum EmojiCatalog {')
end = source.index('\n}\n', start) + 3
program = 'import Foundation\n' + source[start:end] + '''
let catalog: [String: Any] = [
    "categories": EmojiCatalog.categories.map { ["name": $0.name, "emoji": $0.emoji] },
    "named": EmojiCatalog.all.map { ["emoji": $0.emoji, "name": $0.name] }
]
let data = try JSONSerialization.data(withJSONObject: catalog)
FileHandle.standardOutput.write(data)
'''
result = subprocess.run(['swift', '-'], input=program, text=True,
                        capture_output=True, check=True)
generated = json.dumps(json.loads(result.stdout), ensure_ascii=False, indent=2, sort_keys=True) + '\n'
destination = root / 'apps/inboxplus_flutter/assets/reaction_emoji.json'
if arguments.check:
    if destination.read_text() != generated:
        raise SystemExit('Flutter emoji differ; run Scripts/generate-flutter-emoji.py on macOS.')
else:
    destination.write_text(generated)
