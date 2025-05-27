import Foundation
import SwiftUI
import Combine

class ProductService: ObservableObject {
    static let shared = ProductService()
    
    // Published properties
    @Published var products: [Product] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    // API client
    private let productApi = ProductApi.shared
    
    // MARK: - Product Methods
    
    /// Fetch products for a restaurant
    /// - Parameter restaurantId: The restaurant ID
    func fetchRestaurantProducts(restaurantId: String = "") {
        Task {
            await MainActor.run {
                isLoading = true
                error = nil
            }
            
            do {
                DebugLogger.shared.log("Starting to load products", category: .network)
                
                // Use the provided restaurantId if not empty, otherwise use DataController's restaurant
                let targetRestaurantId = !restaurantId.isEmpty ? restaurantId : DataController.shared.restaurant.id
                
                // If we have a restaurantId from DataController, log it
                if !DataController.shared.restaurant.id.isEmpty {
                    DebugLogger.shared.log("Using restaurant ID from DataController: \(DataController.shared.restaurant.id)", category: .network)
                }
                
                // Pass the restaurant ID to the API call
                let fetchedProducts = try await productApi.getAllProducts(restaurantId: targetRestaurantId)
                
                await MainActor.run {
                    self.products = fetchedProducts
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    /// Add a new product
    /// - Parameters:
    ///   - product: The product to add
    func addProduct(product: Product, image: UIImage? = nil) async throws -> Product {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let newProduct = try await productApi.createProductWithMultipart(product: product, image: image)
            
            // Update the products list
            await refreshProducts()
            
            await MainActor.run {
                isLoading = false
            }
            return newProduct
        } catch {
            await MainActor.run {
                isLoading = false
                self.error = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Update a product
    /// - Parameters:
    ///   - productId: The product ID
    ///   - product: The updated product
    ///   - image: The new product image (if changed)
    /// - Returns: The updated product
    func updateProduct(productId: String, product: Product, image: UIImage? = nil) async throws -> Product {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        DebugLogger.shared.log("Starting to update product: \(productId)", category: .network)
        
        // Only include the image in the API call if it was actually changed
        let imageToUse = image
        
        do {
            // Update the product using the API
            let updatedProduct = try await productApi.updateProduct(
                productId: productId,
                product: product,
                image: imageToUse
            )
            
            // Clear the image cache for this product to ensure fresh images are displayed
            ProductApi.shared.clearProductImageCache(productId: productId)
            
            // Refresh the product list to include the updated product
            await refreshProducts()
            
            await MainActor.run {
                isLoading = false
            }
            
            return updatedProduct
        } catch {
            DebugLogger.shared.log("Error updating product: \(error.localizedDescription)", category: .error)
            
            await MainActor.run {
                self.error = "Failed to update product: \(error.localizedDescription)"
                isLoading = false
            }
            
            throw error
        }
    }
    
    /// Delete a product
    /// - Parameter productId: ID of the product to delete
    /// - Returns: Success status
    func deleteProduct(productId: String) async throws -> Bool {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let success = try await productApi.deleteProduct(productId: productId)
            
            if success {
                // Update the products list on success
                await refreshProducts()
            }
            
            await MainActor.run {
                isLoading = false
            }
            return success
        } catch {
            await MainActor.run {
                isLoading = false
                self.error = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Refresh the products list
    private func refreshProducts() async {
        do {
            let targetRestaurantId = DataController.shared.restaurant.id
            if !targetRestaurantId.isEmpty {
                let refreshedProducts = try await productApi.getAllProducts(restaurantId: targetRestaurantId)
                
                await MainActor.run {
                    self.products = refreshedProducts
                }
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
    
    /// Toggle product availability
    /// - Parameters:
    ///   - productId: The product ID
    ///   - isAvailable: New availability state
    ///   - completion: Completion handler
    func toggleProductAvailability(productId: String, isAvailable: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        Task {
            await MainActor.run {
                isLoading = true
                error = nil
            }
            
            // Short delay to simulate network call
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await MainActor.run {
                // Find and update product in array
                if let index = self.products.firstIndex(where: { $0.id == productId }) {
                    var updatedProduct = self.products[index]
                    updatedProduct.isAvailable = isAvailable
                    self.products[index] = updatedProduct
                    
                    self.isLoading = false
                    completion(.success(true))
                } else {
                    self.isLoading = false
                    let error = NSError(domain: "ProductService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Product not found"])
                    self.error = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
} 