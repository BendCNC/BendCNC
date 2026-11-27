import QtQuick
import QtTest
import "../qml/core/sheetmetal/RigidTransform3D.js" as Rigid

Item {
    id: root
    width: 320
    height: 240

    TestCase {
        name: "RigidTransform3DTests"
        when: windowShown

        function close(actual, expected) {
            return Math.abs(actual - expected) < 1.0e-9
        }

        function test_identityPreservesPointAndVector() {
            let transform = Rigid.identity()
            let point = Rigid.transformPoint(transform, Rigid.v(1.25, -2.5, 3.75))
            let vector = Rigid.transformVector(transform, Rigid.v(-4, 5, -6))

            verify(close(point.x, 1.25))
            verify(close(point.y, -2.5))
            verify(close(point.z, 3.75))
            verify(close(vector.x, -4))
            verify(close(vector.y, 5))
            verify(close(vector.z, -6))
        }

        function test_rotationKeepsHingeFixedAndPreservesDistance() {
            let start = Rigid.v(1, 0, 0)
            let end = Rigid.v(1, 2, 0)
            let transform = Rigid.rotationAboutLine(start, end, Math.PI / 2)
            let point = Rigid.transformPoint(transform, Rigid.v(2, 1, 0))
            let fixedStart = Rigid.transformPoint(transform, start)
            let fixedEnd = Rigid.transformPoint(transform, end)

            verify(close(point.x, 1))
            verify(close(point.y, 1))
            verify(close(point.z, -1))
            verify(close(fixedStart.x, start.x))
            verify(close(fixedStart.y, start.y))
            verify(close(fixedStart.z, start.z))
            verify(close(fixedEnd.x, end.x))
            verify(close(fixedEnd.y, end.y))
            verify(close(fixedEnd.z, end.z))
            verify(close(Rigid.length(Rigid.sub(point, fixedStart)), Math.sqrt(2)))
        }

        function test_multiplyComposesParentAndChildRotations() {
            let aroundX = Rigid.rotationAboutLine(Rigid.v(0, 0, 0), Rigid.v(1, 0, 0), Math.PI / 2)
            let aroundY = Rigid.rotationAboutLine(Rigid.v(0, 0, 0), Rigid.v(0, 1, 0), Math.PI / 2)
            let composed = Rigid.multiply(aroundY, aroundX)
            let point = Rigid.transformPoint(composed, Rigid.v(0, 1, 0))

            verify(close(point.x, 1))
            verify(close(point.y, 0))
            verify(close(point.z, 0))
        }

        function test_degenerateAxisIsSafeIdentity() {
            let origin = Rigid.v(2, 3, 4)
            let transform = Rigid.rotationAboutLine(origin, origin, Math.PI / 3)
            let point = Rigid.transformPoint(transform, Rigid.v(5, 6, 7))

            verify(close(point.x, 5))
            verify(close(point.y, 6))
            verify(close(point.z, 7))
        }
    }
}