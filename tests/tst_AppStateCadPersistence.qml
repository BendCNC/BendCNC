import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    id: root
    width: 320
    height: 240

    TestCase {
        name: "AppStateCadPersistenceTests"
        when: windowShown

        property var state: null

        function createState() {
            let component = Qt.createComponent("../qml/AppState.qml")
            verify(component.status === Component.Ready, component.errorString())
            let created = component.createObject(root)
            verify(!!created)
            return created
        }

        function prepareCad(appState, programName) {
            let punch = { id: "test-punch", name: "Test Punch", heightInch: 4.0 }
            let die = { id: "test-die", name: "Test Die", heightInch: 2.0, vdieOpeningInch: 0.5 }
            let material = { id: "test-material", name: "Steel", materialTensileStrengthPsi: 58000,
                insideRadiusRuleOfThumb: 0.16, materialSpringback: 2 }
            appState.cadImported = true
            appState.cadHasErrors = false
            appState.cadProgramName = programName
            appState.cadPartName = "Test Part"
            appState.cadMaterial = "Steel"
            appState.cadThickness = "0.0600 in"
            appState.cadThicknessValue = 0.06
            appState.cadSpringBack = material.materialSpringback
            appState.cadLoadedJson = { part: { name: "Test Part" } }
            appState.cadPunchCatalog = [punch]
            appState.cadDieCatalog = [die]
            appState.cadMaterialCatalog = [material]
            appState.cadSelectedMaterial = material
            appState.cadBends = [{
                seq: 1,
                angle: "90.0",
                processBgPosition: 1.25,
                bgrValue: -0.25,
                tonnage: "1.000",
                punchName: "Test Punch",
                dieName: "Test Die",
                punchId: punch.id,
                dieId: die.id,
                widthValue: 6,
                angleValue: 90,
                dir: "UP",
                ref: "EDGE",
                bg: "1.2500"
            }]
            appState.cadBendCount = 1
        }

        function init() {
            state = createState()
        }

        function cleanup() {
            if (state) {
                state.cadSelectedMaterial = null
                state.cadPunchCatalog = []
                state.cadDieCatalog = []
                state.cadMaterialCatalog = []
                state.cadManualSequenceOverride = false
                state.destroy()
            }
            state = null
        }

        function test_ramSpeedsPersistAndReload() {
            let files = ({})
            let fakeIo = {
                read: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url) ? files[url] : null
                },
                write: function(url, text) {
                    files[url] = text
                    return true
                },
                exists: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url)
                }
            }
            state.storageIoOverride = fakeIo
            state.offlineSimulationEnabled = true
            verify(state.setRamSpeed("bend", 8.5))
            verify(state.setRamSpeed("jog", 3.25))

            let settingsUrl = state.writableCurrentDataPath("local-settings.json")
            verify(Object.prototype.hasOwnProperty.call(files, settingsUrl))
            let stored = JSON.parse(files[settingsUrl])
            compare(stored.bendRamSpeed.value, 8.5)
            compare(stored.jogRamSpeed.value, 3.25)

            let restored = createState()
            restored.applyLocalSettings(stored)
            compare(restored.bendRamSpeed, 8.5)
            compare(restored.jogRamSpeed, 3.25)
            restored.destroy()
        }

            function test_readableFileUrlEncodesWindowsAndUnixPaths() {
                compare(state.readableFileUrl("C:\\Program Files\\Part A.bcbend"),
                    "file:///C:/Program%20Files/Part%20A.bcbend")
                compare(state.readableFileUrl("/opt/bend control/Part A.bcbend"),
                    "file:///opt/bend%20control/Part%20A.bcbend")
                compare(state.readableFileUrl("file:///tmp/Part A.bcbend"),
                    "file:///tmp/Part%20A.bcbend")
            }

        function test_ramSpeedSaveFailureRestoresPreviousValue() {
            let fakeIo = {
                read: function(url) { return "{}" },
                write: function(url, text) { return false },
                exists: function(url) { return true }
            }
            state.storageIoOverride = fakeIo
            state.offlineSimulationEnabled = true
            let previous = state.bendRamSpeed
            let previousSetting = state.localSettingsModel.bendRamSpeed.value
            verify(!state.setRamSpeed("bend", 9.5))
            compare(state.bendRamSpeed, previous)
            compare(state.localSettingsModel.bendRamSpeed.value, previousSetting)
        }

        function test_generateFirstSaveOverwriteBackupAndReload() {
            let files = ({})
            let fakeIo = {
                read: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url) ? files[url] : null
                },
                write: function(url, text) {
                    files[url] = text
                    return true
                },
                exists: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url)
                }
            }
            state.storageIoOverride = fakeIo
            prepareCad(state, "Persistent CAD")
            state.cadAction("generate")

            let programsUrl = state.writableCurrentDataPath("programs.json")
            let bendsUrl = state.writableCurrentDataPath("bends.json")
            verify(Object.prototype.hasOwnProperty.call(files, programsUrl))
            verify(Object.prototype.hasOwnProperty.call(files, bendsUrl))
            verify(!Object.prototype.hasOwnProperty.call(files, programsUrl + ".bak"))
            let firstStoredBends = JSON.parse(files[bendsUrl])
            compare(firstStoredBends.length, 1)
            compare(firstStoredBends[0].id, state.programBends[0].id)
            compare(state.popupButtonText, "VIEW IN RUN")
            compare(state.popupKind, "cad-result")
            compare(state.popupResultData.programName, "Persistent CAD")
            compare(state.popupResultData.bendCount, 1)
            verify(state.popupResultData.saved)
            compare(state.popupResultData.rows.length, 1)
            verify(state.cadStatusMessage.indexOf("and saved") >= 0)
            let firstPayload = files[programsUrl]

            prepareCad(state, "Persistent CAD 2")
            state.cadAction("generate")
            compare(files[programsUrl + ".bak"], firstPayload)
            verify(files[programsUrl].indexOf("Persistent CAD 2") >= 0)
            compare(JSON.parse(files[bendsUrl]).length, 2)

            let reloaded = createState()
            let storedPrograms = JSON.parse(files[programsUrl])
            reloaded.setProgramsFromStorage(storedPrograms, [], [], [], [], {})
            let found = false
            for (let index = 0; index < reloaded.programs.length; index++) {
                if (reloaded.programs[index].name === "Persistent CAD 2"
                        && reloaded.programs[index].cadPreviewJson.length > 0)
                    found = true
            }
            verify(found, "Generated CAD program survives startup mapping")
            reloaded.destroy()
        }

        // Generated CAD bends must carry the canonical editable inputs used by
        // the generator, so a restart keeps the same START/CLAMP/FINAL depths
        // (springback 2, clearance 0.0306, real width) and CREATE BEND can save.
        function test_generatedCadBendKeepsDepthsAfterReload() {
            let files = ({})
            state.storageIoOverride = {
                read: function(url) { return Object.prototype.hasOwnProperty.call(files, url) ? files[url] : null },
                write: function(url, text) { files[url] = text; return true },
                exists: function(url) { return Object.prototype.hasOwnProperty.call(files, url) }
            }
            state.desktopRamToTableOpening = 0
            prepareCad(state, "Canonical CAD")
            state.cadAction("generate")
            let generated = state.programBends[0]
            compare(generated.desiredBendAngle, 90)
            compare(generated.angleCompensation, 2)
            compare(generated.compensation, "2.0")
            compare(generated.punchToMaterialClearance, 0.0306)
            compare(generated.additionalRetractAfterBend, 0)
            compare(generated.bendWidth, 6)
            fuzzyCompare(generated.materialThickness, 0.06, 1e-9)

            let reloaded = createState()
            reloaded.desktopRamToTableOpening = 0
            reloaded.setProgramsFromStorage(JSON.parse(files[state.writableCurrentDataPath("programs.json")]), [],
                state.cadPunchCatalog, state.cadDieCatalog, state.cadMaterialCatalog, {})
            let mapped = null
            for (let index = 0; index < reloaded.programs.length; index++) {
                if (reloaded.programs[index].name === "Canonical CAD")
                    mapped = reloaded.programs[index].bends[0]
            }
            verify(mapped !== null)
            compare(mapped.startPosition, generated.startPosition)
            compare(mapped.clampPosition, generated.clampPosition)
            compare(mapped.finalPosition, generated.finalPosition)
            compare(mapped.angleCompensation, 2)
            compare(mapped.bendWidth, 6)
            verify(Number(mapped.tonnage) > 0, "tonnage survives reload: " + mapped.tonnage)
            reloaded.destroy()
        }

        function test_generateSameCadNameUpdatesInPlace() {
            let files = ({})
            let fakeIo = {
                read: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url) ? files[url] : null
                },
                write: function(url, text) {
                    files[url] = text
                    return true
                },
                exists: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url)
                }
            }
            state.storageIoOverride = fakeIo
            prepareCad(state, "Synchronized N1")
            state.cadAction("generate")
            let originalId = state.programs[0].id

            prepareCad(state, "Synchronized N1")
            state.cadBends[0].processBgPosition = 2.5
            state.cadAction("generate")

            compare(state.programs.length, 1)
            compare(state.programs[0].name, "Synchronized N1")
            compare(state.programs[0].id, originalId)
            compare(state.programs[0].bends.length, 1)
            compare(state.programs[0].bends[0].x, "2.5000")
            let stored = JSON.parse(files[state.writableCurrentDataPath("programs.json")])
            compare(stored.length, 1)
            compare(stored[0].id, originalId)
            let storedBends = JSON.parse(files[state.writableCurrentDataPath("bends.json")])
            compare(storedBends.length, 1)
            compare(storedBends[0].x, "2.5000")
        }

        function test_generateSecondWriteFailureRollsBackFilesAndMemory() {
            let files = ({})
            let failPrograms = false
            let fakeIo = {
                read: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url) ? files[url] : null
                },
                write: function(url, text) {
                    if (failPrograms && /programs\.json$/.test(url))
                        return false
                    files[url] = text
                    return true
                },
                exists: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url)
                }
            }
            state.storageIoOverride = fakeIo
            prepareCad(state, "First CAD")
            state.cadAction("generate")
            let programsUrl = state.writableCurrentDataPath("programs.json")
            let bendsUrl = state.writableCurrentDataPath("bends.json")
            let programsBefore = files[programsUrl]
            let bendsBefore = files[bendsUrl]
            let programCountBefore = state.programs.length

            failPrograms = true
            prepareCad(state, "Rejected CAD")
            state.cadAction("generate")

            compare(files[programsUrl], programsBefore)
            compare(files[bendsUrl], bendsBefore)
            compare(state.programs.length, programCountBefore)
            verify(state.alarmVisible)
            compare(state.alarmTitle, "GENERATE PROGRAM")
        }

        function test_generateWithoutBackendDisclosesSessionOnlyState() {
            prepareCad(state, "Session CAD")
            verify(!state.storageBackendReady)
            state.cadAction("generate")

            compare(state.activeProgram, "Session CAD")
            compare(state.popupButtonText, "VIEW IN RUN")
            compare(state.popupKind, "cad-result")
            verify(!state.popupResultData.saved)
            verify(state.popupResultData.storageLabel.indexOf("SESSION ONLY") >= 0)
            verify(state.popupBody.indexOf("persistent storage is unavailable") >= 0)
            verify(state.cadStatusMessage.indexOf("not saved") >= 0)
        }

        function test_generateRejectsImportedFileWithoutBends() {
            state.cadImported = true
            state.cadHasErrors = false
            state.cadBends = []
            state.cadBendCount = 0

            state.cadAction("generate")

            verify(state.alarmVisible)
            compare(state.alarmTitle, "NO BENDS DETECTED")
        }

        function test_realBatteryPlateImportPopulatesFourRows() {
            let loaded = state.cadLoadFile(
                Qt.resolvedUrl("../../assets/bcbends/Battery Plate N1.bcbend"),
                [], [], [], {})

            verify(loaded, state.cadStatusMessage)
            verify(state.cadImported)
            compare(state.cadBendCount, 4)
            compare(state.cadBends.length, 4)
            compare(state.cadBends[0].angle, "90.0")
            verify(Number(state.cadBends[0].width) > 0)
            compare(state.cadSuggestedOrderIds.length, 4)
        }

        function test_batteryPlateOrdersNarrowBendsFirstAndSharesNineInchPhase() {
            state.punchCoverageSideToleranceIn = 0.5
            let punch = {
                id: "gn88", name: "Gooseneck 88° Punch [BC-8392]",
                punchAngleDegree: 88, punchProfileType: "GOOSENECK",
                segmentCount16In: 2, segmentCount8In: 1,
                segmentCount4In: 1, segmentCount2In: 2, segmentCount1In: 1
            }
            let die = {
                id: "die8", name: "Acute 8mm Die 30° Die [BC-5623]",
                vdieOpeningInch: 0.315,
                segmentCount16In: 2, segmentCount8In: 1,
                segmentCount4In: 1, segmentCount2In: 2, segmentCount1In: 1
            }
            let material = {
                id: "steel", name: "Steel",
                materialTensileStrengthPsi: 58000,
                materialSpringback: 2,
                insideRadiusRuleOfThumb: 0.16,
                thicknessToolingPreferences: [{
                    thicknessLabel: "16 ga",
                    preferredPunchId: punch.id,
                    preferredDieId: die.id
                }]
            }
            let loaded = state.cadLoadFile(
                Qt.resolvedUrl("../../assets/bcbends/Battery Plate N1.bcbend"),
                [punch], [die], [material], {})

            verify(loaded, state.cadStatusMessage)
            compare(String(state.cadBends[0].id), "3")
            compare(String(state.cadBends[1].id), "4")
            compare(String(state.cadBends[2].id), "1")
            compare(String(state.cadBends[3].id), "2")
            compare(String(state.cadLoadedJson.bends[0].id), "3")
            compare(String(state.cadLoadedJson.bends[1].id), "4")
            compare(String(state.cadLoadedJson.bends[2].id), "1")
            compare(String(state.cadLoadedJson.bends[3].id), "2")
            let edgeSequenceByBendId = ({})
            let bendEdges = state.cadLoadedJson.sheetMetalGraph.bendEdges
            for (let edgeIndex = 0; edgeIndex < bendEdges.length; edgeIndex++)
                edgeSequenceByBendId[String(bendEdges[edgeIndex].sourceBendId)]
                    = bendEdges[edgeIndex].sequenceHint
            compare(edgeSequenceByBendId["3"], 1)
            compare(edgeSequenceByBendId["4"], 2)
            compare(edgeSequenceByBendId["1"], 3)
            compare(edgeSequenceByBendId["2"], 4)
            for (let index = 0; index < state.cadBends.length; index++) {
                compare(state.cadBends[index].toolingPhaseIndex, 0)
                compare(state.cadBends[index].punchSegmentWidths.length, 2)
                compare(state.cadBends[index].punchSegmentWidths[0], 8)
                compare(state.cadBends[index].punchSegmentWidths[1], 1)
                compare(state.cadBends[index].dieSegmentWidths[0], 8)
                compare(state.cadBends[index].dieSegmentWidths[1], 1)
                compare(state.cadBends[index].chg, index === 0 ? "START" : "SAME")
            }

            state.cadProgramName = "Battery Plate Phase Test"
            state.cadAction("generate")
            compare(state.programBends.length, 4)
            for (let generatedIndex = 0;
                    generatedIndex < state.programBends.length; generatedIndex++) {
                compare(state.programBends[generatedIndex].toolingPhaseIndex, 0)
                compare(state.programBends[generatedIndex].punchSegmentWidths[0], 8)
                compare(state.programBends[generatedIndex].punchSegmentWidths[1], 1)
                compare(state.programBends[generatedIndex].punchSegmentStartIn, -4.5)
            }
        }

        function test_inverterCoverOrdersLongestOppositeSidesBeforeShorterSides() {
            state.punchCoverageSideToleranceIn = 0.5
            let punch = {
                id: "gn88", name: "Gooseneck 88° Punch [BC-8392]",
                punchAngleDegree: 88, punchProfileType: "GOOSENECK",
                segmentCount16In: 2, segmentCount8In: 1,
                segmentCount4In: 1, segmentCount2In: 2, segmentCount1In: 1
            }
            let die = {
                id: "die8", name: "Acute 8mm Die 30° Die [BC-5623]",
                vdieOpeningInch: 0.315,
                segmentCount16In: 2, segmentCount8In: 1,
                segmentCount4In: 1, segmentCount2In: 2, segmentCount1In: 1
            }
            let material = {
                id: "steel", name: "Steel",
                materialTensileStrengthPsi: 58000,
                materialSpringback: 2,
                insideRadiusRuleOfThumb: 0.16,
                thicknessToolingPreferences: [{
                    thicknessLabel: "18 ga",
                    preferredPunchId: punch.id,
                    preferredDieId: die.id
                }]
            }
            let loaded = state.cadLoadFile(
                Qt.resolvedUrl("../../assets/bcbends/Inverter Cover N1.bcbend"),
                [punch], [die], [material], {})

            verify(loaded, state.cadStatusMessage)
            compare(String(state.cadBends[0].id), "2")
            compare(String(state.cadBends[1].id), "1")
            compare(String(state.cadBends[2].id), "3")
            compare(String(state.cadBends[3].id), "4")
            compare(String(state.cadLoadedJson.bends[0].id), "2")
            compare(String(state.cadLoadedJson.bends[1].id), "1")
            compare(String(state.cadLoadedJson.bends[2].id), "3")
            compare(String(state.cadLoadedJson.bends[3].id), "4")
            compare(state.cadBends[0].width, "43.918")
            compare(state.cadBends[1].width, "43.918")
            compare(state.cadBends[2].width, "28.074")
            compare(state.cadBends[3].width, "27.964")
            for (let index = 0; index < state.cadBends.length; index++) {
                compare(state.cadBends[index].toolingPhaseIndex, 0)
                compare(state.cadBends[index].chg, index === 0 ? "START" : "SAME")
                compare(state.cadBends[index].punchSegmentWidths.join(","), "16,16,8,2,1")
                compare(state.cadBends[index].dieSegmentWidths.join(","), "16,16,8,2,1")
            }
        }

        function test_setupReuseOrderRespectsPreviousBendDependency() {
            let rows = [
                { id: "parent", sequenceHint: 2, widthValue: 10,
                  setupLabel: "STD", punchId: "p", dieId: "d",
                  refType: "EDGE", parentBendId: 0 },
                { id: "child", sequenceHint: 1, widthValue: 6,
                  setupLabel: "STD", punchId: "p", dieId: "d",
                  refType: "PREVIOUS_BEND", parentBendId: "parent" },
                { id: "independent", sequenceHint: 3, widthValue: 7,
                  setupLabel: "STD", punchId: "p", dieId: "d",
                  refType: "EDGE", parentBendId: 0 }
            ]

            let ordered = state.orderCadBendsForSetupReuse(rows)
            let parentIndex = -1
            let childIndex = -1
            for (let index = 0; index < ordered.length; index++) {
                if (ordered[index].id === "parent") parentIndex = index
                if (ordered[index].id === "child") childIndex = index
            }
            verify(parentIndex >= 0)
            verify(childIndex > parentIndex)
        }

        function test_readableFileUrlNormalizesWindowsPaths() {
            compare(state.readableFileUrl("C:\\CAD Files\\Battery Plate 6.bcbend"),
                    "file:///C:/CAD%20Files/Battery%20Plate%206.bcbend")
            compare(state.readableFileUrl("file:///C:/CAD/Battery%20Plate%206.bcbend"),
                    "file:///C:/CAD/Battery%20Plate%206.bcbend")
        }

        function test_nearestThicknessProfileSelectsConfiguredTooling() {
            let material = {
                name: "Steel",
                materialTensileStrengthPsi: 60000,
                insideRadiusRuleOfThumb: 0.16,
                thicknessToolingPreferences: [{
                    thicknessLabel: "16 ga",
                    preferredPunchId: "preferred-punch",
                    preferredDieId: "preferred-die"
                }]
            }
            let punches = [
                { id: "other-punch", name: "Other", punchAngleDegree: 30, punchProfileType: "STANDARD" },
                { id: "preferred-punch", name: "Preferred", punchAngleDegree: 88, punchProfileType: "GOOSENECK" }
            ]
            let dies = [
                { id: "other-die", name: "Other Die", vdieOpeningInch: 0.5 },
                { id: "preferred-die", name: "Preferred Die", vdieOpeningInch: 0.315 }
            ]

            let tooling = state.chooseTooling(material, punches, dies, 0.0600, {
                angleValue: 90,
                widthValue: 10,
                chainDepth: 0,
                processBgPosition: 1
            })

            compare(tooling.punch.id, "preferred-punch")
            compare(tooling.die.id, "preferred-die")
        }

        function test_materialSelectionMatchesJavaScoringAndAvoidsStainlessForPlainSteel() {
            state.cadTensileStrength = 58000
            state.cadSpringBack = 2
            let materials = [
                { id: "stainless", name: "Stainless Steel", stock: true,
                  materialTensileStrengthPsi: 75000, materialSpringback: 3 },
                { id: "a36", name: "Steel ASTM A36", stock: true,
                  materialTensileStrengthPsi: 58000, materialSpringback: 2 }
            ]
            compare(state.findClosestMaterial("Steel ASTM A36", materials).id, "a36")
            compare(state.findClosestMaterial("A36 steel", materials).id, "a36")
        }

        function test_schemaV5ValidationUsesWholePreviewContract() {
            let payload = {
                topologySchemaVersion: "5.0",
                generator: {
                    id: "com.bendcnc.export",
                    version: "1.1.0",
                    revision: "stale",
                    topologySchemaVersion: "5.0"
                },
                sheetMetalGraph: { schemaVersion: 5 }
            }
            compare(state.validateCadSchemaV5(payload), "diagnostics-not-qualified")
            delete payload.sheetMetalGraph
            compare(state.validateCadSchemaV5(payload), "missing-sheet-metal-graph")
        }

        function test_moveCadBendLocksRenumbersAndPersistsPreviewOrder() {
            state.cadSelectedMaterial = {
                name: "Steel",
                materialTensileStrengthPsi: 60000,
                insideRadiusRuleOfThumb: 0.16,
                thicknessToolingPreferences: []
            }
            state.cadPunchCatalog = [{
                id: "punch", name: "Punch", punchAngleDegree: 30,
                punchProfileType: "STANDARD"
            }]
            state.cadDieCatalog = [{
                id: "die", name: "Die", vdieOpeningInch: 0.5
            }]
            state.cadThicknessValue = 0.06
            state.cadTensileStrength = 60000
            state.cadLoadedJson = {
                bends: [
                    { id: 1, sequenceHint: 1, angle_deg: 90, direction: "UP" },
                    { id: 2, sequenceHint: 2, angle_deg: 90, direction: "UP" }
                ],
                sheetMetalGraph: {
                    schemaVersion: 5,
                    bendEdges: [
                        { sourceBendId: "1", sequenceHint: 1 },
                        { sourceBendId: "2", sequenceHint: 2 }
                    ]
                }
            }
            function row(id) {
                return {
                    id: id, seq: id, locked: false, angleValue: 90,
                    angle: "90.0", widthValue: 10, width: "10.000",
                    processBgPosition: 1, bg: "1.0000", bgrValue: -0.25,
                    bgr: "-0.2500", chainDepth: 0, parentBendId: 0,
                    ref: "EDGE", refType: "EDGE", dir: "UP",
                    vdieValue: 0.5, errors: [], warnings: [], notes: []
                }
            }
            state.cadBends = [row(1), row(2)]

            var previousPreview = state.cadLoadedJson
            verify(state.moveCadBend(1, 0))

            compare(previousPreview.bends[0].sequenceHint, 1)
            compare(previousPreview.sheetMetalGraph.bendEdges[0].sequenceHint, 1)
            compare(previousPreview.sheetMetalGraph.bendEdges[1].sequenceHint, 2)
            compare(state.cadBends[0].id, 2)
            compare(state.cadBends[0].seq, 1)
            compare(state.cadBends[0].fix, "LOCK")
            compare(state.cadBends[1].id, 1)
            compare(state.cadLoadedJson.bends[0].id, 2)
            compare(state.cadLoadedJson.sheetMetalGraph.bendEdges[0].sequenceHint, 2)
            compare(state.cadLoadedJson.sheetMetalGraph.bendEdges[1].sequenceHint, 1)
        }

        function test_incompleteEmbeddedMappingLeavesFirstImportAvailable() {
            var stateBefore = state.cadUnfoldState
            var statusBefore = state.cadStatusMessage
            var plan = { stages: [{ bendId: 2, to: { "2": 1 } }] }
            verify(!state.applyCadUnfoldPlan(plan, null, [{ id: 1 }]))
            compare(state.cadUnfoldState, stateBefore)
            compare(state.cadStatusMessage, statusBefore)
        }

        function test_moveCadBendPreservesStringIdsDependenciesAndCompoundRelations() {
            state.cadSelectedMaterial = {
                name: "Steel", materialTensileStrengthPsi: 60000,
                insideRadiusRuleOfThumb: 0.16, thicknessToolingPreferences: []
            }
            state.cadPunchCatalog = [{ id: "p", name: "Punch", punchAngleDegree: 30,
                                       punchProfileType: "STANDARD" }]
            state.cadDieCatalog = [{ id: "d", name: "Die", vdieOpeningInch: 0.5 }]
            state.cadThicknessValue = 0.06
            state.cadTensileStrength = 60000
            state.cadLoadedJson = {
                bends: [
                    { id: "bend-A", sequenceHint: 1, angle_deg: 90, direction: "UP" },
                    { id: "bend-B", sequenceHint: 2, angle_deg: 90, direction: "DOWN",
                      referenceType: "PREVIOUS_BEND", parentBendId: "bend-A" }
                ],
                sheetMetalGraph: {
                    schemaVersion: 5,
                    bendEdges: [
                        { sourceBendId: "bend-A", sequenceHint: 1,
                          operationRelationIndex: 0, operationRelationCount: 2 },
                        { sourceBendId: "bend-A", sequenceHint: 1,
                          operationRelationIndex: 1, operationRelationCount: 2 },
                        { sourceBendId: "bend-B", sequenceHint: 2 }
                    ]
                }
            }
            function row(id, parentId) {
                return {
                    id: id, seq: 1, locked: false, angleValue: 90,
                    angle: "90.0", widthValue: 10, width: "10.000",
                    processBgPosition: 1, bg: "1.0000", bgrValue: -0.25,
                    bgr: "-0.2500", chainDepth: parentId ? 1 : 0,
                    parentBendId: parentId || 0,
                    ref: parentId ? "B" + parentId : "EDGE",
                    refType: parentId ? "PREVIOUS_BEND" : "EDGE", dir: "UP",
                    vdieValue: 0.5, errors: [], warnings: [], notes: []
                }
            }
            state.cadBends = [row("bend-A", null), row("bend-B", "bend-A")]
            verify(state.moveCadBend(1, 0))

            compare(state.cadLoadedJson.bends[0].id, "bend-B")
            compare(state.cadLoadedJson.bends[0].parentBendId, "bend-A")
            compare(state.cadLoadedJson.sheetMetalGraph.bendEdges[0].sequenceHint, 2)
            compare(state.cadLoadedJson.sheetMetalGraph.bendEdges[1].sequenceHint, 2)
            compare(state.cadLoadedJson.sheetMetalGraph.bendEdges[2].sequenceHint, 1)
        }

        function test_restoreSuggestedOrderAndEditBackGaugeR() {
            state.cadSelectedMaterial = {
                name: "Steel", materialTensileStrengthPsi: 60000,
                insideRadiusRuleOfThumb: 0.16, thicknessToolingPreferences: []
            }
            state.cadPunchCatalog = [{ id: "p", name: "Punch", punchAngleDegree: 30,
                                       punchProfileType: "STANDARD" }]
            state.cadDieCatalog = [{ id: "d", name: "Die", vdieOpeningInch: 0.5 }]
            state.cadThicknessValue = 0.06
            state.cadTensileStrength = 60000
            state.cadLoadedJson = {
                bends: [
                    { id: "A", sequenceHint: 1, angle_deg: 90, direction: "UP" },
                    { id: "B", sequenceHint: 2, angle_deg: 90, direction: "UP" }
                ]
            }
            function row(id) {
                return {
                    id: id, seq: 1, locked: false, angleValue: 90,
                    angle: "90.0", widthValue: 10, width: "10.000",
                    processBgPosition: 1, bg: "1.0000", bgrValue: -0.25,
                    bgr: "-0.2500", chainDepth: 0, parentBendId: 0,
                    ref: "EDGE", refType: "EDGE", dir: "UP",
                    vdieValue: 0.5, errors: [], warnings: [], notes: []
                }
            }
            state.cadBends = [row("A"), row("B")]
            state.cadSuggestedOrderIds = ["A", "B"]

            verify(state.moveCadBend(1, 0))
            compare(state.cadBends[0].id, "B")
            verify(state.updateCadBendR(0, "-0.375"))
            compare(state.cadBends[0].bgr, "-0.3750")
            compare(state.cadLoadedJson.bends[0].bgRPosition_in, -0.375)
            verify(!state.updateCadBendR(0, ""))
            verify(!state.updateCadBendR(0, "   "))
            verify(!state.updateCadBendR(0, "not-a-number"))
            verify(state.restoreCadSuggestedOrder())
            compare(state.cadBends[0].id, "A")
            compare(state.cadBends[1].id, "B")
            compare(state.cadBends[0].fix, "AUTO")
            compare(state.cadBends[1].fix, "AUTO")
            verify(!state.cadManualSequenceOverride)
        }

        function test_liveProjectionModeDefaultsValidatesAndPersists() {
            state.applyLocalSettings({ runLiveProjectionMode: "unexpected" })
            compare(state.runLiveProjectionMode, "SIDE")

            let files = ({})
            state.storageIoOverride = {
                read: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url) ? files[url] : null
                },
                write: function(url, text) {
                    files[url] = text
                    return true
                },
                exists: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url)
                }
            }
            state.setRunLiveProjectionMode("isometric")
            compare(state.runLiveProjectionMode, "ISOMETRIC")
            let settingsUrl = state.writableCurrentDataPath("local-settings.json")
            verify(Object.prototype.hasOwnProperty.call(files, settingsUrl))
            compare(JSON.parse(files[settingsUrl]).runLiveProjectionMode, "ISOMETRIC")
        }

        function test_liveCameraOrientationDefaultsValidatesAndPersists() {
            state.applyLocalSettings({ runLiveCameraOrientation: "unexpected" })
            compare(state.runLiveCameraOrientation, "ISO_TOP_LEFT")

            let files = ({})
            state.storageIoOverride = {
                read: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url) ? files[url] : null
                },
                write: function(url, text) {
                    files[url] = text
                    return true
                },
                exists: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url)
                }
            }
            state.setRunLiveCameraOrientation("iso_bottom_right")
            compare(state.runLiveCameraOrientation, "ISO_BOTTOM_RIGHT")
            let settingsUrl = state.writableCurrentDataPath("local-settings.json")
            verify(Object.prototype.hasOwnProperty.call(files, settingsUrl))
            compare(JSON.parse(files[settingsUrl]).runLiveCameraOrientation,
                    "ISO_BOTTOM_RIGHT")
        }

        function test_toolingAppearanceDefaultsValidatesAndPersists() {
            state.applyLocalSettings({ runToolingAppearance: "unexpected" })
            compare(state.runToolingAppearance, "SOLID")

            let files = ({})
            state.storageIoOverride = {
                read: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url) ? files[url] : null
                },
                write: function(url, text) {
                    files[url] = text
                    return true
                },
                exists: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url)
                }
            }
            state.setRunToolingAppearance("translucent")
            compare(state.runToolingAppearance, "TRANSLUCENT")
            let settingsUrl = state.writableCurrentDataPath("local-settings.json")
            compare(JSON.parse(files[settingsUrl]).runToolingAppearance, "TRANSLUCENT")
            state.settingsAction("Tooling Appearance")
            compare(state.runToolingAppearance, "SOLID")
            compare(JSON.parse(files[settingsUrl]).runToolingAppearance, "SOLID")
        }
    }
}
