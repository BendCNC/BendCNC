// test_SheetMetalGeometry.qml — self-contained parity test for the ported
// sheetmetal geometry primitives + bend allowance math. No external data needed;
// validates exact numeric identities against hand-computed Java-equivalent values.
//
// Run:
//   C:\Qt\6.10.1\mingw_64\bin\qml.exe test_SheetMetalGeometry.qml

import QtQuick 2.15
import "SheetMetalGeometry.js" as G
import "BendAllowanceCalculator.js" as BA

Item {
    width: 100; height: 100

    function approx(a, b, tol) { return Math.abs(a - b) <= (tol === undefined ? 1e-9 : tol); }

    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, cond) {
            total++;
            if (cond) { pass++; console.log("PASS  " + name); }
            else console.log("FAIL  " + name);
        }

        // Vector2
        var v = G.vec2(3, 4);
        check("vecLength 3,4 = 5", approx(G.vecLength(v), 5));
        var n = G.vecNormalize(v);
        check("vecNormalize unit", approx(G.vecLength(n), 1));
        check("vecDot", approx(G.vecDot(G.vec2(1, 2), G.vec2(3, 4)), 11));
        check("vecCross", approx(G.vecCross(G.vec2(1, 0), G.vec2(0, 1)), 1));
        check("vecScale", approx(G.vecScale(v, 2).x, 6) && approx(G.vecScale(v, 2).y, 8));

        // Point2
        var p = G.point2(1, 1);
        check("pointPlus", approx(G.pointPlus(p, G.vec2(2, 3)).x, 3));
        check("pointMinus -> vec", approx(G.pointMinus(G.point2(4, 6), p).x, 3));
        check("pointDistanceTo", approx(G.pointDistanceTo(G.point2(0, 0), G.point2(3, 4)), 5));

        // Transform2D — rotation 90deg maps (1,0)->(0,1)
        var r = G.transformRotation(Math.PI / 2);
        var rp = G.transformApply(r, G.point2(1, 0));
        check("rotation90 x", approx(rp.x, 0));
        check("rotation90 y", approx(rp.y, 1));
        // translation
        var t = G.transformTranslation(5, -2);
        var tp = G.transformApply(t, G.point2(1, 1));
        check("translation", approx(tp.x, 6) && approx(tp.y, -1));
        // identity
        var ip = G.transformApply(G.transformIdentity(), G.point2(7, 9));
        check("identity", approx(ip.x, 7) && approx(ip.y, 9));
        // multiply: T(translate)∘R(rotate90) applied to (1,0) -> rotate then translate
        var comp = G.transformMultiply(t, r);
        var cp = G.transformApply(comp, G.point2(1, 0));
        check("multiply order", approx(cp.x, 5) && approx(cp.y, -1));
        // alignSegment: maps source seg [(0,0)->(1,0)] onto target [(2,2)->(2,3)] (90deg)
        var al = G.transformAlignSegment(G.point2(0, 0), G.point2(1, 0), G.point2(2, 2), G.point2(2, 3));
        var as = G.transformApply(al, G.point2(0, 0));
        var ae = G.transformApply(al, G.point2(1, 0));
        check("alignSegment start", approx(as.x, 2) && approx(as.y, 2));
        check("alignSegment end", approx(ae.x, 2) && approx(ae.y, 3));

        // Frame2 — local (1,0)->origin+u; world of (0,1)->origin+v
        var f = G.frame2(G.point2(10, 10), G.vec2(1, 0), G.vec2(0, 1));
        var fw = G.frameToWorld(f, G.point2(2, 3));
        check("frameToWorld", approx(fw.x, 12) && approx(fw.y, 13));

        // BendDirection
        check("dir UP sign", G.bendDirectionSign(G.bendDirectionFromText("up")) === 1);
        check("dir NEG sign", G.bendDirectionSign(G.bendDirectionFromText("negative")) === -1);
        check("dir blank", G.bendDirectionFromText("") === "UNKNOWN");

        // BendAllowanceCalculator — allowance = (ir + k*t)*rad(angle)
        var calc = BA.ofKFactor(0.33);
        var ir = 0.075, th = 0.0747, ang = 90;
        var expAllow = (ir + 0.33 * th) * (Math.PI / 2);
        check("allowance", approx(calc.allowance(ir, th, ang), expAllow));
        var expSet = Math.tan((Math.PI / 180) * (ang / 2)) * (ir + th);
        check("outsideSetback", approx(calc.outsideSetback(ir, th, ang), expSet));
        check("bendDeduction", approx(calc.bendDeduction(ir, th, ang), 2 * expSet - expAllow));
        check("complementary 90", approx(calc.complementaryAngleDegrees(90), 90));
        check("allowance angle 0", approx(calc.allowance(ir, th, 0), 0));
        check("setback angle 0", approx(calc.outsideSetback(ir, th, 0), 0));

        // Validation: kFactor out of range throws
        var threw = false;
        try { BA.ofKFactor(1.5); } catch (e) { threw = true; }
        check("kFactor>1 throws", threw);
        threw = false;
        try { G.vecNormalize(G.vec2(0, 0)); } catch (e2) { threw = true; }
        check("zero-vec normalize throws", threw);

        console.log("======================================");
        console.log("SheetMetalGeometry parity: " + pass + "/" + total + " checks passed");
        console.log("======================================");
        Qt.callLater(Qt.quit);
    }
}
