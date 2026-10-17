package fail.still.rn.ui

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class StillfailUiModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("StillfailUi")
    View(SmoothView::class) {
      Prop("radii") { view: SmoothView, radii: List<Double> -> view.radii = FloatArray(4) { (radii.getOrNull(it) ?: radii.firstOrNull() ?: 0.0).toFloat() } }
      Prop("amount") { view: SmoothView, amount: Double -> view.amount = amount.toFloat() }
      Prop("strokeWidth") { view: SmoothView, width: Double -> view.strokeWidth = width.toFloat() }
      Prop("strokeColor") { view: SmoothView, color: Int? -> view.strokeColor = color ?: 0 }
    }
  }
}
