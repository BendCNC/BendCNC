.pragma library

var CLAMP_DURATION_SECONDS = 0.82
var BEND_DURATION_SECONDS = 2.55
var PUNCH_OPEN_R_IN = 2.15

function finiteValue(value, fallback) {
    var numberValue = Number(value)
    return isFinite(numberValue) ? numberValue : Number(fallback || 0)
}

function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value))
}

function smoothstep(value) {
    var t = clamp(finiteValue(value, 0), 0, 1)
    return t * t * (3 - 2 * t)
}

function lerp(start, end, amount) {
    return Number(start) + (Number(end) - Number(start)) * Number(amount)
}

function durationModel(options) {
    var source = options || ({})
    var bumpOff = Math.max(0, finiteValue(source.bumpOffDistanceIn, 0))
    var retractDistance = Math.max(0,
                                   finiteValue(source.retractDistanceIn, 0))
    var clampDuration = CLAMP_DURATION_SECONDS
    var bumpDuration = bumpOff > 0.001
        ? clamp(0.18 + bumpOff * 0.18, 0.18, 0.42) : 0
    var dwellDuration = clamp(finiteValue(source.dwellSeconds, 0), 0, 4)
    var bendDuration = BEND_DURATION_SECONDS
    var retractDuration = clamp(0.55 + retractDistance * 0.14, 0.60, 1.25)
    return {
        clamp: clampDuration,
        bump: bumpDuration,
        dwell: dwellDuration,
        bend: bendDuration,
        retract: retractDuration,
        bendStart: clampDuration + bumpDuration + dwellDuration,
        retractStart: clampDuration + bumpDuration + dwellDuration
            + bendDuration,
        cycle: clampDuration + bumpDuration + dwellDuration
            + bendDuration + retractDuration
    }
}

function poseAt(options, elapsedSeconds, running, centerDepthForRise) {
    var source = options || ({})
    var durations = durationModel(source)
    var cycle = durations.cycle <= 0.001
        ? 0 : Math.max(0, finiteValue(elapsedSeconds, 0)) % durations.cycle
    if (!running)
        cycle = 0

    var angle = finiteValue(source.angleDeg, 90)
    var thickness = Math.max(0, finiteValue(source.thicknessIn, 0.036))
    var halfThickness = thickness / 2
    var reference = finiteValue(source.referenceDistanceIn, 0)
    var bumpOff = Math.max(0, finiteValue(source.bumpOffDistanceIn, 0))
    var retractDistance = Math.max(0,
                                   finiteValue(source.retractDistanceIn, 0))
    var targetRiseDeg = clamp((180 - angle) / 2, 8, 75)
    var resolveCenter = typeof centerDepthForRise === "function"
        ? centerDepthForRise
        : function(rise) { return halfThickness + Math.max(0, rise) * 0 }
    var finalCenterR = finiteValue(resolveCenter(targetRiseDeg), halfThickness)
    var punchTipR = PUNCH_OPEN_R_IN
    var armRiseDeg = 0
    var centerR = halfThickness
    var gaugeFaceX = -reference
    var phase = "RUN / CLAMP"

    if (cycle < durations.clamp) {
        punchTipR = lerp(PUNCH_OPEN_R_IN, thickness,
                         smoothstep(cycle / durations.clamp))
    } else if (cycle < durations.clamp + durations.bump) {
        punchTipR = thickness
        gaugeFaceX = lerp(-reference, -reference - bumpOff,
                          smoothstep((cycle - durations.clamp)
                                     / durations.bump))
        phase = "RUN / BUMP"
    } else if (cycle < durations.clamp + durations.bump + durations.dwell) {
        punchTipR = thickness
        gaugeFaceX = -reference - bumpOff
        phase = "RUN / DWELL"
    } else if (cycle < durations.retractStart) {
        var bendAmount = smoothstep((cycle - durations.bendStart)
                                    / durations.bend)
        armRiseDeg = lerp(0, targetRiseDeg, bendAmount)
        centerR = finiteValue(resolveCenter(armRiseDeg), halfThickness)
        punchTipR = centerR + halfThickness
        gaugeFaceX = -reference - bumpOff
        phase = "RUN / BEND"
    } else {
        var retractAmount = smoothstep((cycle - durations.retractStart)
                                       / durations.retract)
        armRiseDeg = targetRiseDeg
        centerR = finalCenterR
        punchTipR = lerp(finalCenterR + halfThickness, PUNCH_OPEN_R_IN,
                         retractAmount)
        gaugeFaceX = lerp(-reference - bumpOff,
                          -reference - bumpOff - retractDistance,
                          retractAmount)
        phase = "RUN / RETRACT"
    }

    var programmedX = finiteValue(source.programmedXIn, reference)
    return {
        gaugeFaceX: gaugeFaceX,
        gaugeWorkX: programmedX + Math.max(0, -reference - gaugeFaceX),
        gaugeWorkR: finiteValue(source.programmedRIn, 0),
        centerX: 0,
        punchTipR: punchTipR,
        centerR: centerR,
        armRiseDeg: armRiseDeg,
        phase: phase,
        thickness: thickness,
        angle: angle,
        cycleElapsedSeconds: cycle,
        cycleDurationSeconds: durations.cycle
    }
}

