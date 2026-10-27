// Prepare a game-sized copy of a user-supplied static GLB without changing the
// original. This retains its UVs and PBR maps, but reduces excessive geometry
// and texture memory for real-time play in Godot.
//
// Dependencies: @gltf-transform/{core,extensions,functions} 4.2.1,
// meshoptimizer 0.22.0, mikktspace 1.1.1, and Python Pillow.
// Usage: node tools/optimize_uploaded_model.cjs input.glb output.glb target_triangles
const { spawnSync } = require('node:child_process');
const { NodeIO } = require('@gltf-transform/core');
const { ALL_EXTENSIONS } = require('@gltf-transform/extensions');
const { weld, unweld, simplify, tangents, prune } = require('@gltf-transform/functions');
const { MeshoptSimplifier } = require('meshoptimizer');
const { generateTangents } = require('mikktspace');

async function main() {
  if (process.argv.length !== 5) {
    throw new Error('Usage: node tools/optimize_uploaded_model.cjs input.glb output.glb target_triangles');
  }
  const target = Number(process.argv[4]);
  if (!Number.isFinite(target) || target <= 0) throw new Error('Invalid triangle count');
  await MeshoptSimplifier.ready;
  const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
  const doc = await io.read(process.argv[2]);
  const root = doc.getRoot();
  if (root.listMeshes().length !== 1 || root.listMeshes()[0].listPrimitives().length !== 1) {
    throw new Error('Expected the supplied single-mesh model');
  }
  // The two uploaded models specify a specularColorFactor of [2,2,2], outside
  // the glTF extension's permitted 0..1 range. Remove the optional extension;
  // the original base colour, normal, roughness and metallic maps are kept.
  for (const material of root.listMaterials()) {
    if (material.getExtension('KHR_materials_specular')) {
      material.setExtension('KHR_materials_specular', null);
    }
  }
  for (const extension of root.listExtensionsUsed()) {
    if (extension.extensionName === 'KHR_materials_specular') extension.dispose();
  }
  // Both assets contain three opaque 4096x4096 RGB PNG maps. Limit to 2048px
  // and encode as high-quality JPEGs; retain their role and UV mapping.
  const convert = [
    'import io,sys',
    'from PIL import Image',
    'im=Image.open(io.BytesIO(sys.stdin.buffer.read())).convert("RGB")',
    'im.thumbnail((2048,2048),Image.Resampling.LANCZOS)',
    'im.save(sys.stdout.buffer,format="JPEG",quality=92,optimize=True,subsampling=0)',
  ].join(';');
  for (const texture of root.listTextures()) {
    const resized = spawnSync('python3', ['-c', convert], {
      input: texture.getImage(), maxBuffer: 64 * 1024 * 1024,
    });
    if (resized.status !== 0) throw new Error(String(resized.stderr));
    texture.setImage(resized.stdout).setMimeType('image/jpeg');
  }
  const prim = root.listMeshes()[0].listPrimitives()[0];
  const originalTriangles = prim.getIndices().getCount() / 3;
  const ratio = Math.min(1, target / originalTriangles);
  await doc.transform(
    weld(), simplify({ simplifier: MeshoptSimplifier, ratio, error: 0.01 }),
    unweld(), tangents({ generateTangents }), weld(), prune(),
  );
  // MikkTSpace returns zero tangents for a few degenerate UV triangles in
  // these assets. Replace them with an orthogonal unit tangent, keeping the
  // source normal maps usable and the GLB compliant with the glTF validator.
  const t = prim.getAttribute('TANGENT').getArray();
  const n = prim.getAttribute('NORMAL').getArray();
  let fixed = 0;
  for (let i = 0; i < t.length / 4; i++) {
    const k = i * 4, j = i * 3;
    if (Math.hypot(t[k], t[k + 1], t[k + 2]) >= 1e-8) continue;
    const nx = n[j], ny = n[j + 1], nz = n[j + 2];
    let x, y, z;
    if (Math.abs(nx) < 0.9) { x = 0; y = nz; z = -ny; }
    else { x = -nz; y = 0; z = nx; }
    const length = Math.hypot(x, y, z);
    t[k] = x / length; t[k + 1] = y / length; t[k + 2] = z / length;
    if (t[k + 3] === 0) t[k + 3] = 1;
    fixed++;
  }
  console.log(`${originalTriangles} -> ${prim.getIndices().getCount() / 3} triangles, ${prim.getAttribute('POSITION').getCount()} vertices; ${fixed} tangent fixes`);
  await io.write(process.argv[3], doc);
}
main().catch(error => { console.error(error); process.exit(1); });
