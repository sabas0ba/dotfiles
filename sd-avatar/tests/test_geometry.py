import math
import unittest

from avatar import geometry
from avatar.geometry import Mesh


class LoftTest(unittest.TestCase):
    def test_loft_face_count_and_indices(self) -> None:
        rings = [
            geometry.ring((0.0, 0.0, z), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 1.0, 1.0, 8)
            for z in (0.0, 1.0, 2.0)
        ]
        mesh = geometry.loft(rings, "M", "t")
        self.assertEqual(len(mesh.verts), 3 * 8 + 2)
        self.assertEqual(len(mesh.faces), 2 * 8 + 2 * 8)
        self.assertEqual(len(mesh.tags), len(mesh.verts))
        self.assertEqual(len(mesh.face_materials), len(mesh.faces))
        for face in mesh.faces:
            for index in face:
                self.assertTrue(0 <= index < len(mesh.verts))

    def test_loft_rejects_mismatched_rings(self) -> None:
        a = geometry.ring((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 1.0, 1.0, 8)
        b = geometry.ring((0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 1.0, 1.0, 6)
        with self.assertRaises(ValueError):
            geometry.loft([a, b], "M", "t")

    def test_axis_frame_orthonormal(self) -> None:
        for direction in ((0.0, 0.0, 1.0), (0.3, 0.0, -0.9), (0.0, 1.0, 0.0), (0.0, -1.0, 0.0)):
            u, v = geometry.axis_frame(direction)
            d = geometry.normalize(direction)
            self.assertAlmostEqual(geometry.length(u), 1.0, places=9)
            self.assertAlmostEqual(geometry.length(v), 1.0, places=9)
            self.assertAlmostEqual(geometry.dot(u, v), 0.0, places=9)
            self.assertAlmostEqual(geometry.dot(u, d), 0.0, places=9)


class SplineTest(unittest.TestCase):
    def test_catmull_rom_passes_through_endpoints(self) -> None:
        points = [(0.0, 0.0, 0.0), (1.0, 1.0, 0.0), (2.0, 0.0, 0.0)]
        samples = geometry.catmull_rom(points, 9)
        self.assertEqual(len(samples), 9)
        self.assertEqual(samples[0], points[0])
        for a, b in zip(samples[-1], points[-1], strict=True):
            self.assertAlmostEqual(a, b, places=9)
        # 中央の標本は中間の制御点を通る。
        for a, b in zip(samples[4], points[1], strict=True):
            self.assertAlmostEqual(a, b, places=9)

    def test_superellipse_extents(self) -> None:
        x, y = geometry.superellipse(0.0, 2.0, 3.0, 2.5)
        self.assertAlmostEqual(x, 2.0)
        self.assertAlmostEqual(y, 0.0)
        x, y = geometry.superellipse(math.pi / 2, 2.0, 3.0, 2.5)
        self.assertAlmostEqual(x, 0.0)
        self.assertAlmostEqual(y, 3.0)


class MeshTest(unittest.TestCase):
    def test_mirror_reverses_winding(self) -> None:
        mesh = Mesh(
            [(1.0, 0.0, 0.0), (1.0, 1.0, 0.0), (1.0, 0.0, 1.0)], [(0, 1, 2)], ["a.L"] * 3, ["M"]
        )
        mirrored = mesh.mirrored_x({"a.L": "a.R"})
        self.assertEqual(mirrored.verts[0], (-1.0, 0.0, 0.0))
        self.assertEqual(mirrored.faces[0], (2, 1, 0))
        self.assertEqual(mirrored.tags, ["a.R"] * 3)

    def test_append_offsets_indices(self) -> None:
        a = Mesh([(0.0, 0.0, 0.0)] * 3, [(0, 1, 2)], ["a"] * 3, ["M"])
        b = Mesh([(0.0, 0.0, 0.0)] * 3, [(0, 1, 2)], ["b"] * 3, ["N"])
        a.append(b)
        self.assertEqual(a.faces[1], (3, 4, 5))
        self.assertEqual(a.triangle_count(), 2)

    def test_tube_ring_count(self) -> None:
        path = [(0.0, 0.0, float(i)) for i in range(5)]
        radii = [(0.1, 0.1)] * 5
        mesh = geometry.tube(path, radii, lambda _p: (1.0, 0.0, 0.0), 6, "M", "t")
        self.assertEqual(len(mesh.verts), 5 * 6 + 2)


if __name__ == "__main__":
    unittest.main()
