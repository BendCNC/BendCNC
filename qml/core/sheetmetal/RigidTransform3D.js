.pragma library

function v(x, y, z) { return { x: x, y: y, z: z }; }
function add(a, b) { return v(a.x + b.x, a.y + b.y, a.z + b.z); }
function sub(a, b) { return v(a.x - b.x, a.y - b.y, a.z - b.z); }
function mul(a, scalar) { return v(a.x * scalar, a.y * scalar, a.z * scalar); }
function dot(a, b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
function cross(a, b) { return v(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x); }
function length(a) { return Math.sqrt(dot(a, a)); }
function normalize(a) {
    var len = length(a);
    return len > 1e-9 ? mul(a, 1.0 / len) : v(0, 0, 0);
}
function from2(point) { return v(Number(point && point.x_in || 0), Number(point && point.y_in || 0), 0); }
function to2(point) { return { x_in: Number(point.x.toFixed(4)), y_in: Number(point.y.toFixed(4)) }; }

function identity() {
    return { m: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1] };
}

function multiply(left, right) {
    var result = [];
    for (var row = 0; row < 4; row++) {
        for (var col = 0; col < 4; col++) {
            var value = 0;
            for (var k = 0; k < 4; k++)
                value += left.m[row * 4 + k] * right.m[k * 4 + col];
            result[row * 4 + col] = value;
        }
    }
    return { m: result };
}

function transformPoint(matrix, point) {
    var x = point.x, y = point.y, z = point.z;
    return v(
        matrix.m[0] * x + matrix.m[1] * y + matrix.m[2] * z + matrix.m[3],
        matrix.m[4] * x + matrix.m[5] * y + matrix.m[6] * z + matrix.m[7],
        matrix.m[8] * x + matrix.m[9] * y + matrix.m[10] * z + matrix.m[11]);
}

function transformVector(matrix, vector) {
    return v(
        matrix.m[0] * vector.x + matrix.m[1] * vector.y + matrix.m[2] * vector.z,
        matrix.m[4] * vector.x + matrix.m[5] * vector.y + matrix.m[6] * vector.z,
        matrix.m[8] * vector.x + matrix.m[9] * vector.y + matrix.m[10] * vector.z);
}

function rotationAboutLine(start, end, angleRadians) {
    var axis = normalize(sub(end, start));
    if (length(axis) <= 1e-9)
        return identity();
    var c = Math.cos(angleRadians);
    var s = Math.sin(angleRadians);
    var t = 1 - c;
    var x = axis.x, y = axis.y, z = axis.z;
    var r00 = t*x*x + c, r01 = t*x*y - s*z, r02 = t*x*z + s*y;
    var r10 = t*x*y + s*z, r11 = t*y*y + c, r12 = t*y*z - s*x;
    var r20 = t*x*z - s*y, r21 = t*y*z + s*x, r22 = t*z*z + c;
    var translated = v(
        start.x - (r00 * start.x + r01 * start.y + r02 * start.z),
        start.y - (r10 * start.x + r11 * start.y + r12 * start.z),
        start.z - (r20 * start.x + r21 * start.y + r22 * start.z));
    return { m: [r00,r01,r02,translated.x, r10,r11,r12,translated.y, r20,r21,r22,translated.z, 0,0,0,1] };
}

function rotateAroundLocalHinge(edge, angleRadians) {
    return rotationAboutLine(from2(edge.hingeStart), from2(edge.hingeEnd), angleRadians);
}

function basisDirection(start, end) {
    return normalize(sub(end, start));
}
