import Foundation
import Combine
import UIKit

class RestaurantService: ObservableObject {
    static let shared = RestaurantService()
    
    // Published properties
    @Published var restaurant: Restaurant?
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    // API endpoints
    private struct Endpoints {
        static let baseURL = NetworkManager.baseURL
        static let restaurants = "\(baseURL)/restaurants"
        static let user = "\(baseURL)/restaurants/user"
        static let updateRestaurant = "\(baseURL)/update-restaurant"
        static let deleteRestaurant = "\(baseURL)" // The route is /delete-restaurant/:id
    }
    
    // Private properties
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        DebugLogger.shared.log("RestaurantService initialized", category: .app, tag: "INIT_SERVICE")
    }
    
    // MARK: - Public Methods
    
    /// Fetch restaurant by user ID
    /// - Parameter userId: The user ID
    func fetchRestaurantByUserId(userId: String) {
        isLoading = true
        error = nil
        
        let url = URL(string: "\(Endpoints.user)/\(userId)")!
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: RestaurantResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                switch completion {
                case .failure(let err):
                    self?.error = "Failed to load restaurant: \(err.localizedDescription)"
                    print("Error fetching restaurant: \(err)")
                case .finished:
                    break
                }
            } receiveValue: { [weak self] response in
                self?.restaurant = response.restaurant
            }
            .store(in: &cancellables)
    }
    
    /// Create a new restaurant
    /// - Parameters:
    ///   - restaurant: The restaurant to create
    ///   - completion: Completion handler with result
    func createRestaurant(restaurant: Restaurant, completion: @escaping (Result<Restaurant, Error>) -> Void) {
        isLoading = true
        error = nil
        
        guard let url = URL(string: Endpoints.restaurants) else {
            error = "Invalid URL"
            completion(.failure(NSError(domain: "RestaurantService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert restaurant to JSON data
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(restaurant)
        } catch {
            self.error = "Failed to encode restaurant: \(error.localizedDescription)"
            completion(.failure(error))
            return
        }
        
        // Send request
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: RestaurantResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                switch completion {
                case .failure(let err):
                    self?.error = "Failed to create restaurant: \(err.localizedDescription)"
                    print("Error creating restaurant: \(err)")
                case .finished:
                    break
                }
            } receiveValue: { [weak self] response in
                if let createdRestaurant = response.restaurant {
                    self?.restaurant = createdRestaurant
                    completion(.success(createdRestaurant))
                } else {
                    let error = NSError(domain: "RestaurantService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create restaurant"])
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                }
            }
            .store(in: &cancellables)
    }
    
    /// Update restaurant
    /// - Parameters:
    ///   - restaurant: The restaurant to update
    ///   - completion: Completion handler with result
    func updateRestaurant(restaurant: Restaurant, completion: @escaping (Result<Restaurant, Error>) -> Void) {
        isLoading = true
        error = nil
        
        guard let url = URL(string: "\(Endpoints.restaurants)/\(restaurant.id)") else {
            error = "Invalid URL"
            completion(.failure(NSError(domain: "RestaurantService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert restaurant to JSON data
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(restaurant)
        } catch {
            self.error = "Failed to encode restaurant: \(error.localizedDescription)"
            completion(.failure(error))
            return
        }
        
        // Send request
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure(let err) = completion {
                    self?.error = "Failed to update restaurant: \(err.localizedDescription)"
                    print("Error updating restaurant: \(err)")
                }
            } receiveValue: { [weak self] data in
                do {
                    // First try to decode as RestaurantResponse
                    let response = try JSONDecoder().decode(RestaurantResponse.self, from: data)
                    
                    if let updatedRestaurant = response.restaurant {
                        self?.restaurant = updatedRestaurant
                        completion(.success(updatedRestaurant))
                    } else {
                        // If restaurant is nil, try to see if we have a success message
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let success = json["success"] as? Bool, success == true {
                            // Success response without restaurant data, return the original restaurant
                            self?.restaurant = restaurant
                            completion(.success(restaurant))
                        } else {
                            // No success indicator, throw error
                            let error = NSError(domain: "RestaurantService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to update restaurant: No data returned"])
                            self?.error = error.localizedDescription
                            completion(.failure(error))
                        }
                    }
                } catch {
                    // Decoding failed, try to extract error message or success status
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Check if there's an error message
                        if let errorMsg = json["message"] as? String {
                            let error = NSError(domain: "RestaurantService", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                            self?.error = errorMsg
                            completion(.failure(error))
                        } 
                        // Check if there's a success status
                        else if let success = json["success"] as? Bool, success == true {
                            // Success response without proper data format, return the original restaurant
                            self?.restaurant = restaurant
                            completion(.success(restaurant))
                        } else {
                            // No useful information, log the raw data for debugging
                            if let dataString = String(data: data, encoding: .utf8) {
                                print("Raw response data: \(dataString)")
                            }
                            
                            let error = NSError(domain: "RestaurantService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse server response"])
                            self?.error = "Failed to parse server response"
                            completion(.failure(error))
                        }
                    } else {
                        // Completely invalid JSON
                        let error = NSError(domain: "RestaurantService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                        self?.error = "Invalid response format"
                        completion(.failure(error))
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /// Compress image to target size (approximately 50KB)
    /// - Parameters:
    ///   - image: The original UIImage
    ///   - targetSizeKB: Target size in kilobytes (default: 50)
    /// - Returns: Data object of the compressed image
    private func compressImageToTargetSize(image: UIImage, targetSizeKB: Int = 50) -> Data? {
        // First resize the image to reasonable dimensions
        let maxSize: CGFloat = 600 // Reduced from 800
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
        
        // Start with 0.5 compression quality (more aggressive than 0.7)
        var compression: CGFloat = 0.5
        var imageData = processedImage.jpegData(compressionQuality: compression)!
        
        // Binary search to find best compression quality to meet target size
        var max: CGFloat = 1.0
        var min: CGFloat = 0.0
        
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
        
        print("Final image size: \(imageData.count / 1024) KB with compression \(compression)")
        return imageData
    }
    
    /// Upload restaurant banner image
    /// - Parameters:
    ///   - restaurantId: The restaurant ID
    ///   - image: The image to upload
    ///   - completion: Completion handler with result
    func uploadRestaurantImage(restaurantId: String, image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        isLoading = true
        error = nil
        
        guard let url = URL(string: "\(Endpoints.restaurants)/\(restaurantId)/banner") else {
            error = "Invalid URL"
            completion(.failure(NSError(domain: "RestaurantService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        // Compress image to approximately 100KB
        guard let imageData = compressImageToTargetSize(image: image) else {
            error = "Failed to convert image to data"
            completion(.failure(NSError(domain: "RestaurantService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])))
            return
        }
        
        let base64String = imageData.base64EncodedString()
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create body
        let body: [String: Any] = ["bannerPhoto64Image": base64String]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            self.error = "Failed to encode image data: \(error.localizedDescription)"
            completion(.failure(error))
            return
        }
        
        // Log the request for debugging
        print("Sending image upload request to: \(url.absoluteString)")
        print("Image data size: \(imageData.count) bytes")
        
        // Send request
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure(let err) = completion {
                    self?.error = "Failed to upload image: \(err.localizedDescription)"
                    print("Error uploading image: \(err)")
                }
            } receiveValue: { [weak self] data in
                // Log the raw response for debugging
                if let dataString = String(data: data, encoding: .utf8) {
                    print("Image upload response: \(dataString)")
                }
                
                do {
                    // Try to parse as JSON
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Check for success indicators
                        if let imageUrl = json["bannerUrl"] as? String {
                            // Got a direct URL
                            completion(.success(imageUrl))
                        } else if let success = json["success"] as? Bool, success == true {
                            // Got a success flag
                            completion(.success("Image uploaded successfully"))
                        } else if let message = json["message"] as? String {
                            // Got an error message
                            self?.error = message
                            completion(.failure(NSError(domain: "RestaurantService", code: 1, userInfo: [NSLocalizedDescriptionKey: message])))
                        } else {
                            // No clear success or error indicators, but valid JSON
                            completion(.success("Image upload completed"))
                        }
                    } else {
                        // Not valid JSON
                        throw NSError(domain: "RestaurantService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                    }
                } catch {
                    self?.error = "Failed to parse upload response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
            .store(in: &cancellables)
    }
    
    /// Register a new restaurant
    /// - Parameters:
    ///   - userId: The user ID
    ///   - restaurantName: The restaurant name
    ///   - cuisine: The cuisine type
    ///   - estimatedTime: The estimated time in minutes
    ///   - bannerImage: The banner image
    ///   - completion: Completion handler with result
    func registerRestaurant(userId: String, restaurantName: String, cuisine: String, estimatedTime: Int, bannerImage: UIImage?, completion: @escaping (Result<String, Error>) -> Void) {
        isLoading = true
        error = nil
        
        guard let url = URL(string: "\(NetworkManager.baseURL)/register-restaurant") else {
            error = "Invalid URL"
            completion(.failure(NSError(domain: "RestaurantService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare form data
        var formData: [String: Any] = [
            "userId": userId,
            "restaurant_Name": restaurantName,
            "cuisines": cuisine,
            "estimatedTime": estimatedTime
        ]
        
        // Convert image to Base64
        if let image = bannerImage {
            // Compress image to approximately 100KB
            if let imageData = compressImageToTargetSize(image: image) {
                let base64String = imageData.base64EncodedString()
                formData["bannerPhoto64Image"] = base64String
                print("Image data size: \(imageData.count) bytes")
            } else {
                print("Error: Failed to convert image to JPEG data")
            }
        }
        
        // Convert form data to JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: formData)
        } catch {
            self.error = "Failed to encode restaurant data: \(error.localizedDescription)"
            completion(.failure(error))
            return
        }
        
        // Log the request for debugging
        print("Sending restaurant registration request to: \(url.absoluteString)")
        
        // Send request
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    let error = NSError(domain: "RestaurantService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                
                // Log the raw response for debugging
                if let dataString = String(data: data, encoding: .utf8) {
                    print("Restaurant registration response: \(dataString)")
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let restaurantId = json["_id"] as? String {
                            // Registration successful
                            completion(.success(restaurantId))
                        } else if let errorMsg = json["message"] as? String {
                            // Server returned an error message
                            let error = NSError(domain: "RestaurantService", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                            self?.error = errorMsg
                            completion(.failure(error))
                        } else {
                            // Unknown response format
                            let error = NSError(domain: "RestaurantService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unknown server response"])
                            self?.error = "Unknown server response"
                            completion(.failure(error))
                        }
                    } else {
                        // Invalid JSON
                        let error = NSError(domain: "RestaurantService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                        self?.error = "Invalid response format"
                        completion(.failure(error))
                    }
                } catch {
                    // JSON parsing error
                    self?.error = "Failed to parse response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    /// Register a new restaurant using multipart form data (alternative method for handling large images)
    /// - Parameters:
    ///   - userId: The user ID
    ///   - restaurantName: The restaurant name
    ///   - cuisine: The cuisine type
    ///   - estimatedTime: The estimated time in minutes
    ///   - bannerImage: The banner image
    ///   - completion: Completion handler with result
    func registerRestaurantWithMultipart(userId: String, restaurantName: String, cuisine: String, estimatedTime: Int, bannerImage: UIImage?, completion: @escaping (Result<String, Error>) -> Void) {
        isLoading = true
        error = nil
        
        guard let url = URL(string: "\(NetworkManager.baseURL)/register-restaurant") else {
            error = "Invalid URL"
            completion(.failure(NSError(domain: "RestaurantService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        // Generate a boundary string for multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Create multipart form body
        var body = Data()
        
        // Function to add text field
        func appendTextField(fieldName: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(fieldName)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        // Add text fields
        appendTextField(fieldName: "userId", value: userId)
        appendTextField(fieldName: "restaurant_Name", value: restaurantName)
        appendTextField(fieldName: "cuisines", value: cuisine)
        appendTextField(fieldName: "estimatedTime", value: String(estimatedTime))
        
        // Add image if available - using a MUCH lower compression to ensure small file size
        if let image = bannerImage, let imageData = image.jpegData(compressionQuality: 0.01) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"bannerPhoto64Image\"; filename=\"restaurant.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
            
            print("Image data size (using direct multipart): \(imageData.count / 1024) KB")
        }
        
        // Add final boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Set request body
        request.httpBody = body
        
        // Log the request for debugging
        print("Sending multipart restaurant registration request to: \(url.absoluteString)")
        
        // Send request
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    let error = NSError(domain: "RestaurantService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                
                // Log the raw response for debugging
                if let dataString = String(data: data, encoding: .utf8) {
                    print("Restaurant multipart registration response: \(dataString)")
                }
                
                // For this response, the successful response might just be the restaurant ID as a string
                if let restaurantId = String(data: data, encoding: .utf8), !restaurantId.isEmpty, restaurantId.count > 5 {
                    // Success case where the response is just the restaurant ID
                    completion(.success(restaurantId))
                    return
                }
                
                do {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let restaurantId = json["_id"] as? String {
                            // Registration successful
                            completion(.success(restaurantId))
                        } else if let errorMsg = json["message"] as? String {
                            // Server returned an error message
                            let error = NSError(domain: "RestaurantService", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                            self?.error = errorMsg
                            completion(.failure(error))
                        } else {
                            // Unknown response format
                            let error = NSError(domain: "RestaurantService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unknown server response"])
                            self?.error = "Unknown server response"
                            completion(.failure(error))
                        }
                    } else {
                        // Not valid JSON - could be an HTML error page
                        let errorDescription = String(data: data, encoding: .utf8) ?? "Unknown error"
                        let error = NSError(domain: "RestaurantService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response format: \(errorDescription)"])
                        self?.error = "Invalid response format"
                        completion(.failure(error))
                    }
                } catch {
                    // JSON parsing error
                    self?.error = "Failed to parse response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    // MARK: - Restaurant Image Loading
    
    /// Fetch restaurant image
    /// - Parameters:
    ///   - restaurantId: The restaurant ID
    ///   - completion: Completion handler with optional UIImage
    func fetchRestaurantImage(restaurantId: String, completion: @escaping (UIImage?) -> Void) {
        // First, check if this is the user ID instead of the restaurantId
        // Try to get the actual restaurant ID from the DataController or UserDefaults
        var targetRestaurantId = restaurantId
        
        // Try to get from DataController first
        if !DataController.shared.restaurant.id.isEmpty && DataController.shared.restaurant.id != restaurantId {
            targetRestaurantId = DataController.shared.restaurant.id
            DebugLogger.shared.log("Using restaurant ID from DataController instead: \(targetRestaurantId)", category: .network, tag: "FETCH_RESTAURANT_IMAGE")
        }
        
        // Try to get from UserDefaults if still using the original ID
        if targetRestaurantId == restaurantId, let storedRestaurantId = UserDefaults.standard.string(forKey: "restaurant_id"), !storedRestaurantId.isEmpty {
            targetRestaurantId = storedRestaurantId
            DebugLogger.shared.log("Using restaurant ID from UserDefaults instead: \(targetRestaurantId)", category: .network, tag: "FETCH_RESTAURANT_IMAGE")
        }
        
        // Try multiple endpoint formats with the correct restaurant ID
        let endpoints = [
            "\(NetworkManager.baseURL)/get_restaurant_photo/\(targetRestaurantId)",
            "\(NetworkManager.baseURL)/restaurants/\(targetRestaurantId)/photo",
            "\(NetworkManager.baseURL)/restaurant_photo/\(targetRestaurantId)",
            "\(NetworkManager.baseURL)/restaurant/\(targetRestaurantId)/image"
        ]
        
        // Try loading with a placeholder image if all else fails
        var loadAttempted = false
        
        for endpointString in endpoints {
            guard let url = URL(string: endpointString) else { continue }
            
            DebugLogger.shared.log("Attempting to fetch restaurant image from: \(url.absoluteString)", category: .network, tag: "FETCH_RESTAURANT_IMAGE")
            
            loadAttempted = true
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    DebugLogger.shared.logError(error, tag: "RESTAURANT_IMAGE_FETCH")
                    // Continue with next endpoint if this one fails
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else { return }
                
                // Check if we got a successful response
                if (200...299).contains(httpResponse.statusCode), let data = data, let image = UIImage(data: data) {
                    DebugLogger.shared.log("Successfully fetched restaurant image from \(url.absoluteString)", category: .network, tag: "RESTAURANT_IMAGE_FETCH")
                    DispatchQueue.main.async {
                        completion(image)
                    }
                    return
                }
            }.resume()
        }
        
        // If we couldn't find a valid endpoint or no image was loaded, use a default image
        if !loadAttempted || true {
            DebugLogger.shared.log("Using default restaurant image", category: .network, tag: "RESTAURANT_IMAGE_FETCH")
            let defaultImage = UIImage(systemName: "building.2.fill")?.withTintColor(.green, renderingMode: .alwaysOriginal)
            DispatchQueue.main.async {
                completion(defaultImage)
            }
        }
    }
    
    /// Update restaurant with multipart form data
    /// - Parameters:
    ///   - userId: The user ID
    ///   - restaurantId: The restaurant ID
    ///   - restaurantName: The restaurant name
    ///   - cuisine: The cuisine type
    ///   - estimatedTime: The estimated time in minutes
    ///   - bannerImage: The banner image
    ///   - completion: Completion handler with result
    func updateRestaurantWithMultipart(userId: String, restaurantId: String, restaurantName: String, cuisine: String, estimatedTime: Int, bannerImage: UIImage?, completion: @escaping (Result<String, Error>) -> Void) {
        isLoading = true
        error = nil
        
        guard let url = URL(string: Endpoints.updateRestaurant) else {
            error = "Invalid URL"
            completion(.failure(NSError(domain: "RestaurantService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        // Generate a boundary string for multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Create multipart form body
        var body = Data()
        
        // Function to add text field
        func appendTextField(fieldName: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(fieldName)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        // Add text fields
        appendTextField(fieldName: "userId", value: userId)
        appendTextField(fieldName: "restaurant_Name", value: restaurantName)
        appendTextField(fieldName: "cuisines", value: cuisine)
        appendTextField(fieldName: "estimatedTime", value: String(estimatedTime))
        
        // Add image if available - using a lower compression to ensure small file size
        if let image = bannerImage, let imageData = image.jpegData(compressionQuality: 0.6) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"bannerPhoto64Image\"; filename=\"restaurant.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // End the form data
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Set the body of the request
        request.httpBody = body
        
        // Log the request
        DebugLogger.shared.log("Sending update restaurant request to: \(url.absoluteString)", category: .network)
        
        // Send the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.error = "Failed to update restaurant: \(error.localizedDescription)"
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    let error = NSError(domain: "RestaurantService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                    self.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                
                // Log the response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    DebugLogger.shared.log("Restaurant update response: \(responseString)", category: .network)
                }
                
                do {
                    // Try to parse the response
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let message = json["message"] as? String {
                            DebugLogger.shared.log("Restaurant update message: \(message)", category: .network)
                            
                            // If message contains "updated" or we have an ID, consider it a success
                            if message.contains("updated") || json["id"] != nil {
                                if let id = json["id"] as? String {
                                    completion(.success(id))
                                } else {
                                    completion(.success(restaurantId))
                                }
                                return
                            }
                        }
                        
                        // Look for success status
                        if let success = json["success"] as? Bool, success == true {
                            // If we have a restaurant ID in the response, use it
                            if let id = json["id"] as? String {
                                completion(.success(id))
                            } else {
                                // Otherwise, return the original restaurant ID
                                completion(.success(restaurantId))
                            }
                        } else {
                            // Check for error message
                            if let errorMessage = json["error"] as? String {
                                let error = NSError(domain: "RestaurantService", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                                self.error = errorMessage
                                completion(.failure(error))
                            } else {
                                let error = NSError(domain: "RestaurantService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to update restaurant"])
                                self.error = "Failed to update restaurant"
                                completion(.failure(error))
                            }
                        }
                    } else {
                        // Not valid JSON
                        throw NSError(domain: "RestaurantService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                    }
                } catch {
                    self.error = "Failed to parse update response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    /// Delete a restaurant
    /// - Parameters:
    ///   - restaurantId: The restaurant ID to delete
    ///   - completion: Completion handler with result
    func deleteRestaurant(restaurantId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        print("DELETE RESTAURANT CALLED with ID: \(restaurantId)")
        isLoading = true
        error = nil
        
        // Define a recursive helper to try multiple URL formats
        func tryDeleteWithUrlFormat(urlIndex: Int) {
            // Construct the URL with fallbacks
            let urlOptions = [
                "\(NetworkManager.baseURL)/delete-restaurant/\(restaurantId)",
                "\(NetworkManager.baseURL)/restaurants/delete/\(restaurantId)",
                "\(NetworkManager.baseURL)/restaurants/\(restaurantId)"  // Some APIs use DELETE on the resource URL
            ]
            
            // If we've tried all URLs, give up
            if urlIndex >= urlOptions.count {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.error = "Failed to delete restaurant: No valid endpoint found"
                    completion(.failure(NSError(domain: "RestaurantService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No valid endpoint found"])))
                }
                return
            }
            
            guard let url = URL(string: urlOptions[urlIndex]) else {
                // Try next URL format
                tryDeleteWithUrlFormat(urlIndex: urlIndex + 1)
                return
            }
            
            // Create request
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            
            // Log the request
            DebugLogger.shared.log("Sending delete restaurant request to: \(url.absoluteString)", category: .network)
            
            // Print to console for immediate debugging
            print("DELETE REQUEST URL: \(url.absoluteString)")
            print("Deleting restaurant with ID: \(restaurantId)")
            
            // Send the request
            URLSession.shared.dataTask(with: request) { data, response, error in
                // Log HTTP response details
                if let httpResponse = response as? HTTPURLResponse {
                    print("DELETE RESPONSE STATUS: \(httpResponse.statusCode)")
                    DebugLogger.shared.log("Delete restaurant HTTP status: \(httpResponse.statusCode)", category: .network, tag: "DELETE_RESTAURANT")
                    
                    // If we got a 404 or other error, try the next URL
                    if httpResponse.statusCode >= 400 && urlIndex + 1 < urlOptions.count {
                        tryDeleteWithUrlFormat(urlIndex: urlIndex + 1)
                        return
                    }
                }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        // If network error, try the next URL
                        if urlIndex + 1 < urlOptions.count {
                            tryDeleteWithUrlFormat(urlIndex: urlIndex + 1)
                            return
                        }
                        
                        self.error = "Failed to delete restaurant: \(error.localizedDescription)"
                        completion(.failure(error))
                        return
                    }
                    
                    guard let data = data else {
                        if urlIndex + 1 < urlOptions.count {
                            tryDeleteWithUrlFormat(urlIndex: urlIndex + 1)
                            return
                        }
                        
                        let error = NSError(domain: "RestaurantService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                        self.error = error.localizedDescription
                        completion(.failure(error))
                        return
                    }
                    
                    // Log the response for debugging
                    if let responseString = String(data: data, encoding: .utf8) {
                        DebugLogger.shared.log("Restaurant delete response: \(responseString)", category: .network)
                        print("DELETE RESPONSE BODY: \(responseString)")
                        
                        // If the response is just plain text "success" or similar, consider it a success
                        if responseString.lowercased().contains("success") || 
                           responseString.lowercased().contains("deleted") {
                            self.handleSuccessfulDeletion(completion: completion)
                            return
                        }
                    }
                    
                    do {
                        // Try to parse the response
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            // Consider either "success": true or "message" containing "deleted" as a success
                            let isSuccess = (json["success"] as? Bool == true) || 
                                           (json["message"] as? String)?.contains("deleted") == true
                            
                            if isSuccess {
                                self.handleSuccessfulDeletion(completion: completion)
                                return
                            } else {
                                // Check for error message
                                if let errorMessage = json["error"] as? String {
                                    // If it's a not found error, try the next URL
                                    if errorMessage.lowercased().contains("not found") && urlIndex + 1 < urlOptions.count {
                                        tryDeleteWithUrlFormat(urlIndex: urlIndex + 1)
                                        return
                                    }
                                    
                                    let error = NSError(domain: "RestaurantService", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                                    self.error = errorMessage
                                    completion(.failure(error))
                                } else {
                                    // Try next URL if we haven't exhausted them
                                    if urlIndex + 1 < urlOptions.count {
                                        tryDeleteWithUrlFormat(urlIndex: urlIndex + 1)
                                        return
                                    }
                                    
                                    let error = NSError(domain: "RestaurantService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to delete restaurant"])
                                    self.error = "Failed to delete restaurant"
                                    completion(.failure(error))
                                }
                            }
                        } else {
                            // Not valid JSON, try next URL
                            if urlIndex + 1 < urlOptions.count {
                                tryDeleteWithUrlFormat(urlIndex: urlIndex + 1)
                                return
                            }
                            
                            throw NSError(domain: "RestaurantService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                        }
                    } catch {
                        // Log the raw response for debugging
                        DebugLogger.shared.logError(error, tag: "DELETE_RESTAURANT_PARSE")
                        if let responseString = String(data: data, encoding: .utf8) {
                            DebugLogger.shared.log("Failed to parse response: \(responseString)", category: .network, tag: "DELETE_RESTAURANT_RAW")
                        }
                        
                        // Try next URL if available
                        if urlIndex + 1 < urlOptions.count {
                            tryDeleteWithUrlFormat(urlIndex: urlIndex + 1)
                            return
                        }
                        
                        self.error = "Failed to parse delete response: \(error.localizedDescription)"
                        completion(.failure(error))
                    }
                }
            }.resume()
        }
        
        // Start trying URL formats
        tryDeleteWithUrlFormat(urlIndex: 0)
    }
    
    /// Helper method to handle successful restaurant deletion
    /// - Parameter completion: The completion handler to call with success result
    func handleSuccessfulDeletion(completion: @escaping (Result<Bool, Error>) -> Void) {
        // Clear restaurant ID but maintain user ID
        UserDefaults.standard.removeObject(forKey: "restaurant_id")
        UserDefaults.standard.set(false, forKey: "is_restaurant_registered")
        
        // Post notification that restaurant was deleted
        NotificationCenter.default.post(name: NSNotification.Name("RestaurantDeleted"), object: nil)
        
        // Success
        completion(.success(true))
    }
}

// Response for restaurant data
struct RestaurantResponse: Codable {
    var restaurant: Restaurant?
    
    enum CodingKeys: String, CodingKey {
        case restaurant
    }
} 