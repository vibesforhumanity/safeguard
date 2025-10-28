import Foundation
import UIKit

// MARK: - Overlay Blocking
class AggressiveBlockingManager {
    private var isBlockingActive = false
    private var overlayWindow: UIWindow?
    
    func activateAggressiveBlocking() {
        print("🚨 Activating overlay blocking")
        isBlockingActive = true
        
        // Only use overlay-based blocking - less aggressive approach
        createSystemOverlay()
    }
    
    func deactivateAggressiveBlocking() {
        print("✅ Deactivating overlay blocking")
        isBlockingActive = false
        
        // Remove overlay
        overlayWindow?.isHidden = true
        overlayWindow = nil
    }
    
    private func createSystemOverlay() {
        // Create a system-level overlay window
        guard overlayWindow == nil else { return }
        
        print("🖥️ Creating system-level blocking overlay")
        
        overlayWindow = UIWindow(frame: UIScreen.main.bounds)
        overlayWindow?.windowLevel = UIWindow.Level.alert + 2000 // Highest possible level
        overlayWindow?.backgroundColor = UIColor.red.withAlphaComponent(0.9)
        overlayWindow?.isHidden = false
        
        // Create blocking view controller
        let blockingVC = UIViewController()
        blockingVC.view.backgroundColor = UIColor.black.withAlphaComponent(0.95)
        
        // Add large warning text
        let warningLabel = UILabel()
        warningLabel.text = "🚨\nDEVICE RESTRICTED\n\nExit current app and\nreturn to home screen"
        warningLabel.textColor = .white
        warningLabel.font = .boldSystemFont(ofSize: 24)
        warningLabel.numberOfLines = 0
        warningLabel.textAlignment = .center
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        
        blockingVC.view.addSubview(warningLabel)
        NSLayoutConstraint.activate([
            warningLabel.centerXAnchor.constraint(equalTo: blockingVC.view.centerXAnchor),
            warningLabel.centerYAnchor.constraint(equalTo: blockingVC.view.centerYAnchor)
        ])
        
        overlayWindow?.rootViewController = blockingVC
        overlayWindow?.makeKeyAndVisible()
        
        // Make overlay flash to get attention
        startOverlayFlashing()
    }
    
    private func startOverlayFlashing() {
        guard let overlay = overlayWindow else { return }
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            guard self.isBlockingActive else {
                timer.invalidate()
                return
            }
            
            UIView.animate(withDuration: 0.5, animations: {
                overlay.alpha = overlay.alpha == 1.0 ? 0.7 : 1.0
            })
        }
    }
}