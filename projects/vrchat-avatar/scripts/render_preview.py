"""生成した .blend を Cycles (CPU) で複数視点から描画し、確認用 PNG を出力する。

使い方: blender -b --python-exit-code 1 --python scripts/render_preview.py -- build/avatar.blend build/preview

headless 環境には GPU も OpenGL context も無いため、CPU で完結する Cycles を使う。
確認用であり、sample 数は少なく抑える。
"""

import math
import sys
from pathlib import Path

# 名前: (yaw, 注視点の高さの割合, 距離の割合)。割合は mesh の高さに対する比。
VIEWS = {
    "front": (0.0, 0.5, 2.2),
    "three_quarter": (math.radians(35.0), 0.5, 2.2),
    "side": (math.radians(90.0), 0.5, 2.2),
    "back": (math.radians(180.0), 0.5, 2.2),
    "face": (math.radians(15.0), 0.925, 0.55),
}

RESOLUTION = (540, 960)
SAMPLES = 24


def setup_render(scene) -> None:
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    scene.render.resolution_x, scene.render.resolution_y = RESOLUTION
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    # 既定の view transform (AgX) は明部が圧縮され形状の確認に向かないため Standard にする。
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = scene.world
    if world is None:
        import bpy

        world = bpy.data.worlds.new("World")
        scene.world = world
    if world.node_tree is None:
        world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background is not None:
        background.inputs["Color"].default_value = (0.42, 0.42, 0.46, 1.0)
        background.inputs["Strength"].default_value = 0.8


def add_camera(scene, target_height: float, yaw: float, distance: float):
    import bpy
    from mathutils import Vector

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens = 50.0
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    target = Vector((0.0, 0.0, target_height))
    # yaw 0 で -Y 側 (キャラクター正面) から見る。
    position = target + Vector((distance * math.sin(yaw), -distance * math.cos(yaw), 0.0))
    camera.location = position
    direction = target - position
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    return camera


def add_light(scene) -> None:
    import bpy

    light_data = bpy.data.lights.new("PreviewSun", "SUN")
    light_data.energy = 2.5
    light = bpy.data.objects.new("PreviewSun", light_data)
    light.rotation_euler = (math.radians(50.0), math.radians(-20.0), math.radians(30.0))
    scene.collection.objects.link(light)


def main() -> None:
    import bpy

    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(argv) != 2:
        print("使い方: render_preview.py -- <avatar.blend> <出力ディレクトリ>", file=sys.stderr)
        sys.exit(2)
    blend_path, out_dir = Path(argv[0]), Path(argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.open_mainfile(filepath=str(blend_path))
    scene = bpy.context.scene
    setup_render(scene)
    add_light(scene)
    height = max((o.dimensions.z for o in scene.objects if o.type == "MESH"), default=1.7)

    for name, (yaw, target_ratio, distance_ratio) in VIEWS.items():
        camera = add_camera(scene, height * target_ratio, yaw, distance=height * distance_ratio)
        scene.render.filepath = str(out_dir / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(camera, do_unlink=True)
        print(f"rendered {scene.render.filepath}")


if __name__ == "__main__":
    main()
