import SwiftUI
import Combine
import PhotosUI
// Import the UIKitImagePicker
import UIKit

struct ProductsView: View {
    // Environment
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var productService: ProductService
    
    // State
    @State private var isAddProductSheetPresented = false
    @State private var products: [Product] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showDebugInfo = false
    @State private var selectedProduct: Product? = nil
    @State private var showEditProductSheet = false
    @State private var showProductDetailSheet = false
    @State private var productToView: Product? = nil
    @State private var isLoadingProductDetails = false
    @State private var showLoadingOverlay = false
    
    var body: some View {
        ZStack {
            // Background color
            Color(UIColor.systemGray6)
                .edgesIgnoringSafeArea(.all)
            // Main content
            VStack(spacing: 0) {
                // Custom header that matches the screenshot
                HStack {
                    Text("Products")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button(action: {
                        // Refresh action
                        Task {
                            await loadProductsAsync()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                            .foregroundColor(Color(AppColors.primaryGreen))
                    }
                    .padding(.trailing, 8)
                    
                    Button(action: {
                        isAddProductSheetPresented = true
                    }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Product")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(AppColors.primaryGreen))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
                
                // Loading state for initial products load
                if isLoading && products.isEmpty {
                    // Initial loading view
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                        
                        Text("Loading products...")
                            .font(AppFonts.body)
                            .foregroundColor(Color(AppColors.darkGray))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(AppColors.background))
                } else if let error = errorMessage {
                    // Error view
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(Color(AppColors.errorRed))
                        
                        Text(error)
                            .font(AppFonts.body)
                            .foregroundColor(Color(AppColors.darkGray))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        
                        Button(action: {
                            loadProducts()
                        }) {
                            Text("Try Again")
                                .font(AppFonts.buttonText)
                                .foregroundColor(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 12)
                                .background(Color(AppColors.primaryGreen))
                                .cornerRadius(10)
                        }
                        .padding(.top, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(AppColors.background))
                } else if products.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "cube.box")
                            .font(.system(size: 50))
                            .foregroundColor(Color(AppColors.mediumGray))
                        
                        Text("No Products Found")
                            .font(AppFonts.title)
                            .foregroundColor(Color(AppColors.darkGray))
                        
                        Text("Add your first product to get started")
                            .font(AppFonts.body)
                            .foregroundColor(Color(AppColors.darkGray))
                        
                        Button(action: {
                            isAddProductSheetPresented = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Product")
                            }
                            .font(AppFonts.buttonText)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(Color(AppColors.primaryGreen))
                            .cornerRadius(10)
                        }
                        .padding(.top, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(AppColors.background))
                } else {
                    // Product grid
                    // Simple ScrollView without NavigationView for cleaner UI
                    ScrollView {
                        // Add a small vertical padding at the top
                        Color.clear.frame(height: 8)
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 320, maximum: 320), spacing: 16)
                            ],
                            spacing: 16
                        ) {
                            ForEach(products) { product in
                                ProductCard(product: product)
                                    .onTapGesture {
                                        showProductDetail(product)
                                    }
                                    .contextMenu {
                                        Button(action: {
                                            // Edit product action
                                            selectedProduct = product
                                            showEditProductSheet = true
                                        }) {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        
                                        Button(role: .destructive, action: {
                                            deleteProduct(product)
                                        }) {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            
            // Loading overlay
            if showLoadingOverlay {
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
        }
        .sheet(isPresented: $isAddProductSheetPresented) {
            // Reload products after dismissing the sheet
            loadProducts()
        } content: {
            AddProductView()
                .environmentObject(dataController)
                .environmentObject(authService)
        }
        .sheet(isPresented: $showEditProductSheet) {
            // Reload products after dismissing the edit sheet
            loadProducts()
        } content: {
            if let product = selectedProduct {
                ProductFormView(isPresented: $showEditProductSheet, product: product)
                    .environmentObject(productService)
            }
        }
        .sheet(isPresented: $showProductDetailSheet) {
            // Reload products after viewing details
            loadProducts()
        } content: {
            if let product = productToView {
                ProductDetailView(product: product)
                    .environmentObject(productService)
            }
        }
        .onAppear {
            loadProducts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .productUpdated)) { _ in
            // Refresh the product list when any product is updated
            loadProducts()
        }
    }
    
    // Function to handle product detail view presentation
    private func showProductDetail(_ product: Product) {
        // Set loading overlay while preparing product
        showLoadingOverlay = true
        
        // First ensure we have the product fully loaded
        Task {
            do {
                // Get the latest product data
                if let updatedProduct = try await ProductApi.shared.getProduct(productId: product.id) {
                    await MainActor.run {
                        productToView = updatedProduct
                        showLoadingOverlay = false
                        showProductDetailSheet = true
                    }
                } else {
                    // Fall back to the cached product if we couldn't get the updated one
                    await MainActor.run {
                        productToView = product
                        showLoadingOverlay = false
                        showProductDetailSheet = true
                    }
                }
            } catch {
                // If there's an error, just use the original product
                await MainActor.run {
                    DebugLogger.shared.log("Failed to refresh product details: \(error.localizedDescription)", category: .error)
                    productToView = product
                    showLoadingOverlay = false
                    showProductDetailSheet = true
                }
            }
        }
    }
    
    private func loadProducts() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Log the start of the product loading process
                DebugLogger.shared.log("Starting to load products", category: .network)
                
                // Use the direct product loading method
                let fetchedProducts = try await ProductApi.shared.getAllProducts()
                DebugLogger.shared.log("Successfully loaded \(fetchedProducts.count) products", category: .network)
                
                // Update on main thread
                await MainActor.run {
                    self.products = fetchedProducts
                    self.isLoading = false
                }
            } catch {
                DebugLogger.shared.logError(error, tag: "PRODUCT_LOADING")
                
                await MainActor.run {
                    self.errorMessage = "Failed to load products: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadProductsAsync() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            // Use the direct product loading method with proper logging
            DebugLogger.shared.log("Refreshing products (pull-to-refresh)", category: .network)
            let fetchedProducts = try await ProductApi.shared.getAllProducts()
            DebugLogger.shared.log("Refresh completed, loaded \(fetchedProducts.count) products", category: .network)
            
            // Update on main thread
            await MainActor.run {
                self.products = fetchedProducts
                self.isLoading = false
            }
        } catch {
            DebugLogger.shared.logError(error, tag: "PRODUCT_LOADING")
            
            await MainActor.run {
                self.errorMessage = "Failed to refresh products: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func deleteProduct(_ product: Product) {
        Task {
            do {
                // Show loading state
                await MainActor.run {
                    isLoading = true
                }
                
                // Delete the product using ProductApi
                let success = try await ProductApi.shared.deleteProduct(productId: product.id)
                
                if success {
                    // Remove product from the list
                    await MainActor.run {
                        if let index = products.firstIndex(where: { $0.id == product.id }) {
                            products.remove(at: index)
                        }
                        isLoading = false
                    }
                } else {
                    throw NSError(domain: "ProductsView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to delete product"])
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to delete product: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

// Product Card View for grid display
struct ProductCard: View {
    let product: Product
    @State private var productImage: UIImage? = nil
    @State private var isLoadingImage = false
    @State private var refreshTrigger = UUID()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Product image with category badge overlay
            ZStack(alignment: .topTrailing) {
                if isLoadingImage {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 200)
                        .clipped()
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        )
                } else if let image = productImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 200)
                        .clipped()
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                                .font(.largeTitle)
                        )
                }
                
                // Category badge with app theme colors
                Text(product.category)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white)
                    .foregroundColor(Color(AppColors.primaryGreen))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(AppColors.primaryGreen), lineWidth: 1)
                    )
                    .padding(8)
            }
            .onAppear {
                loadProductImage()
            }
            .onChange(of: refreshTrigger) { _ in
                loadProductImage()
            }
            .onReceive(NotificationCenter.default.publisher(for: .productImageCacheCleared)) { notification in
                if let productId = notification.userInfo?["productId"] as? String, 
                   productId == product.id {
                    // Force a reload of this product's image
                    self.productImage = nil
                    self.refreshTrigger = UUID()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .productUpdated)) { notification in
                if let productId = notification.userInfo?["productId"] as? String,
                   let imageUpdated = notification.userInfo?["imageUpdated"] as? Bool,
                   productId == product.id && imageUpdated {
                    // Force a reload of this product's image
                    self.productImage = nil
                    self.refreshTrigger = UUID()
                }
            }
            
            // Product details
            VStack(alignment: .leading, spacing: 8) {
                // Name and price in the same row
                HStack(alignment: .center) {
                    Text(product.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("₹\(product.price)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(Color(AppColors.primaryGreen))
                }
                
                if !product.description.isEmpty {
                    Text(product.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        .frame(width: 320, height: 320) // Fixed size for consistent grid layout
    }
    
    private func loadProductImage() {
        // Use the correct endpoint for product photos with a timestamp to prevent caching
        let timestamp = Int(Date().timeIntervalSince1970)
        let imageUrl = "\(NetworkManager.baseURL)/get_product_photo/\(product.id)?v=\(timestamp)"
        
        // Delay loading to prevent too many concurrent requests
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.1...0.5)) {
            self.loadImage(from: imageUrl)
        }
    }
    
    private func loadImage(from urlString: String) {
        // Skip if already loading
        if isLoadingImage {
            return
        }
        
        isLoadingImage = true
        
        Task {
            do {
                if let url = URL(string: urlString) {
                    DebugLogger.shared.log("Loading image from \(urlString)", category: .network)
                    let image = try await ProductApi.shared.fetchImage(from: url)
                    
                    await MainActor.run {
                        self.productImage = image
                        self.isLoadingImage = false
                    }
                } else {
                    throw ProductApi.ProductApiError.invalidURL
                }
            } catch {
                print("Error loading image: \(error.localizedDescription)")
                
                // Don't keep retrying failed images
                await MainActor.run {
                    self.isLoadingImage = false
                }
            }
        }
    }
}

// Add Product Sheet View
struct AddProductView: View {
    // Environment
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var authService: AuthService
    @Environment(\.presentationMode) private var presentationMode
    
    // State
    @State private var productName: String = ""
    @State private var productPrice: String = ""
    @State private var productCategory: String = ""
    @State private var productDescription: String = ""
    @State private var preparationTime: String = "0"
    @State private var productImage: UIImage? = nil
    @State private var isImagePickerShown = false
    
    // UI state
    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Product Information").foregroundColor(Color(AppColors.primaryGreen))) {
                    TextField("Product Name", text: $productName)
                    
                    HStack {
                        Text("₹")
                            .foregroundColor(Color(AppColors.primaryGreen))
                        TextField("Price", text: $productPrice)
                            .keyboardType(.decimalPad)
                    }
                    
                    TextField("Category", text: $productCategory)
                    
                    HStack {
                        TextField("Extra Time (minutes)", text: $preparationTime)
                            .keyboardType(.numberPad)
                        Text("minutes")
                            .foregroundColor(Color(AppColors.primaryGreen))
                    }
                }
                
                Section(header: Text("Description").foregroundColor(Color(AppColors.primaryGreen))) {
                    TextEditor(text: $productDescription)
                        .frame(minHeight: 100)
                }
                
                Section(header: Text("Product Image").foregroundColor(Color(AppColors.primaryGreen))) {
                    HStack {
                        Spacer()
                        
                        ZStack {
                            if let image = productImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 200)
                            } else {
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .frame(height: 200)
                                    .overlay(
                                        Text("No Image Selected")
                                            .foregroundColor(.gray)
                                    )
                            }
                        }
                        .cornerRadius(8)
                        
                        Spacer()
                    }
                    
                    Button(action: {
                        isImagePickerShown = true
                    }) {
                        HStack {
                            Image(systemName: "photo")
                            Text("Select Image")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundColor(Color(AppColors.primaryGreen))
                    }
                }
                
                Section {
                    Button(action: submitProduct) {
                        HStack {
                            Spacer()
                            
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .tint(Color(AppColors.primaryGreen))
                            }
                            
                            Text("Add Product")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .background(Color(AppColors.primaryGreen))
                        .cornerRadius(8)
                    }
                    .disabled(isSubmitting)
                    .buttonStyle(PlainButtonStyle())
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }
            .navigationTitle("Add Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(Color(AppColors.primaryGreen))
                }
            }
            .sheet(isPresented: $isImagePickerShown) {
                UIKitImagePicker(selectedImage: $productImage)
            }
            .alert("Message", isPresented: $showAlert) {
                Button("OK", role: .cancel) {
                    if alertMessage == "Product added successfully" {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .foregroundColor(Color(AppColors.primaryGreen))
            } message: {
                Text(alertMessage)
            }
            .accentColor(Color(AppColors.primaryGreen))
            .tint(Color(AppColors.primaryGreen))
        }
    }
    
    private func submitProduct() {
        guard validateProductFields() else { return }
        
        isSubmitting = true
        
        // Create product object
        let product = Product(
            name: productName,
            price: Int(Double(productPrice) ?? 0.0),
            restaurantId: authService.getUserId() ?? "",
            category: productCategory,
            description: productDescription,
            extraTime: Int(preparationTime) ?? 0,
            isAvailable: true,
            isActive: true
        )
        
        // Submit product to API using multipart (better for handling images)
        Task {
            do {
                // Try multipart method first (better for handling images)
                let _ = try await ProductApi.shared.createProductWithMultipart(product: product, image: productImage)
                
                await MainActor.run {
                    isSubmitting = false
                    showAlert(message: "Product added successfully")
                }
            } catch {
                // If multipart fails, try with standard method as fallback
                do {
                    let _ = try await ProductApi.shared.createProduct(product: product, image: productImage)
                    
                    await MainActor.run {
                        isSubmitting = false
                        showAlert(message: "Product added successfully")
                    }
                } catch {
                    await MainActor.run {
                        isSubmitting = false
                        showAlert(message: "Error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func validateProductFields() -> Bool {
        // Basic validation
        if productName.isEmpty {
            showAlert(message: "Please enter product name")
            return false
        }
        
        if productPrice.isEmpty {
            showAlert(message: "Please enter product price")
            return false
        }
        
        if productCategory.isEmpty {
            showAlert(message: "Please enter product category")
            return false
        }
        
        if productDescription.isEmpty {
            showAlert(message: "Please enter product description")
            return false
        }
        
        if productImage == nil {
            showAlert(message: "Please select a product image")
            return false
        }
        
        return true
    }
    
    private func showAlert(message: String) {
        alertMessage = message
        showAlert = true
    }
}

 