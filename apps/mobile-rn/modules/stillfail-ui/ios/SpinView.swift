import ExpoModulesCore
import UIKit

/// A box that turns for ever while `spinning`, once each `period` ms (as the Android SpinView): a Core Animation
/// rotation of its layer, which the render server plays, not Reanimated each frame.
final class SpinView: ExpoView {
  var spinning = false { didSet { if spinning != oldValue { update() } } }
  var period: Double = 1200 { didSet { if period != oldValue && spinning { layer.removeAnimation(forKey: "spin"); update() } } }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    update()
  }

  private func update() {
    if spinning && window != nil {
      guard layer.animation(forKey: "spin") == nil else { return }
      let turn = CABasicAnimation(keyPath: "transform.rotation.z")
      turn.fromValue = 0
      turn.toValue = Double.pi * 2
      turn.duration = period / 1000
      turn.repeatCount = .infinity
      turn.isRemovedOnCompletion = false
      layer.add(turn, forKey: "spin")
    } else {
      layer.removeAnimation(forKey: "spin")
    }
  }
}

public final class StillfailSpinModule: Module {
  public func definition() -> ModuleDefinition {
    Name("StillfailSpin")
    View(SpinView.self) {
      Prop("spinning") { (view: SpinView, spinning: Bool) in view.spinning = spinning }
      Prop("period") { (view: SpinView, period: Double) in view.period = period }
    }
  }
}
