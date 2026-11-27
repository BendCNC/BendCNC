import QtQuick
import QtTest

Item {
    id: root
    width: 320
    height: 240

    TestCase {
        name: "DataStorePersistenceTests"
        when: windowShown

        function createStore(files) {
            let fakeIo = {
                storageFilePath: function(fileName) { return "persistent/current/" + fileName },
                read: function(url) {
                    return Object.prototype.hasOwnProperty.call(files, url) ? files[url] : null
                }
            }
            let component = Qt.createComponent("../qml/DataStore.qml")
            verify(component.status === Component.Ready, component.errorString())
            let store = component.createObject(root, { storageIoOverride: fakeIo })
            verify(!!store)
            store.reload()
            return store
        }

        function test_primaryPersistentProgramsOverrideBundledDefaults() {
            let files = {
                "persistent/current/programs.json": JSON.stringify([{
                    name: "Restart Persistent CAD",
                    bends: [{ seq: 1 }],
                    cadPreviewJson: "{\"topologySchemaVersion\":5}"
                }])
            }
            let store = createStore(files)
            compare(store.programs.length, 1)
            compare(store.programs[0].name, "Restart Persistent CAD")
            verify(store.programs[0].cadPreviewJson.length > 0)
            store.destroy()
        }

        function test_corruptPrimaryRecoversFromBackup() {
            let files = {
                "persistent/current/programs.json": "{not-json",
                "persistent/current/programs.json.bak": JSON.stringify([{
                    name: "Backup CAD",
                    bends: []
                }])
            }
            let store = createStore(files)
            compare(store.programs.length, 1)
            compare(store.programs[0].name, "Backup CAD")
            store.destroy()
        }
    }
}