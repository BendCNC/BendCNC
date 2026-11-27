import QtQuick

Item {
    id: theme
    visible: false

    property string fontMode: "original"

    readonly property string originalFontFamily: firaRegular.name.length > 0 ? firaRegular.name : "Fira Sans"
    readonly property string currentFontFamily: "Segoe UI"
    readonly property string appFontFamily: fontMode === "current" ? currentFontFamily : originalFontFamily
    readonly property string iconFontFamily: "Segoe UI Symbol"

    readonly property color red: "#A82011"
    readonly property color blue: "#2D83B2"
    readonly property color green: "#59A60C"
    readonly property color orange: "orange"
    readonly property color ink: "#232323"
    readonly property color white: "#FFFFFF"
    readonly property color charcoal: "#2B2C2B"
    readonly property color grey: "#A8A8A8"
    readonly property color lightGrey: "#E0E0E0"
    readonly property color paper: "#F5F5F5"
    readonly property color purple: "#800080"
    readonly property color cyanDark: "#009E9E"
    readonly property color black: "#000000"

    readonly property int spaceHairline: 1
    readonly property int spaceSmall: 4
    readonly property int spaceStandard: 7
    readonly property int spaceMedium: 10
    readonly property int spaceLarge: 15
    readonly property int runLeftIndent: 49
    readonly property int radiusStandard: 7
    readonly property int radiusSmall: 4

    readonly property var fontSizes: [8, 10, 11, 12, 13, 14, 16, 17, 18, 20, 22, 26, 36, 42]

    // Fonts are bundled into the qrc under qml/fonts/ (copied from
    // src/main/resources/fonts). The runtime resolves these relative to
    // qrc:/BendCNCPrototype/qml/Theme.qml. Note the on-disk typo
    // "fire-sans-italic.ttf" is preserved to match the original asset filename.
    FontLoader { id: firaRegular; source: "fonts/fira-sans-regular.ttf" }
    FontLoader { source: "fonts/fira-sans-bold.ttf" }
    FontLoader { source: "fonts/fira-sans-light.ttf" }
    FontLoader { source: "fonts/fire-sans-italic.ttf" }
}
