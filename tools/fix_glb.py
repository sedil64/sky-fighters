#!/usr/bin/env python3
"""Arregla los .glb que genera Higgsfield (sam_3_3d) para usarlos en Godot.

Problemas que corrige:
  1. No traen normales (atributo NORMAL). Las que genera el importador salen
     mal y la iluminación depende del giro del modelo. Aquí se calculan normales
     suaves, soldando los vértices duplicados en las costuras de UV.
  2. No definen metallicFactor, que en glTF vale 1.0 por defecto (metal puro):
     todo se ve oscuro. Se pone a 0 (o al valor de --metallic).

Uso:
  python3 tools/fix_glb.py entrada.glb [salida.glb] [--metallic 0.0] [--roughness 0.85]
Si no se da salida, sobrescribe la entrada.
"""
import argparse
import json
import struct

import numpy as np

COMPONENT_DTYPE = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _ = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67 and version == 2, "no es un GLB v2"
    off, gltf, binchunk = 12, None, b""
    while off < len(data):
        length, ctype = struct.unpack("<II", data[off:off + 8])
        chunk = data[off + 8:off + 8 + length]
        if ctype == 0x4E4F534A:
            gltf = json.loads(chunk)
        elif ctype == 0x004E4942:
            binchunk = bytearray(chunk)
        off += 8 + length
    return gltf, binchunk


def write_glb(path, gltf, binchunk):
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    binchunk = bytes(binchunk) + b"\0" * ((4 - len(binchunk) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binchunk)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binchunk), 0x004E4942) + binchunk)


def read_accessor(gltf, binchunk, idx):
    acc = gltf["accessors"][idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    dtype = COMPONENT_DTYPE[acc["componentType"]]
    n = TYPE_COUNT[acc["type"]]
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    item = np.dtype(dtype).itemsize * n
    if stride and stride != item:
        raw = np.frombuffer(binchunk, np.uint8, count=stride * acc["count"], offset=start)
        raw = raw.reshape(acc["count"], stride)[:, :item].copy()
        return raw.view(dtype).reshape(acc["count"], n)
    arr = np.frombuffer(binchunk, dtype, count=acc["count"] * n, offset=start)
    return arr.reshape(acc["count"], n) if n > 1 else arr


def smooth_normals(pos, tris):
    # Suelda vértices con la misma posición (costuras de UV) para que las
    # normales sean continuas.
    key = np.round(pos / (np.ptp(pos, axis=0).max() * 1e-5)).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    a, b, c = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    fn = np.cross(b - a, c - a)  # ponderada por área
    acc = np.zeros((weld.max() + 1, 3))
    for k in range(3):
        np.add.at(acc, weld[tris[:, k]], fn)
    nrm = acc[weld]
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
    # No se voltean: la normal sale del winding de cada cara, que es lo que el
    # motor usa para decidir qué cara se ve. (Algunos modelos, como la isla,
    # son cáscaras finas con una capa interior mirando hacia dentro; un
    # criterio "hacia fuera del centro" las estropearía.)
    return nrm.astype(np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst", nargs="?")
    ap.add_argument("--metallic", type=float, default=0.0)
    ap.add_argument("--roughness", type=float, default=0.85)
    args = ap.parse_args()

    gltf, binchunk = read_glb(args.src)
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            pos = read_accessor(gltf, binchunk, attrs["POSITION"]).astype(np.float64)
            if "indices" in prim:
                tris = read_accessor(gltf, binchunk, prim["indices"]).astype(np.int64).reshape(-1, 3)
            else:
                tris = np.arange(len(pos)).reshape(-1, 3)
            nrm = smooth_normals(pos, tris)
            while len(binchunk) % 4:
                binchunk.append(0)
            offset = len(binchunk)
            binchunk += nrm.tobytes()
            gltf["bufferViews"].append({"buffer": 0, "byteOffset": offset,
                                        "byteLength": nrm.nbytes, "target": 34962})
            gltf["accessors"].append({"bufferView": len(gltf["bufferViews"]) - 1,
                                      "componentType": 5126, "count": len(nrm), "type": "VEC3",
                                      "min": nrm.min(0).tolist(), "max": nrm.max(0).tolist()})
            attrs["NORMAL"] = len(gltf["accessors"]) - 1
            print(f" {args.src}: {len(pos)} vértices, {len(tris)} triángulos -> normales añadidas")
    for mat in gltf.get("materials", []):
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = args.metallic
        pbr["roughnessFactor"] = args.roughness
    gltf["buffers"][0]["byteLength"] = len(binchunk)
    write_glb(args.dst or args.src, gltf, binchunk)


if __name__ == "__main__":
    main()
