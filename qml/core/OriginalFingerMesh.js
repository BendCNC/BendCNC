.pragma library
// Exact STEP tessellation of the ORIGINAL back-gauge finger (inches, LEFT finger:
// x = hinge 0 .. tip 4.0, y = height, z = width about station centre). The data
// lives in the tooling assets (assets/Fingers/Original Finger Mesh.json, shipped
// as .json.bct in public builds) and is loaded once through the caller's loadText.
var positions = null
var triangles = null
var attempted = false

function ensure(loadText) {
    if (positions)
        return true
    if (attempted)
        return false
    attempted = true
    try {
        var mesh = JSON.parse(loadText("../../assets/Fingers/Original Finger Mesh.json"))
        if (mesh && mesh.positions && mesh.triangles) {
            positions = mesh.positions
            triangles = mesh.triangles
        }
    } catch (error) {}
    return positions !== null
}
