#!/usr/bin/env python3
"""Generate Flutter vector paths directly from the canonical brand SVGs."""

import argparse
import math
from pathlib import Path
import re
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = (
    'instagram', 'whatsapp', 'messenger', 'telegram', 'discord',
    'slack', 'linkedin', 'imessage', 'wechat',
)
NUMBER = re.compile(r'[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?')


def arc_segments(start, end, rx, ry, rotation, large_arc, sweep):
    if start == end:
        return []
    if rx == 0 or ry == 0:
        return [('lineTo', end)]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(rotation)
    cosine, sine = math.cos(phi), math.sin(phi)
    dx, dy = ((start[i] - end[i]) / 2 for i in (0, 1))
    x1, y1 = cosine * dx + sine * dy, -sine * dx + cosine * dy
    scale = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if scale > 1:
        rx *= math.sqrt(scale)
        ry *= math.sqrt(scale)
    numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
    denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    coefficient = (-1 if large_arc == sweep else 1) * math.sqrt(numerator / denominator)
    cx1, cy1 = coefficient * rx * y1 / ry, -coefficient * ry * x1 / rx
    cx = cosine * cx1 - sine * cy1 + (start[0] + end[0]) / 2
    cy = sine * cx1 + cosine * cy1 + (start[1] + end[1]) / 2

    def angle(ux, uy, vx, vy):
        length = math.hypot(ux, uy) * math.hypot(vx, vy)
        value = max(-1, min(1, (ux * vx + uy * vy) / length))
        return (-1 if ux * vy - uy * vx < 0 else 1) * math.acos(value)

    theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    turn = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if not sweep and turn > 0:
        turn -= 2 * math.pi
    if sweep and turn < 0:
        turn += 2 * math.pi
    count = max(1, math.ceil(abs(turn) / (math.pi / 2)))
    delta = turn / count
    alpha = 4 / 3 * math.tan(delta / 4)

    def point(x, y):
        return cosine * rx * x - sine * ry * y + cx, sine * rx * x + cosine * ry * y + cy

    segments = []
    for _ in range(count):
        next_theta = theta + delta
        c, s = math.cos(theta), math.sin(theta)
        nc, ns = math.cos(next_theta), math.sin(next_theta)
        first = point(c - alpha * s, s + alpha * c)
        second = point(nc + alpha * ns, ns - alpha * nc)
        segments.append(('cubicTo', first + second + point(nc, ns)))
        theta = next_theta
    return segments


class PathParser:
    def __init__(self, data):
        self.data = data
        self.index = 0

    def skip_separators(self):
        while self.index < len(self.data) and self.data[self.index] in ' ,\n\t\r':
            self.index += 1

    def number(self):
        self.skip_separators()
        match = NUMBER.match(self.data, self.index)
        if match is None:
            raise ValueError('Expected an SVG path number')
        self.index = match.end()
        return float(match.group())

    def flag(self):
        self.skip_separators()
        if self.index == len(self.data) or self.data[self.index] not in '01':
            raise ValueError('Expected a single SVG arc flag')
        value = self.data[self.index] == '1'
        self.index += 1
        return value

    def parse(self):
        segments = []
        current = start = (0, 0)
        cubic_control = quad_control = None
        command = None
        while True:
            self.skip_separators()
            if self.index == len(self.data):
                return segments
            if self.data[self.index].isalpha():
                command = self.data[self.index]
                self.index += 1
            elif command == 'M':
                command = 'L'
            elif command == 'm':
                command = 'l'
            if command is None or command.lower() not in 'mlhvcsqtaz':
                raise ValueError('Unsupported SVG path command')
            kind = command.lower()

            def point():
                x, y = self.number(), self.number()
                return (current[0] + x, current[1] + y) if command.islower() else (x, y)

            previous_cubic, previous_quad = cubic_control, quad_control
            cubic_control = quad_control = None
            if kind == 'm':
                current = start = point()
                segments.append(('moveTo', current))
            elif kind == 'l':
                current = point()
                segments.append(('lineTo', current))
            elif kind in 'hv':
                axis = 0 if kind == 'h' else 1
                value = self.number() + (current[axis] if command.islower() else 0)
                current = (value, current[1]) if axis == 0 else (current[0], value)
                segments.append(('lineTo', current))
            elif kind in 'cs':
                first = point() if kind == 'c' else (
                    tuple(2 * current[i] - previous_cubic[i] for i in (0, 1))
                    if previous_cubic is not None else current
                )
                second, end = point(), point()
                segments.append(('cubicTo', first + second + end))
                current, cubic_control = end, second
            elif kind in 'qt':
                control = point() if kind == 'q' else (
                    tuple(2 * current[i] - previous_quad[i] for i in (0, 1))
                    if previous_quad is not None else current
                )
                end = point()
                segments.append(('quadraticBezierTo', control + end))
                current, quad_control = end, control
            elif kind == 'a':
                rx, ry, rotation = self.number(), self.number(), self.number()
                large_arc, sweep = self.flag(), self.flag()
                end = point()
                segments.extend(arc_segments(current, end, rx, ry, rotation, large_arc, sweep))
                current = end
            elif kind == 'z':
                segments.append(('close', ()))
                current, command = start, None


def svg_segments(path):
    svg = ET.fromstring(path.read_text())
    if svg.attrib.get('viewBox') != '0 0 24 24':
        raise ValueError('Brand SVG must use a 24x24 viewBox: ' + path.name)
    paths = svg.findall('{http://www.w3.org/2000/svg}path')
    if len(paths) != 1 or 'transform' in svg.attrib or 'transform' in paths[0].attrib:
        raise ValueError('Brand SVG must contain one untransformed path: ' + path.name)
    return PathParser(paths[0].attrib['d']).parse()


def generate():
    lines = [
        '// Generated by Scripts/generate-flutter-glyphs.py; do not edit.',
        '// Simple Icons brand marks are CC0; trademarks belong to their owners.',
        "import 'dart:ui';", '', 'Path? platformGlyphPath(String platform) {',
        '  switch (platform) {',
    ]
    for platform in PLATFORMS:
        lines.extend([f"    case '{platform}':", '      return Path()'])
        for method, values in svg_segments(ROOT / 'Scripts/brand-icons' / (platform + '.svg')):
            arguments = ', '.join(f'{value:.3f}' for value in values)
            lines.append(f'        ..{method}({arguments})')
        lines[-1] += ';'
    lines.extend(['    default:', '      return null;', '  }', '}', ''])
    return '\n'.join(lines)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    arguments = parser.parse_args()
    destination = ROOT / 'apps/inboxplus_flutter/lib/ui/platform_glyphs.dart'
    generated = generate()
    if arguments.check:
        if destination.read_text() != generated:
            raise SystemExit('Flutter platform glyphs differ; run Scripts/generate-flutter-glyphs.py.')
    else:
        destination.write_text(generated)
