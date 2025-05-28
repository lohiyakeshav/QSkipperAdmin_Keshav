import SwiftUI
import Combine
import PhotosUI
// Import the UIKitImagePicker
import UIKit

// Alert types enum
enum AlertType: Equatable {
    case message(String)
    case deleteConfirmation
    case none
    
    static func == (lhs: AlertType, rhs: AlertType) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.deleteConfirmation, .deleteConfirmation):
            return true
        case (.message(let lhsMsg), .message(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

struct RestaurantManagementView: View {
    // Environment
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var authService: AuthService
    @StateObject private var restaurantService = RestaurantService()
    
    // State
    @State private var restaurantName: String = ""
    @State private var estimatedTime: String = ""
    @State private var selectedCuisine: String = ""
    @State private var restaurantImage: UIImage? = nil
    @State private var isImagePickerShown = false
    @State private var isRegistered: Bool = true // Default to true, will be updated in onAppear
    
    // Product state
    @State private var productName: String = ""
    @State private var productPrice: String = ""
    @State private var productCategory: String = ""
    @State private var productDescription: String = ""
    @State private var preparationTime: String = "0"
    @State private var productImage: UIImage? = nil
    @State private var isProductImagePickerShown = false
    
    // UI state
    @State private var isSubmitting = false
    @State private var alertType: AlertType = .none
    @State private var alertMessage = ""
    @State private var currentImageSelection: ImageSelectionType = .restaurant
    @State private var selectedTab: SidebarTab = .profile
    
    // Cuisine types for selection
    let cuisineTypes = ["North Indian", "South Indian", "Chinese", "Fast Food", "Drinks & Snacks", "Italian", "Mexican", "Continental"]
    
    enum ImageSelectionType {
        case restaurant
        case product
    }
    
    enum SidebarTab {
        case profile
        case addProduct
        case products
        case statistics
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                restaurantProfileSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(isRegistered ? "Restaurant Profile" : "Register Restaurant")
        .sheet(isPresented: $isImagePickerShown) {
            UIKitImagePicker(selectedImage: $restaurantImage)
        }
        // Handle delete confirmation alert
        .alert("Delete Restaurant", isPresented: Binding<Bool>(
            get: { alertType == .deleteConfirmation },
            set: { if !$0 { alertType = .none } }
        ), actions: {
            Button("Cancel", role: .cancel) {
                alertType = .none
            }
            Button("Yes, Delete Restaurant", role: .destructive) {
                print("Delete confirmed")
                deleteRestaurant()
            }
        }, message: {
            Text("Are you sure you want to delete this restaurant? This action CANNOT be undone and will permanently remove all associated products and orders. Your account will remain but you'll need to register a new restaurant.")
        })
        // Handle message alerts
        .alert("Message", isPresented: Binding<Bool>(
            get: { 
                if case .message(_) = alertType {
                    return true
                }
                return false
            },
            set: { if !$0 { alertType = .none } }
        ), actions: {
            Button("OK", role: .cancel) {
                alertType = .none
            }
        }, message: {
            if case .message(let message) = alertType {
                return Text(message)
            }
            return Text("")
        })
        .onAppear {
            // First check registration status
            checkRegistrationStatus()
            
            // Then load restaurant data (which will only load if registered)
            loadRestaurantData()
            
            // Only attempt to load restaurant image if registered
            if isRegistered {
                // Force attempt to load restaurant image - try both user ID and restaurant ID
                if let userId = authService.getUserId() {
                    RestaurantService.shared.fetchRestaurantImage(restaurantId: userId) { image in
                        if let image = image {
                            DispatchQueue.main.async {
                                self.restaurantImage = image
                                DebugLogger.shared.log("Successfully loaded restaurant image from user ID", category: .network, tag: "RESTAURANT_MANAGEMENT")
                            }
                        }
                    }
                }
                
                // Also try with restaurant ID if different
                if let restaurantId = UserDefaults.standard.string(forKey: "restaurant_id"), 
                   restaurantId != authService.getUserId() {
                    RestaurantService.shared.fetchRestaurantImage(restaurantId: restaurantId) { image in
                        if let image = image {
                            DispatchQueue.main.async {
                                self.restaurantImage = image
                                DebugLogger.shared.log("Successfully loaded restaurant image from restaurant ID", category: .network, tag: "RESTAURANT_MANAGEMENT")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Restaurant Profile Section
    private var restaurantProfileSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header with Delete button aligned to top right
            HStack {
                Spacer()
                if isRegistered {
                    Button(action: {
                        print("Delete button tapped")
                        alertType = .deleteConfirmation
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(AppColors.errorRed))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isSubmitting)
                    .buttonStyle(PlainButtonStyle()) // Add explicit button style
                }
            }
            
            // Restaurant name
            VStack(alignment: .leading) {
                Text("Restaurant Name")
                    .font(.headline)
                TextField("Enter restaurant name", text: $restaurantName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Estimated time
            VStack(alignment: .leading) {
                Text("Estimated Time (minutes)")
                    .font(.headline)
                TextField("30", text: $estimatedTime)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
            }
            
            // Cuisine selection
            VStack(alignment: .leading) {
                Text("Cuisine")
                    .font(.headline)
                
                Picker("Select cuisine", selection: $selectedCuisine) {
                    ForEach(cuisineTypes, id: \.self) { cuisine in
                        Text(cuisine).tag(cuisine)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
            
            // Banner photo
            VStack(alignment: .leading) {
                Text("Banner Photo")
                    .font(.headline)
                
                if let image = restaurantImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 150)
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 150)
                        .cornerRadius(8)
                        .overlay(
                            Text("No image selected")
                                .foregroundColor(.gray)
                        )
                }
                
                Button(action: {
                    currentImageSelection = .restaurant
                    isImagePickerShown = true
                }) {
                    HStack {
                        Image(systemName: "arrow.up.square")
                        Text("Upload Photo")
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(AppColors.primaryGreen))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            }
            
            Spacer(minLength: 30) // Add space between upload photo and update button
            
            // Action Buttons
            if isRegistered {
                Button(action: submitRestaurantProfile) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Update Restaurant")
                                .font(AppFonts.buttonText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(AppColors.primaryGreen))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isSubmitting)
            } else {
                // Register Button (when not registered)
                Button(action: submitRestaurantProfile) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text("Register Restaurant")
                            .font(AppFonts.buttonText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(AppColors.primaryGreen))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isSubmitting)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
    }
    
    // MARK: - Methods
    private func shouldHideSaveButton() -> Bool {
        // Always hide the button when fields are filled and registered
        if isRegistered && !restaurantName.isEmpty && !estimatedTime.isEmpty && !selectedCuisine.isEmpty && restaurantImage != nil {
            return true
        }
        
        // Also hide if there's an active submission
        if isSubmitting {
            return true
        }
        
        return false
    }
    
    private func loadRestaurantData() {
        // First check if restaurant is registered
        let isRestaurantRegistered = UserDefaults.standard.bool(forKey: "is_restaurant_registered")
        
        // If not registered, ensure all fields are empty and return early
        if !isRestaurantRegistered {
            restaurantName = ""
            estimatedTime = ""
            selectedCuisine = ""
            restaurantImage = nil
            return
        }
        
        // Check if we have values in the current user profile first
        if let currentUser = authService.currentUser {
            // Use current user profile values
            restaurantName = currentUser.restaurantName
            
            // Only set these if they're not empty
            if currentUser.estimatedTime > 0 {
                estimatedTime = String(currentUser.estimatedTime)
            }
            
            if !currentUser.cuisine.isEmpty {
                selectedCuisine = currentUser.cuisine
            }
            
            DebugLogger.shared.log("Loaded restaurant data from user profile - Name: \(currentUser.restaurantName), Time: \(currentUser.estimatedTime), Cuisine: \(currentUser.cuisine)", category: .app)
        }
        
        // Load existing restaurant data from DataController
        if !dataController.restaurant.name.isEmpty {
            restaurantName = dataController.restaurant.name
        }
        
        // Try to load restaurant image if we have a restaurantId
        if let restaurantId = authService.getUserId(), restaurantImage == nil {
            RestaurantService.shared.fetchRestaurantImage(restaurantId: restaurantId) { image in
                if let image = image {
                    DispatchQueue.main.async {
                        self.restaurantImage = image
                        DebugLogger.shared.log("Successfully loaded restaurant image", category: .network, tag: "RESTAURANT_MANAGEMENT")
                    }
                }
            }
        }
        
        // Finally, load restaurant data from UserDefaults (overrides other sources if available)
        if let restaurantDataEncoded = UserDefaults.standard.data(forKey: "restaurant_data"),
           let restaurantData = try? JSONSerialization.jsonObject(with: restaurantDataEncoded, options: []) as? [String: Any] {
            
            if let name = restaurantData["name"] as? String, !name.isEmpty {
                restaurantName = name
            }
            
            if let time = restaurantData["estimatedTime"] as? Int {
                estimatedTime = String(time)
            }
            
            if let cuisine = restaurantData["cuisine"] as? String, !cuisine.isEmpty {
                selectedCuisine = cuisine
            }
            
            DebugLogger.shared.log("Loaded restaurant data from UserDefaults - Name: \(restaurantData["name"] as? String ?? ""), Time: \(restaurantData["estimatedTime"] as? Int ?? 0), Cuisine: \(restaurantData["cuisine"] as? String ?? "")", category: .app)
        }
        
        // If still no cuisine value, try to load from raw data
        if selectedCuisine.isEmpty {
            if let rawDataEncoded = UserDefaults.standard.data(forKey: "restaurant_raw_data"),
               let rawData = try? JSONSerialization.jsonObject(with: rawDataEncoded, options: []) as? [String: Any] {
                
                if let cuisine = rawData["resturantCusine"] as? String, !cuisine.isEmpty {
                    selectedCuisine = cuisine
                    DebugLogger.shared.log("Loaded cuisine from raw data: \(cuisine)", category: .app)
                }
                
                if estimatedTime.isEmpty, let time = rawData["resturantEstimateTime"] as? Int {
                    estimatedTime = String(time)
                    DebugLogger.shared.log("Loaded estimated time from raw data: \(time)", category: .app)
                }
            }
        }
    }
    
    private func checkRegistrationStatus() {
        // Check if restaurant is registered
        isRegistered = UserDefaults.standard.bool(forKey: "is_restaurant_registered")
        
        // If not registered, ensure all fields are empty
        if !isRegistered {
            restaurantName = ""
            estimatedTime = ""
            selectedCuisine = ""
            restaurantImage = nil
        }
    }
    
    private func submitRestaurantProfile() {
        guard validateRestaurantFields() else { return }
        
        isSubmitting = true
        
        // Get the user ID
        guard let userId = authService.getUserId() else {
            showAlert(message: "User ID not found")
            isSubmitting = false
            return
        }
        
        if isRegistered {
            // Update existing restaurant
            updateRestaurantProfile()
        } else {
            // Register new restaurant
            registerNewRestaurant(userId: userId)
        }
    }
    
    private func validateRestaurantFields() -> Bool {
        // Basic validation
        if restaurantName.isEmpty {
            showAlert(message: "Please enter restaurant name")
            return false
        }
        
        if estimatedTime.isEmpty {
            showAlert(message: "Please enter estimated time")
            return false
        }
        
        // For new registrations, require an image
        if !isRegistered && restaurantImage == nil {
            showAlert(message: "Please select a banner image")
            return false
        }
        
        return true
    }
    
    private func createRestaurantFormData() -> [String: Any] {
        var formData: [String: Any] = [
            "restaurant_Name": restaurantName,
            "userId": authService.getUserId() ?? "",
            "cuisines": selectedCuisine,
            "estimatedTime": Int(estimatedTime) ?? 30
        ]
        
        // Convert image to Base64
        if let restaurantImage = restaurantImage {
            // Process image to ensure it's not too large
            let maxSize: CGFloat = 600  // Reduced from 1200
            var processedImage = restaurantImage
            
            if max(restaurantImage.size.width, restaurantImage.size.height) > maxSize {
                let scale = maxSize / max(restaurantImage.size.width, restaurantImage.size.height)
                let newWidth = restaurantImage.size.width * scale
                let newHeight = restaurantImage.size.height * scale
                let newSize = CGSize(width: newWidth, height: newHeight)
                
                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                restaurantImage.draw(in: CGRect(origin: .zero, size: newSize))
                if let resizedImage = UIGraphicsGetImageFromCurrentImageContext() {
                    processedImage = resizedImage
                }
                UIGraphicsEndImageContext()
            }
            
            // Try to get JPEG data with very low compression quality (0.01 = 1%)
            if let imageData = processedImage.jpegData(compressionQuality: 0.01) {
                let base64String = imageData.base64EncodedString()
                formData["bannerPhoto64Image"] = base64String
                print("Image data size in form data: \(imageData.count) bytes")
            } else {
                print("Error: Failed to convert image to JPEG data")
            }
        }
        
        return formData
    }
    
    private func registerNewRestaurant(userId: String) {
        // Try the multipart approach first (better for large images)
        restaurantService.registerRestaurantWithMultipart(
            userId: userId,
            restaurantName: restaurantName,
            cuisine: selectedCuisine,
            estimatedTime: Int(estimatedTime) ?? 30,
            bannerImage: restaurantImage
        ) { result in
            self.isSubmitting = false
            
            switch result {
            case .success(let restaurantId):
                self.handleSuccessfulRegistration(userId: userId, restaurantId: restaurantId)
            case .failure(let error):
                // If the multipart endpoint is not available, fall back to the regular method
                print("Multipart registration failed: \(error.localizedDescription). Trying standard method...")
                
                // Fall back to regular registration
                self.registerWithStandardMethod(userId: userId)
            }
        }
    }
    
    private func registerWithStandardMethod(userId: String) {
        // Use RestaurantService to register the restaurant with the old method
        restaurantService.registerRestaurant(
            userId: userId,
            restaurantName: restaurantName,
            cuisine: selectedCuisine,
            estimatedTime: Int(estimatedTime) ?? 30,
            bannerImage: restaurantImage
        ) { result in
            self.isSubmitting = false
            
            switch result {
            case .success(let restaurantId):
                self.handleSuccessfulRegistration(userId: userId, restaurantId: restaurantId)
            case .failure(let error):
                self.showAlert(message: error.localizedDescription)
            }
        }
    }
    
    private func handleSuccessfulRegistration(userId: String, restaurantId: String) {
        // Update UserDefaults with the new restaurant ID
        UserDefaults.standard.set(restaurantId, forKey: "restaurant_id")
        UserDefaults.standard.set(true, forKey: "is_restaurant_registered")
        
        // Update the restaurant data in UserDefaults
        let restaurantData: [String: Any] = [
            "id": restaurantId,
            "name": self.restaurantName,
            "estimatedTime": Int(self.estimatedTime) ?? 30,
            "cuisine": self.selectedCuisine,
            "isRegistered": true
        ]
        
        if let encodedData = try? JSONSerialization.data(withJSONObject: restaurantData) {
            UserDefaults.standard.set(encodedData, forKey: "restaurant_data")
        }
        
        // Update the auth service with restaurant info
        let updatedUser = UserRestaurantProfile(
            id: userId,
            restaurantId: restaurantId,
            restaurantName: self.restaurantName,
            estimatedTime: Int(self.estimatedTime) ?? 30,
            cuisine: self.selectedCuisine,
            restaurantImage: self.restaurantImage
        )
        self.authService.currentUser = updatedUser
        
        // Update the data controller
        self.dataController.restaurant.id = restaurantId
        self.dataController.restaurant.name = self.restaurantName
        
        // Update the isRegistered state
        self.isRegistered = true
        
        self.showAlert(message: "Restaurant registered successfully")
    }
    
    private func updateRestaurantProfile() {
        // Get the user ID and restaurant ID
        guard let userId = authService.getUserId(),
              let restaurantId = UserDefaults.standard.string(forKey: "restaurant_id") else {
            showAlert(message: "User ID or Restaurant ID not found")
            isSubmitting = false
            return
        }
        
        // Update existing restaurant using multipart
        restaurantService.updateRestaurantWithMultipart(
            userId: userId,
            restaurantId: restaurantId,
            restaurantName: restaurantName,
            cuisine: selectedCuisine,
            estimatedTime: Int(estimatedTime) ?? 30,
            bannerImage: restaurantImage
        ) { result in
            switch result {
            case .success(let updatedRestaurantId):
                self.isSubmitting = false
                
                // Update restaurant data in UserDefaults
                let restaurantData: [String: Any] = [
                    "id": updatedRestaurantId,
                    "name": self.restaurantName,
                    "estimatedTime": Int(self.estimatedTime) ?? 30,
                    "cuisine": self.selectedCuisine,
                    "isRegistered": true
                ]
                
                if let encodedData = try? JSONSerialization.data(withJSONObject: restaurantData) {
                    UserDefaults.standard.set(encodedData, forKey: "restaurant_data")
                }
                
                // Update the data controller
                self.dataController.restaurant.id = updatedRestaurantId
                self.dataController.restaurant.name = self.restaurantName
                
                self.showAlert(message: "Restaurant updated successfully")
                
            case .failure(let error):
                // Check if the error is related to the image size
                if error.localizedDescription.contains("too large") || error.localizedDescription.contains("too long") {
                    // Try updating without the image
                    DebugLogger.shared.log("First update attempt failed due to image size. Trying without image...", category: .network)
                    
                    self.tryUpdateWithoutImage(userId: userId, restaurantId: restaurantId)
                } else {
                    self.isSubmitting = false
                    self.showAlert(message: "Failed to update restaurant: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Fallback method to update restaurant without image
    private func tryUpdateWithoutImage(userId: String, restaurantId: String) {
        // Create a restaurant with just the text fields
        let restaurant = Restaurant(
            id: restaurantId,
            restaurantId: userId,
            restaurantName: restaurantName,
            cuisine: selectedCuisine,
            estimatedTime: Int(estimatedTime) ?? 30,
            bannerPhoto: nil // Don't include the image
        )
        
        // Use the updateRestaurant method instead of multipart
        restaurantService.updateRestaurant(restaurant: restaurant) { result in
            self.isSubmitting = false
            
            switch result {
            case .success(let updatedRestaurant):
                // Update restaurant data in UserDefaults
                let restaurantData: [String: Any] = [
                    "id": updatedRestaurant.id,
                    "name": self.restaurantName,
                    "estimatedTime": Int(self.estimatedTime) ?? 30,
                    "cuisine": self.selectedCuisine,
                    "isRegistered": true
                ]
                
                if let encodedData = try? JSONSerialization.data(withJSONObject: restaurantData) {
                    UserDefaults.standard.set(encodedData, forKey: "restaurant_data")
                }
                
                // Update the data controller
                self.dataController.restaurant.id = updatedRestaurant.id
                self.dataController.restaurant.name = self.restaurantName
                
                self.showAlert(message: "Restaurant details updated successfully (without image)")
                
                // If we have an image that needs updating, suggest separate image upload
                if self.restaurantImage != nil {
                    DebugLogger.shared.log("Text data updated successfully. Image was not included due to size limits.", category: .network)
                }
                
            case .failure(let error):
                self.showAlert(message: "Failed to update restaurant: \(error.localizedDescription)")
            }
        }
    }
    
    private func deleteRestaurant() {
        isSubmitting = true
        
        // Get the restaurant ID
        guard let restaurantId = UserDefaults.standard.string(forKey: "restaurant_id") else {
            showAlert(message: "Restaurant ID not found")
            isSubmitting = false
            return
        }
        
        // Log the deletion attempt
        DebugLogger.shared.log("Attempting to delete restaurant with ID: \(restaurantId)", category: .network, tag: "DELETE_RESTAURANT")
        
        // Delete the restaurant
        restaurantService.deleteRestaurant(restaurantId: restaurantId) { result in
            DispatchQueue.main.async {
                self.isSubmitting = false
                
                switch result {
                case .success(_):
                    // Reset restaurant state but keep the user account
                    self.restaurantName = ""
                    self.estimatedTime = ""
                    self.selectedCuisine = ""
                    self.restaurantImage = nil
                    self.isRegistered = false
                    
                    // Clear UserDefaults restaurant data
                    UserDefaults.standard.removeObject(forKey: "restaurant_data")
                    UserDefaults.standard.set(false, forKey: "is_restaurant_registered")
                    UserDefaults.standard.removeObject(forKey: "restaurant_id")
                    
                    // Reset restaurant data in DataController
                    self.dataController.restaurant.id = ""
                    self.dataController.restaurant.name = ""
                    
                    // Update the user's restaurant info in AuthService but maintain user ID
                    if var currentUser = self.authService.currentUser {
                        // Preserve the user ID
                        let userId = currentUser.id
                        
                        // Reset restaurant-specific fields
                        currentUser.restaurantId = ""
                        currentUser.restaurantName = ""
                        currentUser.estimatedTime = 0
                        currentUser.cuisine = ""
                        
                        // Update the user
                        self.authService.currentUser = currentUser
                    }
                    
                    self.showAlert(message: "Restaurant deleted successfully")
                    
                case .failure(let error):
                    DebugLogger.shared.logError(error, tag: "DELETE_RESTAURANT_ERROR")
                    self.showAlert(message: "Failed to delete restaurant: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showAlert(message: String) {
        alertMessage = message
        alertType = .message(message)
    }
}

// MARK: - Styling
struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
    }
} 
