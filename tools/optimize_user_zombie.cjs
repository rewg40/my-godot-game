// Rebuild the game-ready copy from the user-supplied static GLB.
// Dependencies: @gltf-transform/{core,extensions,functions} 4.2.1,
// meshoptimizer 0.22.0, mikktspace 1.1.1, and Python Pillow.
// Usage: node tools/optimize_user_zombie.cjs ORIGINAL.glb OPTIMIZED.glb
const { spawnSync } = require('node:child_process');
const { NodeIO } = require('@gltf-transform/core');
const { ALL_EXTENSIONS } = require('@gltf-transform/extensions');
const { weld, unweld, simplify, tangents, prune } = require('@gltf-transform/functions');
const { MeshoptSimplifier } = require('meshoptimizer');
const { generateTangents } = require('mikktspace');

async function main() {
  if (process.argv.length !== 4) {
    throw new Error('Usage: node tools/optimize_user_zombie.cjs ORIGINAL.glb OPTIMIZED.glb');
  }
  await MeshoptSimplifier.ready;
  const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
  const doc = await io.read(process.argv[2]);
  const convert = [
    'import io,sys',
    'from PIL import Image',
    'im=Image.open(io.BytesIO(sys.stdin.buffer.read())).convert("RGB")',
    'im.thumbnail((2048,2048),Image.Resampling.LANCZOS)',
    'im.save(sys.stdout.buffer,format="JPEG",quality=90,optimize=True)',
  ].join(';');
  for (const texture of doc.getRoot().listTextures()) {
    const resized = spawnSync('python3', ['-c', convert], {
      input: texture.getImage(), maxBuffer: 64 * 1024 * 1024,
    });
    if (resized.status !== 0) throw new Error(String(resized.stderr));
    texture.setImage(resized.stdout).setMimeType('image/jpeg');
  }
  // 1.5 million input triangles are unsuitable for many enemies at once.
  // Tangents are generated after simplification for the original normal map.
  await doc.transform(
    weld(), simplify({ simplifier: MeshoptSimplifier, ratio: 0.025, error: 0.01 }),
    unweld(), tangents({ generateTangents }), weld(), prune(),
  );
  const prim = doc.getRoot().listMeshes()[0].listPrimitives()[0];
  console.log(`${prim.getAttribute('POSITION').getCount()} vertices, ${prim.getIndices().getCount() / 3} triangles`);
  await io.write(process.argv[3], doc);
}
main().catch(error => { console.error(error); process.exit(1); });
