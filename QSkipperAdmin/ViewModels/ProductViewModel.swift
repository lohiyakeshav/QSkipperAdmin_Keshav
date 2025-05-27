import Foundation
import UIKit
import Combine

class ProductViewModel: ObservableObject {
    // Published properties
    @Published var products: [Product] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    // Services
    private let networkUtils = NetworkUtils.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        DebugLogger.shared.log("ProductViewModel initialized", category: .app)
    }
    
    // MARK: - Public Methods
    
    /// Load all products for the current restaurant
    func loadProducts() {
        isLoading = true
        error = nil
        
        // Get restaurant ID from UserDefaults
        guard let restaurantId = UserDefaults.standard.string(forKey: "restaurant_id"), !restaurantId.isEmpty else {
            error = "Restaurant ID not found"
            isLoading = false
            return
        }
        
        // Use async/await pattern with task
        Task {
            do {
                let fetchedProducts = try await networkUtils.fetchProducts(for: restaurantId)
                DispatchQueue.main.async {
                    self.products = fetchedProducts
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Failed to load products: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    /// Create a new product
    /// - Parameters:
    ///   - product: The product to create
    ///   - image: Optional product image
    ///   - completion: Completion handler with result
    func createProduct(product: Product, image: UIImage?, completion: @escaping (Result<Product, Error>) -> Void) {
        isLoading = true
        error = nil
        
        Task {
            do {
                let createdProduct = try await networkUtils.createProduct(product: product, image: image)
                DispatchQueue.main.async {
                    self.products.append(createdProduct)
                    self.isLoading = false
                    completion(.success(createdProduct))
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Failed to create product: \(error.localizedDescription)"
                    self.isLoading = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Update an existing product
    /// - Parameters:
    ///   - product: The product to update
    ///   - image: Optional updated product image
    ///   - completion: Completion handler with result
    func updateProduct(product: Product, image: UIImage?, completion: @escaping (Result<Product, Error>) -> Void) {
        isLoading = true
        error = nil
        
        Task {
            do {
                let updatedProduct = try await APIClient.shared.updateProduct(product: product, image: image)
                
                // Clear the image cache for this product to ensure fresh images are displayed
                ProductApi.shared.clearProductImageCache(productId: product.id)
                
                DispatchQueue.main.async {
                    // Find and replace the product in the array
                    if let index = self.products.firstIndex(where: { $0.id == updatedProduct.id }) {
                        self.products[index] = updatedProduct
                    }
                    self.isLoading = false
                    completion(.success(updatedProduct))
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Failed to update product: \(error.localizedDescription)"
                    self.isLoading = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Delete a product
    /// - Parameters:
    ///   - productId: The product ID to delete
    ///   - completion: Completion handler with result
    func deleteProduct(productId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        isLoading = true
        error = nil
        
        Task {
            do {
                let success = try await APIClient.shared.deleteProduct(productId: productId)
                DispatchQueue.main.async {
                    if success {
                        // Remove the product from the array
                        self.products.removeAll { $0.id == productId }
                    }
                    self.isLoading = false
                    completion(.success(success))
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Failed to delete product: \(error.localizedDescription)"
                    self.isLoading = false
                    completion(.failure(error))
                }
            }
        }
    }
} 