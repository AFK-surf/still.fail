import UIKit

extension UIViewController {
    /// Let UIKit render the navigation bar's native soft scroll-edge effect.
    /// Register explicitly because these scroll views are embedded in SwiftUI.
    func useSystemHeaderEffect(for scrollView: UIScrollView) {
        scrollView.topEdgeEffect.style = .soft
        scrollView.topEdgeEffect.isHidden = false
        setContentScrollView(scrollView, for: .top)
    }
}
