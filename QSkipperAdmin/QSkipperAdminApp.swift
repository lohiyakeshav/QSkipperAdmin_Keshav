//
//  QSkipperAdminApp.swift
//  QSkipperAdmin
//
//  Created by Keshav Lohiya on 19/05/25.
//

import SwiftUI

@main
struct QSkipperAdminApp: App {
    // Create services that will be shared across the app
    @StateObject private var authService = AuthService()
    @StateObject private var dataController = DataController.shared
    @StateObject private var productService = ProductService()
    
    init() {
        // Configure logging
        DebugLogger.shared.enableLogging = true
        
        // Clear any default or hardcoded restaurant data
        clearDefaultRestaurantData()
    }
    
    private func clearDefaultRestaurantData() {
        // Check if user is logged in
        if let userId = UserDefaults.standard.string(forKey: "qskipper_user_id"), !userId.isEmpty {
            // User is logged in, don't clear data
            DebugLogger.shared.log("User is logged in with ID: \(userId), keeping data", category: .auth)
            return
        }
        
        // Not logged in, clear potential default data
        DebugLogger.shared.log("No user logged in, clearing any potential default restaurant data", category: .auth)
        
        // Clear all restaurant-related data
        UserDefaults.standard.removeObject(forKey: "userData")
        UserDefaults.standard.removeObject(forKey: "restaurantData")
        UserDefaults.standard.removeObject(forKey: "restaurant_id")
        UserDefaults.standard.removeObject(forKey: "restaurant_data")
        UserDefaults.standard.removeObject(forKey: "restaurant_raw_data")
        UserDefaults.standard.removeObject(forKey: "is_restaurant_registered")
        UserDefaults.standard.synchronize()
        
        // Reset DataController's restaurant data
        DataController.shared.clearData()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(dataController)
                .environmentObject(productService)
                // Improve padding on iPad
                .modifier(DeviceAdaptiveModifier())
        }
    }
}

// Make DeviceAdaptiveModifier public so it can be used by other parts of the app
public struct DeviceAdaptiveModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    public func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Special handling for iPad
            content
                .font(.system(size: UIFont.preferredFont(forTextStyle: .body).pointSize * 1.1))
                .environment(\.defaultMinListRowHeight, 56)
        } else {
            // Default for iPhone
            content
        }
    }
}

struct LoginViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        DebugLogger.shared.log("Creating LoginViewController", category: .navigation)
        let loginVC = LoginViewController()
        let navigationController = UINavigationController(rootViewController: loginVC)
        navigationController.isNavigationBarHidden = true
        
        // Set presentation style for better iPad layout
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Create a visually appealing iPad login experience
            loginVC.view.backgroundColor = UIColor(AppColors.backgroundWhite)
            
            // Use form sheet for better iPad experience if shown modally
            navigationController.modalPresentationStyle = .formSheet
        }
        
        return navigationController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Nothing to update
    }
}

struct RegisterViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        DebugLogger.shared.log("Creating RegisterViewController", category: .navigation)
        let registerVC = RegisterViewController()
        let navigationController = UINavigationController(rootViewController: registerVC)
        navigationController.isNavigationBarHidden = true
        
        // Set presentation style for better iPad layout
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Create a visually appealing iPad register experience
            registerVC.view.backgroundColor = UIColor(AppColors.backgroundWhite)
        }
        
        return navigationController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Nothing to update
    }
}

struct RootSplitViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        DebugLogger.shared.log("Creating RootSplitViewController", category: .navigation)
        
        // Fix: Initialize with the proper style
        let splitVC: RootSplitViewController
        
        if #available(iOS 14.0, *) {
            splitVC = RootSplitViewController(style: .doubleColumn)
        } else {
            // For iOS 13 and earlier, use the default constructor
            splitVC = RootSplitViewController()
        }
        
        // Configure for iPad display
        if UIDevice.current.userInterfaceIdiom == .pad {
            splitVC.preferredDisplayMode = .oneBesideSecondary
            
            if #available(iOS 15.0, *) {
                // Better use of iPad screen real estate
                splitVC.preferredSplitBehavior = .tile
                
                // Ensure we have appropriate column widths
                splitVC.preferredPrimaryColumnWidth = 320
                splitVC.minimumPrimaryColumnWidth = 280
                splitVC.maximumPrimaryColumnWidth = 380
            }
            
            // Always show the split view toggle in landscape
            splitVC.displayModeButtonVisibility = .always
            
            // Allow swipe gesture to reveal sidebar
            splitVC.presentsWithGesture = true
        }
        
        return splitVC
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Nothing to update
    }
}
