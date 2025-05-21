import Foundation
import UIKit

// MARK: - Product Model
struct Product: Codable, Identifiable {
    var id: String
    var name: String
    var price: Int
    var restaurantId: String
    var category: String
    var description: String
    var extraTime: Int = 0
    var rating: Double
    var isAvailable: Bool
    var isActive: Bool = true
    var isFeatured: Bool = false
    var quantity: Int = 1
    var topPicks: Bool = false
    private var productPhoto64Image: String?
    var imageUrl: String?
    
    var productPhoto: UIImage? {
        get {
            guard let imageData = productPhoto64Image,
                  let data = Data(base64Encoded: imageData) else { return nil }
            return UIImage(data: data)
        }
        set {
            if let newImage = newValue, let data = newImage.jpegData(compressionQuality: 0.7) {
                productPhoto64Image = data.base64EncodedString()
            } else {
                productPhoto64Image = nil
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name = "product_name"
        case price = "product_price"
        case restaurantId = "restaurant_id"
        case category = "food_category"
        case description
        case extraTime
        case rating
        case isAvailable = "availability"
        case isActive = "is_active"
        case isFeatured = "featured"
        case productPhoto64Image = "product_photo64Image"
        case imageUrl = "image_url"
        case quantity
        case topPicks = "top_picks"
    }
    
    // Custom init from decoder to handle missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        price = try container.decode(Int.self, forKey: .price)
        restaurantId = try container.decode(String.self, forKey: .restaurantId)
        category = try container.decode(String.self, forKey: .category)
        description = try container.decode(String.self, forKey: .description)
        
        // Optional fields with defaults
        extraTime = try container.decodeIfPresent(Int.self, forKey: .extraTime) ?? 0
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable) ?? true
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        isFeatured = try container.decodeIfPresent(Bool.self, forKey: .isFeatured) ?? false
        quantity = try container.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        topPicks = try container.decodeIfPresent(Bool.self, forKey: .topPicks) ?? false
        
        // Rating can be Double or Int
        if let doubleRating = try? container.decode(Double.self, forKey: .rating) {
            rating = doubleRating
        } else if let intRating = try? container.decode(Int.self, forKey: .rating) {
            rating = Double(intRating)
        } else {
            rating = 0.0
        }
        
        // Optional fields that can be null
        productPhoto64Image = try container.decodeIfPresent(String.self, forKey: .productPhoto64Image)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
    }
    
    init(id: String = "",
         name: String = "",
         price: Int = 0,
         restaurantId: String = "",
         category: String = "",
         description: String = "",
         extraTime: Int = 0,
         rating: Double = 0.0,
         isAvailable: Bool = true,
         isActive: Bool = true,
         isFeatured: Bool = false,
         productPhoto: UIImage? = nil,
         imageUrl: String? = nil,
         quantity: Int = 1,
         topPicks: Bool = false) {
        self.id = id
        self.name = name
        self.price = price
        self.restaurantId = restaurantId
        self.category = category
        self.description = description
        self.extraTime = extraTime
        self.rating = rating
        self.isAvailable = isAvailable
        self.isActive = isActive
        self.isFeatured = isFeatured
        self.productPhoto = productPhoto
        self.imageUrl = imageUrl
        self.quantity = quantity
        self.topPicks = topPicks
    }
}

// MARK: - Product List Response
struct ProductResponse: Codable {
    var products: [Product]?
    var product: Product?
    var success: Bool?
    var message: String?
}

// MARK: - Product Image Response
struct ProductImageResponse: Codable {
    let id: String
    let image: ProductImage
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case image = "product_photo64Image"
    }
}

// MARK: - Product Image
struct ProductImage: Codable {
    var data: String
    var contentType: String
    
    enum CodingKeys: String, CodingKey {
        case data
        case contentType
    }
    
    var uiImage: UIImage? {
        guard let imageData = Data(base64Encoded: data) else { return nil }
        return UIImage(data: imageData)
    }
}

struct DeleteProductResponse: Codable {
    let success: Bool
    let message: String
} 