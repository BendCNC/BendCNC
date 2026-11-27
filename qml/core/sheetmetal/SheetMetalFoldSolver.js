.pragma library

// Finite-radius fold kinematics ported from the "unfold" engine
// (unfold viewer/solver.mjs, engine/import_bcbend.py).
//
// The flat hinge line is the centreline of the developed neutral strip. The
// strip (width = neutral length) rolls around a cylinder of radius Ri + K*t
// and the child panel is attached rigidly at the moving tangent, so bend
// allowance, inside radius, K-factor and thickness all affect the pose.
// Units: inches, radians. Matrices use RigidTransform3D's row-major {m:[16]}.

.import "RigidTransform3D.js" as Rigid

function sinc(x) {
    if (Math.abs(x) < 1e-4) { var x2 = x * x; return 1 - x2 / 6 + x2 * x2 / 120; }
    return Math.sin(x) / x;
}

function cosc(x) {
    if (Math.abs(x) < 1e-4) { var x2 = x * x; return x / 2 - x * x2 / 24 + x * x2 * x2 / 720; }
    return (1 - Math.cos(x)) / x;
}

function clamp01(x) {
    var n = Number(x);
    return isFinite(n) ? Math.max(0, Math.min(1, n)) : 0;
}

// Signed fold about hingeStart -> hingeEnd (right hand). An explicit
// signedSweepDegrees from the exporter wins; otherwise direction x childSide,
// the convention the BendCNC add-in direction export is validated against.
function signedFoldRadians(edge, foldDegrees) {
    var fold = Math.max(0, Math.min(180, Number(foldDegrees)));
    if (!isFinite(fold))
        return 0;
    if (edge.signedSweepDegrees !== undefined && isFinite(Number(edge.signedSweepDegrees)))
        return (Number(edge.signedSweepDegrees) < 0 ? -1 : 1) * fold * Math.PI / 180;
    var direction = String(edge.direction || "UP").toUpperCase() === "DOWN" ? -1 : 1;
    var side = Number(edge.childSideSign || 1) < 0 ? -1 : 1;
    return direction * side * fold * Math.PI / 180;
}

// Per-edge frame (cached on the edge). axis = directed hinge * childSide, so
// transverse points into the child; theta is expressed about that axis.
function edgeFrame(edge) {
    if (edge.__foldFrame)
        return edge.__foldFrame;
    var start = Rigid.from2(edge.hingeStart), end = Rigid.from2(edge.hingeEnd);
    var directed = Rigid.normalize(Rigid.sub(end, start));
    var side = Number(edge.childSideSign || 1) < 0 ? -1 : 1;
    var axis = Rigid.mul(directed, side);
    var frame = {
        start: start,
        directed: directed,
        side: side,
        axis: axis,
        transverse: Rigid.v(-axis.y, axis.x, 0),
        normal: Rigid.v(0, 0, 1),
        radius: Math.max(0, Number(edge.insideRadius_in) || 0),
        thickness: Math.max(0, Number(edge.thickness_in) || 0),
        k: isFinite(Number(edge.kFactor)) ? Math.max(0, Math.min(1, Number(edge.kFactor))) : 0.44
    };
    // Developed strip length at the full fold (Unfold model): constant while
    // forming, so partial angles change curvature, not material length.
    var fold = Number(edge.foldAngleDegrees !== undefined ? edge.foldAngleDegrees
                                                          : 180 - Number(edge.bendAngleDegrees));
    frame.developed = isFinite(fold)
        ? Math.max(0, Math.min(180, fold)) * Math.PI / 180 * (frame.radius + frame.k * frame.thickness)
        : 0;
    edge.__foldFrame = frame;
    return frame;
}

// Bend geometry for a given signed fold about the directed hinge.
function bendAt(edge, signedAboutDirected) {
    var f = edgeFrame(edge);
    var theta = signedAboutDirected * f.side;            // about f.axis
    var neutralLength = f.developed > 1e-9 ? f.developed
                                           : Math.abs(theta) * (f.radius + f.k * f.thickness);
    return {
        frame: f,
        theta: theta,
        neutralLength: neutralLength,
        neutralZ: theta > 0 ? -f.k * f.thickness : -(1 - f.k) * f.thickness,
        origin: Rigid.sub(f.start, Rigid.mul(f.transverse, neutralLength / 2))
    };
}

// Material point of the strip: axial offset, fraction 0..1 across the strip,
// flat z. amount scales the fold (0 flat, 1 full).
function bandPoint(bend, axial, fraction, zFlat, amount) {
    var f = bend.frame;
    var angle = bend.theta * clamp01(amount) * fraction;
    var arc = bend.neutralLength * fraction;
    var c = Math.cos(angle), s = Math.sin(angle);
    var b = arc * sinc(angle) - (zFlat - bend.neutralZ) * s;
    var n = bend.neutralZ + arc * cosc(angle) + (zFlat - bend.neutralZ) * c;
    return Rigid.add(Rigid.add(Rigid.add(bend.origin, Rigid.mul(f.axis, axial)),
                               Rigid.mul(f.transverse, b)), Rigid.mul(f.normal, n));
}

function rotation(axis, theta) {
    var x = axis.x, y = axis.y, z = axis.z;
    var c = Math.cos(theta), s = Math.sin(theta), v = 1 - c;
    return { m: [x*x*v+c, x*y*v-z*s, x*z*v+y*s, 0,
                 y*x*v+z*s, y*y*v+c, y*z*v-x*s, 0,
                 z*x*v-y*s, z*y*v+x*s, z*z*v+c, 0,
                 0, 0, 0, 1] };
}

// Rigid child motion (local, parent frame) for a signed fold about the
// directed hinge. Equivalent to the legacy hinge rotation when Ri = t = 0.
function jointTransform(edge, signedAboutDirected) {
    if (Math.abs(signedAboutDirected) < 1e-12)
        return Rigid.identity();
    var bend = bendAt(edge, signedAboutDirected);
    if (bend.neutralLength <= 1e-9)
        return Rigid.rotateAroundLocalHinge(edge, signedAboutDirected);
    var r = rotation(bend.frame.axis, bend.theta);
    var a = Rigid.add(Rigid.add(bend.origin, Rigid.mul(bend.frame.transverse, bend.neutralLength)),
                      Rigid.mul(bend.frame.normal, bend.neutralZ));
    var e = bandPoint(bend, 0, 1, bend.neutralZ, 1);
    var t = Rigid.sub(e, Rigid.transformPoint(r, a));
    r.m[3] = t.x; r.m[7] = t.y; r.m[11] = t.z;
    return r;
}

// Strip outline (parent frame) for drawing the radius zone: samples of the
// mid-surface across the hinge span.
function bandPolyline(edge, signedAboutDirected, samples) {
    var bend = bendAt(edge, signedAboutDirected);
    var f = bend.frame;
    var end = Rigid.from2(edge.hingeEnd);
    var span = Rigid.dot(Rigid.sub(end, f.start), f.axis);
    var n = Math.max(2, samples || 8);
    var zMid = -f.thickness / 2;
    var near = [], far = [];
    for (var i = 0; i <= n; i++) {
        var fraction = i / n;
        near.push(bandPoint(bend, 0, fraction, zMid, 1));
        far.push(bandPoint(bend, span, fraction, zMid, 1));
    }
    return { near: near, far: far, neutralLength: bend.neutralLength };
}
