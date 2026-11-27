import QtQuick
import QtTest
import "../qml/core/execution/RunSimulationTimeline.js" as Timeline

TestCase {
    name: "RunSimulationTimelineTests"

    function options(sequence) {
        return {
            bendId: "bend-" + String(sequence),
            sequence: sequence,
            angleDeg: 90,
            thicknessIn: 0.1,
            referenceDistanceIn: 2.0,
            bumpOffDistanceIn: 0.25,
            retractDistanceIn: 2.0,
            dwellSeconds: 0.3,
            programmedXIn: 3.0,
            programmedRIn: 0.5
        }
    }

    function bends(count) {
        let result = []
        for (let index = 0; index < count; index++)
            result.push({ id: "bend-" + String(index + 1) })
        return result
    }

    function test_compileProgramUsesEverySequence_data() {
        return [
            { tag: "zero", count: 0 },
            { tag: "one", count: 1 },
            { tag: "four", count: 4 },
            { tag: "five", count: 5 },
            { tag: "nine", count: 9 }
        ]
    }

    function test_compileProgramUsesEverySequence(data) {
        let compiled = Timeline.compileProgram(
            bends(data.count),
            function(bend, index) { return options(index + 1) },
            0.033)
        compare(compiled.sequenceCount, data.count)
        compare(compiled.entries.length, data.count)
        for (let index = 0; index < data.count; index++) {
            let key = "bend-" + String(index + 1) + ":" + String(index + 1)
            verify(!!compiled.byKey[key], key)
            verify(compiled.byKey[key].sampleTimes.length > 100)
        }
    }

    function test_nonContiguousSequenceHintsRemainSemantic() {
        let source = bends(5)
        let hints = [40, 3, 17, 8, 101]
        let compiled = Timeline.compileProgram(
            source,
            function(bend, index) {
                let value = options(hints[index])
                value.bendId = bend.id
                return value
            },
            0.033)
        compare(compiled.sequenceCount, hints.length)
        for (let index = 0; index < hints.length; index++) {
            let key = source[index].id + ":" + String(hints[index])
            compare(compiled.entries[index].sequence, hints[index])
            verify(!!compiled.byKey[key], key)
        }
    }

    function test_poseRepeatsDeterministically() {
        let value = options(1)
        let durations = Timeline.durationModel(value)
        let resolver = function(rise) { return 0.05 + rise * 0.01 }
        let first = Timeline.poseAt(value, 1.75, true, resolver)
        let repeated = Timeline.poseAt(
            value, 1.75 + durations.cycle * 7, true, resolver)
        compare(repeated.phase, first.phase)
        fuzzyCompare(repeated.gaugeFaceX, first.gaugeFaceX, 0.000001)
        fuzzyCompare(repeated.punchTipR, first.punchTipR, 0.000001)
        fuzzyCompare(repeated.armRiseDeg, first.armRiseDeg, 0.000001)
    }

    function test_visualElapsedRepeatsExactSamplesAcrossCycles() {
        let options = {
            angleDeg: 90,
            thicknessIn: 0.1,
            retractDistanceIn: 0.37,
            dwellSeconds: 0.13
        }
        let duration = Timeline.durationModel(options).cycle
        let sampleCount = Math.ceil(duration / 0.033)
        let visualCycleDuration = sampleCount * 0.033
        let first = Timeline.quantizedVisualElapsed(options, 1.237, 0.033)
        let repeated = Timeline.quantizedVisualElapsed(
            options, visualCycleDuration * 137 + 1.237, 0.033)
        compare(first, repeated)
        compare(first, Math.floor(1.237 / 0.033) * 0.033)
        verify(Math.abs(visualCycleDuration - duration) > 0.000001)
    }

    function test_visualElapsedRemainsFiniteWithIrregularTimerTicks() {
        let options = {
            angleDeg: 90,
            thicknessIn: 0.1,
            retractDistanceIn: 0.37,
            dwellSeconds: 0.13
        }
        let interval = 0.033
        let sampleCount = Math.ceil(
            Timeline.durationModel(options).cycle / interval)
        let observed = ({})
        let elapsed = 0
        for (let tick = 0; tick < 20000; tick++) {
            elapsed += tick % 3 === 0 ? 0.031 : tick % 3 === 1 ? 0.034 : 0.038
            let sample = Timeline.quantizedVisualElapsed(
                options, elapsed, interval)
            observed[String(Math.round(sample * 1000000))] = true
            verify(sample >= 0)
            verify(sample < sampleCount * interval)
        }
        compare(Object.keys(observed).length, sampleCount)
    }

    function test_visualSamplesMatchExactReachableLattice() {
        let value = options(4)
        let interval = 0.033
        let duration = Timeline.durationModel(value).cycle
        let expectedCount = Math.ceil(duration / interval)
        let samples = Timeline.visualSampleTimes(value, interval)

        compare(samples.length, expectedCount)
        compare(samples[0], 0)
        compare(samples[samples.length - 1], (expectedCount - 1) * interval)
        verify(samples[samples.length - 1] < expectedCount * interval)
        verify(samples.indexOf(duration) < 0,
               "The modulo-aliasing cycle endpoint must not be appended")
        for (let index = 0; index < samples.length; index++) {
            compare(Timeline.quantizedVisualElapsed(
                        value, index * interval, interval), samples[index])
        }
        compare(Timeline.quantizedVisualElapsed(
                    value, expectedCount * interval, interval), samples[0])
    }

    function test_stoppedPoseDoesNotAdvance() {
        let value = options(1)
        let pose = Timeline.poseAt(value, 999, false,
                                   function() { return 0.05 })
        compare(pose.phase, "RUN / CLAMP")
        fuzzyCompare(pose.armRiseDeg, 0, 0.000001)
        fuzzyCompare(pose.gaugeFaceX, -2, 0.000001)
    }

    function test_postClampPunchMotionIsSmooth() {
        let value = options(1)
        let durations = Timeline.durationModel(value)
        let resolver = function(rise) { return 0.05 + rise * 0.01 }
        let first = Timeline.poseAt(
            value, durations.bendStart + 0.20, true, resolver)
        let middle = Timeline.poseAt(
            value, durations.bendStart + 0.40, true, resolver)
        let last = Timeline.poseAt(
            value, durations.bendStart + 0.60, true, resolver)
        verify(first.punchTipR < middle.punchTipR)
        verify(middle.punchTipR < last.punchTipR)
        verify(last.punchTipR < Timeline.poseAt(
            value, durations.bendStart + durations.bend, true, resolver).punchTipR)
    }

    function test_finalRetractPieceAndPunchMotionRemainsSmooth() {
        let value = options(1)
        let durations = Timeline.durationModel(value)
        let resolver = function(rise) { return 0.05 + rise * 0.01 }
        let samples = []
        for (let index = 1; index <= 4; index++) {
            let elapsed = durations.retractStart
                + durations.retract * index / 5
            samples.push(Timeline.poseAt(value, elapsed, true, resolver))
        }
        for (let index = 1; index < samples.length; index++) {
            verify(samples[index - 1].punchTipR < samples[index].punchTipR)
            verify(samples[index - 1].gaugeFaceX > samples[index].gaugeFaceX)
        }
    }
}
