import SwiftUI

struct ProductDetailView: View {
    // Environment
    @EnvironmentObject private var productService: ProductService
    @Environment(\.presentationMode) private var presentationMode
    
    // Product being viewed
    let product: Product
    
    // State
    @State private var showEditSheet = false
    @State private var isShowingDeleteAlert = false
    @State private var isAvailable = false
    @State private var productImage: UIImage? = nil
    @State private var isLoadingImage = false
    @State private var isDeleting = false
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var hasAppeared = false
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Product image with overlay header
                        ZStack(alignment: .bottom) {
                            // Image container
                            if isLoadingImage {
                                Rectangle()
                                    .fill(Color(AppColors.lightGray))
                                    .frame(height: 250)
                                    .frame(maxWidth: .infinity)
                                    .overlay(
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .scaleEffect(1.5)
                                    )
                            } else if let image = productImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 250)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                            } else {
                                Rectangle()
                                    .fill(Color(AppColors.lightGray))
                                    .frame(height: 250)
                                    .frame(maxWidth: .infinity)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 60, height: 60)
                                            .foregroundColor(Color(AppColors.mediumGray))
                                    )
                            }
                            
                            // Product name and price overlay
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(product.name)
                                            .font(AppFonts.title)
                                            .foregroundColor(.white)
                                            .shadow(radius: 2)
                                        
                                        Text(product.category)
                                            .font(AppFonts.body)
                                            .foregroundColor(.white.opacity(0.9))
                                            .shadow(radius: 2)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("₹\(product.price)")
                                        .font(AppFonts.title)
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Color(AppColors.primaryGreen))
                                        .cornerRadius(8)
                                        .shadow(radius: 2)
                                }
                            }
                            .padding(16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0)]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .productImageCacheCleared)) { notification in
                            if let productId = notification.userInfo?["productId"] as? String, 
                               productId == product.id {
                                // Force a reload of this product's image
                                loadProductImage()
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .productUpdated)) { notification in
                            if let productId = notification.userInfo?["productId"] as? String,
                               let imageUpdated = notification.userInfo?["imageUpdated"] as? Bool,
                               productId == product.id && imageUpdated {
                                // Force a reload of this product's image
                                loadProductImage()
                            }
                        }
                        
                        // Description section
                        VStack(alignment: .leading, spacing: 16) {
                            // Description
                            Group {
                                Text("Description")
                                    .font(AppFonts.sectionTitle)
                                    .foregroundColor(Color(AppColors.darkGray))
                                
                                Text(product.description.isEmpty ? "No description provided" : product.description)
                                    .font(AppFonts.body)
                                    .foregroundColor(Color(AppColors.darkGray))
                                    .padding(.bottom, 8)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal)
                            
                            Divider()
                                .padding(.horizontal)
                            
                            if product.isFeatured {
                                HStack {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(Color.yellow)
                                    
                                    Text("Featured Item")
                                        .font(AppFonts.body.bold())
                                        .foregroundColor(Color.yellow)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                
                                Divider()
                                    .padding(.horizontal)
                            }
                            
                            // Action buttons
                            VStack(spacing: 16) {
                                Button(action: {
                                    showEditSheet = true
                                }) {
                                    HStack {
                                        Image(systemName: "pencil")
                                        Text("Update Product")
                                            .font(AppFonts.buttonText)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(AppColors.primaryGreen))
                                    .cornerRadius(10)
                                }
                                
                                Button(action: {
                                    isShowingDeleteAlert = true
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Delete Product")
                                            .font(AppFonts.buttonText)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(AppColors.errorRed))
                                    .cornerRadius(10)
                                }
                            }
                            .padding()
                        }
                        .padding(.vertical, 16)
                    }
                }
                
                // Loading overlay for when data is loading
                if isLoadingImage && !hasAppeared {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(
                            VStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                
                                Text("Loading product details...")
                                    .foregroundColor(.white)
                                    .font(AppFonts.body)
                                    .padding(.top, 10)
                            }
                        )
                }
                
                // Delete overlay
                if isDeleting {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(
                            VStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                
                                Text("Deleting...")
                                    .foregroundColor(.white)
                                    .font(AppFonts.body)
                                    .padding(.top, 10)
                            }
                        )
                }
            }
            .navigationTitle("Product Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                ProductFormView(isPresented: $showEditSheet, product: product)
                    .environmentObject(productService)
            }
            .alert(isPresented: $isShowingDeleteAlert) {
                Alert(
                    title: Text("Delete Product"),
                    message: Text("Are you sure you want to delete this product? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteProduct()
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(successMessage)
            }
            .onAppear {
                isAvailable = product.isAvailable
                loadProductImage()
            }
            .onChange(of: isLoadingImage) { newValue in
                if !newValue && !hasAppeared {
                    hasAppeared = true
                }
            }
        }
    }
    
    private func updateAvailability(_ available: Bool) {
        // Create a mutable copy of the product
        var updatedProduct = product
        updatedProduct.isAvailable = available
        
        Task {
            do {
                // Update the product using the service
                _ = try await productService.updateProduct(
                    productId: product.id,
                    product: updatedProduct
                )
                await MainActor.run {
                    successMessage = "Product availability updated successfully"
                    showSuccessAlert = true
                }
            } catch {
                // Revert the toggle on error
                await MainActor.run {
                    isAvailable = !available
                    print("Failed to update availability: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func deleteProduct() {
        isDeleting = true
        
        Task {
            do {
                // Delete the product using the service
                let success = try await productService.deleteProduct(productId: product.id)
                
                await MainActor.run {
                    isDeleting = false
                    
                    if success {
                        // Go back to product list
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    print("Failed to delete product: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func loadProductImage() {
        isLoadingImage = true
        
        // First check if product already has a photo in memory
        if let photoFromProduct = product.productPhoto {
            self.productImage = photoFromProduct
            self.isLoadingImage = false
            return
        }
        
        // Use the correct endpoint for product photos with timestamp to prevent caching
        let timestamp = Int(Date().timeIntervalSince1970)
        let imageUrlString = "\(NetworkManager.baseURL)/get_product_photo/\(product.id)?v=\(timestamp)"
        
        guard let url = URL(string: imageUrlString) else {
            isLoadingImage = false
            return
        }
        
        Task {
            do {
                let image = try await ProductApi.shared.fetchImage(from: url)
                
                await MainActor.run {
                    self.productImage = image
                    self.isLoadingImage = false
                }
            } catch {
                print("Error loading product image: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoadingImage = false
                }
            }
        }
    }
}

struct ProductDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ProductDetailView(product: Product(
                id: "123",
                name: "Cheese Pizza",
                price: 12,
                restaurantId: "",
                category: "Pizza",
                description: "Delicious cheese pizza with our signature tomato sauce and premium mozzarella cheese.",
                extraTime: 15,
                rating: 4.5,
                isAvailable: true,
                isFeatured: true
            ))
            .environmentObject(ProductService())
            .environmentObject(AuthService())
            .environmentObject(DataController.shared)
        }
    }
} 