function probeElapsedTimes(options) {
    var durations = durationModel(options)
    return [
        0,
        durations.bendStart + durations.bend * 0.25,
        durations.bendStart + durations.bend * 0.50,
        durations.bendStart + durations.bend * 0.75,
        durations.retractStart + Math.min(0.10, durations.retract * 0.25)
    ]
}

function visualSampleTimes(options, intervalSeconds) {
    var durations = durationModel(options)
    var interval = clamp(finiteValue(intervalSeconds, 0.033), 0.001, 1)
    var times = []
    var sampleCount = Math.max(1, Math.ceil(durations.cycle / interval))
    for (var index = 0; index < sampleCount; index++)
        times.push(index * interval)
    return times
}

function quantizedVisualElapsed(options, elapsedSeconds, intervalSeconds) {
    var durations = durationModel(options)
    if (durations.cycle <= 0.001)
        return 0
    var interval = clamp(finiteValue(intervalSeconds, 0.033), 0.001, 1)
    var sampleCount = Math.max(1, Math.ceil(durations.cycle / interval))
    // Wrap the integer sample index, not continuous time. When cycle is not
    // divisible by interval, wrapping elapsed time first shifts the lattice
    // on every cycle and eventually visits near-identical samples forever.
    // Neutralize binary floating-point drift at exact lattice boundaries
    // (for example, 61 * 0.033 can divide back to 60.99999999999999).
    var absoluteIndex = Math.floor(
        Math.max(0, finiteValue(elapsedSeconds, 0)) / interval + 1.0e-9)
    return (absoluteIndex % sampleCount) * interval
}

function compileProgram(bends, optionsForBend, intervalSeconds) {
    var sourceBends = Array.isArray(bends) ? bends : []
    var entries = []
    var byKey = ({})
    for (var index = 0; index < sourceBends.length; index++) {
        var bend = sourceBends[index]
        var options = typeof optionsForBend === "function"
            ? optionsForBend(bend, index) : ({})
        var sequenceValue = options && isFinite(Number(options.sequence))
            ? Number(options.sequence) : index + 1
        var bendId = String(options && options.bendId !== undefined
                            ? options.bendId : "")
        var key = bendId + ":" + String(sequenceValue)
        var entry = {
            index: index,
            bend: bend,
            bendId: bendId,
            sequence: sequenceValue,
            key: key,
            options: options || ({}),
            durations: durationModel(options),
            sampleTimes: visualSampleTimes(options, intervalSeconds)
        }
        entries.push(entry)
        byKey[key] = entry
    }
    return {
        sequenceCount: entries.length,
        entries: entries,
        byKey: byKey
    }
}
