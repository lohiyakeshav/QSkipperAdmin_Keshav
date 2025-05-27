import SwiftUI
import PhotosUI

struct ProductFormView: View {
    // Environment
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var productService: ProductService
    @Environment(\.presentationMode) private var presentationMode
    @Binding var isPresented: Bool
    
    // Product to edit (nil if adding new)
    var product: Product?
    
    // State
    @State private var name = ""
    @State private var description = ""
    @State private var price = ""
    @State private var category = ""
    @State private var isAvailable = true
    @State private var isFeatured = false
    @State private var extraTime = 0
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var imageChanged = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Information")) {
                    TextField("Product Name", text: $name)
                    
                    TextField("Category", text: $category)
                        .autocapitalization(.words)
                    
                    TextField("Price", text: $price)
                        .keyboardType(.decimalPad)
                    
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                        .overlay(
                            Text("Description")
                                .foregroundColor(Color(AppColors.mediumGray))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                                .opacity(description.isEmpty ? 1 : 0),
                            alignment: .topLeading
                        )
                }
                
                Section(header: Text("Product Image")) {
                    HStack {
                        Spacer()
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 200, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(AppColors.primaryGreen), lineWidth: imageChanged ? 2 : 0)
                                )
                        } else {
                            Rectangle()
                                .fill(Color(AppColors.lightGray))
                                .frame(width: 200, height: 200)
                                .cornerRadius(10)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(Color(AppColors.mediumGray))
                                        .font(.system(size: 40))
                                )
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    
                    ImagePicker(image: $selectedImage, onImageSelected: {
                        imageChanged = true
                    })
                }
                
                Section {
                    Button(action: saveProduct) {
                        Text(product == nil ? "Add Product" : "Update Product")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color(AppColors.primaryGreen))
                    .disabled(name.isEmpty || category.isEmpty || price.isEmpty || isLoading)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(Color(AppColors.errorRed))
                            .font(AppFonts.caption)
                    }
                }
                
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(product == nil ? "Add Product" : "Edit Product")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage, onImageSelected: {
                    imageChanged = true
                })
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK", role: .cancel) {
                    isPresented = false
                }
            } message: {
                Text(successMessage)
            }
            .onAppear {
                // Populate form if editing existing product
                if let existingProduct = product {
                    name = existingProduct.name
                    description = existingProduct.description
                    price = String(existingProduct.price)
                    category = existingProduct.category
                    isAvailable = existingProduct.isAvailable
                    isFeatured = existingProduct.isFeatured
                    extraTime = existingProduct.extraTime
                    selectedImage = existingProduct.productPhoto
                }
            }
        }
    }
    
    private func saveProduct() {
        guard let priceValue = Int(price) else {
            errorMessage = "Price must be a valid number"
            return
        }
        
        // Get restaurant ID using multiple fallback options
        let restaurantId: String
        
        // Option 1: Try to get from UserDefaults (most reliable)
        if let storedRestaurantId = UserDefaults.standard.string(forKey: "restaurant_id"), !storedRestaurantId.isEmpty {
            restaurantId = storedRestaurantId
            DebugLogger.shared.log("Using restaurant ID from UserDefaults: \(restaurantId)", category: .network)
        }
        // Option 2: Try to get from authService.currentUser
        else if let userRestaurantId = authService.currentUser?.restaurantId, !userRestaurantId.isEmpty {
            restaurantId = userRestaurantId
            DebugLogger.shared.log("Using restaurant ID from current user: \(restaurantId)", category: .network)
        }
        // Option 3: Try to get from DataController
        else if !DataController.shared.restaurant.id.isEmpty {
            restaurantId = DataController.shared.restaurant.id
            DebugLogger.shared.log("Using restaurant ID from DataController: \(restaurantId)", category: .network)
        }
        // Option 4: Use user ID as a fallback (least preferred)
        else if let userId = authService.getUserId() {
            restaurantId = userId
            DebugLogger.shared.log("Using user ID as fallback for restaurant ID: \(restaurantId)", category: .network)
        }
        else {
            errorMessage = "Restaurant ID not found. Please try logging out and logging in again."
            return
        }
        
        // Create product model
        var updatedProduct = Product(
            id: product?.id ?? "",
            name: name,
            price: priceValue,
            restaurantId: restaurantId,
            category: category,
            description: description,
            extraTime: extraTime,
            rating: product?.rating ?? 0.0,
            isAvailable: isAvailable,
            isFeatured: isFeatured,
            productPhoto: selectedImage
        )
        
        // Update isLoading on the main thread
        Task { @MainActor in
            isLoading = true
        }
        
        Task {
            do {
                if let existingProduct = product {
                    // Update existing product
                    _ = try await productService.updateProduct(
                        productId: existingProduct.id,
                        product: updatedProduct,
                        // Only pass image if it was changed
                        image: imageChanged ? selectedImage : nil
                    )
                    
                    // Show success alert
                    await MainActor.run {
                        isLoading = false
                        errorMessage = nil
                        successMessage = "Product updated successfully"
                        showSuccessAlert = true
                    }
                } else {
                    // Add new product
                    _ = try await productService.addProduct(
                        product: updatedProduct,
                        image: selectedImage
                    )
                    
                    // Close the form on success
                    await MainActor.run {
                        isLoading = false
                        errorMessage = nil
                        isPresented = false
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct ProductFormView_Previews: PreviewProvider {
    static var previews: some View {
        ProductFormView(isPresented: .constant(true))
            .environmentObject(AuthService())
            .environmentObject(ProductService())
    }
} 