const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const guard = path.join(root, 'cmake', 'ThcLiveIntegrationGuard.cmake');
const files = ['CMakeLists.txt', 'qml/ManualModeView.qml', 'qml/ThcLiveTuningPanel.qml',
    'qml/ThcLiveTuningView.qml', 'qml/ThcTelemetryHistory.qml', 'qml/ThcTonnageChart.qml',
    'qml/main.qml', 'src/MachineControlBackend.h', 'src/MachineControlBackend.cpp',
    'src/SerialMachineTransport.cpp', 'src/main.cpp', 'src/ThcLiveIntegrationCheck.h'];

function check(mutate) {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'thc-integration-'));
    try {
        for (const file of files) {
            const target = path.join(temp, file);
            fs.mkdirSync(path.dirname(target), { recursive: true });
            fs.copyFileSync(path.join(root, file), target);
        }
        if (mutate) mutate(temp);
        const result = spawnSync(process.env.THC_GUARD_CMAKE || 'cmake',
            [`-DTHC_SOURCE_DIR=${temp}`, '-P', guard], { encoding: 'utf8', timeout: 5000 });
        assert.ifError(result.error);
        return result;
    } finally {
        fs.rmSync(temp, { recursive: true, force: true });
    }
}

test('complete current integration passes the same mandatory build guard', () => {
    const result = check();
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /THC live integration source guard passed/);
});

for (const [name, file, marker] of [
    ['removed Manual entry', 'qml/ManualModeView.qml', 'button-thc-live-fine-tune'],
    ['removed lazy panel', 'qml/ManualModeView.qml', 'ThcLiveTuningPanel {'],
    ['omitted packaged resource', 'CMakeLists.txt', 'qml/ThcLiveTuningPanel.qml'],
    ['omitted visual resource', 'CMakeLists.txt', 'qml/ThcLiveTuningView.qml'],
    ['omitted history resource', 'CMakeLists.txt', 'qml/ThcTelemetryHistory.qml'],
    ['omitted chart resource', 'CMakeLists.txt', 'qml/ThcTonnageChart.qml'],
    ['removed visual confirmation', 'qml/ThcLiveTuningView.qml', 'root.controller.confirmStart()'],
    ['removed visual stop', 'qml/ThcLiveTuningView.qml', 'root.controller.cancelOwned()'],
    ['removed native API', 'src/MachineControlBackend.h', 'Q_INVOKABLE bool queryThcLiveTuning()'],
    ['removed isolated fine property', 'src/MachineControlBackend.h', 'Q_PROPERTY(QVariantMap thcFineLoad READ thcFineLoad NOTIFY thcFineLoadChanged FINAL)'],
    ['removed modal fine owner fence', 'qml/ThcLiveTuningPanel.qml', 'preferFine: root.ownsOperation'],
    ['removed fine arrival observer', 'qml/ThcTelemetryHistory.qml', 'function onThcFineLoadChanged()'],
    ['removed packaged fine metadata check', 'src/ThcLiveIntegrationCheck.h', 'meta->indexOfProperty("thcFineLoad")'],
    ['removed controller owner', 'src/MachineControlBackend.cpp', 'MachineControlBackend::checkThcV53Deadlines()'],
    ['removed serial command', 'src/SerialMachineTransport.cpp', '<THC:V53?>'],
    ['removed offline capture', 'qml/main.qml', '--open-thc-live-tuning'],
    ['removed build dependency', 'CMakeLists.txt', 'add_dependencies(prototype thc_live_integration_guard)'],
    ['removed packaged test', 'CMakeLists.txt', 'NAME thc_live_packaged_tests'],
    ['removed runtime check', 'src/main.cpp', 'startThcLiveIntegrationCheck('],
    ['removed foreground cleanup', 'qml/ThcLiveTuningPanel.qml', 'onSurfaceActiveChanged:']
]) {
    test(`rejects ${name}`, () => {
        const result = check(temp => {
            const target = path.join(temp, file);
            const before = fs.readFileSync(target, 'utf8');
            assert.ok(before.includes(marker), `invalid mutation: ${marker}`);
            fs.writeFileSync(target, before.split(marker).join('REMOVED_FOR_REGRESSION_TEST'));
        });
        assert.notEqual(result.status, 0);
        assert.match(result.stderr, /THC live integration regression/);
        assert.ok(result.stderr.includes(file));
    });
}

test('rejects missing panel file rather than relying on stale compiled resources', () => {
    const result = check(temp => fs.unlinkSync(path.join(temp, 'qml/ThcLiveTuningPanel.qml')));
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /THC live integration missing file: qml\/ThcLiveTuningPanel.qml/);
});