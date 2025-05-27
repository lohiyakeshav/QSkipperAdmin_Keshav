import Foundation
import UIKit

/// APIClient - Handles direct API communications with the server
class APIClient {
    static let shared = APIClient()
    
    // Cache for API responses
    private var responseCache: [String: (data: Data, timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = 30 // 30 seconds cache
    
    private init() {
        DebugLogger.shared.log("APIClient initialized", category: .app)
    }
    
    /// Fetch products for a restaurant
    /// - Parameter restaurantId: The restaurant ID
    /// - Returns: Array of products
    func fetchProducts(restaurantId: String) async throws -> [Product] {
        DebugLogger.shared.log("📡 APIClient: GET request to \(NetworkManager.baseURL)/get_all_product/\(restaurantId)", category: .network, tag: "API_CLIENT")
        
        // Check cache first
        let cacheKey = "/get_all_product/\(restaurantId)"
        if let cachedResponse = responseCache[cacheKey],
           Date().timeIntervalSince(cachedResponse.timestamp) < cacheDuration {
            DebugLogger.shared.log("✅ Using cached response for \(cacheKey), age: \(Int(Date().timeIntervalSince(cachedResponse.timestamp)))s", category: .cache)
            
            // Decode from cache
            let decoder = JSONDecoder()
            do {
                let productResponse = try decoder.decode(ProductResponse.self, from: cachedResponse.data)
                DebugLogger.shared.log("✅ Decoded \(productResponse.products?.count ?? 0) products using standard key 'products'", category: .cache)
                return productResponse.products ?? []
            } catch {
                DebugLogger.shared.log("❌ Failed to decode cached response: \(error)", category: .error)
                // Cache decoding failure, continue with fresh request
            }
        }
        
        // Create URL and request
        guard let url = URL(string: "\(NetworkManager.baseURL)/get_all_product/\(restaurantId)") else {
            let error = NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            DebugLogger.shared.logError(error, tag: "URL_CONSTRUCTION")
            throw error
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add auth token if available
        if let token = AuthService.shared.getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Make the request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Cache the response
            responseCache[cacheKey] = (data, Date())
            
            // Log the response in full detail
            if let httpResponse = response as? HTTPURLResponse {
                DebugLogger.shared.log("📥 Response status: \(httpResponse.statusCode) from \(url.host ?? "unknown")", category: .network)
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                DebugLogger.shared.log("📥 Response: \(responseString)", category: .network)
            }
            
            // Check status code
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let error = NSError(domain: "APIClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed with status \(statusCode)"])
                DebugLogger.shared.logError(error, tag: "API_ERROR")
                throw error
            }
            
            // Decode the response
            let decoder = JSONDecoder()
            do {
                let productResponse = try decoder.decode(ProductResponse.self, from: data)
                DebugLogger.shared.log("✅ Decoded \(productResponse.products?.count ?? 0) products using standard key 'products'", category: .network)
                return productResponse.products ?? []
            } catch {
                DebugLogger.shared.log("❌ Decoding error: \(error)", category: .error)
                
                // Try alternative decoding approaches
                do {
                    // Try to decode as an array directly
                    let products = try decoder.decode([Product].self, from: data)
                    DebugLogger.shared.log("✅ Decoded \(products.count) products directly as array", category: .network)
                    return products
                } catch {
                    DebugLogger.shared.log("❌ Alternative decoding failed: \(error)", category: .error)
                    throw error
                }
            }
        } catch {
            DebugLogger.shared.logError(error, tag: "NETWORK_REQUEST")
            throw error
        }
    }
    
