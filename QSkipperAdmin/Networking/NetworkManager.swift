import Foundation
import UIKit
// Import our debugging utilities
import SwiftUI

enum NetworkError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case decodingFailed(Error)
    case serverError(String)
    case unauthorized
    case notFound
    case imageNotFound
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let message):
            return message
        case .unauthorized:
            return "Unauthorized access"
        case .notFound:
            return "Resource not found"
        case .imageNotFound:
            return "Image not found or could not be loaded"
        }
    }
}

class NetworkManager {
    static let shared = NetworkManager()
    
    // Changed to static and public so it can be accessed from other classes
    #if DEBUG
    static let baseURL = "https://qskipper-server-2ul5.onrender.com"
    #else
    static let baseURL = "https://qskipper-server-2ul5.onrender.com"
    #endif
    private var authToken: String?
    
    // Image cache
    private let imageCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private lazy var cacheDirectory: URL = {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDir = documentsDirectory.appendingPathComponent("ImageCache")
        
        do {
            try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Error creating cache directory: \(error.localizedDescription)")
        }
        
        return cacheDir
    }()
    
    // Custom URLSession that allows insecure localhost connections
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        
        // For development purposes, allow insecure localhost connections
        if NetworkManager.baseURL.contains("localhost") {
            class LocalhostTrustingDelegate: NSObject, URLSessionDelegate {
                func urlSession(_ session: URLSession, 
                               didReceive challenge: URLAuthenticationChallenge, 
                               completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                    
                    // Accept certificates for localhost connections
                    if challenge.protectionSpace.host.contains("localhost") {
                        let credential = URLCredential(trust: challenge.protectionSpace.serverTrust!)
                        completionHandler(.useCredential, credential)
                    } else {
                        completionHandler(.performDefaultHandling, nil)
                    }
                }
            }
            
            return URLSession(configuration: config, delegate: LocalhostTrustingDelegate(), delegateQueue: nil)
        } else {
            return URLSession(configuration: config)
        }
    }()
    
    private init() {
        DebugLogger.shared.log("NetworkManager initialized", category: .app)
        DebugLogger.shared.log("Base URL configured as: \(NetworkManager.baseURL)", category: .network)
    }
    
    // Set auth token after login
    func setAuthToken(_ token: String) {
        self.authToken = token
        DebugLogger.shared.logAuthEvent("Auth token set", details: "Token length: \(token.count)")
    }
    
    // Clear auth token on logout
    func clearAuthToken() {
        self.authToken = nil
        DebugLogger.shared.logAuthEvent("Auth token cleared")
    }
    
    // Endpoint mapping to ensure correct API paths
    private func mapEndpoint(_ endpoint: String) -> String {
        DebugLogger.shared.log("Mapping endpoint: \(endpoint)", category: .network)
        
        // Mapping for API endpoints to match the server routes
        let endpointMappings: [String: String] = [
            "/resturant-register": "/resturant-register",
            "/register-restaurant": "/resturant-register",
            "/resturant-login": "/resturant-login",
            "/add-product": "/create-product",
            "/get_all_product/": "/get_all_product/",
            "/update-product/": "/update-product/",
            "/delete-product/": "/delete-product/",
            "/get-order/": "/get-order/",
            "/order-complete/": "/order-complete/",
            "/upload-image": "/upload-image",
            "/update-restaurant": "/update-restaurant",
            "/delete-restaurant/": "/delete-restaurant/"
        ]
        
        // Check if there's a direct mapping for the endpoint
        for (key, value) in endpointMappings {
            if endpoint.hasPrefix(key) {
                let mapped = endpoint.replacingOccurrences(of: key, with: value)
                DebugLogger.shared.log("Mapped endpoint from \(endpoint) to \(mapped)", category: .network)
                return mapped
            }
        }
        
        // Return original if no mapping exists
        DebugLogger.shared.log("No mapping found for endpoint: \(endpoint), using as is", category: .network)
        return endpoint
    }
    
    // MARK: - Generic Network Request
    func performRequest<T: Decodable>(endpoint: String, method: String, body: [String: Any]? = nil) async throws -> T {
        let mappedEndpoint = mapEndpoint(endpoint)
        
        guard let url = URL(string: NetworkManager.baseURL + mappedEndpoint) else {
            let error = NetworkError.invalidURL
            DebugLogger.shared.logError(error, tag: "URL_CONSTRUCTION")
            throw error
        }
        
        // Log full request URL
        DebugLogger.shared.log("API Request: \(method) \(url.absoluteString)", category: .network, tag: "API_CALL")
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            DebugLogger.shared.log("Added auth token to request", category: .network)
        }
        
        if let body = body {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: body)
                request.httpBody = jsonData
                
                if let bodyString = String(data: jsonData, encoding: .utf8) {
                    DebugLogger.shared.log("Request body: \(bodyString)", category: .network, tag: "REQUEST_BODY")
                }
                
                DebugLogger.shared.log("Request body serialized successfully", category: .network)
            } catch {
                DebugLogger.shared.logError(error, tag: "BODY_SERIALIZATION")
                throw NetworkError.requestFailed(error)
            }
        }
        
        DebugLogger.shared.logRequest(request)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            // Enhanced response logging
            if let httpResponse = response as? HTTPURLResponse {
                DebugLogger.shared.log("API Response: Status \(httpResponse.statusCode) from \(url.absoluteString)", category: .network, tag: "API_RESPONSE")
                
                // Log response headers for debugging
                let headerLog = httpResponse.allHeaderFields.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                DebugLogger.shared.log("Response Headers:\n\(headerLog)", category: .network, tag: "RESPONSE_HEADERS")
            }
            
            // Log raw response for debugging
            if let rawString = String(data: data, encoding: .utf8) {
                DebugLogger.shared.log("Raw API response: \(rawString)", category: .network, tag: "API_RESPONSE_BODY")
            }
            
            DebugLogger.shared.logResponse(data: data, response: response, error: nil as Error?)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NetworkError.invalidResponse
                DebugLogger.shared.logError(error, tag: "INVALID_HTTP_RESPONSE")
                throw error
            }
            
            DebugLogger.shared.log("Got HTTP response with status code: \(httpResponse.statusCode)", category: .network)
            
            switch httpResponse.statusCode {
            case 200...299:
                do {
                    // Check if we're trying to decode UserResponse which needs special handling for restaurant login
                    if T.self == UserResponse.self {
                        // First try normal decoding
                        do {
                            let decoder = JSONDecoder()
                            let result = try decoder.decode(T.self, from: data)
                            DebugLogger.shared.log("Successfully decoded response to \(T.self)", category: .network)
                            return result
                        } catch {
                            // If regular decoding fails, try manual approach for restaurant login
                            DebugLogger.shared.log("Regular decoding failed, trying manual approach for restaurant login", category: .network)
                            
                            // Try to parse as dictionary
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                // Create a manually constructed response using the helper method
                                let userResponse = UserResponse.createFromRestaurantResponse(json: json)
                                
                                DebugLogger.shared.log("Created UserResponse manually for restaurant login", category: .network)
                                return userResponse as! T
                            }
                            
                            // If all parsing attempts fail, throw the original error
                            throw error
                        }
                    } else {
                        // For other types, use standard decoding
                        let decoder = JSONDecoder()
                        let result = try decoder.decode(T.self, from: data)
                        DebugLogger.shared.log("Successfully decoded response to \(T.self)", category: .network)
                        return result
                    }
                } catch {
                    DebugLogger.shared.logError(error, tag: "JSON_DECODING")
                    if let dataString = String(data: data, encoding: .utf8) {
                        DebugLogger.shared.log("Raw response data: \(dataString)", category: .network, tag: "DECODING_FAILED_DATA")
                    }
                    throw NetworkError.decodingFailed(error)
                }
            case 401:
                let error = NetworkError.unauthorized
                DebugLogger.shared.logError(error, tag: "UNAUTHORIZED")
                throw error
            case 404:
                let error = NetworkError.notFound
                DebugLogger.shared.logError(error, tag: "NOT_FOUND")
                throw error
            default:
                var errorMessage = "Server error with status code: \(httpResponse.statusCode)"
                
                if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
                   let message = errorResponse["message"] {
                    errorMessage = message
                    DebugLogger.shared.log("Server error message: \(message)", category: .network, tag: "SERVER_ERROR")
                } else if let dataString = String(data: data, encoding: .utf8) {
                    DebugLogger.shared.log("Raw error response: \(dataString)", category: .network, tag: "SERVER_ERROR_RAW")
                }
                
                let error = NetworkError.serverError(errorMessage)
                DebugLogger.shared.logError(error, tag: "SERVER_ERROR")
                throw error
            }
        } catch let error as NetworkError {
            DebugLogger.shared.logError(error, tag: "NETWORK_ERROR")
            throw error
        } catch {
            DebugLogger.shared.logError(error, tag: "NETWORK_ERROR")
            throw NetworkError.requestFailed(error)
        }
    }
    
    // MARK: - Upload Image
    func uploadImage(imageData: Data, endpoint: String) async throws -> [String: Any] {
        DebugLogger.shared.log("Starting image upload, data size: \(imageData.count) bytes", category: .network)
        
        let mappedEndpoint = mapEndpoint(endpoint)
        guard let url = URL(string: NetworkManager.baseURL + mappedEndpoint) else {
            let error = NetworkError.invalidURL
            DebugLogger.shared.logError(error, tag: "IMAGE_UPLOAD_URL")
            throw error
        }
        
        let boundary = UUID().uuidString
        DebugLogger.shared.log("Using multipart boundary: \(boundary)", category: .network)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            DebugLogger.shared.log("Added auth token to image upload request", category: .network)
        }
        
        var body = Data()
        
        // Add image data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End multipart form
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        DebugLogger.shared.log("Image upload request prepared with body size: \(body.count) bytes", category: .network)
        DebugLogger.shared.logRequest(request)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            DebugLogger.shared.logResponse(data: data, response: response, error: nil as Error?)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NetworkError.invalidResponse
                DebugLogger.shared.logError(error, tag: "IMAGE_UPLOAD_RESPONSE")
                throw error
            }
            
            DebugLogger.shared.log("Image upload HTTP response with status code: \(httpResponse.statusCode)", category: .network)
            
            guard (200...299).contains(httpResponse.statusCode) else {
                var errorMessage = "Server error with status code: \(httpResponse.statusCode)"
                
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errorJson["message"] as? String {
                    errorMessage = message
                    DebugLogger.shared.log("Image upload server error message: \(message)", category: .network, tag: "IMAGE_UPLOAD_ERROR")
                }
                
                let error = NetworkError.serverError(errorMessage)
                DebugLogger.shared.logError(error, tag: "IMAGE_UPLOAD_ERROR")
                throw error
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    let error = NetworkError.decodingFailed(NSError(domain: "JSONParsing", code: 0))
                    DebugLogger.shared.logError(error, tag: "IMAGE_UPLOAD_JSON_PARSING")
                    throw error
                }
                
                DebugLogger.shared.log("Image upload successful, response received", category: .network)
                return json
            } catch {
                DebugLogger.shared.logError(error, tag: "IMAGE_UPLOAD_JSON_PARSING")
                throw NetworkError.decodingFailed(error)
            }
        } catch {
            DebugLogger.shared.logError(error, tag: "IMAGE_UPLOAD_REQUEST_FAILED")
            throw NetworkError.requestFailed(error)
        }
    }
    
    // MARK: - Alternative API methods using the approach from the provided Networking class
    
    func registerRestaurantDirect(currentUser: UserAuth) async throws -> User? {
        DebugLogger.shared.log("Using direct registration method for restaurant with email: \(currentUser.email)", category: .network)
        
        let registerUrl = URL(string: NetworkManager.baseURL + "/resturant-register")!
        var request = URLRequest(url: registerUrl)
        
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsonEncoder = JSONEncoder()
        let jsonData = try? jsonEncoder.encode(currentUser)
        request.httpBody = jsonData
        
        DebugLogger.shared.logRequest(request)
        
        let (data, response) = try await urlSession.data(for: request)
        DebugLogger.shared.logResponse(data: data, response: response, error: nil as Error?)
        
        if let string = String(data: data, encoding: .utf8) {
            DebugLogger.shared.log("Raw response: \(string)", category: .network)
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202 || httpResponse.statusCode == 200 else {
            let error = NetworkError.serverError("Registration failed with unexpected status code")
            DebugLogger.shared.logError(error, tag: "DIRECT_REGISTRATION")
            throw error
        }
        
        // The server is returning just an ID, not a full User object
        // Let's create a minimal User object with this ID
        do {
            // Try to decode the response as a simple ID response
            struct IDResponse: Codable {
                let id: String
            }
            
            let idResponse = try JSONDecoder().decode(IDResponse.self, from: data)
            
            // Create a User object with the ID and email
            let user = User(
                id: idResponse.id,
                name: "",  // Default values for required fields
                email: currentUser.email,
                restaurantName: nil,
                restaurantAddress: nil,
                phone: nil,
                restaurantId: idResponse.id  // Use the ID as restaurantId as well
            )
            
            DebugLogger.shared.log("Direct registration successful, created user with ID: \(idResponse.id)", category: .network)
            return user
            
        } catch {
            DebugLogger.shared.logError(error, tag: "DIRECT_REGISTRATION_PARSING")
            throw error
        }
    }
    
    func loginRestaurantDirect(currentUser: UserAuth) async throws -> UserResponse? {
        DebugLogger.shared.log("Using direct login method for restaurant with email: \(currentUser.email)", category: .network)
        
        let loginUrl = URL(string: NetworkManager.baseURL + "/resturant-login")!
        var request = URLRequest(url: loginUrl)
        
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsonEncoder = JSONEncoder()
        let jsonData = try? jsonEncoder.encode(currentUser)
        request.httpBody = jsonData
        
        DebugLogger.shared.logRequest(request)
        
        let (data, response) = try await urlSession.data(for: request)
        DebugLogger.shared.logResponse(data: data, response: response, error: nil as Error?)
        
        if let string = String(data: data, encoding: .utf8) {
            DebugLogger.shared.log("Raw login response: \(string)", category: .network)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        // Handle error status codes
        if httpResponse.statusCode == 401 {
            throw NetworkError.unauthorized
        } else if httpResponse.statusCode == 404 {
            throw NetworkError.notFound
        } else if httpResponse.statusCode >= 400 {
            // Try to extract error message
            if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
               let message = errorResponse["message"] {
                throw NetworkError.serverError(message)
            } else {
                throw NetworkError.serverError("Server error with status code: \(httpResponse.statusCode)")
            }
        }
        
        // Try decoding the response as UserResponse, or create a minimal one
        do {
            let decoder = JSONDecoder()
            let userResponse = try decoder.decode(UserResponse.self, from: data)
            
            DebugLogger.shared.log("Direct login successful", category: .network)
            
            // Save auth token if available
            if let token = userResponse.token {
                self.setAuthToken(token)
                DebugLogger.shared.log("Auth token saved from direct login", category: .auth)
            }
            
            return userResponse
        } catch {
            // If structured decoding fails, try to extract the critical fields
            do {
                // Try parsing as a dictionary to get essential fields
                if let jsonDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var token: String? = nil
                    var userId: String? = nil
                    var success = true
                    var message = "Login successful"
                    
                    // Extract token
                    if let tokenValue = jsonDict["token"] as? String {
                        token = tokenValue
                        self.setAuthToken(tokenValue)
                        DebugLogger.shared.log("Auth token saved from direct login (manual parsing)", category: .auth)
                    }
                    
                    // Extract user ID
                    if let user = jsonDict["user"] as? [String: Any], 
                       let id = (user["_id"] as? String) ?? (user["id"] as? String) {
                        userId = id
                    } else if let id = jsonDict["id"] as? String {
                        userId = id
                    } else if let id = jsonDict["restaurantid"] as? String {
                        userId = id
                    }
                    
                    // Extract success/message
                    if let successValue = jsonDict["success"] as? Bool {
                        success = successValue
                    }
                    if let messageValue = jsonDict["message"] as? String {
                        message = messageValue
                    }
                    
                    // Create a manually constructed response
                    let response = UserResponse(
                        success: success,
                        message: message,
                        token: token,
                        user: nil,
                        id: userId,
                        username: nil,
                        restaurantId: userId,
                        restaurantName: nil,
                        estimatedTime: nil,
                        cuisine: nil
                    )
                    
                    DebugLogger.shared.log("Created UserResponse manually from JSON dictionary", category: .network)
                    return response
                }
            } catch {
                DebugLogger.shared.logError(error, tag: "LOGIN_MANUAL_PARSING")
            }
            
            DebugLogger.shared.logError(error, tag: "DIRECT_LOGIN_PARSING")
            throw error
        }
    }
    
    // MARK: - Image Handling with Caching
    
    // Cache an image
    private func cacheImage(_ image: UIImage, forKey key: String) {
        imageCache.setObject(image, forKey: key as NSString)
        saveImageToDisk(image, forKey: key)
        DebugLogger.shared.log("Image cached for key: \(key)", category: .network)
    }
    
    // Get image from cache
    private func getCachedImage(forKey key: String) -> UIImage? {
        // First try memory cache
        if let cachedImage = imageCache.object(forKey: key as NSString) {
            DebugLogger.shared.log("Used cached image from memory for key: \(key)", category: .network)
            return cachedImage
        }
        
        // If not in memory, try disk cache
        if let diskCachedImage = getImageFromDisk(forKey: key) {
            // Update memory cache
            imageCache.setObject(diskCachedImage, forKey: key as NSString)
            DebugLogger.shared.log("Used cached image from disk for key: \(key)", category: .network)
            return diskCachedImage
        }
        
        return nil
    }
    
    // Save image to disk
    private func saveImageToDisk(_ image: UIImage, forKey key: String) {
        let fileURL = cacheDirectory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_"))
        
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            DebugLogger.shared.log("Could not convert image to data for key: \(key)", category: .error)
            return
        }
        
        do {
            try data.write(to: fileURL)
            DebugLogger.shared.log("Image saved to disk for key: \(key)", category: .network)
        } catch {
            DebugLogger.shared.log("Error saving image to disk: \(error.localizedDescription)", category: .error)
        }
    }
    
    // Get image from disk
    private func getImageFromDisk(forKey key: String) -> UIImage? {
        let fileURL = cacheDirectory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_"))
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return UIImage(data: data)
        } catch {
            DebugLogger.shared.log("Error loading image from disk: \(error.localizedDescription)", category: .error)
            return nil
        }
    }
    
    // Fetch image with caching
    func fetchImage(from url: URL) async throws -> UIImage {
        // Create a URL string to use as cache key
        let urlString = url.absoluteString
        
        // Check if image exists in cache
        if let cachedImage = getCachedImage(forKey: urlString) {
            DebugLogger.shared.log("Using cached image for URL: \(urlString)", category: .network)
            return cachedImage
        }
        
        DebugLogger.shared.log("Fetching image from network: \(urlString)", category: .network)
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, 
                  httpResponse.statusCode == 200 else {
                throw NetworkError.imageNotFound
            }
            
            guard let image = UIImage(data: data) else {
                throw NetworkError.imageNotFound
            }
            
            // Cache the downloaded image
            cacheImage(image, forKey: urlString)
            DebugLogger.shared.log("Image downloaded and cached for URL: \(urlString)", category: .network)
            
            return image
        } catch {
            DebugLogger.shared.logError(error, tag: "IMAGE_FETCH")
            throw NetworkError.imageNotFound
        }
    }
    
    // Use the DebugLogger instead of our own implementation
    private func logRequest(_ request: URLRequest) {
        DebugLogger.shared.logRequest(request)
    }
} 
