import importlib.util
from pathlib import Path
import unittest


root = Path(__file__).resolve().parents[2]
specification = importlib.util.spec_from_file_location('glyphs', root / 'Scripts/generate-flutter-glyphs.py')
glyphs = importlib.util.module_from_spec(specification)
specification.loader.exec_module(glyphs)


class FlutterGlyphTests(unittest.TestCase):
    def test_adjacent_arc_flags_do_not_consume_the_endpoint(self):
        segments = glyphs.PathParser('M1 0a1 1 0 011 1').parse()
        self.assertEqual(segments[0], ('moveTo', (1, 0)))
        self.assertEqual(segments[1][0], 'cubicTo')
        self.assertEqual(len(segments), 2)
        for actual, expected in zip(segments[1][1], (1.552285, 0, 2, 0.447715, 2, 1)):
            self.assertAlmostEqual(actual, expected, places=5)

    def test_repeated_move_pairs_and_close_preserve_relative_coordinates(self):
        self.assertEqual(
            glyphs.PathParser('M1 2 3 4h2v-1z m1 1 2 3').parse(),
            [
                ('moveTo', (1, 2)), ('lineTo', (3, 4)),
                ('lineTo', (5, 4)), ('lineTo', (5, 3)), ('close', ()),
                ('moveTo', (2, 3)), ('lineTo', (4, 6)),
            ],
        )

    def test_smooth_curve_reflects_only_the_previous_curve(self):
        segments = glyphs.PathParser('M0 0C1 0 2 1 3 1s2 1 3 0l1 0s2 1 3 0').parse()
        self.assertEqual(segments[2], ('cubicTo', (4, 1, 5, 2, 6, 1)))
        self.assertEqual(segments[4], ('cubicTo', (7, 1, 9, 2, 10, 1)))

    def test_degenerate_arcs_follow_svg_rules(self):
        self.assertEqual(glyphs.arc_segments((0, 0), (0, 0), 1, 1, 0, False, True), [])
        self.assertEqual(
            glyphs.arc_segments((0, 0), (2, 3), 0, 1, 0, False, True),
            [('lineTo', (2, 3))],
        )

    def test_invalid_paths_fail_instead_of_emitting_partial_glyphs(self):
        for data in ('M1', 'M0 0R1 2', 'M0 0A1 1 0 2 0 1 1', 'M0 0z1 2'):
            with self.subTest(data=data), self.assertRaises(ValueError):
                glyphs.PathParser(data).parse()


if __name__ == '__main__':
    unittest.main()