    /// Compress image to target size (approximately 50KB)
    /// - Parameters:
    ///   - image: The original UIImage
    ///   - targetSizeKB: Target size in kilobytes (default: 50)
    ///   - usePNG: Whether to use PNG format for absolutely lossless quality
    /// - Returns: Data object of the compressed image
    private func compressImageToTargetSize(image: UIImage, targetSizeKB: Int = 50, usePNG: Bool = false) -> Data? {
        // First resize the image to reasonable dimensions
        let maxSize: CGFloat = 1200 // Increased from 600 for higher resolution
        var processedImage = image
        
        if max(image.size.width, image.size.height) > maxSize {
            let scale = maxSize / max(image.size.width, image.size.height)
            let newWidth = image.size.width * scale
            let newHeight = image.size.height * scale
            let newSize = CGSize(width: newWidth, height: newHeight)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            if let resizedImage = UIGraphicsGetImageFromCurrentImageContext() {
                processedImage = resizedImage
            }
            UIGraphicsEndImageContext()
        }
        
        // Option to use PNG for absolutely lossless quality
        if usePNG {
            guard let pngData = processedImage.pngData() else { return nil }
            DebugLogger.shared.log("🖼️ Using lossless PNG format, Size: \(pngData.count / 1024)KB", category: .network)
            return pngData
        }
        
        // Start with higher compression quality (0.9 instead of 0.5)
        var compression: CGFloat = 0.9
        var imageData = processedImage.jpegData(compressionQuality: compression)!
        
        // Binary search to find best compression quality to meet target size
        var max: CGFloat = 1.0
        var min: CGFloat = 0.5 // Increased minimum quality from 0.0
        
        // Max 6 attempts to find the right compression level
        for _ in 0..<6 {
            let targetSize = targetSizeKB * 1024 // Convert to bytes
            
            if imageData.count <= targetSize {
                // Image is already smaller than target size, try increasing quality
                min = compression
                compression = (max + compression) / 2
            } else {
                // Image is larger than target size, try decreasing quality
                max = compression
                compression = (min + compression) / 2
            }
            
            // Get new data with adjusted compression
            imageData = processedImage.jpegData(compressionQuality: compression)!
            
            // If we're within 10% of the target size, it's good enough
            if Double(abs(imageData.count - targetSize)) < (Double(targetSize) * 0.1) {
                break
            }
        }
        
        DebugLogger.shared.log("🖼️ Final image size: \(imageData.count / 1024) KB with compression \(compression)", category: .network)
        return imageData
    }
    
    /// Create a new product
    /// - Parameters:
    ///   - product: The product to create
    ///   - image: Optional product image
    /// - Returns: Created product
    func createProduct(product: Product, image: UIImage? = nil) async throws -> Product {
        DebugLogger.shared.log("📡 APIClient: POST request to \(NetworkManager.baseURL)/create-product", category: .network)
        
        // Create URL and request
        guard let url = URL(string: "\(NetworkManager.baseURL)/create-product") else {
            let error = NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            DebugLogger.shared.logError(error, tag: "URL_CONSTRUCTION")
            throw error
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Handle product with or without image
        var jsonData: Data
        
        if let image = image {
            // Compress image using exact same approach as restaurant images
            guard let imageData = compressImageToTargetSize(image: image, targetSizeKB: 500, usePNG: false) else {
                DebugLogger.shared.log("⚠️ Failed to compress image", category: .error)
                throw NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
            }
            
            // With image
            let base64String = imageData.base64EncodedString()
            
            // Create payload dictionary
            var productDict: [String: Any] = [
                "product_name": product.name,
                "restaurant_id": product.restaurantId,
                "description": product.description,
                "food_category": product.category,
                "extraTime": String(product.extraTime),
                "product_price": String(product.price),
                "product_photo64Image": base64String
            ]
            
            if !product.id.isEmpty {
                productDict["_id"] = product.id
            }
            
            jsonData = try JSONSerialization.data(withJSONObject: productDict)
            DebugLogger.shared.log("📥 Product with image payload size: \(jsonData.count / 1024)KB", category: .network)
        } else {
            // Without image
            let encoder = JSONEncoder()
            jsonData = try encoder.encode(product)
            DebugLogger.shared.log("📥 Product without image payload size: \(jsonData.count / 1024)KB", category: .network)
        }
        
        request.httpBody = jsonData
        
        // Dump shortened request body for debugging
        if let bodyPreview = String(data: jsonData.prefix(500), encoding: .utf8) {
            DebugLogger.shared.log("📡 Request body (preview): \(bodyPreview)...", category: .network)
        }
        
        // Make the request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log the response
            if let responseString = String(data: data, encoding: .utf8) {
                DebugLogger.shared.log("📥 Create product response: \(responseString)", category: .network)
            }
            
            // Check status code
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let error = NSError(domain: "APIClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed with status \(statusCode)"])
                DebugLogger.shared.logError(error, tag: "API_ERROR")
                throw error
            }
            
