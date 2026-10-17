package fail.still.rn.ui

import android.graphics.Color
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class StillfailUiModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("StillfailUi")
    View(SmoothView::class) {
      Prop("radii") { view: SmoothView, radii: List<Double> -> view.radii = FloatArray(4) { (radii.getOrNull(it) ?: radii.firstOrNull() ?: 0.0).toFloat() } }
      Prop("amount") { view: SmoothView, amount: Double -> view.amount = amount.toFloat() }
      Prop("strokeWidth") { view: SmoothView, width: Double -> view.strokeWidth = width.toFloat() }
      // As a Color (Expo reads a CSS colour string into it): taken as an Int it came out black.
      Prop("strokeColor") { view: SmoothView, color: Color? -> view.strokeColor = color?.toArgb() ?: 0 }
    }
  }
}
