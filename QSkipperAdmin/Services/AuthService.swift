import Foundation
import Combine
import SwiftUI
import Security

class AuthService: ObservableObject {
    // Shared instance
    static let shared = AuthService()
    
    // Published properties
    @Published var currentUser: UserRestaurantProfile?
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    // API endpoints
    private struct Endpoints {
        static let baseURL = NetworkManager.baseURL
        static let login = "\(baseURL)/resturant-login"
        static let register = "\(baseURL)/resturant-register"
        static let profile = "\(baseURL)/auth/profile"
    }
    
    // Constants
    private enum StorageKeys {
        static let authToken = "qskipper_auth_token"
        static let userId = "qskipper_user_id"
    }
    
    // Private properties
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Check for existing ID on launch
        if let userId = getUserId() {
            // Set authenticated immediately based on user ID
            self.isAuthenticated = true
            DebugLogger.shared.log("User ID found (\(userId)), setting authenticated state to true", category: .auth)
            
            // Check if we also have a token
            if let token = getToken() {
                DebugLogger.shared.log("Auth token also found for user \(userId)", category: .auth)
                
                // Get the correct restaurant ID from UserDefaults if available
                let restaurantId = UserDefaults.standard.string(forKey: "restaurant_id") ?? userId
                DebugLogger.shared.log("Found restaurant ID: \(restaurantId)", category: .auth)
                
                // Create minimal profile
                self.currentUser = UserRestaurantProfile(
                    id: userId,
                    restaurantId: restaurantId,
                    restaurantName: "",
                    estimatedTime: 30,
                    cuisine: "",
                    restaurantImage: nil
                )
            }
        } else {
            // No ID found, ensure user is logged out
            self.isAuthenticated = false
            DebugLogger.shared.log("No user ID found, user is not authenticated", category: .auth)
            
            // Clear any leftover tokens to be safe
            UserDefaults.standard.removeObject(forKey: StorageKeys.authToken)
            NetworkManager.shared.clearAuthToken()
        }
        
