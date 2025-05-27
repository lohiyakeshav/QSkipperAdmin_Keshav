import Foundation
import UIKit
import Combine
import CommonCrypto
import CoreGraphics

// Define a notification name for product updates
extension Notification.Name {
    static let productUpdated = Notification.Name("ProductUpdated")
    static let productImageCacheCleared = Notification.Name("ProductImageCacheCleared")
}

class ProductApi {
    static let shared = ProductApi()
    
    // Base URL
    private let baseUrl = URL(string: NetworkManager.baseURL)!
    
    // Image cache
    private let imageCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Create cache directory in the documents folder
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirectory = documentsDirectory.appendingPathComponent("ImageCache")
        
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Error creating cache directory: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Image Cache Methods
    
    /// Error enum for product API operations
    enum ProductApiError: Error {
        case invalidURL
        case imageNotFound
        case networkError
        
        var localizedDescription: String {
            switch self {
            case .invalidURL: return "Invalid URL provided"
            case .imageNotFound: return "Image could not be found or loaded"
            case .networkError: return "Network error occurred"
            }
        }
    }
    
    /// Cache an image in both memory and disk
    private func cacheImage(_ image: UIImage, forKey key: String) {
        // Generate a safe cache key
        let safeKey = key.md5
        
        // Memory cache
        imageCache.setObject(image, forKey: safeKey as NSString)
        
        // Disk cache
        let imagePath = cacheDirectory.appendingPathComponent(safeKey).path
        if let data = image.jpegData(compressionQuality: 0.9) {
            do {
                try data.write(to: URL(fileURLWithPath: imagePath))
                DebugLogger.shared.log("Image saved to disk cache: \(safeKey)", category: .cache)
            } catch {
                DebugLogger.shared.log("Failed to write image to disk: \(error.localizedDescription)", category: .error)
            }
        }
    }
    
