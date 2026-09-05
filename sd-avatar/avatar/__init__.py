"""SD 頭身キャラクターの VRChat 向け 3D model を生成する package。

bpy に依存しない module (spec, geometry, weights, shapekeys) と、Blender 内でのみ動作する
module (bl_*, build, export, render) に分けている。前者は plain Python で unit test する。
"""
