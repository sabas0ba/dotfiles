import os
import tempfile
import unittest

from avatar import body, clothes, face, hair, png, shapekeys, spec, weights


class PartsTest(unittest.TestCase):
    def test_parts_are_consistent(self) -> None:
        for module in (body, face, hair, clothes):
            mesh = module.build()
            self.assertEqual(len(mesh.tags), len(mesh.verts))
            self.assertEqual(len(mesh.face_materials), len(mesh.faces))
            for tag in set(mesh.tags):
                self.assertIn(tag, module.WEIGHT_RULES, f"{module.__name__}: 規則のない tag {tag}")
            for material in set(mesh.face_materials):
                self.assertIn(material, spec.MATERIALS)
            for f in mesh.faces:
                for index in f:
                    self.assertTrue(0 <= index < len(mesh.verts))

    def test_body_is_symmetric_and_grounded(self) -> None:
        mesh = body.build()
        min_z = min(v[2] for v in mesh.verts)
        max_z = max(v[2] for v in mesh.verts)
        self.assertGreaterEqual(min_z, 0.0)
        ratio = (max_z - min_z) / spec.HEAD_H
        self.assertTrue(2.35 <= ratio <= 2.55, ratio)
        xs = [v[0] for v in mesh.verts]
        self.assertAlmostEqual(max(xs), -min(xs), places=6)

    def test_triangle_budget_before_subdivision(self) -> None:
        # subdivision で素体と衣装は 4 倍になる。上限に収まる見込みを確認する。
        estimate = (
            body.build().triangle_count() * 4
            + clothes.build().triangle_count() * 4
            + hair.build().triangle_count() * 2
            + face.build().triangle_count()
        )
        self.assertLessEqual(estimate, spec.MAX_TRIANGLES)


class WeightsTest(unittest.TestCase):
    def test_chain_weights_normalized(self) -> None:
        for rule in body.WEIGHT_RULES.values():
            for point in ((0.0, 0.0, 0.3), (0.05, -0.02, 0.9), (0.1, 0.0, 0.05)):
                w = weights.weights_for(point, rule)
                self.assertAlmostEqual(sum(w.values()), 1.0, places=9)
                for name in w:
                    self.assertIn(name, spec.BONE_BY_NAME)

    def test_joint_blend_is_shared(self) -> None:
        knee = spec.BONE_BY_NAME["LowerLeg.L"].head
        w = weights.chain_weights(knee, spec.CHAINS["leg.L"])
        self.assertAlmostEqual(w["UpperLeg.L"], 0.5, places=6)
        self.assertAlmostEqual(w["LowerLeg.L"], 0.5, places=6)

    def test_ends_saturate(self) -> None:
        w = weights.chain_weights((0.0, 0.0, 0.0), spec.CHAINS["torso"])
        self.assertEqual(w, {"Hips": 1.0})
        w = weights.chain_weights((0.0, 0.0, 2.0), spec.CHAINS["torso"])
        self.assertEqual(w, {"Head": 1.0})

    def test_unknown_rule(self) -> None:
        with self.assertRaises(ValueError):
            weights.weights_for((0.0, 0.0, 0.0), "magic:x")


class ShapeKeyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.mesh = face.build()

    def test_all_keys_defined(self) -> None:
        for key in ("Basis", *spec.SHAPE_KEYS):
            positions = shapekeys.positions(key, self.mesh.verts, self.mesh.tags)
            self.assertEqual(len(positions), len(self.mesh.verts))

    def test_dot_eyes_hidden_in_basis_and_visible_in_key(self) -> None:
        basis = shapekeys.positions("Basis", self.mesh.verts, self.mesh.tags)
        dots = shapekeys.positions("DotEyes", self.mesh.verts, self.mesh.tags)
        for tag, b, d in zip(self.mesh.tags, basis, dots, strict=True):
            base, _ = face.split_tag(tag)
            if base == "dot":
                self.assertGreater(b[1], d[1])  # 基準では +Y 側 (内側)
            elif base in shapekeys.ANIME_EYE:
                self.assertLess(b[1], d[1])

    def test_blink_flattens_eyes(self) -> None:
        basis = shapekeys.positions("Basis", self.mesh.verts, self.mesh.tags)
        blink = shapekeys.positions("Blink", self.mesh.verts, self.mesh.tags)
        eye_z = [p[2] for p, t in zip(basis, self.mesh.tags, strict=True) if t == "eye.L"]
        blink_z = [p[2] for p, t in zip(blink, self.mesh.tags, strict=True) if t == "eye.L"]
        self.assertLess(max(blink_z) - min(blink_z), (max(eye_z) - min(eye_z)) * 0.1)

    def test_mouth_closed_in_basis(self) -> None:
        basis = shapekeys.positions("Basis", self.mesh.verts, self.mesh.tags)
        aa = shapekeys.positions("vrc.v_aa", self.mesh.verts, self.mesh.tags)
        mouth_basis = [p[2] for p, t in zip(basis, self.mesh.tags, strict=True) if t == "mouth"]
        mouth_aa = [p[2] for p, t in zip(aa, self.mesh.tags, strict=True) if t == "mouth"]
        self.assertLess(max(mouth_basis) - min(mouth_basis), spec.MOUTH_FULL_H * 0.1)
        self.assertAlmostEqual(max(mouth_aa) - min(mouth_aa), spec.MOUTH_FULL_H, places=6)


class PngTest(unittest.TestCase):
    def test_gradient_endpoints(self) -> None:
        self.assertEqual(
            png.gradient_rgb8(0.0, spec.HAIR_GRADIENT_STOPS),
            png.srgb_hex_to_rgb8(spec.PALETTE["hair_blue"]),
        )
        self.assertEqual(
            png.gradient_rgb8(1.0, spec.HAIR_GRADIENT_STOPS),
            png.srgb_hex_to_rgb8(spec.PALETTE["hair_base"]),
        )

    def test_write_png_signature(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "g.png")
            png.write_hair_gradient(path, width=4, height=16)
            with open(path, "rb") as f:
                data = f.read()
        self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertTrue(data.endswith(b"IEND\xaeB`\x82"))

    def test_srgb_conversion(self) -> None:
        self.assertAlmostEqual(png.srgb_to_linear(1.0), 1.0)
        self.assertAlmostEqual(png.srgb_to_linear(0.0), 0.0)
        self.assertLess(png.srgb_to_linear(0.5), 0.5)


if __name__ == "__main__":
    unittest.main()
