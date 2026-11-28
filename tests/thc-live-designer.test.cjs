const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const previewPath = 'qml/modal-previews/v5/ThcLiveTuningPreview.qml';

test('designer candidate has no production imports, backend, transport or storage', () => {
    const source = read(previewPath).replace(/\/\/[^\n]*/g, '');
    assert.deepEqual([...source.matchAll(/^import (.+)$/gm)].map(match => match[1].trim()),
        ['QtQuick', 'QtQuick.Controls.Basic', 'QtQuick.Layouts']);
    const code = source.replace(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g, '""');
    assert.doesNotMatch(code, /\b(?:AppState|machineControl|backend|fileIo|XMLHttpRequest|Settings|Timer)\b/);
    assert.doesNotMatch(source, /queryThcLiveTuning|applyThcLiveTuning|startContinuousThcContactProfile|heartbeatThcCommissioning|releaseThcCommissioning|cancelThcCommissioning/);
    assert.match(source, /No machine commands/);
});

test('v5 rail loads the candidate only while selected, and registers its resource', () => {
    const scene = read('qml/modal-previews/v5/PreviewScene.qml');
    assert.match(scene, /key: "THC_LIVE_TUNING"/);
    assert.match(scene, /active: root\.visible && root\.selectedPreview === "THC_LIVE_TUNING"/);
    assert.match(scene, /ThcLiveTuningPreview\s*\{/);
    assert.ok(read('CMakeLists.txt').includes(previewPath));
});

test('production Manual keeps using the guarded panel, never the designer candidate', () => {
    const manual = read('qml/ManualModeView.qml');
    assert.match(manual, /ThcLiveTuningPanel\s*\{/);
    assert.doesNotMatch(manual, /ThcLiveTuningPreview/);
    assert.doesNotMatch(read('qml/ThcLiveTuningPanel.qml'), /ThcLiveTuningPreview|designerInteractive/);
    for (const file of ['qml/ThcLiveTuningView.qml', 'qml/ThcTelemetryHistory.qml', 'qml/ThcTonnageChart.qml']) {
        assert.doesNotMatch(read(file), /modal-previews|ThcLiveTuningPreview|Math\.random|sampleValues|stepDynamics/);
    }
});

test('redesigned candidate stays a centered 950x600 mock with local animation only', () => {
    const candidate = read(previewPath);
    assert.match(candidate, /width: 950/);
    assert.match(candidate, /height: 600/);
    assert.match(candidate, /SequentialAnimation\s*\{\s*running: root\.visible/);
    assert.match(candidate, /ScriptAction\s*\{\s*script: root\.stepDynamics\(\)/);
    assert.match(candidate, /readonly property bool previewOnly: true/);
    const scene = read('qml/modal-previews/v5/PreviewScene.qml');
    assert.match(scene, /id: tuningStage/);
    assert.match(scene, /color: "#A6000000"/);
    assert.match(scene, /scale: Math\.min\(1, tuningStage\.width \/ width, tuningStage\.height \/ height\)/);
});

test('designer launch remains behind packaged verification and image lock', () => {
    const launch = read('tools/launch-qt-offline.ps1');
    assert.match(launch, /\[switch\]\$ModalDesigner/);
    assert.match(launch, /--modal-preview-selection=THC_LIVE_TUNING/);
    assert.match(launch, /\$arguments = @\('--offline-validation'\)/);
    assert.match(launch, /\$check\.ExitCode -ne 0/);
    assert.match(launch, /\$output -notmatch 'THC-LIVE-INTEGRATION PASS'/);
    assert.match(launch, /\$output -match 'THC-LIVE-INTEGRATION FAIL'/);
    assert.ok(launch.indexOf('$imageLock =') < launch.indexOf('$arguments ='));
    assert.ok(launch.indexOf('Refusing app without verified V53 integration') < launch.indexOf('$arguments ='));
    assert.ok(launch.indexOf('& $exe @arguments') < launch.indexOf('$imageLock.Dispose()'));
});

test('capture cannot silently accept a missing directory, stale file or failed save', () => {
    const launch = read('tools/launch-qt-offline.ps1');
    assert.match(launch, /Modal capture directory must already exist/);
    assert.match(launch, /Modal capture path already exists/);
    assert.match(launch, /\(Get-Item -LiteralPath \$ModalCapturePath\)\.Length -eq 0/);
    assert.ok(launch.indexOf('choose a fresh filename') < launch.indexOf('$imageLock ='));
    assert.ok(launch.indexOf('Qt did not save the requested modal capture') > launch.indexOf('& $exe @arguments'));
});

test('designer binds every platform Refresh shortcut including Windows F5', () => {
    const viewer = read('qml/ModalPreviewer.qml');
    assert.match(viewer, /sequences:\s*\[StandardKey\.Refresh\]/);
    assert.doesNotMatch(viewer, /\bsequence:\s*StandardKey\.Refresh/);
    assert.match(viewer, /onActivated:\s*window\.reloadDesign\(window\.previewVersion\)/);
});

test('production capture keeps offline verification, image lock and fresh-path admission', () => {
    const launch = read('tools/launch-qt-offline.ps1');
    assert.match(launch, /\[string\]\$ProductionCapturePath/);
    assert.match(launch, /\$ProductionCapturePath -and \(-not \$OpenTuning -or \$ModalDesigner -or \$VerifyOnly\)/);
    assert.match(launch, /Production capture directory must already exist/);
    assert.match(launch, /Production capture path already exists; choose a fresh filename/);
    assert.match(launch, /'--capture-full=' \+ \$ProductionCapturePath/);
    assert.match(launch, /'--run-exit-after-ms=10000'/);
    assert.match(launch, /\(Get-Item -LiteralPath \$ProductionCapturePath\)\.Length -eq 0/);
    assert.ok(launch.indexOf('Production capture path already exists') < launch.indexOf('$imageLock ='));
    assert.ok(launch.indexOf('Qt did not save the requested production capture') > launch.indexOf('& $exe @arguments'));
});