    /// Get image from cache (memory or disk)
    private func getCachedImage(forKey key: String) -> UIImage? {
        // Generate a safe cache key
        let safeKey = key.md5
        
        // Check memory cache first
        if let cachedImage = imageCache.object(forKey: safeKey as NSString) {
            DebugLogger.shared.log("Using cached image from memory for key: \(safeKey)", category: .cache)
            return cachedImage
        }
        
        // Check disk cache
        let imagePath = cacheDirectory.appendingPathComponent(safeKey).path
        if fileManager.fileExists(atPath: imagePath),
           let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)),
           let image = UIImage(data: imageData) {
            // Add to memory cache for faster access next time
            imageCache.setObject(image, forKey: safeKey as NSString)
            DebugLogger.shared.log("Using cached image from disk for key: \(safeKey)", category: .cache)
            return image
        }
        
        return nil
    }
    
    /// Clear all cached images
    func clearImageCache() {
        // Clear memory cache
        imageCache.removeAllObjects()
        
        // Clear disk cache
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try fileManager.removeItem(at: fileURL)
            }
            DebugLogger.shared.log("Image cache cleared", category: .cache)
        } catch {
            DebugLogger.shared.log("Failed to clear disk cache: \(error.localizedDescription)", category: .error)
        }
    }
    
    /// Remove a specific product image from cache
    /// - Parameter productId: The ID of the product whose image should be removed from cache
    func clearProductImageCache(productId: String) {
        // Create the URL string that would be used as the cache key
        let imageUrl = "\(NetworkManager.baseURL)/get_product_photo/\(productId)"
        let safeKey = imageUrl.md5
        
        // Remove from memory cache
        imageCache.removeObject(forKey: safeKey as NSString)
        
        // Remove from disk cache
        let imagePath = cacheDirectory.appendingPathComponent(safeKey).path
        if fileManager.fileExists(atPath: imagePath) {
            do {
                try fileManager.removeItem(atPath: imagePath)
                DebugLogger.shared.log("Image removed from disk cache for product ID: \(productId)", category: .cache)
            } catch {
                DebugLogger.shared.log("Failed to remove image from disk cache: \(error.localizedDescription)", category: .error)
            }
        }
        
        // Post notification that image cache was cleared for this product
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .productImageCacheCleared,
                object: nil,
                userInfo: ["productId": productId]
            )
        }
    }
    
    /// Fetch an image from a URL, using cache if available
    /// - Parameter url: URL for the image
    /// - Returns: UIImage if successful
    func fetchImage(from url: URL) async throws -> UIImage {
        // Create a URL string to use as cache key
        let urlString = url.absoluteString
        
        // Check if image exists in cache
        if let cachedImage = getCachedImage(forKey: urlString) {
            DebugLogger.shared.log("Using cached image for URL: \(urlString)", category: .cache)
            return cachedImage
        }
        
        DebugLogger.shared.log("Fetching image from network: \(urlString)", category: .network)
        
        do {
            // Configure request with longer timeout
            var request = URLRequest(url: url)
            request.timeoutInterval = 30.0
            request.cachePolicy = .reloadIgnoringLocalCacheData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ProductApiError.networkError
            }
            
            // Check if we received an error response
            if httpResponse.statusCode != 200 {
                DebugLogger.shared.log("HTTP error: \(httpResponse.statusCode) for \(urlString)", category: .error)
                throw ProductApiError.imageNotFound
            }
            
            // Check if we received an image
            guard let image = UIImage(data: data) else {
                // Try to see if the data can be interpreted as text for debugging
                if let string = String(data: data, encoding: .utf8), string.count < 1000 {
                    DebugLogger.shared.log("Image data response as string: \(string)", category: .network)
                } else {
                    DebugLogger.shared.log("Received non-image data for \(urlString)", category: .error)
                }
                throw ProductApiError.imageNotFound
            }
            
            // Cache the downloaded image
            cacheImage(image, forKey: urlString)
            DebugLogger.shared.log("Image downloaded and cached for URL: \(urlString)", category: .cache)
            
            return image
        } catch {
            DebugLogger.shared.log("Error fetching image: \(error.localizedDescription)", category: .error)
            throw ProductApiError.networkError
        }
    }
    
    /// Fetch an image from a URL string, using cache if available
    /// - Parameter urlString: URL string for the image
    /// - Returns: UIImage if successful
    func fetchImage(from urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw ProductApiError.invalidURL
        }
        
        return try await fetchImage(from: url)
    }
    
    /// Compress image to match restaurant image quality (500KB)
    /// - Parameter image: The original UIImage
    /// - Returns: Compressed image data
    private func compressImageToTinySize(image: UIImage) -> Data? {
        // First resize the image to reasonable dimensions
        let maxSize: CGFloat = 600 // Same as restaurant images
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
        
        // Start with 0.5 compression quality (same as restaurant images)
        var compression: CGFloat = 0.5
        var imageData = processedImage.jpegData(compressionQuality: compression)!
        
        // Binary search to find best compression quality to meet target size
        var max: CGFloat = 1.0
        var min: CGFloat = 0.0
        
        // Target 500KB size - matching restaurant images
        let targetSizeKB = 500
        
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
        
        DebugLogger.shared.log("Final product image size: \(imageData.count / 1024) KB with compression \(compression)", category: .network)
        return imageData
    }
    
    // MARK: - Product Methods
    
    /// Helper function to get the correct restaurant ID
    private func getCorrectRestaurantId() -> String {
        // First try to get from UserDefaults which should have the most accurate restaurant ID
        if let storedRestaurantId = UserDefaults.standard.string(forKey: "restaurant_id"), !storedRestaurantId.isEmpty {
            DebugLogger.shared.log("Using restaurant ID from UserDefaults: \(storedRestaurantId)", category: .network, tag: "PRODUCT_API")
            return storedRestaurantId
        }
        
        // Next, check current user
        if let user = AuthService.shared.currentUser, !user.restaurantId.isEmpty {
            DebugLogger.shared.log("Using restaurant ID from current user: \(user.restaurantId)", category: .network, tag: "PRODUCT_API")
            return user.restaurantId
        }
        
        // Finally, get from DataController if available
        if !DataController.shared.restaurant.id.isEmpty {
            DebugLogger.shared.log("Using restaurant ID from DataController: \(DataController.shared.restaurant.id)", category: .network, tag: "PRODUCT_API")
            return DataController.shared.restaurant.id
        }
        
        // No restaurant ID available
        DebugLogger.shared.log("No restaurant ID available", category: .network, tag: "PRODUCT_API")
        return ""
    }
    
    /// Get all products for a restaurant
    /// - Parameter restaurantId: The restaurant ID
    /// - Returns: Array of products
    func getAllProducts(restaurantId: String = "") async throws -> [Product] {
        // If restaurantId is provided, use it; otherwise get the correct restaurant ID
        let targetRestaurantId = !restaurantId.isEmpty ? restaurantId : getCorrectRestaurantId()
        
        // Check if we have a valid restaurant ID, if not return empty array
        if targetRestaurantId.isEmpty {
            DebugLogger.shared.log("📱 No restaurant ID available, returning empty products array", category: .network)
            return []
        }
        
        DebugLogger.shared.log("📱 RESTAURANT DETAIL: Starting product load for restaurant ID: \(targetRestaurantId)", category: .network)
        DebugLogger.shared.log("⏱️ Time: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))", category: .network)
        
        // Log using NetworkUtils for enhanced debugging
        DebugLogger.shared.log("📡 RESTAURANT DETAIL: Calling networkUtils.fetchProducts", category: .network)
        
        // Use the traditional approach but with more detailed logging
        let productUrl = baseUrl.appendingPathComponent("get_all_product/\(targetRestaurantId)")
        var request = URLRequest(url: productUrl)
        
        // Add auth token if available
        if let token = AuthService.shared.getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            DebugLogger.shared.log("Added auth token to request", category: .network, tag: "PRODUCT_API")
        }
        
        DebugLogger.shared.log("📡 Full URL: \(productUrl.absoluteString) (Server: \(productUrl.host ?? "unknown"))", category: .network)
        DebugLogger.shared.logRequest(request)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let string = String(data: data, encoding: .utf8) {
            DebugLogger.shared.log("📥 Response: \(string)", category: .network)
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            DebugLogger.shared.log("Invalid response: \(response)", category: .network, tag: "PRODUCT_API_ERROR")
            throw NSError(domain: "ProductApi", code: 0, userInfo: [NSLocalizedDescriptionKey: "Products not found"])
        }
        
        let decoder = JSONDecoder()
        
        do {
            let productResponse = try decoder.decode(ProductResponse.self, from: data)
            DebugLogger.shared.log("✅ Decoded \(productResponse.products?.count ?? 0) products using standard key 'products'", category: .network)
            
            // Log detailed results
            DebugLogger.shared.log("📋 RESTAURANT DETAIL: Fetched \(productResponse.products?.count ?? 0) products:", category: .network)
            if productResponse.products?.isEmpty ?? true {
                DebugLogger.shared.log("⚠️ No products returned for restaurant ID: \(targetRestaurantId)", category: .network, tag: "EMPTY_PRODUCTS")
            } else {
                // Log the first 3 products as a sample
                let sampleProducts = productResponse.products?.prefix(3) ?? []
                for (index, product) in sampleProducts.enumerated() {
                    DebugLogger.shared.log("  \(index+1). \(product.name) (\(product.id)) - $\(product.price)", category: .network)
                }
                
                // Log categories
                let categories = Set(productResponse.products?.map { $0.category } ?? []).sorted()
                DebugLogger.shared.log("📋 Categories: \(categories.joined(separator: ", "))", category: .network)
            }
            
            DebugLogger.shared.log("✅ RESTAURANT DETAIL: Final \(productResponse.products?.count ?? 0) products:", category: .network)
            return productResponse.products ?? []
        } catch {
            DebugLogger.shared.log("Failed to decode product response: \(error.localizedDescription)", category: .error, tag: "PRODUCT_LOADING")
            
            // Try to decode just the array directly
            do {
                let products = try decoder.decode([Product].self, from: data)
                DebugLogger.shared.log("✅ Decoded \(products.count) products directly as array", category: .network)
                return products
            } catch {
                DebugLogger.shared.log("Failed final attempt to decode products: \(error.localizedDescription)", category: .error, tag: "PRODUCT_LOADING")
                throw error
            }
        }
    }
    
    /// Create a new product
    /// - Parameters:
    ///   - product: The product to create
    ///   - image: Optional product image
    /// - Returns: Created product
    func createProduct(product: Product, image: UIImage? = nil) async throws -> Product {
        // Use '/create-product' endpoint instead of '/products'
        guard let url = URL(string: "\(NetworkManager.baseURL)/create-product") else {
            throw NSError(domain: "ProductApi", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // Get the correct restaurant ID
        let correctRestaurantId = getCorrectRestaurantId()
        
        // Check if we have a valid restaurant ID
        if correctRestaurantId.isEmpty {
            throw NSError(domain: "ProductApi", code: 0, userInfo: [NSLocalizedDescriptionKey: "No restaurant ID available to create product"])
        }
        
        // Create a product with the correct restaurant ID
        var productToCreate = product
        productToCreate.restaurantId = correctRestaurantId
        
        DebugLogger.shared.log("📡 Creating product at URL: \(url.absoluteString) for restaurant ID: \(correctRestaurantId)", category: .network)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // Increase timeout to 60 seconds
        
        // If we have an image, convert to base64
        var productWithImage = productToCreate
        if let image = image, let imageData = compressImageToTinySize(image: image) {
            // Use extremely compressed image
            let base64String = imageData.base64EncodedString()
            
            // Create a custom dictionary to match exact server expectations
            var productDict: [String: Any] = [
                "product_name": productToCreate.name,
                "restaurant_id": correctRestaurantId,
                "description": productToCreate.description,
                "food_category": productToCreate.category,
                "extraTime": String(productToCreate.extraTime),
                "product_price": String(productToCreate.price),
                "product_photo64Image": base64String
            ]
            
            // Convert to JSON data
            if let jsonData = try? JSONSerialization.data(withJSONObject: productDict) {
                request.httpBody = jsonData
                DebugLogger.shared.log("📤 Product JSON size: \(jsonData.count / 1024) KB", category: .network)
                
                // Log specific fields for debugging
                DebugLogger.shared.log("📤 Product fields: name=\(productToCreate.name), category=\(productToCreate.category), price=\(productToCreate.price)", category: .network)
            } else {
                // Fall back to using the Product model's encoder if custom JSON fails
                productWithImage.productPhoto = image
                let encoder = JSONEncoder()
                request.httpBody = try encoder.encode(productWithImage)
            }
            
            DebugLogger.shared.log("📤 Product image base64 size: \(base64String.count / 1024) KB", category: .network)
        } else {
            // No image case
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(productWithImage)
            
            // Log the request payload for debugging
            if let jsonData = request.httpBody,
               let jsonString = String(data: jsonData, encoding: .utf8) {
                DebugLogger.shared.log("📤 Product JSON (no image): \(jsonString)", category: .network)
            }
        }
        
        DebugLogger.shared.log("📡 Sending create product request to: \(url.host ?? "unknown")", category: .network)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Log response status and body
        if let httpResponse = response as? HTTPURLResponse {
            DebugLogger.shared.log("📥 Create product response status: \(httpResponse.statusCode)", category: .network)
        }
        
        if let responseText = String(data: data, encoding: .utf8) {
            DebugLogger.shared.log("📥 Create product response: \(responseText)", category: .network)
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            if let responseText = String(data: data, encoding: .utf8) {
                DebugLogger.shared.log("❌ Server error response: \(responseText)", category: .error)
            }
            throw NSError(domain: "ProductApi", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create product"])
        }
        
        // Try to parse response
        do {
            // For this endpoint, a successful response might come in various formats
            // First check if it's a JSON object with a productId field (as shown in logs)
            if let jsonDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let productId = jsonDict["productId"] as? String {
                // Success case where the response has a productId field
                var createdProduct = product
                createdProduct.id = productId
                DebugLogger.shared.log("✅ Product created successfully with ID: \(productId)", category: .network)
                return createdProduct
            }
            
            // Next try pure string response
            if let productId = String(data: data, encoding: .utf8), !productId.isEmpty, productId.count > 5 {
                // Success case where the response is just the product ID
                var createdProduct = product
                createdProduct.id = productId
                DebugLogger.shared.log("✅ Product created successfully with ID: \(productId)", category: .network)
                return createdProduct
            }
            
            // Try to decode as ProductResponse (less likely with your server)
            let productResponse = try JSONDecoder().decode(ProductResponse.self, from: data)
            if let createdProduct = productResponse.product {
                DebugLogger.shared.log("✅ Product created and decoded successfully with ID: \(createdProduct.id)", category: .network)
                return createdProduct
            }
            
            // If we got here, we have a success response but couldn't get the product
            // Your server returns status 200 but we can't parse properly
            var createdProduct = product
            createdProduct.id = "temp_" + UUID().uuidString // Generate temporary ID
            DebugLogger.shared.log("⚠️ Product created with temporary ID: \(createdProduct.id)", category: .network)
            return createdProduct
        } catch {
            DebugLogger.shared.log("❌ Failed to decode product response: \(error.localizedDescription)", category: .error)
            
            // If parsing failed but we got a 200 response, return the original product
            var createdProduct = product
            // Try to extract an ID from the response if possible
            if let responseString = String(data: data, encoding: .utf8), 
               responseString.count > 5 {
                createdProduct.id = responseString
                DebugLogger.shared.log("✅ Extracted product ID from response: \(responseString)", category: .network)
            } else {
                // Your server returns status 200 with no content, so we just assume success
                createdProduct.id = "temp_" + UUID().uuidString // Generate temporary ID
                DebugLogger.shared.log("⚠️ Using temporary product ID: \(createdProduct.id)", category: .network)
            }
            return createdProduct
        }
    }
    
    /// Create a new product using multipart form data (better for handling images)
    /// - Parameters:
    ///   - product: The product to create
    ///   - image: Product image
    /// - Returns: Created product
    func createProductWithMultipart(product: Product, image: UIImage? = nil) async throws -> Product {
        // Confirmed from server code: the endpoint is "/create-product" 
        guard let url = URL(string: "\(NetworkManager.baseURL)/create-product") else {
            throw NSError(domain: "ProductApi", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // Get the correct restaurant ID
        let correctRestaurantId = getCorrectRestaurantId()
        
        // Create a product with the correct restaurant ID
        var productToCreate = product
        productToCreate.restaurantId = correctRestaurantId
        
        DebugLogger.shared.log("Creating product at URL: \(url.absoluteString) for restaurant ID: \(correctRestaurantId)", category: .network)
        
        // Generate boundary string for multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // Increase timeout to 120 seconds
        
        // Create multipart form body
        var body = Data()
        
        // Function to append text field
        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
            DebugLogger.shared.log("Added field \(name): \(value)", category: .network)
        }
        
        // Add product fields to form data - using EXACT field names from server
        appendField("product_name", value: productToCreate.name)
        appendField("restaurant_id", value: correctRestaurantId) // Use the correct restaurant ID
        appendField("description", value: productToCreate.description)
        appendField("food_category", value: productToCreate.category)
        appendField("extraTime", value: String(productToCreate.extraTime))
        appendField("product_price", value: String(productToCreate.price))
        
        // Add image if available (with very low compression)
        if let image = image, let imageData = compressImageToTinySize(image: image) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            // Note: Server expects "product_photo64Image" in req.files, not req.fields
            body.append("Content-Disposition: form-data; name=\"product_photo64Image\"; filename=\"product.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
            
            DebugLogger.shared.log("Product image size: \(imageData.count / 1024) KB", category: .network)
        } else {
            // If no image or compression failed, add a placeholder tiny image
            let placeholderSize = CGSize(width: 50, height: 50)
            UIGraphicsBeginImageContextWithOptions(placeholderSize, false, 1.0)
            UIColor.gray.setFill()
            UIRectFill(CGRect(origin: .zero, size: placeholderSize))
            if let placeholderImage = UIGraphicsGetImageFromCurrentImageContext(),
               let placeholderData = placeholderImage.jpegData(compressionQuality: 0.01) {
                
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"product_photo64Image\"; filename=\"placeholder.jpg\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
                body.append(placeholderData)
                body.append("\r\n".data(using: .utf8)!)
                
                DebugLogger.shared.log("Using placeholder image, size: \(placeholderData.count / 1024) KB", category: .network)
            }
            UIGraphicsEndImageContext()
        }
        
        // Add final boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Set body data
        request.httpBody = body
        
        // Log request details
        DebugLogger.shared.log("Total request size: \(body.count / 1024) KB", category: .network)
        DebugLogger.shared.log("Sending product creation request", category: .network)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log response
            if let responseString = String(data: data, encoding: .utf8) {
                DebugLogger.shared.log("Server response: \(responseString)", category: .network)
            }
            
            // Check response code
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                DebugLogger.shared.log("Product creation failed with status \(statusCode): \(errorMessage)", category: .error)
                throw NSError(domain: "ProductApi", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to create product: \(errorMessage)"])
            }
            
            // Try to parse response
            do {
                // For this endpoint, a successful response might come in various formats
                // First check if it's a JSON object with a productId field (as shown in logs)
                if let jsonDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let productId = jsonDict["productId"] as? String {
                    // Success case where the response has a productId field
                    var createdProduct = product
                    createdProduct.id = productId
                    DebugLogger.shared.log("Product created successfully with ID: \(productId)", category: .network)
                    return createdProduct
                }
                
                // Next try pure string response
                if let productId = String(data: data, encoding: .utf8), !productId.isEmpty, productId.count > 5 {
                    // Success case where the response is just the product ID
                    var createdProduct = product
                    createdProduct.id = productId
                    DebugLogger.shared.log("Product created successfully with ID: \(productId)", category: .network)
                    return createdProduct
                }
                
                // Try to decode as ProductResponse (less likely with your server)
                let productResponse = try JSONDecoder().decode(ProductResponse.self, from: data)
                if let createdProduct = productResponse.product {
                    DebugLogger.shared.log("Product created and decoded successfully with ID: \(createdProduct.id)", category: .network)
                    return createdProduct
                }
                
                // If we got here, we have a success response but couldn't get the product
                // Your server returns status 200 but we can't parse properly
                var createdProduct = product
                createdProduct.id = "temp_" + UUID().uuidString // Generate temporary ID
                DebugLogger.shared.log("Product created with temporary ID: \(createdProduct.id)", category: .network)
                return createdProduct
            } catch {
                DebugLogger.shared.log("Failed to decode product response: \(error.localizedDescription)", category: .error)
                
                // If parsing failed but we got a 200 response, return the original product
                var createdProduct = product
                // Try to extract an ID from the response if possible
                if let responseString = String(data: data, encoding: .utf8), 
                   responseString.count > 5 {
                    createdProduct.id = responseString
                    DebugLogger.shared.log("Extracted product ID from response: \(responseString)", category: .network)
                } else {
                    // Your server returns status 200 with no content, so we just assume success
                    createdProduct.id = "temp_" + UUID().uuidString // Generate temporary ID
                    DebugLogger.shared.log("Using temporary product ID: \(createdProduct.id)", category: .network)
                }
                return createdProduct
            }
        } catch {
            DebugLogger.shared.log("Multipart request failed: \(error.localizedDescription)", category: .error)
            
            // If multipart request fails due to timeout, try the JSON-based approach
            if (error as NSError).domain == NSURLErrorDomain && 
               (error as NSError).code == NSURLErrorTimedOut {
                DebugLogger.shared.log("Trying fallback to JSON-based product creation", category: .network)
                return try await createProduct(product: product, image: image)
            }
            throw error
        }
    }
    
    /// Delete a product by ID
    /// - Parameter productId: The product ID to delete
    /// - Returns: Success boolean
    func deleteProduct(productId: String) async throws -> Bool {
        guard let url = URL(string: "\(NetworkManager.baseURL)/delete-product/\(productId)") else {
            throw NSError(domain: "ProductApi", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        // Add auth token if available
        if let token = AuthService.shared.getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        DebugLogger.shared.log("Deleting product with ID: \(productId)", category: .network)
        DebugLogger.shared.log("DELETE request to: \(url.absoluteString)", category: .network)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                DebugLogger.shared.log("Delete product failed: \(responseString)", category: .error)
            }
            throw NSError(domain: "ProductApi", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to delete product"])
        }
        
        // Try to parse response
        if let responseString = String(data: data, encoding: .utf8) {
            DebugLogger.shared.log("Delete product response: \(responseString)", category: .network)
        }
        
        let deleteResponse = try JSONDecoder().decode(DeleteProductResponse.self, from: data)
        return deleteResponse.success
    }
    
    /// Update a product with form data (for multipart/form-data)
    /// - Parameters:
    ///   - product: The product to update
    ///   - image: Optional product image
    /// - Returns: Updated product
    func updateProduct(productId: String, product: Product, image: UIImage? = nil) async throws -> Product {
        guard let url = URL(string: "\(NetworkManager.baseURL)/update-food/\(productId)") else {
            throw NSError(domain: "ProductApi", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 60 // Increase timeout to 60 seconds
        
        // Add auth token if available
        if let token = AuthService.shared.getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Create boundary string for multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Create form data
        var formData = Data()
        
        // Get the correct restaurant ID
        let restaurantId: String
        
        // First try to get from UserDefaults which should have the most accurate restaurant ID
        if let storedRestaurantId = UserDefaults.standard.string(forKey: "restaurant_id"), !storedRestaurantId.isEmpty {
            restaurantId = storedRestaurantId
            DebugLogger.shared.log("Using restaurant ID from UserDefaults for update: \(restaurantId)", category: .network)
        }
        // If not in UserDefaults, use the provided product's restaurant ID
        else if !product.restaurantId.isEmpty {
            restaurantId = product.restaurantId
            DebugLogger.shared.log("Using product's restaurant ID for update: \(restaurantId)", category: .network)
        }
        // If still not found, try DataController
        else if !DataController.shared.restaurant.id.isEmpty {
            restaurantId = DataController.shared.restaurant.id
            DebugLogger.shared.log("Using DataController restaurant ID for update: \(restaurantId)", category: .network)
        }
        // Last resort, use the user ID
        else if let userId = AuthService.shared.getUserId() {
            restaurantId = userId
            DebugLogger.shared.log("Using user ID as fallback for restaurant ID in update: \(restaurantId)", category: .network)
        }
        else {
            throw NSError(domain: "ProductApi", code: 0, userInfo: [NSLocalizedDescriptionKey: "No restaurant ID available to update product"])
        }
        
        // Add text fields
        let textFields: [String: String] = [
            "product_name": product.name,
            "product_price": "\(product.price)",
            "food_category": product.category,
            "restaurant_id": restaurantId,
            "description": product.description,
            "extraTime": "\(product.extraTime)",
            "featured_Item": product.isFeatured ? "true" : "false"
        ]
        
        // Log the fields being sent (for debugging)
        DebugLogger.shared.log("Updating product \(productId) with restaurant ID: \(restaurantId)", category: .network)
        
        for (key, value) in textFields {
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            formData.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        // Add image if available - with compression like in createProduct
        if let image = image {
            if let imageData = compressImageToTinySize(image: image) {
                // Use the compressed image data
                formData.append("--\(boundary)\r\n".data(using: .utf8)!)
                formData.append("Content-Disposition: form-data; name=\"product_photo64Image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
                formData.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
                formData.append(imageData)
                formData.append("\r\n".data(using: .utf8)!)
                
                DebugLogger.shared.log("Adding compressed image to update request, size: \(imageData.count / 1024) KB", category: .network)
            } else {
                // Fallback to standard compression if our method fails
                if let standardData = image.jpegData(compressionQuality: 0.5) {
                    formData.append("--\(boundary)\r\n".data(using: .utf8)!)
                    formData.append("Content-Disposition: form-data; name=\"product_photo64Image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
                    formData.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
                    formData.append(standardData)
                    formData.append("\r\n".data(using: .utf8)!)
                    
                    DebugLogger.shared.log("Adding standard compressed image to update request, size: \(standardData.count / 1024) KB", category: .network)
                }
            }
        }
        
        // Add final boundary
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Set the request body
        request.httpBody = formData
        
        DebugLogger.shared.log("Updating product with ID: \(productId)", category: .network)
        DebugLogger.shared.log("PUT request to: \(url.absoluteString)", category: .network)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            if let responseString = String(data: data, encoding: .utf8) {
                DebugLogger.shared.log("Update product failed: \(responseString)", category: .error)
            }
            throw NSError(domain: "ProductApi", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to update product"])
        }
        
        // Log response
        if let responseString = String(data: data, encoding: .utf8) {
            DebugLogger.shared.log("Update product response: \(responseString)", category: .network)
        }
        
        // Create an updated product to return
        var updatedProduct = product
        updatedProduct.restaurantId = restaurantId
        updatedProduct.productPhoto = image // Set the updated image
        
        // Post notification that product was updated
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .productUpdated,
                object: nil,
                userInfo: ["productId": productId, "imageUpdated": image != nil]
            )
        }
        
        // Return the updated product
        return updatedProduct
    }
    
    // MARK: - Get All Products Methods 
    
    /// Get all products using direct URL approach - DEPRECATED
    /// Use getAllProducts() instead
    /// - Returns: Array of products
    func getAllProduct() async throws -> [Product] {
        return try await getAllProducts()
    }
    
    /// Get a single product by ID
    /// - Parameter productId: The ID of the product to fetch
    /// - Returns: The product if found, nil otherwise
    func getProduct(productId: String) async throws -> Product? {
        guard !productId.isEmpty else {
            DebugLogger.shared.log("Cannot fetch product with empty ID", category: .error)
            return nil
        }
        
        let productUrl = baseUrl.appendingPathComponent("get-product/\(productId)")
        var request = URLRequest(url: productUrl)
        
        // Add auth token if available
        if let token = AuthService.shared.getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        DebugLogger.shared.log("Fetching product with ID: \(productId)", category: .network)
        DebugLogger.shared.log("GET request to: \(productUrl.absoluteString)", category: .network)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DebugLogger.shared.log("Invalid response type", category: .error)
                return nil
            }
            
            // Check if we got a successful response
            if httpResponse.statusCode != 200 {
                if let responseString = String(data: data, encoding: .utf8) {
                    DebugLogger.shared.log("Failed to fetch product: \(responseString)", category: .error)
                }
                return nil
            }
            
            // Try to decode the product
            do {
                // First try to decode as a ProductResponse which might contain the product
                let productResponse = try JSONDecoder().decode(ProductResponse.self, from: data)
                if let product = productResponse.product {
                    DebugLogger.shared.log("Successfully decoded product: \(product.name)", category: .network)
                    return product
                } else if let products = productResponse.products, let firstProduct = products.first {
                    // Some APIs might return an array with a single product
                    DebugLogger.shared.log("Successfully decoded product from array: \(firstProduct.name)", category: .network)
                    return firstProduct
                }
                
                // If we have a success message but no product, log it
                if let message = productResponse.message {
                    DebugLogger.shared.log("API message: \(message)", category: .network)
                }
                
                // Try to decode directly as a Product
                let product = try JSONDecoder().decode(Product.self, from: data)
                DebugLogger.shared.log("Successfully decoded single product: \(product.name)", category: .network)
                return product
                
            } catch {
                DebugLogger.shared.log("Failed to decode product: \(error.localizedDescription)", category: .error)
                
                // Try to log the response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    DebugLogger.shared.log("Response data: \(responseString)", category: .network)
                }
                
                return nil
            }
        } catch {
            DebugLogger.shared.log("Network error: \(error.localizedDescription)", category: .error)
            throw error
        }
    }
    
    /// This method uses whatever ID is provided - for testing only
    /// You can remove this and update getCorrectRestaurantId() with the right logic once you identify the issue
    func getAllProductsWithTargetId(restaurantId: String) async throws -> [Product] {
        DebugLogger.shared.log("📱 RESTAURANT DETAIL: Starting product load for restaurant ID: \(restaurantId)", category: .network)
        DebugLogger.shared.log("⏱️ Time: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))", category: .network)
        
        // Use the restaurant ID (not user ID) for the API endpoint
        let productUrl = baseUrl.appendingPathComponent("get_all_product/\(restaurantId)")
        var request = URLRequest(url: productUrl)
        
        // Add auth token if available
        if let token = AuthService.shared.getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            DebugLogger.shared.log("Added auth token to request", category: .network, tag: "PRODUCT_API")
        }
        
        DebugLogger.shared.log("📡 Full URL: \(productUrl.absoluteString) (Server: \(productUrl.host ?? "unknown"))", category: .network)
        DebugLogger.shared.logRequest(request)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let string = String(data: data, encoding: .utf8) {
            DebugLogger.shared.log("📥 Response: \(string)", category: .network)
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            DebugLogger.shared.log("Invalid response: \(response)", category: .network, tag: "PRODUCT_API_ERROR")
            throw NSError(domain: "ProductApi", code: 0, userInfo: [NSLocalizedDescriptionKey: "Products not found"])
        }
        
        let decoder = JSONDecoder()
        
        do {
            let productResponse = try decoder.decode(ProductResponse.self, from: data)
            DebugLogger.shared.log("✅ Decoded \(productResponse.products?.count ?? 0) products using standard key 'products'", category: .network)
            
            // Log detailed results
            DebugLogger.shared.log("📋 RESTAURANT DETAIL: Fetched \(productResponse.products?.count ?? 0) products:", category: .network)
            if productResponse.products?.isEmpty ?? true {
                DebugLogger.shared.log("⚠️ No products returned for restaurant ID: \(restaurantId)", category: .network, tag: "EMPTY_PRODUCTS")
            } else {
                // Log the first 3 products as a sample
                let sampleProducts = productResponse.products?.prefix(3) ?? []
                for (index, product) in sampleProducts.enumerated() {
                    DebugLogger.shared.log("  \(index+1). \(product.name) (\(product.id)) - $\(product.price)", category: .network)
                }
                
                // Log categories
                let categories = Set(productResponse.products?.map { $0.category } ?? []).sorted()
                DebugLogger.shared.log("📋 Categories: \(categories.joined(separator: ", "))", category: .network)
            }
            
            DebugLogger.shared.log("✅ RESTAURANT DETAIL: Final \(productResponse.products?.count ?? 0) products:", category: .network)
            return productResponse.products ?? []
        } catch {
            DebugLogger.shared.log("Failed to decode product response: \(error.localizedDescription)", category: .error, tag: "PRODUCT_LOADING")
            
            // Try to decode just the array directly
            do {
                let products = try decoder.decode([Product].self, from: data)
                DebugLogger.shared.log("✅ Decoded \(products.count) products directly as array", category: .network)
                return products
            } catch {
                DebugLogger.shared.log("Failed final attempt to decode products: \(error.localizedDescription)", category: .error, tag: "PRODUCT_LOADING")
                throw error
            }
        }
    }
}

// Extension for MD5 hashing (for cache keys)
extension String {
    var md5: String {
        let data = Data(self.utf8)
        let hash = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5(bytes.baseAddress, CC_LONG(data.count), &hash)
            return hash
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
} 