            // Decode the response
            let decoder = JSONDecoder()
            do {
                let productResponse = try decoder.decode(ProductResponse.self, from: data)
                if let createdProduct = productResponse.product {
                    return createdProduct
                } else {
                    throw NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Created product not found in response"])
                }
            } catch {
                DebugLogger.shared.log("❌ Decoding error: \(error)", category: .error)
                throw error
            }
        } catch {
            DebugLogger.shared.logError(error, tag: "NETWORK_REQUEST")
            throw error
        }
    }
    
    /// Register a new restaurant
    /// - Parameter restaurant: Restaurant data
    /// - Returns: Registered restaurant
    func registerRestaurant(restaurant: Restaurant) async throws -> Restaurant {
        DebugLogger.shared.log("📡 APIClient: POST request to \(NetworkManager.baseURL)/resturant-register", category: .network)
        
        // Create URL and request
        guard let url = URL(string: "\(NetworkManager.baseURL)/resturant-register") else {
            let error = NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            DebugLogger.shared.logError(error, tag: "URL_CONSTRUCTION")
            throw error
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert restaurant to JSON
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(restaurant)
        request.httpBody = jsonData
        
        // Log the request body
        if let bodyString = String(data: jsonData, encoding: .utf8) {
            DebugLogger.shared.log("📡 Restaurant registration payload: \(bodyString)", category: .network)
        }
        
        // Make the request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log the response
            if let responseString = String(data: data, encoding: .utf8) {
                DebugLogger.shared.log("📥 Restaurant registration response: \(responseString)", category: .network)
            }
            
            // Check status code
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let error = NSError(domain: "APIClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed with status \(statusCode)"])
                DebugLogger.shared.logError(error, tag: "API_ERROR")
                throw error
            }
            
            // Decode the response
            let decoder = JSONDecoder()
            do {
                let restaurantResponse = try decoder.decode(RestaurantResponse.self, from: data)
                if let registeredRestaurant = restaurantResponse.restaurant {
                    return registeredRestaurant
                } else {
                    throw NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Registered restaurant not found in response"])
                }
            } catch {
                DebugLogger.shared.log("❌ Decoding error: \(error)", category: .error)
                throw error
            }
        } catch {
            DebugLogger.shared.logError(error, tag: "NETWORK_REQUEST")
            throw error
        }
    }
    
    /// Login a restaurant
    /// - Parameters:
    ///   - email: Restaurant email
    ///   - password: Restaurant password
    /// - Returns: UserResponse
    func loginRestaurant(email: String, password: String) async throws -> UserResponse {
        DebugLogger.shared.log("📡 APIClient: POST request to \(NetworkManager.baseURL)/resturant-login", category: .network)
        
        // Create URL and request
        guard let url = URL(string: "\(NetworkManager.baseURL)/resturant-login") else {
            let error = NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            DebugLogger.shared.logError(error, tag: "URL_CONSTRUCTION")
            throw error
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create login payload
        let loginPayload: [String: Any] = [
            "email": email,
            "password": password
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: loginPayload)
        request.httpBody = jsonData
        
        // Log the request (exclude password)
        DebugLogger.shared.log("📡 Login request for email: \(email)", category: .network)
        
        // Make the request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log the response (be careful not to log sensitive information)
            if let responseString = String(data: data, encoding: .utf8) {
                // Redact any sensitive info like tokens before logging
                let sanitizedResponse = responseString
                    .replacingOccurrences(of: "\"token\":\"[^\"]+\"", with: "\"token\":\"[REDACTED]\"", options: .regularExpression)
                
                DebugLogger.shared.log("📥 Login response: \(sanitizedResponse)", category: .network)
            }
            
            // Check status code
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let error = NSError(domain: "APIClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed with status \(statusCode)"])
                DebugLogger.shared.logError(error, tag: "API_ERROR")
                throw error
            }
            
            // Decode the response
            let decoder = JSONDecoder()
            do {
                let userResponse = try decoder.decode(UserResponse.self, from: data)
                return userResponse
            } catch {
                DebugLogger.shared.log("❌ Decoding error: \(error)", category: .error)
                
                // Try alternative parsing if standard decoding fails
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DebugLogger.shared.log("📥 Parsed login response as dictionary: \(json)", category: .network)
                    
                    // Try to construct UserResponse manually
                    if let userId = json["id"] as? String {
                        let userResponse = UserResponse(
                            success: true,
                            message: "Login successful",
                            token: json["token"] as? String,
                            user: nil,
                            id: userId,
                            username: nil,
                            restaurantId: userId,
                            restaurantName: nil,
                            estimatedTime: nil,
                            cuisine: nil
                        )
                        return userResponse
                    }
                }
                
                throw error
            }
        } catch {
            DebugLogger.shared.logError(error, tag: "NETWORK_REQUEST")
            throw error
        }
    }
    
    /// Update an existing product
    /// - Parameters:
    ///   - product: The product to update
    ///   - image: Optional product image
    /// - Returns: Updated product
    func updateProduct(product: Product, image: UIImage? = nil) async throws -> Product {
        DebugLogger.shared.log("📡 APIClient: PUT request to \(NetworkManager.baseURL)/update-product/\(product.id)", category: .network)
        
        // Create URL and request
        guard let url = URL(string: "\(NetworkManager.baseURL)/update-product/\(product.id)") else {
            let error = NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            DebugLogger.shared.logError(error, tag: "URL_CONSTRUCTION")
            throw error
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Handle product with or without image
        var jsonData: Data
        
        if let image = image {
            // Compress image using exact same approach as restaurant images
            guard let imageData = compressImageToTargetSize(image: image, targetSizeKB: 500, usePNG: false) else {
                DebugLogger.shared.log("⚠️ Failed to compress image", category: .error)
                throw NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
            }
            
            // With image
            let base64String = imageData.base64EncodedString()
            
            // Create payload dictionary
            var productDict: [String: Any] = [
                "product_name": product.name,
                "restaurant_id": product.restaurantId,
                "description": product.description,
                "food_category": product.category,
                "extraTime": String(product.extraTime),
                "product_price": String(product.price),
                "product_photo64Image": base64String
            ]
            
            if !product.id.isEmpty {
                productDict["_id"] = product.id
            }
            
            jsonData = try JSONSerialization.data(withJSONObject: productDict)
            DebugLogger.shared.log("📥 Product update with image payload size: \(jsonData.count / 1024)KB", category: .network)
        } else {
            // Without image
            let encoder = JSONEncoder()
            jsonData = try encoder.encode(product)
            DebugLogger.shared.log("📥 Product update without image payload size: \(jsonData.count / 1024)KB", category: .network)
        }
        
        request.httpBody = jsonData
        
        // Dump shortened request body for debugging
        if let bodyPreview = String(data: jsonData.prefix(500), encoding: .utf8) {
            DebugLogger.shared.log("📡 Update request body (preview): \(bodyPreview)...", category: .network)
        }
        
        // Make the request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log the response
            if let responseString = String(data: data, encoding: .utf8) {
                DebugLogger.shared.log("📥 Update product response: \(responseString)", category: .network)
            }
            
            // Check status code
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let error = NSError(domain: "APIClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed with status \(statusCode)"])
                DebugLogger.shared.logError(error, tag: "API_ERROR")
                throw error
            }
            
            // Decode the response
            let decoder = JSONDecoder()
            do {
                let productResponse = try decoder.decode(ProductResponse.self, from: data)
                if let updatedProduct = productResponse.product {
                    return updatedProduct
                } else {
                    throw NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Updated product not found in response"])
                }
            } catch {
                DebugLogger.shared.log("❌ Decoding error: \(error)", category: .error)
                throw error
            }
        } catch {
            DebugLogger.shared.logError(error, tag: "NETWORK_REQUEST")
            throw error
        }
    }
    
    /// Delete a product
    /// - Parameter productId: The product ID to delete
    /// - Returns: Success boolean
    func deleteProduct(productId: String) async throws -> Bool {
        DebugLogger.shared.log("📡 APIClient: DELETE request to \(NetworkManager.baseURL)/delete-product/\(productId)", category: .network)
        
        // Create URL and request
        guard let url = URL(string: "\(NetworkManager.baseURL)/delete-product/\(productId)") else {
            let error = NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            DebugLogger.shared.logError(error, tag: "URL_CONSTRUCTION")
            throw error
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        // Make the request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log the response
            if let responseString = String(data: data, encoding: .utf8) {
                DebugLogger.shared.log("📥 Delete product response: \(responseString)", category: .network)
            }
            
            // Check status code
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let error = NSError(domain: "APIClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed with status \(statusCode)"])
                DebugLogger.shared.logError(error, tag: "API_ERROR")
                throw error
            }
            
            // Decode the response
            let decoder = JSONDecoder()
            do {
                let deleteResponse = try decoder.decode(DeleteProductResponse.self, from: data)
                return deleteResponse.success
            } catch {
                DebugLogger.shared.log("❌ Decoding error: \(error)", category: .error)
                throw error
            }
        } catch {
            DebugLogger.shared.logError(error, tag: "NETWORK_REQUEST")
            throw error
        }
    }
    
    /// Clear the response cache
    func clearCache() {
        responseCache.removeAll()
        DebugLogger.shared.log("🧹 API response cache cleared", category: .cache)
    }
} 