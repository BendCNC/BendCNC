#include <QtQuickTest/quicktest.h>
#include <QtQml/qqml.h>

#include "NativeRunRenderer.h"
#if defined(BENDCNC_HAS_CANVAS_PAINTER)
#include "CanvasPainterRunRenderer.h"
#endif

namespace {
const int nativeRunRendererTypeId = qmlRegisterType<NativeRunRenderer>(
	"BendCNCPrototype", 1, 0, "NativeRunRenderer");
#if defined(BENDCNC_HAS_CANVAS_PAINTER)
const int canvasPainterRunRendererTypeId = qmlRegisterType<CanvasPainterRunItem>(
    "BendCNCPrototype", 1, 0, "CanvasPainterRunRenderer");
#endif
}

QUICK_TEST_MAIN(sheetmetal)