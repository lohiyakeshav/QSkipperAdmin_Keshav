import SwiftUI
import PhotosUI

struct ProfileEditView: View {
    // Environment
    @EnvironmentObject private var authService: AuthService
    @StateObject private var restaurantService = RestaurantService()
    @Environment(\.presentationMode) private var presentationMode
    
    // State
    @State private var restaurantName = ""
    @State private var cuisine = ""
    @State private var estimatedTime = 30
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var showSuccessAlert = false
    @State private var userImage: UIImage?
    
    var body: some View {
        Form {
            Section(header: Text("Restaurant Profile")) {
                // Restaurant image
                HStack {
                    Spacer()
                    
                    Button(action: {
                        showImagePicker = true
                    }) {
                        VStack {
                            if let image = selectedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "photo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                    .foregroundColor(Color(AppColors.mediumGray))
                                    .frame(width: 100, height: 100)
                                    .background(Color(AppColors.lightGray))
                                    .clipShape(Circle())
                            }
                            
                            Text("Change Image")
                                .font(AppFonts.caption)
                                .foregroundColor(Color(AppColors.primaryGreen))
                                .padding(.top, 4)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 12)
                
                // Restaurant name
                TextField("Restaurant Name", text: $restaurantName)
                
                // Cuisine picker
                Picker("Cuisine", selection: $cuisine) {
                    ForEach(CuisineTypes.list, id: \.self) { cuisine in
                        Text(cuisine)
                    }
                }
                
                // Estimated time
                Stepper("Estimated Time: \(estimatedTime) mins", value: $estimatedTime, in: 10...120, step: 5)
            }
            
            Section {
                Button(action: updateProfile) {
                    Text("Save Changes")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                }
                .listRowBackground(Color(AppColors.primaryGreen))
                .disabled(restaurantName.isEmpty || restaurantService.isLoading)
            }
            
            if let error = restaurantService.error {
                Section {
                    Text(error)
                        .foregroundColor(Color(AppColors.errorRed))
                        .font(AppFonts.caption)
                }
            }
            
            if restaurantService.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Edit Profile")
        .onAppear(perform: loadUserProfile)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage, onImageSelected: {
                userImage = selectedImage
            })
        }
        .alert(isPresented: $showSuccessAlert) {
            Alert(
                title: Text("Profile Updated"),
                message: Text("Your restaurant profile has been updated successfully."),
                dismissButton: .default(Text("OK")) {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    private func loadUserProfile() {
        guard let currentUser = authService.currentUser else { return }
        
        restaurantName = currentUser.restaurantName
        cuisine = currentUser.cuisine
        estimatedTime = currentUser.estimatedTime
        selectedImage = currentUser.restaurantImage
        
        // Load the full restaurant to get any data not in the user profile
        if !currentUser.restaurantId.isEmpty {
            restaurantService.fetchRestaurantByUserId(userId: currentUser.id)
        }
    }
    
    private func updateProfile() {
        guard let currentUser = authService.currentUser,
              !currentUser.restaurantId.isEmpty else { return }
        
        // Create restaurant model for update
        let restaurant = Restaurant(
            id: currentUser.restaurantId,
            restaurantId: currentUser.id,
            restaurantName: restaurantName,
            cuisine: cuisine,
            estimatedTime: estimatedTime,
            bannerPhoto: selectedImage
        )
        
        // Log the update attempt
        DebugLogger.shared.log("Updating restaurant profile: \(restaurant.id)", category: .network)
        
        // Update restaurant
        restaurantService.updateRestaurant(restaurant: restaurant) { result in
            switch result {
            case .success(let updatedRestaurant):
                DebugLogger.shared.log("Restaurant profile update successful", category: .network)
                
                // Update auth service with restaurant info
                let updatedUser = UserRestaurantProfile(
                    id: currentUser.id,
                    restaurantId: updatedRestaurant.id,
                    restaurantName: updatedRestaurant.restaurantName,
                    estimatedTime: updatedRestaurant.estimatedTime,
                    cuisine: updatedRestaurant.cuisine,
                    restaurantImage: updatedRestaurant.bannerPhoto
                )
                authService.currentUser = updatedUser
                
                // Show success alert
                showSuccessAlert = true
                
            case .failure(let error):
                DebugLogger.shared.logError(error, tag: "RESTAURANT_UPDATE")
                restaurantService.error = "Update failed: \(error.localizedDescription)"
                
                // If there's a selected image and the update failed, try uploading the image separately
                if let image = selectedImage {
                    DebugLogger.shared.log("Attempting to upload restaurant image separately", category: .network)
                    uploadRestaurantImage(restaurantId: currentUser.restaurantId, image: image)
                }
            }
        }
    }
    
    private func uploadRestaurantImage(restaurantId: String, image: UIImage) {
        restaurantService.uploadRestaurantImage(restaurantId: restaurantId, image: image) { result in
            switch result {
            case .success(let message):
                DebugLogger.shared.log("Restaurant image upload successful: \(message)", category: .network)
                
                // Show success alert even if only the image upload succeeded
                showSuccessAlert = true
                
            case .failure(let error):
                DebugLogger.shared.logError(error, tag: "RESTAURANT_IMAGE_UPLOAD")
                restaurantService.error = "Image upload failed: \(error.localizedDescription)"
            }
        }
    }
}

struct ProfileEditView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ProfileEditView()
                .environmentObject(AuthService())
        }
    }
} 