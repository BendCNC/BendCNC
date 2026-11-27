// Samples the unfold sequence playback (same code as the unfold viewer) into
// mesh frames for the Qt Quick 3D comparison viewer.
// Usage: node export_unfold_scene.mjs --plan <plan.json> --out <dir> [--samples 10]
// Kinematics are never reimplemented here: every frame is sequenceSceneAt() of
// the selected engine. Engine selection matches UnfoldSequencePlanner (explicit):
// BENDCNC_UNFOLD_DIR > ~/Documents/VSCode/unfold-v6 > ~/Documents/VSCode/unfold (legacy).
import {createHash} from 'node:crypto';
import {existsSync} from 'node:fs';
import {readFile, writeFile, mkdir, open} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

// Bump when the frames.bin/frames.json layout or sampling changes.
const EXPORT_FORMAT = 2;

const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, i, all) =>
    (value.startsWith('--') ? [...pairs, [value.slice(2), all[i + 1]]] : pairs), []));
if (!args.plan || !args.out) throw new Error('--plan and --out are required');
const vscode = join(homedir(), 'Documents', 'VSCode');
const [unfoldDir, engineSource] = process.env.BENDCNC_UNFOLD_DIR ? [process.env.BENDCNC_UNFOLD_DIR, 'env']
    : existsSync(join(vscode, 'unfold-v6', 'viewer', 'sequence-playback.mjs')) ? [join(vscode, 'unfold-v6'), 'v6']
    : [join(vscode, 'unfold'), 'legacy'];
const readText = path => readFile(path, 'utf8');
const tryText = async path => { try { return await readText(path); } catch { return ''; } };
async function engineRevision() {
    const stamp = (await tryText(join(unfoldDir, 'ENGINE_REVISION'))).trim();
    if (stamp) return stamp;
    let ref = (await tryText(join(unfoldDir, '.git', 'HEAD'))).trim();
    if (ref.startsWith('ref: ')) ref = (await tryText(join(unfoldDir, '.git', ref.slice(5)))).trim();
    return ref.slice(0, 12) || 'unknown';
}

const out = resolve(args.out);
const samples = Math.max(2, Number(args.samples ?? 10));
const planText = await readText(resolve(args.plan));
const plan = JSON.parse(planText);
const modelText = await readText(plan.modelPath);
const toolingText = await readText(join(unfoldDir, 'viewer', 'tooling.json'));
const fingersText = await tryText(join(unfoldDir, 'viewer', 'fingers.json'));
const engine = `unfold ${engineSource} @ ${await engineRevision()} (${unfoldDir})`;
// Cache key: model, plan, catalog, options (samples) and engine/playback/exporter version.
const sha = text => createHash('sha256').update(text).digest('hex');
const playbackText = await readText(join(unfoldDir, 'viewer', 'sequence-playback.mjs'));
const exporterText = await readText(fileURLToPath(import.meta.url));
const cacheKey = sha(JSON.stringify({
    format: EXPORT_FORMAT, samples, engine,
    model: sha(modelText), plan: sha(planText), tooling: sha(toolingText), fingers: sha(fingersText),
    playback: sha(playbackText), exporter: sha(exporterText),
}));
if (!args.force && existsSync(join(out, 'frames.bin'))) {
    const previous = JSON.parse(await tryText(join(out, 'frames.json')) || '{}');
    if (previous.cacheKey === cacheKey) {
        console.log(JSON.stringify({status: 'cached', cacheKey, engine}));
        process.exit(0);
    }
}

const viewer = file => import(pathToFileURL(join(unfoldDir, 'viewer', file)).href);
const {buildSequenceTimeline, sequenceSceneAt, phaseLabels} = await viewer('sequence-playback.mjs');
const {isPart} = await viewer('sequence-scene.mjs');
const model = JSON.parse(modelText);
const catalog = JSON.parse(toolingText);
if (plan.stages.some(stage => stage.backgauge))
    catalog.fingerDefinition = JSON.parse(fingersText).definitions[0];
const timeline = buildSequenceTimeline(plan);
const groups = ['part', 'punch', 'die', 'riser', 'table', 'finger'];
const groupOf = body => isPart(body) ? 'part' : groups.includes(body.kind) ? body.kind : 'finger';
const bendLabel = id => model.bends.find(b => String(b.id) === String(id))?.label ?? String(id);

await mkdir(out, {recursive: true});
const bin = await open(join(out, 'frames.bin'), 'w');
let offset = 0;
const frames = [];
for (const [segmentIndex, segment] of timeline.segments.entries()) {
    for (let i = 0; i < samples; i++) {
        const q = i / (samples - 1);
        const scene = sequenceSceneAt(model, catalog, plan, segment.stageIndex, segment.phase, q);
        const blocks = [], topology = [];
        for (const group of groups) {
            const bodies = scene.bodies.filter(body => groupOf(body) === group);
            // Topology signature (body ids + triangle indices): the viewer only
            // interpolates between frames whose vertices really correspond.
            const topo = createHash('sha256');
            for (const body of bodies) {
                topo.update(String(body.id ?? body.kind ?? '') + ':' + body.positions.length + ';');
                topo.update(new Uint32Array(body.triangles));
            }
            topology.push(topo.digest('hex').slice(0, 16));
            const vertexCount = bodies.reduce((sum, body) => sum + body.positions.length / 3, 0);
            const indexCount = bodies.reduce((sum, body) => sum + body.triangles.length, 0);
            const positions = new Float32Array(vertexCount * 3), indices = new Uint32Array(indexCount);
            let v = 0, k = 0;
            for (const body of bodies) {
                for (const index of body.triangles) indices[k++] = index + v / 3;
                positions.set(body.positions, v);
                v += body.positions.length;
            }
            const header = new Uint32Array([vertexCount, indexCount]);
            blocks.push(Buffer.from(header.buffer), Buffer.from(positions.buffer), Buffer.from(indices.buffer));
        }
        const data = Buffer.concat(blocks);
        await bin.write(data);
        const stage = plan.stages[segment.stageIndex];
        frames.push({
            offset, bytes: data.length, segment: segmentIndex, topology,
            time: segment.startSeconds + q * segment.durationSeconds,
            stage: segment.stageIndex, bend: bendLabel(stage.bendId),
            partial: (stage.to[stage.bendId] ?? 1) < 0.999,
            phase: phaseLabels[segment.phase] ?? segment.phase, q,
        });
        offset += data.length;
    }
}
await bin.close();
await writeFile(join(out, 'frames.json'), JSON.stringify({
    format: EXPORT_FORMAT, cacheKey, engine,
    plan: resolve(args.plan), groups, durationSeconds: timeline.durationSeconds,
    stages: plan.stages.length, samplesPerPhase: samples, frames,
}));
console.log(JSON.stringify({status: 'ok', frames: frames.length, bytes: offset, cacheKey, engine}));
