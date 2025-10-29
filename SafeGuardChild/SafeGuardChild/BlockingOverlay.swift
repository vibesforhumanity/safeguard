import SwiftUI
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.safeguard.child", category: "CountdownOverlay")

// MARK: - Countdown Timer Overlay
@MainActor
class CountdownOverlayManager: ObservableObject {
    private var overlayWindow: UIWindow?
    private var countdownVC: CountdownViewController?
    private var isActive = false
    private var onExpiration: (() -> Void)?

    func showCountdown(minutes: Int, customMessage: String? = nil, onExpiration: (() -> Void)? = nil) {
        self.onExpiration = onExpiration
        logger.info("showCountdown called with \(minutes) minutes, isActive: \(self.isActive)")

        if isActive {
            logger.debug("Updating existing countdown")
            countdownVC?.updateCountdown(minutes: minutes, message: customMessage)
            return
        }

        logger.info("Creating new countdown overlay")

        // Ensure we're on main thread
        guard Thread.isMainThread else {
            logger.error("Not on main thread, dispatching to main")
            DispatchQueue.main.async {
                self.showCountdown(minutes: minutes, customMessage: customMessage)
            }
            return
        }

        // Create a new window for the countdown - use same approach as blocking overlay
        logger.debug("Looking for window scene, connected scenes: \(UIApplication.shared.connectedScenes.count)")

        // Try active scene first, fall back to any scene
        var windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene

        if windowScene == nil {
            logger.warning("No foreground active scene, trying any scene")
            windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        }

        guard let windowScene = windowScene else {
            logger.error("Failed to get window scene")
            return
        }

        logger.debug("Got window scene: \(String(describing: windowScene))")

        overlayWindow = UIWindow(windowScene: windowScene)
        overlayWindow?.frame = windowScene.coordinateSpace.bounds
        overlayWindow?.windowLevel = UIWindow.Level.alert + 1  // Normal overlay level (only visible in SafeGuardChild app)
        overlayWindow?.backgroundColor = .clear

        // Create the countdown view controller
        countdownVC = CountdownViewController(minutes: minutes, message: customMessage, onExpiration: onExpiration)
        overlayWindow?.rootViewController = countdownVC

        overlayWindow?.isHidden = false
        overlayWindow?.makeKeyAndVisible()

        logger.info("Countdown window created - frame: \(String(describing: self.overlayWindow?.frame)), level: \(self.overlayWindow?.windowLevel.rawValue ?? 0)")

        isActive = true
        logger.info("Countdown overlay setup complete - visible only in SafeGuardChild app")
    }

    func hideCountdown() {
        guard isActive else { return }

        logger.info("Hiding countdown overlay")

        overlayWindow?.isHidden = true
        overlayWindow = nil
        countdownVC = nil
        isActive = false
    }
}

// MARK: - Countdown View Controller
class CountdownViewController: UIViewController {
    private var endTime: Date
    private var timer: Timer?
    private var containerView: UIView!
    private var timerLabel: UILabel!
    private var messageLabel: UILabel!
    private let customMessage: String?
    private let onExpiration: (() -> Void)?
    private var hasExpired = false

    init(minutes: Int, message: String?, onExpiration: (() -> Void)?) {
        self.endTime = Date().addingTimeInterval(TimeInterval(minutes * 60))
        self.customMessage = message
        self.onExpiration = onExpiration
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("CountdownViewController.viewDidLoad called")
        setupCountdownInterface()
        startTimer()
        logger.debug("CountdownViewController setup complete")
    }

    private func setupCountdownInterface() {
        logger.debug("Setting up countdown interface")
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)

        // Container with rounded corners - centered
        containerView = UIView()
        containerView.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.95)
        containerView.layer.cornerRadius = 20
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.4
        containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        containerView.layer.shadowRadius = 8
        containerView.translatesAutoresizingMaskIntoConstraints = false

        // Timer icon
        let iconLabel = UILabel()
        iconLabel.text = "⏰"
        iconLabel.font = .systemFont(ofSize: 60)
        iconLabel.textAlignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        // Timer text
        timerLabel = UILabel()
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 64, weight: .bold)
        timerLabel.textColor = .white
        timerLabel.textAlignment = .center
        timerLabel.translatesAutoresizingMaskIntoConstraints = false

        // Message label
        messageLabel = UILabel()
        messageLabel.text = customMessage ?? "Until shutdown"
        messageLabel.font = .systemFont(ofSize: 20, weight: .medium)
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(iconLabel)
        containerView.addSubview(timerLabel)
        containerView.addSubview(messageLabel)
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            // Center the container
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 280),
            containerView.heightAnchor.constraint(equalToConstant: 280),

            iconLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 30),
            iconLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            timerLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 20),
            timerLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            timerLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            messageLabel.topAnchor.constraint(equalTo: timerLabel.bottomAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -30)
        ])

        // Make view non-interactive so touches pass through to app below
        view.isUserInteractionEnabled = false

        logger.debug("Countdown interface setup complete, container frame: \(String(describing: self.containerView.frame))")
    }

    private func startTimer() {
        logger.debug("Starting countdown timer")
        updateDisplay()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
    }

    private func updateDisplay() {
        let remaining = endTime.timeIntervalSinceNow

        if remaining <= 0 {
            timerLabel.text = "00:00"
            timer?.invalidate()

            // Flash red to indicate time's up
            UIView.animate(withDuration: 0.5, delay: 0, options: [.repeat, .autoreverse]) {
                self.containerView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.95)
            }

            // Trigger expiration callback once
            if !hasExpired {
                hasExpired = true
                logger.info("Countdown expired - triggering onExpiration callback")
                onExpiration?()
            }

            return
        }

        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        timerLabel.text = String(format: "%02d:%02d", minutes, seconds)

        // Change color as time runs out
        if remaining < 60 {
            containerView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.95)
        } else if remaining < 120 {
            containerView.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.95)
        }
    }

    func updateCountdown(minutes: Int, message: String?) {
        endTime = Date().addingTimeInterval(TimeInterval(minutes * 60))
        if let message = message {
            messageLabel.text = message
        }
        containerView.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.95)
        updateDisplay()
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - Full-Screen Blocking Overlay
private let blockingLogger = Logger(subsystem: "com.safeguard.child", category: "BlockingOverlay")

