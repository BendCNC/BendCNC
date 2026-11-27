.pragma library
.import "../BendCalculator.js" as BendCalculator

// ExecutionStateModel.js
// Implements the DETERMINISTIC core of the legacy execution package:
//   - core/BendMode (repeatable / isProgramMode flags)
//   - core/BendPhase (phase sequence + isHaveBackgaugeMove)
//   - model/execution/ExecutionModel (selected program/bend/index navigation)
//   - model/execution/BendProgramModel.refreshExecutingBends + refreshProblematicExecutingBends
//
// Hardware orchestration (jog/back-gauge motion, timers, LinkedTaskService) is
// intentionally NOT ported here — that is Phase 6 (machine/serial). This module
// is the pure state machine the Run tab binds to: which bends will execute, which
// bend/index is selected, navigation, and problem classification.

// [resourceKey, repeatable, isProgramMode]
var BendMode = {
    SINGLE_BEND_MODE:   { name: "SINGLE_BEND_MODE",   repeatable: false, programMode: false },
    SINGLE_BEND_REPEAT: { name: "SINGLE_BEND_REPEAT", repeatable: true,  programMode: false },
    PROGRAM_BEND_MODE:  { name: "PROGRAM_BEND_MODE",  repeatable: false, programMode: true  },
    PROGRAM_BEND_LOOP:  { name: "PROGRAM_BEND_LOOP",  repeatable: true,  programMode: true  }
};
function bendModeFromString(s) {
    if (!s) return null;
    var key = String(s).replace(/ /g, "_").toUpperCase();
    return BendMode[key] || null;
}

// Order matters: this is the per-bend execution sequence.
var BendPhase = {
    STARTING:                        { name: "STARTING",                        haveBackgaugeMove: false },
    BACK_GAUGE_MOVE:                 { name: "BACK_GAUGE_MOVE",                 haveBackgaugeMove: true  },
    SAFETY_CLEARANCE_POSITION_MOVE:  { name: "SAFETY_CLEARANCE_POSITION_MOVE",  haveBackgaugeMove: true  },
    CLAMP_MATERIAL_MOVE:             { name: "CLAMP_MATERIAL_MOVE",             haveBackgaugeMove: false },
    BACK_GAUGE_BUMP_MOVE:            { name: "BACK_GAUGE_BUMP_MOVE",            haveBackgaugeMove: true  },
    DWELL_TIMER_WAIT:                { name: "DWELL_TIMER_WAIT",                haveBackgaugeMove: false },
    BEND_MOVE:                       { name: "BEND_MOVE",                       haveBackgaugeMove: false },
    BACK_GAUGE_AND_RAM_RETRACT_MOVE: { name: "BACK_GAUGE_AND_RAM_RETRACT_MOVE", haveBackgaugeMove: true  },
    FINISHING_PROGRAM:               { name: "FINISHING_PROGRAM",               haveBackgaugeMove: false }
};
// Canonical per-bend phase order used by BendProgramModel.runProgram.
var BEND_PHASE_SEQUENCE = [
    BendPhase.BACK_GAUGE_MOVE,
    BendPhase.SAFETY_CLEARANCE_POSITION_MOVE,
    BendPhase.CLAMP_MATERIAL_MOVE,
    BendPhase.BACK_GAUGE_BUMP_MOVE,
    BendPhase.BEND_MOVE,
    BendPhase.BACK_GAUGE_AND_RAM_RETRACT_MOVE
];

// ---- ExecutionModel (deterministic) ----
// Construct a state object holding selectedProgram, index, and derived selectedBend.
function createExecution() {
    return {
        selectedProgram: null,    // { name, bends: [...] }
        selectedBendIndex: 0,
        savedBendIndex: 0,
        mode: BendMode.PROGRAM_BEND_MODE
    };
}

function programBends(state) {
    return (state.selectedProgram && state.selectedProgram.bends) ? state.selectedProgram.bends : [];
}

// Derived selectedBend (ExecutionModel.selectedBend binding): null if index out of range.
function selectedBend(state) {
    var bends = programBends(state);
    if (state.selectedBendIndex >= bends.length) return null;
    return bends[state.selectedBendIndex];
}