        DebugLogger.shared.log("AuthService initialized", category: .auth)
    }
    
    // MARK: - Public Methods
    
    /// Login user
    /// - Parameters:
    ///   - email: User email
    ///   - password: User password
    func login(email: String, password: String) {
        isLoading = true
        error = nil
        
        // Ensure we're starting with a clean state by clearing all previous data
        logout()
        
        // Clear UserDefaults for any potential leftover data
        UserDefaults.standard.removeObject(forKey: "userData")
        UserDefaults.standard.removeObject(forKey: "restaurantData")
        UserDefaults.standard.removeObject(forKey: "restaurant_id")
        UserDefaults.standard.removeObject(forKey: "restaurant_data")
        UserDefaults.standard.removeObject(forKey: "restaurant_raw_data")
        UserDefaults.standard.removeObject(forKey: "is_restaurant_registered")
        UserDefaults.standard.synchronize()
        
        guard let url = URL(string: Endpoints.login) else {
            error = "Invalid URL"
            return
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create body
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            self.error = "Failed to encode login data: \(error.localizedDescription)"
            isLoading = false
            return
        }
        
        // Log the request
        DebugLogger.shared.log("Restaurant login request: \(Endpoints.login)", category: .auth)
        
        // Send request
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .tryMap { data -> (id: String?, token: String?, restaurantInfo: [String: Any]?) in
                // Log raw response
                if let responseString = String(data: data, encoding: .utf8) {
                    DebugLogger.shared.log("Restaurant login response: \(responseString)", category: .auth)
                }
                
                // Try to parse as JSON
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                
                // Extract id and token
                let id = json?["id"] as? String
                let token = json?["token"] as? String
                
                // Create a copy of the JSON as restaurant info
                var restaurantInfo: [String: Any]? = nil
                if let json = json {
                    restaurantInfo = json
                }
                
                return (id: id, token: token, restaurantInfo: restaurantInfo)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure(let err) = completion {
                    self?.error = "Login failed: \(err.localizedDescription)"
                    DebugLogger.shared.log("Error logging in: \(err)", category: .auth)
                }
            } receiveValue: { [weak self] result in
                guard let self = self else { return }
                
                // Save ID and token
                if let id = result.id {
                    self.saveUserId(userId: id)
                    DebugLogger.shared.log("User ID saved: \(id)", category: .auth)
                    
                    // Set authenticated flag
                    self.isAuthenticated = true
                    
                    // Extract restaurant details from the response
                    let restaurantId = result.restaurantInfo?["restaurantid"] as? String ?? ""
                    let restaurantName = result.restaurantInfo?["restaurantName"] as? String ?? ""
                    let estimatedTime = result.restaurantInfo?["resturantEstimateTime"] as? Int ?? 30
                    let cuisine = result.restaurantInfo?["resturantCusine"] as? String ?? ""
                    
                    // Check if restaurant is registered (restaurantId is not empty)
                    let isRestaurantRegistered = !restaurantId.isEmpty
                    
                    // Log the restaurant details
                    DebugLogger.shared.log("Restaurant details - ID: \(restaurantId), Name: \(restaurantName), Registered: \(isRestaurantRegistered)", category: .auth)
                    
                    // Save restaurant ID separately - THIS IS CRUCIAL for correct API calls
                    UserDefaults.standard.set(restaurantId, forKey: "restaurant_id")
                    UserDefaults.standard.set(isRestaurantRegistered, forKey: "is_restaurant_registered")
                    DebugLogger.shared.log("Restaurant ID saved: \(restaurantId)", category: .auth)
                    
                    // Save complete restaurant info from login response
                    if let restaurantInfo = result.restaurantInfo {
                        if let encodedData = try? JSONSerialization.data(withJSONObject: restaurantInfo) {
                            UserDefaults.standard.set(encodedData, forKey: "restaurant_raw_data")
                            DebugLogger.shared.log("Complete restaurant raw data saved to UserDefaults", category: .auth)
                        }
                    }
                    
                    // Save restaurant data in structured format as well
                    let restaurantData: [String: Any] = [
                        "id": restaurantId,
                        "name": restaurantName,
                        "estimatedTime": estimatedTime,
                        "cuisine": cuisine,
                        "isRegistered": isRestaurantRegistered
                    ]
                    if let encodedData = try? JSONSerialization.data(withJSONObject: restaurantData) {
                        UserDefaults.standard.set(encodedData, forKey: "restaurant_data")
                        DebugLogger.shared.log("Restaurant data saved to UserDefaults", category: .auth)
                    }
                    
                    // Create a minimal profile
                    self.currentUser = UserRestaurantProfile(
                        id: id,
                        restaurantId: restaurantId,
                        restaurantName: restaurantName,
                        estimatedTime: estimatedTime,
                        cuisine: cuisine,
                        restaurantImage: nil
                    )
                    
                    // Update data controller
                    DataController.shared.restaurant = RestaurantInfo(
                        id: restaurantId,
                        name: restaurantName,
                        email: email,
                        address: "",
                        phone: "",
                        categories: []
                    )
                }
                
                if let token = result.token {
                    self.saveToken(token: token)
                    DebugLogger.shared.log("Token saved", category: .auth)
                }
                
                DebugLogger.shared.log("Login successful", category: .auth)
            }
            .store(in: &cancellables)
    }
    
    /// Register new user
    /// - Parameters:
    ///   - email: User email
    ///   - password: User password
    ///   - name: User name
    func register(email: String, password: String, name: String) {
        isLoading = true
        error = nil
        
        // Ensure we're starting with a clean state
        logout()
        
        guard let url = URL(string: Endpoints.register) else {
            error = "Invalid URL"
            return
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create body
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "name": name
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            self.error = "Failed to encode registration data: \(error.localizedDescription)"
            isLoading = false
            return
        }
        
        // Log the request
        DebugLogger.shared.log("Restaurant registration request: \(Endpoints.register)", category: .auth)
        
        // Send request
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .tryMap { data -> (id: String?, token: String?) in
                // Log raw response
                if let responseString = String(data: data, encoding: .utf8) {
                    DebugLogger.shared.log("Restaurant registration response: \(responseString)", category: .auth)
                }
                
                // Try to parse as JSON
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                
                // Extract id and token
                let id = json?["id"] as? String
                let token = json?["token"] as? String
                
                return (id: id, token: token)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure(let err) = completion {
                    self?.error = "Registration failed: \(err.localizedDescription)"
                    DebugLogger.shared.log("Error registering: \(err)", category: .auth)
                }
            } receiveValue: { [weak self] result in
                guard let self = self else { return }
                
                // Save ID and token
                if let id = result.id {
                    self.saveUserId(userId: id)
                    DebugLogger.shared.log("User ID saved after registration: \(id)", category: .auth)
                    
                    // Set authenticated flag
                    self.isAuthenticated = true
                    
                    // Create a minimal profile
                    self.currentUser = UserRestaurantProfile(
                        id: id,
                        restaurantId: id,
                        restaurantName: name,
                        estimatedTime: 30,
                        cuisine: "",
                        restaurantImage: nil
                    )
                }
                
                if let token = result.token {
                    self.saveToken(token: token)
                    DebugLogger.shared.log("Token saved after registration", category: .auth)
                }
                
                DebugLogger.shared.log("Registration successful", category: .auth)
            }
            .store(in: &cancellables)
    }
    
    /// Fetch user profile
    /// - Parameter userId: User ID
    func fetchUserProfile(userId: String) {
        isLoading = true
        error = nil
        
        guard let url = URL(string: "\(Endpoints.profile)/\(userId)") else {
            error = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        
        // Add auth token
        if let token = getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Send request
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: ProfileResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                switch completion {
                case .failure(let err):
                    self?.error = "Failed to load profile: \(err.localizedDescription)"
                    print("Error fetching profile: \(err)")
                    // Clear token if unauthorized and set not authenticated
                    if let httpResponse = err as? URLError,
                       httpResponse.code.rawValue == 401 {
                        self?.logout()
                    }
                case .finished:
                    break
                }
            } receiveValue: { [weak self] response in
                self?.currentUser = response.profile
                // Ensure authentication state is set
                self?.isAuthenticated = true
                DebugLogger.shared.log("User profile loaded successfully, authentication confirmed", category: .auth)
            }
            .store(in: &cancellables)
    }
    
    /// Logout user
    func logout() {
        // Ensure we're on the main thread for all UI operations
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.logout()
            }
            return
        }
        
        // Log before clearing
        if let userId = getUserId() {
            DebugLogger.shared.log("Logging out user with ID: \(userId)", category: .auth)
        } else {
            DebugLogger.shared.log("Logging out user with no ID stored", category: .auth)
        }
        
        // Clear all user data
        clearUserData()
        
        // Reset state
        self.currentUser = nil
        self.isAuthenticated = false
        
        // Notify DataController to clear its data as well
        DataController.shared.logout()
        
        // Post notification for any observers
        NotificationCenter.default.post(name: DataController.userDidLogoutNotification, object: nil)
        
        DebugLogger.shared.log("User logged out, all auth data cleared", category: .auth)
    }
    
    /// Clear all user data from UserDefaults and memory
    private func clearUserData() {
        // Ensure we're on the main thread
        assert(Thread.isMainThread, "clearUserData must be called from the main thread")
        
        // Clear auth data
        UserDefaults.standard.removeObject(forKey: StorageKeys.authToken)
        UserDefaults.standard.removeObject(forKey: StorageKeys.userId)
        
        // Clear restaurant data
        UserDefaults.standard.removeObject(forKey: "userData")
        UserDefaults.standard.removeObject(forKey: "restaurantData")
        UserDefaults.standard.removeObject(forKey: "restaurant_id")
        UserDefaults.standard.removeObject(forKey: "restaurant_data")
        UserDefaults.standard.removeObject(forKey: "restaurant_raw_data")
        UserDefaults.standard.removeObject(forKey: "is_restaurant_registered")
        
        // Clear any other potential user-related data
        UserDefaults.standard.removeObject(forKey: "user_profile")
        UserDefaults.standard.removeObject(forKey: "user_settings")
        UserDefaults.standard.removeObject(forKey: "last_login")
        UserDefaults.standard.removeObject(forKey: "restaurant_settings")
        UserDefaults.standard.removeObject(forKey: "menu_data")
        
        // Clear any cached data
        ProductApi.shared.clearImageCache()
        
        // Clear all UserDefaults keys that might contain user data
        // This is a more aggressive approach to ensure all user data is cleared
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in allKeys {
            if key.contains("user") || key.contains("auth") || 
               key.contains("token") || key.contains("restaurant") ||
               key.contains("profile") || key.contains("login") ||
               key.contains("qskipper") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        // Force UserDefaults to synchronize
        UserDefaults.standard.synchronize()
        
        // Clear NetworkManager token
        NetworkManager.shared.clearAuthToken()
        
        // Clear DataController data (which should also be main thread safe)
        DataController.shared.clearData()
        
        DebugLogger.shared.log("All user data cleared from UserDefaults and memory", category: .auth)
    }
    
    // MARK: - Token Management
    
    /// Get the stored auth token
    /// - Returns: Auth token string if available
    func getToken() -> String? {
        return UserDefaults.standard.string(forKey: StorageKeys.authToken)
    }
    
    /// Get the stored user ID
    /// - Returns: User ID string if available
    func getUserId() -> String? {
        return UserDefaults.standard.string(forKey: StorageKeys.userId)
    }
    
    /// Save auth token
    /// - Parameter token: The token to save
    private func saveToken(token: String) {
        UserDefaults.standard.set(token, forKey: StorageKeys.authToken)
        NetworkManager.shared.setAuthToken(token)
    }
    
    /// Save user ID
    /// - Parameter userId: The user ID to save
    private func saveUserId(userId: String) {
        UserDefaults.standard.set(userId, forKey: StorageKeys.userId)
    }
    
    /// Update user data
    /// - Parameter user: Updated user information
    func updateUserData(_ user: User) {
        isLoading = true
        error = nil
        
        guard let currentUser = currentUser else {
            error = "No current user found"
            isLoading = false
            return
        }
        
        // For now, we'll just update the local user data
        // In a real app, you would make an API call to update the server
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // Update the current user with the new values
            self?.currentUser = UserRestaurantProfile(
                id: currentUser.id,
                restaurantId: currentUser.restaurantId,
                restaurantName: user.restaurantName ?? "",
                estimatedTime: currentUser.estimatedTime,
                cuisine: currentUser.cuisine,
                restaurantImage: currentUser.restaurantImage
            )
            
            self?.isLoading = false
            DebugLogger.shared.log("User data updated locally", category: .auth)
        }
    }
    
    // MARK: - Compatibility with Old AuthService Implementation
    
    /// Get the auth state (for compatibility with code calling old AuthService)
    /// - Returns: AuthState object with token and userId
    func getAuthState() throws -> AuthState {
        guard let userId = getUserId() else {
            throw NSError(domain: "AuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Get token if available, but don't require it - the ID is the main thing
        let token = getToken() ?? ""
        
        DebugLogger.shared.log("Getting auth state: userID=\(userId)", category: .auth)
        return AuthState(token: token, userId: userId)
    }
    
    /// Direct restaurant login (for compatibility with old implementation)
    /// - Parameters:
    ///   - email: User email
    ///   - password: User password
    /// - Returns: UserResponse
    func loginRestaurantDirect(email: String, password: String) async throws -> UserResponse? {
        isLoading = true
        error = nil
        
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        
        do {
            DebugLogger.shared.log("📡 Sending restaurant login request to \(Endpoints.login)", category: .auth)
            
            // Manually construct the URL and request here for more control
            guard let url = URL(string: Endpoints.login) else {
                throw NSError(domain: "AuthService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = jsonData
            
            // Log request details
            DebugLogger.shared.log("📡 Full URL: \(url.absoluteString) (Server: \(url.host ?? "unknown"))", category: .auth)
            DebugLogger.shared.log("📤 Login request for email: \(email)", category: .auth)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log response details
            if let httpResponse = response as? HTTPURLResponse {
                DebugLogger.shared.log("📥 Login response status: \(httpResponse.statusCode) from \(url.host ?? "unknown")", category: .auth)
            }
            
            // Log the raw response (carefully to avoid exposing tokens)
            if let responseString = String(data: data, encoding: .utf8) {
                // Sanitize response to redact sensitive information
                let sanitized = responseString.replacingOccurrences(of: "\"token\":\"[^\"]+\"", with: "\"token\":\"[REDACTED]\"", options: .regularExpression)
                DebugLogger.shared.log("📥 Login response: \(sanitized)", category: .auth)
            }
            
            // Try parsing as a simple JSON object first (for the {id: "..."} format)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let id = json["id"] as? String
                let token = json["token"] as? String
                
                if let id = id {
                    DebugLogger.shared.log("✅ Received restaurant ID: \(id)", category: .auth)
                    
                    // Ensure we use local values for thread safety
                    let userId = id
                    let authToken = token
                    
                    // Extract restaurant details from the response
                    let restaurantId = json["restaurantid"] as? String ?? id
                    let restaurantName = json["restaurantName"] as? String ?? ""
                    let estimatedTime = json["resturantEstimateTime"] as? Int ?? 30
                    let cuisine = json["resturantCusine"] as? String ?? ""
                    
                    // Log the extracted values
                    DebugLogger.shared.log("📋 Restaurant details extracted - ID: \(restaurantId), Name: \(restaurantName), Time: \(estimatedTime), Cuisine: \(cuisine)", category: .auth)
                    
                    // If we have a restaurantId different from the user ID, log it
                    if restaurantId != id {
                        DebugLogger.shared.log("📋 Found restaurant ID in response: \(restaurantId)", category: .auth)
                    }
                    
                    // Save the ID - all UI updates on main thread
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        // Explicitly logout first to ensure all data is cleared
                        self.logout()
                        
                        self.saveUserId(userId: userId)
                        self.isAuthenticated = true
                        
                        // Save restaurant ID separately - CRUCIAL for correct API calls
                        UserDefaults.standard.set(restaurantId, forKey: "restaurant_id")
                        UserDefaults.standard.set(!restaurantId.isEmpty, forKey: "is_restaurant_registered")
                        
                        // Save token if available
                        if let token = authToken {
                            self.saveToken(token: token)
                            NetworkManager.shared.setAuthToken(token)
                            DebugLogger.shared.log("✅ Auth token saved", category: .auth)
                        }
                        
                        // Create a basic profile with the restaurant data
                        if self.currentUser == nil {
                            self.currentUser = UserRestaurantProfile(
                                id: userId,
                                restaurantId: restaurantId,
                                restaurantName: restaurantName,
                                estimatedTime: estimatedTime,
                                cuisine: cuisine,
                                restaurantImage: nil
                            )
                            DebugLogger.shared.log("👤 Created basic user profile with ID: \(userId), restaurant ID: \(restaurantId), name: \(restaurantName), time: \(estimatedTime), cuisine: \(cuisine)", category: .auth)
                        }
                        
                        // Save complete restaurant info from login response
                        if let encodedData = try? JSONSerialization.data(withJSONObject: json) {
                            UserDefaults.standard.set(encodedData, forKey: "restaurant_raw_data")
                            DebugLogger.shared.log("Complete restaurant raw data saved to UserDefaults", category: .auth)
                        }
                        
                        // Also save in structured format
                        let restaurantData: [String: Any] = [
                            "id": restaurantId,
                            "name": restaurantName,
                            "estimatedTime": estimatedTime,
                            "cuisine": cuisine,
                            "isRegistered": true
                        ]
                        
                        if let encodedData = try? JSONSerialization.data(withJSONObject: restaurantData) {
                            UserDefaults.standard.set(encodedData, forKey: "restaurant_data")
                        }
                    }
                    
                    // Create response object
                    let userResponse = UserResponse(
                        success: true,
                        message: "Login successful",
                        token: token,
                        user: nil,
                        id: id,
                        username: nil,
                        restaurantId: restaurantId,
                        restaurantName: restaurantName,
                        estimatedTime: estimatedTime,
                        cuisine: cuisine
                    )
                    
                    return userResponse
                }
            }
            
            // If we get here, try the NetworkManager approach as fallback
            DebugLogger.shared.log("📡 Using NetworkManager fallback for login", category: .auth)
            let userResponse: UserResponse = try await NetworkManager.shared.performRequest(
                endpoint: "/resturant-login",
                method: "POST",
                body: body
            )
            
            // Handle UI updates on main thread
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
            }
            
            DebugLogger.shared.log("📥 Restaurant login response processed - success: \(userResponse.success)", category: .auth)
            
            if let token = userResponse.token, userResponse.success {
                // Save token to NetworkManager and UserDefaults
                NetworkManager.shared.setAuthToken(token)
                DebugLogger.shared.log("✅ Auth token saved to NetworkManager", category: .auth)
                
                // Get user ID from the response
                var userId: String? = nil
                if let user = userResponse.user {
                    userId = user.id
                    DebugLogger.shared.log("👤 Getting user ID from user object: \(user.id)", category: .auth)
                } else if let directId = userResponse.id {
                    userId = directId
                    DebugLogger.shared.log("👤 Getting user ID from direct ID: \(directId)", category: .auth)
                } else if let restaurantId = userResponse.restaurantId {
                    userId = restaurantId
                    DebugLogger.shared.log("👤 Getting user ID from restaurant ID: \(restaurantId)", category: .auth)
                }
                
                // Save auth state if we have a user ID
                if let userId = userId {
                    // Store values locally for thread safety
                    let finalUserId = userId
                    let finalToken = token
                    let finalRestaurantId = userResponse.restaurantId ?? userId
                    let finalName = userResponse.restaurantName ?? ""
                    let finalTime = userResponse.estimatedTime ?? 30
                    let finalCuisine = userResponse.cuisine ?? ""
                    
                    // Perform all UI updates on main thread
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        // Explicitly logout first to ensure all data is cleared
                        self.logout()
                        
                        // Then set new data
                        self.saveToken(token: finalToken)
                        self.saveUserId(userId: finalUserId)
                        self.isAuthenticated = true
                        
                        // Create a basic profile with the restaurant data
                        if self.currentUser == nil {
                            self.currentUser = UserRestaurantProfile(
                                id: finalUserId,
                                restaurantId: finalRestaurantId,
                                restaurantName: finalName,
                                estimatedTime: finalTime,
                                cuisine: finalCuisine,
                                restaurantImage: nil
                            )
                            
                            // Log the profile creation to verify the values
                            DebugLogger.shared.log("Created user profile with id: \(finalUserId), restaurantId: \(finalRestaurantId), name: \(finalName), time: \(finalTime), cuisine: \(finalCuisine)", category: .auth)
                            
                            // Also save to restaurant_data in UserDefaults
                            let restaurantData: [String: Any] = [
                                "id": finalRestaurantId,
                                "name": finalName,
                                "estimatedTime": finalTime,
                                "cuisine": finalCuisine,
                                "isRegistered": true
                            ]
                            
                            if let encodedData = try? JSONSerialization.data(withJSONObject: restaurantData) {
                                UserDefaults.standard.set(encodedData, forKey: "restaurant_data")
                                UserDefaults.standard.set(true, forKey: "is_restaurant_registered")
                                UserDefaults.standard.set(finalRestaurantId, forKey: "restaurant_id")
                            }
                        }
                    }
                    
                    DebugLogger.shared.log("✅ Auth state saved and basic profile created for user ID: \(userId)", category: .auth)
                } else {
                    DebugLogger.shared.log("⚠️ No user ID found in response - using token only", category: .auth)
                }
            } else {
                DebugLogger.shared.log("❌ Login failed - token or success flag not present", category: .auth)
            }
            
            return userResponse
        } catch {
            // Handle error on main thread
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
                self?.error = error.localizedDescription
            }
            
            DebugLogger.shared.log("❌ Login error: \(error.localizedDescription)", category: .error, tag: "RESTAURANT_LOGIN")
            throw error
        }
    }
    
    /// Direct restaurant registration (for compatibility with old implementation)
    /// - Parameters:
    ///   - email: User email
    ///   - password: User password
    ///   - confirmPassword: Confirmation password
    /// - Returns: UserResponse
    func registerRestaurantDirect(email: String, password: String, confirmPassword: String = "") async throws -> UserResponse? {
        isLoading = true
        error = nil
        
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        
        do {
            DebugLogger.shared.log("📡 Sending restaurant registration request to \(Endpoints.register)", category: .auth)
            
            // Manually construct the URL and request here for more control
            guard let url = URL(string: Endpoints.register) else {
                throw NSError(domain: "AuthService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = jsonData
            
            // Log detailed request information
            DebugLogger.shared.log("📡 Full URL: \(url.absoluteString) (Server: \(url.host ?? "unknown"))", category: .auth)
            DebugLogger.shared.log("📤 Registration request for email: \(email)", category: .auth)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log response details
            if let httpResponse = response as? HTTPURLResponse {
                DebugLogger.shared.log("📥 Registration response status: \(httpResponse.statusCode) from \(url.host ?? "unknown")", category: .auth)
            }
            
            // Log the raw response
            if let responseString = String(data: data, encoding: .utf8) {
                // Sanitize response to redact sensitive information
                let sanitized = responseString.replacingOccurrences(of: "\"token\":\"[^\"]+\"", with: "\"token\":\"[REDACTED]\"", options: .regularExpression)
                DebugLogger.shared.log("📥 Registration response: \(sanitized)", category: .auth)
            }
            
            // Try parsing as a simple JSON object first (for the {id: "..."} format)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let id = json["id"] as? String
                let token = json["token"] as? String
                
                if let id = id {
                    DebugLogger.shared.log("✅ Received restaurant ID after registration: \(id)", category: .auth)
                    
                    // Ensure we use local values for thread safety
                    let userId = id
                    let authToken = token
                    
                    // Save the ID - all UI updates on main thread
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        // Explicitly logout first to ensure all data is cleared
                        self.logout()
                        
                        self.saveUserId(userId: userId)
                        self.isAuthenticated = true
                        
                        // Save token if available
                        if let token = authToken {
                            self.saveToken(token: token)
                            NetworkManager.shared.setAuthToken(token)
                            DebugLogger.shared.log("✅ Auth token saved after registration", category: .auth)
                        }
                        
                        // Create basic profile
                        if self.currentUser == nil {
                            self.currentUser = UserRestaurantProfile(
                                id: userId,
                                restaurantId: userId,
                                restaurantName: "",
                                estimatedTime: 30,
                                cuisine: "",
                                restaurantImage: nil
                            )
                            DebugLogger.shared.log("👤 Created basic user profile with ID: \(userId)", category: .auth)
                        }
                    }
                    
                    // Create response object
                    let userResponse = UserResponse(
                        success: true,
                        message: "Registration successful",
                        token: token,
                        user: nil,
                        id: id,
                        username: nil,
                        restaurantId: id,
                        restaurantName: nil,
                        estimatedTime: nil,
                        cuisine: nil
                    )
                    
                    return userResponse
                }
            }
            
            // If we get here, try the NetworkManager approach as fallback
            DebugLogger.shared.log("📡 Using NetworkManager fallback for registration", category: .auth)
            let userResponse: UserResponse = try await NetworkManager.shared.performRequest(
                endpoint: "/resturant-register",
                method: "POST",
                body: body
            )
            
            // Handle UI updates on main thread
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
            }
            
            DebugLogger.shared.log("📥 Restaurant registration response processed - success: \(userResponse.success)", category: .auth)
            
            if let token = userResponse.token, userResponse.success {
                // Save token to NetworkManager and UserDefaults
                NetworkManager.shared.setAuthToken(token)
                DebugLogger.shared.log("✅ Auth token saved to NetworkManager", category: .auth)
                
                // Get user ID from the response
                var userId: String? = nil
                if let user = userResponse.user {
                    userId = user.id
                    DebugLogger.shared.log("👤 Getting user ID from user object: \(user.id)", category: .auth)
                } else if let directId = userResponse.id {
                    userId = directId
                    DebugLogger.shared.log("👤 Getting user ID from direct ID: \(directId)", category: .auth)
                } else if let restaurantId = userResponse.restaurantId {
                    userId = restaurantId
                    DebugLogger.shared.log("👤 Getting user ID from restaurant ID: \(restaurantId)", category: .auth)
                }
                
                // Save auth state if we have a user ID
                if let userId = userId {
                    // Store values locally for thread safety
                    let finalUserId = userId
                    let finalToken = token
                    let finalRestaurantId = userResponse.restaurantId ?? userId
                    let finalName = userResponse.restaurantName ?? ""
                    let finalTime = userResponse.estimatedTime ?? 30
                    let finalCuisine = userResponse.cuisine ?? ""
                    
                    // Perform all UI updates on main thread
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        // Explicitly logout first to ensure all data is cleared
                        self.logout()
                        
                        // Then set new data
                        self.saveToken(token: finalToken)
                        self.saveUserId(userId: finalUserId)
                        self.isAuthenticated = true
                        
                        // Create a basic profile with the restaurant data
                        if self.currentUser == nil {
                            self.currentUser = UserRestaurantProfile(
                                id: finalUserId,
                                restaurantId: finalRestaurantId,
                                restaurantName: finalName,
                                estimatedTime: finalTime,
                                cuisine: finalCuisine,
                                restaurantImage: nil
                            )
                            
                            // Log the profile creation to verify the values
                            DebugLogger.shared.log("Created user profile with id: \(finalUserId), restaurantId: \(finalRestaurantId), name: \(finalName), time: \(finalTime), cuisine: \(finalCuisine)", category: .auth)
                            
                            // Also save to restaurant_data in UserDefaults
                            let restaurantData: [String: Any] = [
                                "id": finalRestaurantId,
                                "name": finalName,
                                "estimatedTime": finalTime,
                                "cuisine": finalCuisine,
                                "isRegistered": true
                            ]
                            
                            if let encodedData = try? JSONSerialization.data(withJSONObject: restaurantData) {
                                UserDefaults.standard.set(encodedData, forKey: "restaurant_data")
                                UserDefaults.standard.set(true, forKey: "is_restaurant_registered")
                                UserDefaults.standard.set(finalRestaurantId, forKey: "restaurant_id")
                            }
                        }
                    }
                    
                    DebugLogger.shared.log("✅ Auth state saved and basic profile created for user ID: \(userId)", category: .auth)
                } else {
                    DebugLogger.shared.log("⚠️ No user ID found in response - using token only", category: .auth)
                }
            } else {
                DebugLogger.shared.log("❌ Registration failed - token or success flag not present", category: .auth)
            }
            
            return userResponse
        } catch {
            // Handle error on main thread
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
                self?.error = error.localizedDescription
            }
            
            DebugLogger.shared.log("❌ Registration error: \(error.localizedDescription)", category: .error, tag: "RESTAURANT_REGISTRATION")
            throw error
        }
    }
    
    /// Check if restaurant is registered
    /// - Returns: True if restaurant is registered
    func isRestaurantRegistered() -> Bool {
        return UserDefaults.standard.bool(forKey: "is_restaurant_registered")
    }
}

// MARK: - Auth State
// struct AuthState {
//     let token: String
//     let userId: String
// }

// MARK: - Response Models
struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct ProfileResponse: Codable {
    let profile: UserRestaurantProfile
}

// For compatibility with the old implementation
// struct UserResponse: Codable {
//     let success: Bool
//     let message: String
//     let token: String?
//     let user: User?
//     let id: String?
//     let restaurantId: String?
// } 