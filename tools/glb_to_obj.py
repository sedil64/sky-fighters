#!/usr/bin/env python3
"""Convierte un .glb (una malla con textura, como los de Higgsfield) a OBJ + MTL + PNG
y lo empaqueta en un .zip listo para subir a Mixamo (que no acepta GLB).

Uso:
  python3 tools/glb_to_obj.py assets/models/hero.glb build/mixamo/hero_mixamo.zip [--height 1.6]

El modelo se escala a `--height` metros, con los pies en y = 0, mirando hacia +Z
(lo que espera Mixamo). Solo necesita numpy.
"""
import argparse
import io
import os
import zipfile

import numpy as np

from fix_glb import read_glb, read_accessor


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst_zip")
    ap.add_argument("--height", type=float, default=1.6)
    args = ap.parse_args()

    gltf, binchunk = read_glb(args.src)
    prim = gltf["meshes"][0]["primitives"][0]
    attrs = prim["attributes"]
    pos = read_accessor(gltf, binchunk, attrs["POSITION"]).astype(np.float64)
    uv = read_accessor(gltf, binchunk, attrs["TEXCOORD_0"]).astype(np.float64)
    nrm = read_accessor(gltf, binchunk, attrs["NORMAL"]).astype(np.float64) if "NORMAL" in attrs else None
    tris = read_accessor(gltf, binchunk, prim["indices"]).astype(np.int64).reshape(-1, 3)

    # Escala a la altura pedida, pies en y = 0, centrado en X/Z.
    lo, hi = pos.min(0), pos.max(0)
    s = args.height / (hi[1] - lo[1])
    center = (lo + hi) / 2
    pos = (pos - np.array([center[0], lo[1], center[2]])) * s

    # Textura base embebida en el GLB.
    mat = gltf["materials"][prim.get("material", 0)]
    tex_index = mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    img = gltf["images"][gltf["textures"][tex_index]["source"]]
    bv = gltf["bufferViews"][img["bufferView"]]
    png = bytes(binchunk[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])
    ext = ".png" if img.get("mimeType", "image/png") == "image/png" else ".jpg"
    name = os.path.splitext(os.path.basename(args.dst_zip))[0]
    tex_name = name + "_albedo" + ext

    obj = io.StringIO()
    obj.write(f"mtllib {name}.mtl\no {name}\n")
    for p in pos:
        obj.write(f"v {p[0]:.6f} {p[1]:.6f} {p[2]:.6f}\n")
    for t in uv:
        obj.write(f"vt {t[0]:.6f} {1.0 - t[1]:.6f}\n")  # glTF tiene la V invertida respecto a OBJ
    if nrm is not None:
        for n in nrm:
            obj.write(f"vn {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}\n")
    obj.write(f"usemtl {name}_mat\ns 1\n")
    for a, b, c in tris + 1:
        if nrm is not None:
            obj.write(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}\n")
        else:
            obj.write(f"f {a}/{a} {b}/{b} {c}/{c}\n")
    mtl = (f"newmtl {name}_mat\nKa 1 1 1\nKd 1 1 1\nKs 0 0 0\nd 1\nillum 1\n"
           f"map_Kd {tex_name}\n")

    os.makedirs(os.path.dirname(os.path.abspath(args.dst_zip)), exist_ok=True)
    with zipfile.ZipFile(args.dst_zip, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(f"{name}.obj", obj.getvalue())
        z.writestr(f"{name}.mtl", mtl)
        z.writestr(tex_name, png)
    print(f"{args.dst_zip}: {len(pos)} vértices, {len(tris)} triángulos, altura {args.height} m, textura {tex_name}")


if __name__ == "__main__":
    main()