class BlockingOverlayManager: ObservableObject {
    private var overlayWindow: UIWindow?
    private var isActive = false

    func showBlockingOverlay() {
        guard !isActive else { return }

        blockingLogger.info("Showing full-screen blocking overlay")

        // Create a new window that appears over all apps
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            overlayWindow = UIWindow(windowScene: windowScene)
            overlayWindow?.frame = UIScreen.main.bounds
            overlayWindow?.windowLevel = UIWindow.Level.alert + 1000 // Very high priority
            overlayWindow?.backgroundColor = .clear
            overlayWindow?.isHidden = false
        } else {
            blockingLogger.error("Failed to get window scene for blocking overlay")
            return
        }
        
        // Create the blocking view controller
        let blockingVC = BlockingViewController()
        overlayWindow?.rootViewController = blockingVC
        overlayWindow?.makeKeyAndVisible()
        
        isActive = true
        
        // Aggressive measures to maintain overlay
        scheduleOverlayMaintenance()
    }
    
    func hideBlockingOverlay() {
        guard isActive else { return }

        blockingLogger.info("Hiding blocking overlay - restrictions removed")

        overlayWindow?.isHidden = true
        overlayWindow = nil
        isActive = false

        // Cancel maintenance (DispatchQueue tasks auto-cancel when isActive = false)
    }

    private func scheduleOverlayMaintenance() {
        // Reshow overlay every 2 seconds in case user tries to dismiss it
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.maintainOverlay()
        }
    }

    private func maintainOverlay() {
        guard isActive else { return }

        // Ensure overlay stays visible
        overlayWindow?.makeKeyAndVisible()
        overlayWindow?.windowLevel = UIWindow.Level.alert + 1000

        blockingLogger.debug("Maintaining blocking overlay")
        scheduleOverlayMaintenance()
    }
}

// MARK: - Blocking View Controller
class BlockingViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBlockingInterface()
    }
    
    private func setupBlockingInterface() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.95)
        
        let containerView = UIView()
        containerView.backgroundColor = .systemRed
        containerView.layer.cornerRadius = 20
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let iconLabel = UILabel()
        iconLabel.text = "🚨"
        iconLabel.font = .systemFont(ofSize: 60)
        iconLabel.textAlignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = "Device Restricted"
        titleLabel.font = .boldSystemFont(ofSize: 28)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let messageLabel = UILabel()
        messageLabel.text = "All apps are currently blocked.\nPlease return to the home screen."
        messageLabel.font = .systemFont(ofSize: 18)
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let homeButton = UIButton(type: .system)
        homeButton.setTitle("Go to Home Screen", for: .normal)
        homeButton.setTitleColor(.white, for: .normal)
        homeButton.backgroundColor = .systemBlue
        homeButton.layer.cornerRadius = 10
        homeButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        homeButton.translatesAutoresizingMaskIntoConstraints = false
        homeButton.addTarget(self, action: #selector(homeButtonTapped), for: .touchUpInside)
        
        containerView.addSubview(iconLabel)
        containerView.addSubview(titleLabel)
        containerView.addSubview(messageLabel)
        containerView.addSubview(homeButton)
        view.addSubview(containerView)
        
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 300),
            containerView.heightAnchor.constraint(equalToConstant: 400),
            
            iconLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 40),
            iconLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            homeButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -40),
            homeButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 40),
            homeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40),
            homeButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Prevent dismissing this view
        isModalInPresentation = true
    }
    
    @objc private func homeButtonTapped() {
        // Attempt to minimize current app and go to home screen
        blockingLogger.debug("Home button tapped in blocking overlay")

        // iOS doesn't allow apps to programmatically go to home screen
        // But we can provide clear guidance
        let alert = UIAlertController(
            title: "Exit Current App",
            message: "Please press the home button or swipe up to return to the home screen. Apps will remain blocked until you do.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Understood", style: .default))
        present(alert, animated: true)
    }
    
    // Prevent user from dismissing this overlay
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Disable swipe gestures and other dismissal methods
        view.isUserInteractionEnabled = true
        navigationController?.navigationBar.isHidden = true
        
        // Make this the key window
        view.window?.makeKey()
    }
}