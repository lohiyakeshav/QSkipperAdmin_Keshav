import SwiftUI

struct OrderDetailsView: View {
    @ObservedObject var viewModel: OrderDetailsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Order Header
                    orderHeader
                    
                    Divider()
                    
                    // Order Items
                    orderItems
                    
                    Divider()
                    
                    // Order Summary
                    orderSummary
                    
                    // Action Buttons
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Order Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.4)
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            
                            Text(viewModel.isCompleting ? "Completing order..." : "Loading...")
                                .font(AppFonts.body)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                    }
                    .edgesIgnoringSafeArea(.all)
                }
            }
            .alert(isPresented: $viewModel.showErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(viewModel.errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    private var orderHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Order #\(viewModel.order.id.suffix(6))")
                        .font(AppFonts.title)
                        .foregroundColor(AppColors.darkGray)
                    
                    Text(viewModel.order.formattedDate)
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.mediumGray)
                }
                
                Spacer()
                
                orderStatusBadge
            }
        }
    }
    
    private var orderStatusBadge: some View {
        Text(viewModel.order.status.capitalized)
            .font(AppFonts.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor)
            .cornerRadius(12)
    }
    
    private var statusColor: Color {
        switch viewModel.order.status.lowercased() {
        case "pending":
            return Color.orange
        case "completed":
            return AppColors.primaryGreen
        case "cancelled":
            return AppColors.errorRed
        default:
            return AppColors.mediumGray
        }
    }
    
    private var orderItems: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Order Items")
                .font(AppFonts.sectionTitle)
                .foregroundColor(AppColors.darkGray)
            
            ForEach(viewModel.order.products) { product in
                HStack(spacing: 12) {
                    // Product image or placeholder
                    if let imageUrlString = product.imageUrl,
                       let imageUrl = URL(string: "\(imageUrlString)?v=\(Int(Date().timeIntervalSince1970))") {
                        AsyncImage(url: imageUrl) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: 60, height: 60)
                                    .background(AppColors.lightGray)
                                    .cornerRadius(8)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                            case .failure:
                                Image(systemName: "photo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 30, height: 30)
                                    .frame(width: 60, height: 60)
                                    .background(AppColors.lightGray)
                                    .cornerRadius(8)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "photo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                            .frame(width: 60, height: 60)
                            .background(AppColors.lightGray)
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.productName)
                            .font(AppFonts.body)
                            .foregroundColor(AppColors.darkGray)
                        
                        Text("$\(String(format: "%.2f", product.price))")
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.primaryGreen)
                    }
                    
                    Spacer()
                    
                    Text("x\(product.quantity)")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.mediumGray)
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var orderSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Order Summary")
                .font(AppFonts.sectionTitle)
                .foregroundColor(AppColors.darkGray)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Items")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.darkGray)
                    
                    Spacer()
                    
                    Text("\(viewModel.order.products.count)")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.darkGray)
                }
                
                HStack {
                    Text("Total Quantity")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.darkGray)
                    
                    Spacer()
                    
                    Text("\(viewModel.totalQuantity)")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.darkGray)
                }
                
                Divider()
                
                HStack {
                    Text("Total Amount")
                        .font(AppFonts.sectionTitle)
                        .foregroundColor(AppColors.darkGray)
                    
                    Spacer()
                    
                    Text("$\(String(format: "%.2f", viewModel.order.totalAmount))")
                        .font(AppFonts.sectionTitle)
                        .foregroundColor(AppColors.primaryGreen)
                }
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 16) {
            if viewModel.order.status.lowercased() == "pending" {
                PrimaryButton(
                    title: "Complete Order",
                    action: {
                        viewModel.completeOrder()
                    },
                    isLoading: viewModel.isCompleting
                )
                .padding(.top, 16)
            }
            
            SecondaryButton(
                title: "Close",
                action: {
                    dismiss()
                }
            )
        }
    }
}

class OrderDetailsViewModel: ObservableObject {
    let order: Order
    let onComplete: () -> Void
    
    @Published var isLoading: Bool = false
    @Published var isCompleting: Bool = false
    @Published var errorMessage: String = ""
    @Published var showErrorAlert: Bool = false
    
    init(order: Order, onComplete: @escaping () -> Void) {
        self.order = order
        self.onComplete = onComplete
    }
    
    // Computed property for total quantity
    var totalQuantity: Int {
        // Use products if available, otherwise use items
        if !order.products.isEmpty {
            return order.products.reduce(0) { $0 + $1.quantity }
        } else {
            return order.items.reduce(0) { $0 + $1.quantity }
        }
    }
    
    // Complete the order
    func completeOrder() {
        isLoading = true
        isCompleting = true
        
        Task {
            do {
                let success = try await OrderService.shared.completeOrder(orderId: order.id)
                
                DispatchQueue.main.async { [weak self] in
                    self?.isLoading = false
                    self?.isCompleting = false
                    
                    if success {
                        // Invalidate the order cache so it fetches fresh data
                        OrderService.shared.invalidateOrderCache()
                        self?.onComplete()
                    } else {
                        self?.errorMessage = "Failed to complete order. Please try again."
                        self?.showErrorAlert = true
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.isLoading = false
                    self?.isCompleting = false
                    self?.errorMessage = error.localizedDescription
                    self?.showErrorAlert = true
                }
            }
        }
    }
}

#Preview {
    OrderDetailsView(viewModel: OrderDetailsViewModel(
        order: Order(
            id: "order123456",
            userId: "user123",
            restaurantId: "restaurant123",
            products: [
                OrderProduct(
                    id: "item1",
                    productName: "Margherita Pizza",
                    price: 12.99,
                    quantity: 2,
                    imageUrl: nil
                ),
                OrderProduct(
                    id: "item2",
                    productId: "product2",
                    productName: "Caesar Salad",
                    price: 8.99,
                    quantity: 1,
                    imageUrl: nil
                )
            ],
            totalAmount: 34.97,
            status: "pending",
            createdAt: "2023-01-01T12:00:00.000Z",
            updatedAt: "2023-01-01T12:00:00.000Z"
        ),
        onComplete: {}
    ))
} 