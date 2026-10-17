import ExpoModulesCore

public final class StillfailUiModule: Module {
  public func definition() -> ModuleDefinition {
    Name("StillfailUi")
    View(SmoothView.self) {
      Prop("radii") { (view: SmoothView, radii: [Double]) in
        view.radii = (0..<4).map { CGFloat(radii.indices.contains($0) ? radii[$0] : radii.first ?? 0) }
      }
      Prop("amount") { (view: SmoothView, amount: Double) in view.amount = CGFloat(amount) }
      Prop("strokeWidth") { (view: SmoothView, width: Double) in view.strokeWidth = CGFloat(width) }
      Prop("strokeColor") { (view: SmoothView, color: UIColor?) in view.strokeColor = color }
    }
  }
}
