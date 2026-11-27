import QtQuick

QtObject {
    readonly property int columnLeftWidth: 864
    readonly property int columnLeftHeight: 668
    readonly property int tabHeaderHeight: 30
    readonly property int contentTopOverlap: 7
    // Tab INDEX is identity (--tab=N, hardcoded 4 = MANUAL, 5 = CAD): new tabs
    // are appended. tabOrder is only the left-to-right display order.
    readonly property var tabLabels: ["RUN", "CREATE BEND", "TOOLS", "BACK GAUGE", "MANUAL", "CAD", "SETTINGS", "PROGRAMS"]
    readonly property var tabWidths: [52, 118, 70, 113, 82, 50, 91, 98]
    readonly property var tabOrder: [0, 7, 1, 2, 3, 4, 5, 6]

    readonly property int standardMargin: 7
    readonly property int headerHeight: 37
    readonly property int controlHeight: 35
    readonly property int compactControlHeight: 31
    readonly property int bodyInset: 8
    readonly property int panelRadius: 7
    readonly property int smallRadius: 4

    readonly property int columnRightWidth: 462
    readonly property int columnRightGap: 7
    readonly property int columnRightPanelTopHeight: 35
    readonly property int columnRightRamDroHeight: 246
    readonly property int columnRightLedHeight: 81
    readonly property int columnRightJogHeight: 59
    readonly property int columnRightUserHeaderHeight: 21

    readonly property var cadPanelHeights: [74, 206, 282, 48]
    readonly property int cadPanelGap: 5
    readonly property int cadImportButtonWidth: 380
    readonly property int cadPartLabelWidth: 105
    readonly property int cadPartValueWidth: 720
    readonly property int cadProgramFieldHeight: 28
    readonly property int cadGenerateSpacing: 5
    readonly property var cadTableColumns: [
        ["Bend", 40], ["Mode", 56], ["Angle", 56], ["Width", 64], ["Ton", 70], ["V-Die", 64],
        ["Dir", 42], ["Ref", 50], ["Setup", 56], ["Punch", 60], ["Change", 62], ["BG Pos", 70], ["BG R", 68], ["Status", 66]
    ]

    readonly property int ramDroHeaderHeight: 33
    readonly property int ramDroBodyGap: 7
    readonly property int ramDroLoadPanelWidth: 60
    readonly property int ramDroLoadBarHeight: 110
    readonly property int ramDroMainAxisHeight: 84
    readonly property int ramDroSecondaryAxisHeight: 43
    readonly property int ramDroSmallPanelHeight: 56
    readonly property int ramDroMainValueWidth: 200
    readonly property int ramDroMainValueFont: 42
    readonly property int ramDroAxisTitleFont: 11
    readonly property int ramDroAxisValueFont: 13
    readonly property int ramDroAxisUnitFont: 11
    readonly property int ramDroHeaderFont: 14
}