function setSelectedProgram(state, program) {
    state.selectedProgram = program;
    state.selectedBendIndex = 0;   // EasyBind.subscribe(selectedProgram -> index=0)
}

// nextBend(): advance index in program mode; returns whether advancing is allowed.
function nextBend(state) {
    if (state.mode.programMode) {
        if (state.selectedBendIndex >= programBends(state).length - 1) return false;
        state.selectedBendIndex += 1;
        return true;
    }
    return state.mode.repeatable && selectedBend(state) !== null;
}

function saveBendIndex(state) { state.savedBendIndex = state.selectedBendIndex; }
function toSavedIndex(state) { state.selectedBendIndex = state.savedBendIndex; }
function selectFirstBendInProgram(state) {
    if (programBends(state).length > 0) state.selectedBendIndex = 0;
}

// ---- BendProgramModel.refreshExecutingBends ----
// Which bends will actually execute given mode + current index.
//   program mode + repeatable  -> all bends
//   program mode (not repeat)  -> bends[index .. end]
//   single-bend mode           -> [selectedBend] (if any)
function executingBends(state) {
    var program = state.selectedProgram;
    if (!program || !program.bends || program.bends.length === 0) return [];
    if (state.mode.programMode) {
        return state.mode.repeatable
            ? program.bends.slice()
            : program.bends.slice(state.selectedBendIndex);
    }
    var sb = selectedBend(state);
    return sb ? [sb] : [];
}

// backGaugeEnabledInProgram: any executing bend has back-gauge ref-edge stop enabled.
function backGaugeEnabledInProgram(state, isBackGaugeRefEdgeStopEnabled) {
    var bends = executingBends(state);
    for (var i = 0; i < bends.length; i++)
        if (isBackGaugeRefEdgeStopEnabled(bends[i])) return true;
    return false;
}

// ---- refreshProblematicExecutingBends ----
// Classify executing bends into problem buckets using the ported BendCalculator.
//   resolve(bend) must return { punch, die, material, settings, machine, limits }
//   (machine/limits/settings default to BendCalculator DEFAULTS when omitted).
// Returns lists of the offending bends per category, matching the Java property set.
function problematicExecutingBends(state, resolve) {
    var result = {
        exceedingTonnage: [],
        exceedingUpperTravelLimit: [],
        exceedingLowerTravelLimit: [],
        undefinedDie: [],
        undefinedMaterial: [],
        undefinedPunch: [],
        notInRangeFinalBendPos: []
    };
    var bends = executingBends(state);
    for (var i = 0; i < bends.length; i++) {
        var bend = bends[i];
        var ctx = resolve(bend) || {};
        var hasTooling = ctx.punch && ctx.die && ctx.material;
        if (hasTooling) {
            var r = BendCalculator.computeBend({
                bend: bend, punch: ctx.punch, die: ctx.die, material: ctx.material,
                settings: ctx.settings, machine: ctx.machine, limits: ctx.limits
            });
            if (r.lowerLimitExceededError) result.exceedingLowerTravelLimit.push(bend);
            if (r.upperLimitExceededError) result.exceedingUpperTravelLimit.push(bend);
            if (r.tonnageError) result.exceedingTonnage.push(bend);
            if (r.finalBendPositionOutLimit) result.notInRangeFinalBendPos.push(bend);
        }
        if (!ctx.die) result.undefinedDie.push(bend);
        if (!ctx.material) result.undefinedMaterial.push(bend);
        if (!ctx.punch) result.undefinedPunch.push(bend);
    }
    return result;
}

// executingBendsValid: true when no problem bucket is populated (Java AND-binding).
function executingBendsValid(problems) {
    return problems.exceedingTonnage.length === 0
        && problems.exceedingUpperTravelLimit.length === 0
        && problems.exceedingLowerTravelLimit.length === 0
        && problems.notInRangeFinalBendPos.length === 0
        && problems.undefinedDie.length === 0
        && problems.undefinedMaterial.length === 0
        && problems.undefinedPunch.length === 0;
}
