import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root
    objectName: "punch-die-materials-view"
    property var appState: null

    readonly property real designWidth: 864
    readonly property real designHeight: 668
    readonly property real sx: width / designWidth
    readonly property real sy: height / designHeight
    readonly property real pagePadding: 7 * sx
    readonly property real moduleGap: 7 * sx
    readonly property real moduleWidth: (width - pagePadding * 2 - moduleGap * 2) / 3
    readonly property color red: "#A82011"
    readonly property color green: "#59A60C"
    readonly property color blue: "#2D83B2"
    readonly property color charcoal: "#2B2C2B"
    readonly property color lightGrey: "#E0E0E0"
    readonly property color grey: "#A8A8A8"
    readonly property color ink: "#232323"
    readonly property color white: "#FFFFFF"
    readonly property color midGrey: "#BCBCBC"
    readonly property color softGrey: "#D6D6D6"
    readonly property color cardBorder: "#C4C4C4"
    readonly property color darkGrey: "#5E5E5E"

    DataStore { id: dataStore }

    function names(items) {
        return items.map(function(item) { return item.name || "" })
    }

    function recordsForKind(kind) {
        return kind === "punch" ? dataStore.punches
                                : (kind === "die" ? dataStore.dies : dataStore.materials)
    }

    function displayNumber(value, digits) {
        return value === null || value === undefined || isNaN(value)
                ? "" : Number(value).toFixed(digits)
    }

    function findNameById(items, identifier) {
        if (!identifier)
            return ""
        for (let index = 0; index < items.length; index++) {
            if (items[index].id === identifier)
                return items[index].name || ""
        }
        return ""
    }

    function firstPreference(material) {
        var preferences = material && material.thicknessToolingPreferences
                ? material.thicknessToolingPreferences : []
        return preferences.length > 0 ? preferences[0] : ({})
    }

    function formatPreferredToolName(name, kind) {
        var value = String(name || "").trim()
        var bracketStart = value.indexOf("[")
        var identifier = bracketStart >= 0 ? value.substring(bracketStart).trim() : ""
        var title = bracketStart >= 0 ? value.substring(0, bracketStart).trim() : value
        if (kind === "punch")
            title = title.replace(/\s+Punch\b/gi, "").trim()
        else if (kind === "die")
            title = title.replace(/\s+Die\b/gi, "").trim()
        return identifier.length > 0 ? title + "\n" + identifier : title
    }

    Rectangle {
        anchors.fill: parent
        color: root.grey
        radius: 7
    }

    Row {
        x: root.pagePadding
        y: 7 * root.sy
        width: root.width - root.pagePadding * 2
        height: root.height - 14 * root.sy
        spacing: root.moduleGap

        ToolModule {
            objectName: "punch-view"
            property real pageX: parent.x + x
            width: root.moduleWidth
            height: parent.height
            kind: "punch"
            title: "PUNCH"
            accent: root.red
            addClass: "button-add-new-punch"
            primaryTitle: "ORIGINAL SPECS"
            primaryRows: ["Punch Height", "Punch Profile", "Punch Angle"]
            primaryTypes: ["info-field", "combo", "field"]
            secondaryTitle: "AVAILABLE SEGMENTS"
            secondarySegments: true
        }

        ToolModule {
            objectName: "die-view"
            property real pageX: parent.x + x
            width: root.moduleWidth
            height: parent.height
            kind: "die"
            title: "DIE"
            accent: root.blue
            addClass: "button-add-new-die"
            primaryTitle: "ORIGINAL SPECS"
            primaryRows: ["Die Height", "V Die Opening"]
            primaryTypes: ["info-field", "info-field"]
            secondaryTitle: "ADVANCED DETAILS"
            secondaryRows: ["Die Angle", "Overall Width"]
            secondaryTypes: ["field", "field"]
            tertiaryTitle: "AVAILABLE SEGMENTS"
            tertiarySegments: true
        }

        ToolModule {
            objectName: "material-view"
            property real pageX: parent.x + x
            width: root.moduleWidth
            height: parent.height
            kind: "material"
            title: "MATERIALS"
            accent: root.green
            addClass: "button-add-new-material"
            primaryTitle: "MATERIAL DEFAULTS"
            primaryRows: ["Tensile Strength", "Inside Radius", "Spring Back"]
            primaryTypes: ["field", "label-info-field", "label-info-field"]
            secondaryTitle: "THICKNESS PROFILE"
            helper: "Default punch and die choices for each material thickness."
            secondaryRows: ["Thickness", "Preferred Punch", "Preferred Die", "Punch Clearance"]
            secondaryTypes: ["combo", "combo", "combo", "field"]
            materialMode: true
        }
    }

    component ToolModule: Item {
        id: module
        property string kind: ""
        property string title: ""
        property color accent: root.red
        property string addClass: ""
        property string primaryTitle: ""
        property var primaryRows: []
        property var primaryTypes: []
        property string secondaryTitle: ""
        property var secondaryRows: []
        property var secondaryTypes: []
        property string tertiaryTitle: ""
        property string helper: ""
        property bool secondarySegments: false
        property bool tertiarySegments: false
        property bool materialMode: false
        property int selectedIndex: 0
        readonly property var records: root.recordsForKind(kind)
        readonly property var selectedRecord: records.length > 0
                ? records[Math.max(0, Math.min(selectedIndex, records.length - 1))] : ({})
        readonly property real headerHeight: 34 * root.sy
        readonly property real bodyPadding: 7 * root.sx

        function rowValue(label, rowType) {
            var record = selectedRecord
            var preference = root.firstPreference(record)
            if (kind === "punch") {
                if (label === "Punch Height") return root.displayNumber(record.heightInch, 3)
                if (label === "Punch Profile") return record.punchProfileType || ""
                if (label === "Punch Angle") return root.displayNumber(record.punchAngleDegree, 1)
            } else if (kind === "die") {
                if (label === "Die Height") return root.displayNumber(record.heightInch, 3)
                if (label === "V Die Opening") return root.displayNumber(record.vdieOpeningInch, 3)
                if (label === "Die Angle") return root.displayNumber(record.dieAngleDegree, 1)
                if (label === "Overall Width") return root.displayNumber(record.overallWidthInch, 3)
            } else if (kind === "material") {
                if (label === "Tensile Strength") return root.displayNumber(record.materialTensileStrengthPsi, 0)
                if (label === "Inside Radius") return root.displayNumber((record.insideRadiusRuleOfThumb || 0) * 100, 0)
                if (label === "Spring Back") return root.displayNumber(record.materialSpringback, 1)
                if (label === "Thickness") return preference.thicknessLabel || ""
                if (label === "Preferred Punch") return root.formatPreferredToolName(root.findNameById(dataStore.punches, preference.preferredPunchId), "punch")
                if (label === "Preferred Die") return root.formatPreferredToolName(root.findNameById(dataStore.dies, preference.preferredDieId), "die")
                if (label === "Punch Clearance") return root.displayNumber(preference.punchToMaterialClearancePercent, 0)
            }
            return rowType === "combo" ? "" : "0"
        }

        function rowModel(label) {
            if (kind === "punch" && label === "Punch Profile")
                return ["ACUTE", "STANDARD", "GOOSENECK", "EXTREME GOOSENECK"]
            if (kind === "material" && label === "Thickness") {
                const preferences = selectedRecord.thicknessToolingPreferences || []
                return preferences.map(function(preference) { return preference.thicknessLabel || "" })
            }
            if (kind === "material" && label === "Preferred Punch")
                return root.names(dataStore.punches).map(function(name) {
                    return root.formatPreferredToolName(name, "punch")
                })
            if (kind === "material" && label === "Preferred Die")
                return root.names(dataStore.dies).map(function(name) {
                    return root.formatPreferredToolName(name, "die")
                })
            return [rowValue(label, "combo")]
        }

        function segmentValue(label) {
            var record = selectedRecord
            if (label === "16\"") return root.displayNumber(record.segmentCount16In, 0)
            if (label === "8\"") return root.displayNumber(record.segmentCount8In, 0)
            if (label === "4\"") return root.displayNumber(record.segmentCount4In, 0)
            if (label === "2\"") return root.displayNumber(record.segmentCount2In, 0)
            if (label === "1\"") return root.displayNumber(record.segmentCount1In, 0)
            return ""
        }

        function replaceSelectedRecord(record) {
            if (records.length === 0)
                return
            var next = records.slice(0)
            next[selectedIndex] = record
            if (kind === "punch")
                dataStore.punches = next
            else if (kind === "die")
                dataStore.dies = next
            else
                dataStore.materials = next
        }

        function setRowValue(label, value, optionIndex) {
            if (records.length === 0)
                return
            var record = Object.assign({}, selectedRecord)
            var numeric = Number(value)
            if (kind === "punch") {
                if (label === "Punch Height" && isFinite(numeric)) record.heightInch = numeric
                else if (label === "Punch Profile") record.punchProfileType = String(value)
                else if (label === "Punch Angle" && isFinite(numeric)) record.punchAngleDegree = numeric
            } else if (kind === "die") {
                if (label === "Die Height" && isFinite(numeric)) record.heightInch = numeric
                else if (label === "V Die Opening" && isFinite(numeric)) record.vdieOpeningInch = numeric
                else if (label === "Die Angle" && isFinite(numeric)) record.dieAngleDegree = numeric
                else if (label === "Overall Width" && isFinite(numeric)) record.overallWidthInch = numeric
            } else {
                if (label === "Tensile Strength" && isFinite(numeric)) record.materialTensileStrengthPsi = numeric
                else if (label === "Inside Radius" && isFinite(numeric)) record.insideRadiusRuleOfThumb = numeric / 100
                else if (label === "Spring Back" && isFinite(numeric)) record.materialSpringback = numeric
                else {
                    let preferences = (record.thicknessToolingPreferences || []).slice(0)
                    if (preferences.length > 0) {
                        let preference = Object.assign({}, preferences[0])
                        if (label === "Preferred Punch" && optionIndex >= 0 && optionIndex < dataStore.punches.length)
                            preference.preferredPunchId = dataStore.punches[optionIndex].id
                        else if (label === "Preferred Die" && optionIndex >= 0 && optionIndex < dataStore.dies.length)
                            preference.preferredDieId = dataStore.dies[optionIndex].id
                        else if (label === "Punch Clearance" && isFinite(numeric))
                            preference.punchToMaterialClearancePercent = numeric
                        preferences[0] = preference
                        record.thicknessToolingPreferences = preferences
                    }
                }
            }
            replaceSelectedRecord(record)
        }

        function setSegmentValue(label, value) {
            var numeric = Number(value)
            if (!isFinite(numeric) || records.length === 0)
                return
            var record = Object.assign({}, selectedRecord)
            if (label === "16\"") record.segmentCount16In = numeric
            else if (label === "8\"") record.segmentCount8In = numeric
            else if (label === "4\"") record.segmentCount4In = numeric
            else if (label === "2\"") record.segmentCount2In = numeric
            else if (label === "1\"") record.segmentCount1In = numeric
            replaceSelectedRecord(record)
        }

        function runToolAction(action) {
            if (!root.appState)
                return
            var result = root.appState.toolAction(kind, action, records, selectedIndex)
            if (!result || result.ok !== true)
                return
            if (kind === "punch")
                dataStore.punches = result.records
            else if (kind === "die")
                dataStore.dies = result.records
            else
                dataStore.materials = result.records
            selectedIndex = result.selectedIndex
        }

        Rectangle {
            objectName: "header"
            width: parent.width
            height: module.headerHeight
            color: module.accent
            radius: 7
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 7 * root.sy
                color: module.accent
            }
            Text {
                anchors.centerIn: parent
                text: module.title
                color: root.white
                font.pixelSize: 16
                font.bold: true
            }
        }

        Rectangle {
            id: body
            objectName: "body"
            y: module.headerHeight
            width: parent.width
            height: parent.height - y
            color: root.lightGrey
            radius: 7

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 7 * root.sy
                color: root.lightGrey
            }

            StyledCombo {
                objectName: "tool-selector"
                x: module.bodyPadding
                y: 7 * root.sy
                width: body.width - module.bodyPadding * 2 - 36 * root.sx
                height: 36 * root.sy
                options: root.names(module.records)
                currentIndex: module.selectedIndex
                onActivated: function(index) { module.selectedIndex = index }
            }

            ToolIconButton {
                objectName: "button-edit"
                x: body.width - module.bodyPadding - 31 * root.sx
                y: 7 * root.sy
                width: 31 * root.sx
                height: 36 * root.sy
                iconName: "pen"
                base: root.white
                textColor: root.ink
                borderColor: root.ink
                onClicked: module.runToolAction("SAVE")
            }

            Separator {
                x: module.bodyPadding
                y: 50 * root.sy
                width: body.width - module.bodyPadding * 2
            }

            Column {
                objectName: "tool-section-stack"
                x: module.bodyPadding
                y: 75 * root.sy
                width: body.width - module.bodyPadding * 2
                spacing: 12 * root.sy

                SectionBlock {
                    width: parent.width
                    title: module.primaryTitle
                    rows: module.primaryRows
                    rowTypes: module.primaryTypes
                    ownerModule: module
                    materialMode: module.materialMode
                }

                SectionBlock {
                    visible: module.secondaryTitle.length > 0
                    width: parent.width
                    title: module.secondaryTitle
                    helper: module.helper
                    rows: module.secondaryRows
                    rowTypes: module.secondaryTypes
                    ownerModule: module
                    materialMode: module.materialMode
                    showSegments: module.secondarySegments
                }

                SectionBlock {
                    visible: module.tertiaryTitle.length > 0
                    width: parent.width
                    title: module.tertiaryTitle
                    ownerModule: module
                    showSegments: module.tertiarySegments
                }
            }

            ButtonRow {
                objectName: "tool-footer"
                x: module.bodyPadding
                y: body.height - 43 * root.sy
                width: body.width - module.bodyPadding * 2
                height: 36 * root.sy
                kind: module.kind
                ownerModule: module
                addBase: module.accent
                addClass: module.addClass
            }
        }
    }

    component SectionBlock: Item {
        id: section
        property string title: ""
        property string helper: ""
        property var ownerModule: null
        property var rows: []
        property var rowTypes: []
        property bool materialMode: false
        property bool showSegments: false
        readonly property real titleHeight: 19 * root.sy
        readonly property real helperHeight: helper.length > 0 ? 30 * root.sy : 0
        readonly property real rowHeight: 32 * root.sy
        readonly property real rowGap: 7 * root.sy
        readonly property real detailHeight: 16 * root.sy
                + rows.length * rowHeight + Math.max(0, rows.length - 1) * rowGap
        readonly property real panelHeight: showSegments ? 132 * root.sy : detailHeight
        readonly property real blockHeight: titleHeight + helperHeight + panelHeight
        height: visible ? blockHeight : 0

        Text {
            x: 2 * root.sx
            width: parent.width - 4 * root.sx
            height: titleHeight
            text: section.title
            color: Qt.lighter(root.ink, 1.2)
            font.pixelSize: 11
            font.bold: true
            verticalAlignment: Text.AlignTop
        }

        Text {
            visible: section.helper.length > 0
            x: 2 * root.sx
            y: titleHeight - 2 * root.sy
            width: parent.width - 4 * root.sx
            height: helperHeight + 2 * root.sy
            text: section.helper
            color: root.darkGrey
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            maximumLineCount: 2
        }

        Rectangle {
            objectName: section.showSegments
                    ? "tool-details-section segment-cards-grid" : "tool-details-section"
            y: titleHeight + helperHeight
            width: parent.width
            height: section.panelHeight
            radius: 7
            color: root.softGrey
            border.color: root.cardBorder
            border.width: 1

            SegmentGrid {
                visible: section.showSegments
                anchors.fill: parent
                ownerModule: section.ownerModule
            }

            DetailRows {
                visible: !section.showSegments
                anchors.fill: parent
                labels: section.rows
                rowTypes: section.rowTypes
                ownerModule: section.ownerModule
                materialMode: section.materialMode
            }
        }
    }

    component DetailRows: Item {
        property var labels: []
        property var rowTypes: []
        property var ownerModule: null
        property bool materialMode: false
        readonly property real padX: 8 * root.sx
        readonly property real padY: 8 * root.sy
        readonly property real rowHeight: 32 * root.sy
        readonly property real rowGap: 7 * root.sy
        readonly property real labelRatio: materialMode ? 0.45 : 0.35

        Repeater {
            model: labels.length
            Item {
                id: detailRow
                required property int index
                readonly property string labelText: parent.labels[index] || ""
                readonly property string rowType: parent.rowTypes[index] || "field"
                readonly property var moduleOwner: parent.ownerModule
                readonly property bool fieldInfo: rowType === "info-field"
                readonly property bool labelInfo: rowType === "label-info-field"
                readonly property real contentWidth: parent.width - parent.padX * 2
                readonly property real labelWidth: contentWidth * parent.labelRatio
                readonly property real fieldBaseX: labelWidth + 8 * root.sx
                readonly property real infoReserve: fieldInfo ? 20 * root.sx : 0
                x: parent.padX
                y: parent.padY + index * (parent.rowHeight + parent.rowGap)
                width: contentWidth
                height: parent.rowHeight

                Text {
                    width: detailRow.labelWidth - (detailRow.labelInfo ? 19 * root.sx : 0)
                    height: parent.height
                    text: detailRow.labelText
                    color: root.ink
                    font.pixelSize: 11
                    font.bold: true
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 9
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    verticalAlignment: Text.AlignVCenter
                }

                VectorIcon {
                    visible: detailRow.labelInfo
                    x: detailRow.labelWidth - 16 * root.sx
                    y: (parent.height - height) / 2
                    width: 16 * root.sx
                    height: 16 * root.sy
                    iconName: "info-circle"
                }

                VectorIcon {
                    visible: detailRow.fieldInfo
                    x: detailRow.fieldBaseX
                    y: (parent.height - height) / 2
                    width: 16 * root.sx
                    height: 16 * root.sy
                    iconName: "info-circle"
                }

                StyledCombo {
                    objectName: detailRow.labelText === "Preferred Punch"
                            ? "preferred-punch-combo"
                            : (detailRow.labelText === "Preferred Die"
                               ? "preferred-die-combo" : "detail-combo")
                    visible: detailRow.rowType === "combo"
                    x: detailRow.fieldBaseX
                    width: parent.width - x
                    height: parent.height
                    twoLineItems: detailRow.labelText === "Preferred Punch"
                            || detailRow.labelText === "Preferred Die"
                        options: detailRow.moduleOwner
                            ? detailRow.moduleOwner.rowModel(detailRow.labelText) : []
                        valueText: detailRow.moduleOwner
                            ? detailRow.moduleOwner.rowValue(detailRow.labelText, detailRow.rowType) : ""
                    onActivated: function(optionIndex) {
                        if (detailRow.moduleOwner)
                            detailRow.moduleOwner.setRowValue(detailRow.labelText, currentText, optionIndex)
                    }
                }

                MeasurementField {
                    visible: detailRow.rowType !== "combo"
                    x: detailRow.fieldBaseX + detailRow.infoReserve
                    width: parent.width - x
                    height: parent.height
                        text: detailRow.moduleOwner
                            ? detailRow.moduleOwner.rowValue(detailRow.labelText, detailRow.rowType) : ""
                    onEditingFinished: if (detailRow.moduleOwner)
                        detailRow.moduleOwner.setRowValue(detailRow.labelText, text, -1)
                }
            }
        }
    }

    component SegmentGrid: Item {
        property var ownerModule: null
        readonly property real margin: 8 * root.sx
        readonly property real gap: 8 * root.sx
        readonly property real cardWidth: (width - margin * 2 - gap * 2) / 3
        readonly property real cardHeight: 54 * root.sy

        Repeater {
            model: ["16\"", "8\"", "4\"", "2\"", "1\""]
            Rectangle {
                required property int index
                required property string modelData
                objectName: "segment-card"
                x: parent.margin + (index % 3) * (parent.cardWidth + parent.gap)
                y: 8 * root.sy + Math.floor(index / 3) * (parent.cardHeight + 8 * root.sy)
                width: parent.cardWidth
                height: parent.cardHeight
                radius: 6
                color: "#ECECEC"
                border.color: "#CDCDCD"
                border.width: 1

                Text {
                    objectName: "segment-card-title"
                    x: 6 * root.sx
                    y: 4 * root.sy
                    text: modelData
                    color: root.ink
                    font.pixelSize: 11
                    font.bold: true
                }

                MeasurementField {
                    x: 6 * root.sx
                    y: 21 * root.sy
                    width: parent.width - 12 * root.sx
                    height: 27 * root.sy
                    text: ownerModule ? ownerModule.segmentValue(modelData) : ""
                    onEditingFinished: if (ownerModule)
                        ownerModule.setSegmentValue(modelData, text)
                }
            }
        }
    }

    component ButtonRow: Item {
        property string kind: "tool"
        property var ownerModule: null
        property color addBase: root.red
        property string addClass: ""
        readonly property real gap: 4 * root.sx
        readonly property real shortWidth: (width - gap * 3) / 4

        ActionButton {
            objectName: parent.addClass
            width: parent.shortWidth
            height: parent.height
            text: "NEW"
            base: parent.addBase
            textColor: root.white
            roundedLeft: true
            onClicked: if (parent.ownerModule)
                parent.ownerModule.runToolAction("NEW")
        }

        ActionButton {
            objectName: "button-save"
            x: parent.shortWidth + parent.gap
            width: parent.shortWidth
            height: parent.height
            text: "SAVE"
            base: root.charcoal
            textColor: root.white
            onClicked: if (parent.ownerModule)
                parent.ownerModule.runToolAction("SAVE")
        }

        ActionButton {
            objectName: "button-duplicate"
            x: (parent.shortWidth + parent.gap) * 2
            width: parent.shortWidth
            height: parent.height
            text: "DUPLICATE"
            base: "orange"
            textColor: root.ink
            roundedRight: true
            onClicked: if (parent.ownerModule)
                parent.ownerModule.runToolAction("DUPLICATE")
        }

        ActionButton {
            objectName: "button-delete"
            x: (parent.shortWidth + parent.gap) * 3
            width: parent.width - x
            height: parent.height
            text: "DELETE"
            base: root.red
            textColor: root.white
            roundedRight: true
            onClicked: if (parent.ownerModule)
                parent.ownerModule.runToolAction("DELETE")
        }
    }

    component ActionButton: Button {
        property color base: root.charcoal
        property color textColor: root.white
        property bool roundedLeft: false
        property bool roundedRight: false
        font.pixelSize: 14
        font.bold: true
        contentItem: Text {
            text: parent.text
            color: parent.textColor
            font: parent.font
            fontSizeMode: Text.Fit
            minimumPixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: RoundedCorners {
            radiusSize: 4
            color: parent.down ? Qt.darker(parent.base, 1.15) : parent.base
            topLeft: parent.roundedLeft
            bottomLeft: parent.roundedLeft
            topRight: parent.roundedRight
            bottomRight: parent.roundedRight
        }
    }

    component MeasurementField: TextField {
        objectName: "measurement-text-field text-field"
        selectByMouse: true
        horizontalAlignment: TextInput.AlignRight
        verticalAlignment: TextInput.AlignVCenter
        color: root.ink
        font.pixelSize: 14
        padding: 4 * root.sy
        leftPadding: 6 * root.sx
        rightPadding: 7 * root.sx
        background: Rectangle {
            radius: 4
            color: root.white
            border.color: "#CDCDCD"
            border.width: 1
        }
    }

    component StyledCombo: ComboBox {
        id: comboControl
        property var options: []
        property string valueText: ""
        property bool twoLineItems: false
        objectName: "combo-box-base white-combo-box"
        model: options
        font.pixelSize: 12
        font.bold: true
        leftPadding: 8 * root.sx
        rightPadding: 27 * root.sx
        displayText: valueText.length > 0 ? valueText : currentText
        indicator: VectorIcon {
            x: parent.width - 18 * root.sx
            y: (parent.height - height) / 2
            width: 10 * root.sx
            height: 10 * root.sy
            iconName: "caret-down"
        }
        contentItem: Text {
            leftPadding: comboControl.leftPadding
            rightPadding: comboControl.rightPadding
            text: comboControl.displayText
            color: root.ink
            font: comboControl.font
            fontSizeMode: Text.Fit
            minimumPixelSize: 9
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            maximumLineCount: comboControl.twoLineItems ? 2 : 1
            lineHeight: comboControl.twoLineItems ? 0.88 : 1.0
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 7
            color: root.white
            border.color: root.ink
            border.width: 1
        }
        popup: Popup {
            y: comboControl.height
            width: comboControl.width
            implicitHeight: Math.min(comboList.contentHeight + 2, 168 * root.sy)
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            contentItem: ListView {
                id: comboList
                clip: true
                implicitHeight: contentHeight
                model: comboControl.popup.visible ? comboControl.delegateModel : null
                currentIndex: comboControl.highlightedIndex >= 0
                        ? comboControl.highlightedIndex : comboControl.currentIndex
            }
            background: Rectangle {
                color: root.white
                border.color: root.ink
                border.width: 1
                radius: 4
            }
        }
        delegate: Component {
            ItemDelegate {
                width: comboControl.width
                height: (comboControl.twoLineItems ? 42 : 32) * root.sy
                highlighted: comboControl.highlightedIndex === index
                contentItem: Text {
                    text: modelData
                    color: root.ink
                    font.pixelSize: 12
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 7 * root.sx
                    rightPadding: 7 * root.sx
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    maximumLineCount: comboControl.twoLineItems ? 2 : 1
                    lineHeight: comboControl.twoLineItems ? 0.9 : 1.0
                }
                background: Rectangle { color: highlighted ? "#D8D8D8" : root.white }
            }
        }
    }

    component ToolIconButton: Button {
        property string iconName: "pen"
        property color base: root.white
        property color textColor: root.ink
        property color borderColor: root.ink
        contentItem: Item {
            VectorIcon {
                anchors.centerIn: parent
                width: 14 * root.sx
                height: 14 * root.sy
                iconName: parent.parent.iconName
            }
        }
        background: Rectangle {
            radius: 4
            color: parent.down ? Qt.darker(parent.base, 1.05) : parent.base
            border.color: parent.borderColor
            border.width: 1
        }
    }

    component VectorIcon: Image {
        property string iconName: "info-circle"
        source: iconName === "pen" ? "icons/fa-pen.svg"
                : (iconName === "trash" ? "icons/fa-trash.svg"
                   : (iconName === "caret-down" ? "icons/fa-caret-down.svg"
                      : "icons/fa-info-circle.svg"))
        sourceSize.width: Math.max(1, width)
        sourceSize.height: Math.max(1, height)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }

    component Separator: Rectangle {
        height: Math.max(1, root.sy)
        color: root.midGrey
    }

    component RoundedCorners: Rectangle {
        property real radiusSize: 7
        property bool topLeft: false
        property bool topRight: false
        property bool bottomLeft: false
        property bool bottomRight: false
        radius: radiusSize
        Rectangle { visible: !topLeft; x: 0; y: 0; width: parent.radiusSize; height: parent.radiusSize; color: parent.color }
        Rectangle { visible: !topRight; x: parent.width - parent.radiusSize; y: 0; width: parent.radiusSize; height: parent.radiusSize; color: parent.color }
        Rectangle { visible: !bottomLeft; x: 0; y: parent.height - parent.radiusSize; width: parent.radiusSize; height: parent.radiusSize; color: parent.color }
        Rectangle { visible: !bottomRight; x: parent.width - parent.radiusSize; y: parent.height - parent.radiusSize; width: parent.radiusSize; height: parent.radiusSize; color: parent.color }
    }
}
