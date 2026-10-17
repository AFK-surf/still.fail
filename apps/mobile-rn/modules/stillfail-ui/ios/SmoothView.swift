import ExpoModulesCore
import UIKit

/// A box with still.fail's corners (as the Android SmoothView): what it holds (its own background, set by React
/// Native, included) is clipped to them by its layer's mask, and its line (`stroke`) is drawn along them over what it
/// holds. Radii in points. Unlike Android's outline, a mask clips the layer's own shadow too: a shadow wanted around
/// it goes on a view outside it.
final class SmoothView: ExpoView {
  var radii: [CGFloat] = [0, 0, 0, 0] { didSet { reshape() } }
  var amount: CGFloat = 1 { didSet { reshape() } }
  var strokeWidth: CGFloat = 0 { didSet { restroke() } }
  var strokeColor: UIColor? { didSet { restroke() } }

  private let clip = CAShapeLayer()
  private let line = CAShapeLayer()

  override class var layerClass: AnyClass { SmoothLayer.self }

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    line.fillColor = nil
    // Over what it holds: the subviews' layers are its siblings, at 0.
    line.zPosition = 10_000
    line.isHidden = true
    layer.addSublayer(line)
    (layer as? SmoothLayer)?.shape = clip
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    reshape()
  }

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    restroke()
  }

  private func reshape() {
    let path = smoothPath(bounds, radii[0], radii[1], radii[2], radii[3], amount: amount)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    clip.frame = bounds
    clip.path = path
    line.frame = bounds
    line.path = path
    CATransaction.commit()
  }

  private func restroke() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    // Inside the edge, as a CSS border: the outline stroked twice as wide, its outer half clipped off by the mask.
    line.lineWidth = strokeWidth * 2
    line.strokeColor = strokeColor?.resolvedColor(with: traitCollection).cgColor
    line.isHidden = strokeWidth <= 0 || strokeColor == nil
    CATransaction.commit()
  }
}

/// The view's layer, whose mask is the corners' shape: React Native's view sets its own mask (and takes it off, nil)
/// each time it redoes its layer, after props or layout change; this one stays.
final class SmoothLayer: CALayer {
  var shape: CALayer? {
    didSet { super.mask = shape }
  }

  override var mask: CALayer? {
    get { super.mask }
    set { super.mask = shape ?? newValue }
  }
}
