import UIKit
import SwiftUI
import Combine

class MenuViewController: UIViewController {
    
    // MARK: - Properties
    private var menuView: UIHostingController<MenuUIView>!
    private var viewModel = MenuViewModel()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBindings()
        setupUI()
        setupNavigation()
        
        // Load data
        viewModel.loadProducts()
    }
    
    // MARK: - Setup
    private func setupUI() {
        // Create SwiftUI view
        let swiftUIView = MenuUIView(viewModel: viewModel)
        
        // Create hosting controller for SwiftUI view
        menuView = UIHostingController(rootView: swiftUIView)
        
        // Add as child view controller
        addChild(menuView)
        view.addSubview(menuView.view)
        menuView.didMove(toParent: self)
        
        // Setup constraints
        menuView.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            menuView.view.topAnchor.constraint(equalTo: view.topAnchor),
            menuView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            menuView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            menuView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupNavigation() {
        title = "Menu"
        navigationController?.navigationBar.prefersLargeTitles = true
        
        // Add button
        let addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addButtonTapped)
        )
        navigationItem.rightBarButtonItem = addButton
    }
    
    private func setupBindings() {
        viewModel.$showAddProductSheet
            .sink { [weak self] showSheet in
                if showSheet {
                    self?.presentAddProductSheet()
                }
            }
            .store(in: &cancellables)
        
        viewModel.$selectedProduct
            .compactMap { $0 }
            .sink { [weak self] product in
                self?.presentEditProductSheet(product: product)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    @objc private func addButtonTapped() {
        viewModel.addProductTapped()
    }
    
    private func presentAddProductSheet() {
        let addProductController = UIHostingController(rootView: AddEditProductView(
            viewModel: AddEditProductViewModel(mode: .add) { [weak self] in
                self?.viewModel.loadProducts()
                self?.dismiss(animated: true)
            }
        ))
        
        if let sheet = addProductController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        
        present(addProductController, animated: true) {
            self.viewModel.showAddProductSheet = false
        }
    }
    
    private func presentEditProductSheet(product: Product) {
        let editProductController = UIHostingController(rootView: AddEditProductView(
            viewModel: AddEditProductViewModel(mode: .edit(product)) { [weak self] in
                self?.viewModel.loadProducts()
                self?.dismiss(animated: true)
            }
        ))
        
        if let sheet = editProductController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        
        present(editProductController, animated: true) {
            self.viewModel.selectedProduct = nil
        }
    }
}

// MARK: - SwiftUI View
struct MenuUIView: View {
    @ObservedObject var viewModel: MenuViewModel
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("Loading menu...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .padding()
            } else if viewModel.products.isEmpty {
                emptyStateView
            } else {
                productListView
            }
            
            if viewModel.showErrorAlert && !viewModel.errorMessage.contains("not authenticated") {
                Text(viewModel.errorMessage)
                    .font(AppFonts.body)
                    .foregroundColor(.white)
                    .padding()
                    .background(AppColors.errorRed)
                    .cornerRadius(8)
                    .padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                viewModel.showErrorAlert = false
                            }
                        }
                    }
                    .zIndex(1)
            }
        }
        .refreshable {
            await viewModel.refreshProducts()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 70)
                .foregroundColor(AppColors.mediumGray)
            
            Text("Your menu is empty")
                .font(AppFonts.title)
                .foregroundColor(AppColors.darkGray)
            
            Text("Add some dishes to get started")
                .font(AppFonts.body)
                .foregroundColor(AppColors.mediumGray)
                .multilineTextAlignment(.center)
            
            PrimaryButton(title: "Add Dish", action: {
                viewModel.addProductTapped()
            })
            .frame(width: 200)
            .padding(.top, 20)
        }
        .padding()
    }
    
    private var productListView: some View {
        List {
            ForEach(viewModel.filteredProducts) { product in
                ProductCell(product: product, onEdit: {
                    viewModel.editProduct(product)
                }, onToggle: { isActive in
                    viewModel.toggleProductStatus(product, isActive: isActive)
                })
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.deleteProduct(product)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .overlay(
            VStack {
                Spacer()
                
                Button(action: {
                    viewModel.addProductTapped()
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.white)
                        
                        Text("Add Dish")
                            .foregroundColor(.white)
                            .font(AppFonts.buttonText)
                    }
                    .padding()
                    .background(AppColors.primaryGreen)
                    .cornerRadius(25)
                    .shadow(radius: 3)
                    .padding(.bottom, 16)
                }
            }
        )
        .searchable(text: $viewModel.searchText, prompt: "Search menu items")
    }
}

// MARK: - Product Cell
struct ProductCell: View {
    let product: Product
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void
    @State private var refreshTrigger = UUID()
    
    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                // Product image or placeholder
                let timestamp = Int(Date().timeIntervalSince1970)
                let imageUrlString = "\(NetworkManager.baseURL)/get_product_photo/\(product.id)?v=\(timestamp)"
                if let imageUrl = URL(string: imageUrlString) {
                    AsyncImage(url: imageUrl, transaction: Transaction(animation: .easeInOut)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 80, height: 80)
                                .background(AppColors.lightGray)
                                .cornerRadius(10)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .cornerRadius(10)
                        case .failure:
                            Image(systemName: "photo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                                .frame(width: 80, height: 80)
                                .background(AppColors.lightGray)
                                .cornerRadius(10)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .id(refreshTrigger) // Force refresh when this ID changes
                    .onReceive(NotificationCenter.default.publisher(for: .productImageCacheCleared)) { notification in
                        if let productId = notification.userInfo?["productId"] as? String, 
                           productId == product.id {
                            // Force a reload of this product's image
                            refreshTrigger = UUID()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .productUpdated)) { notification in
                        if let productId = notification.userInfo?["productId"] as? String,
                           let imageUpdated = notification.userInfo?["imageUpdated"] as? Bool,
                           productId == product.id && imageUpdated {
                            // Force a reload of this product's image
                            refreshTrigger = UUID()
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .frame(width: 80, height: 80)
                        .background(AppColors.lightGray)
                        .cornerRadius(10)
                }
                
                // Product info
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(AppFonts.sectionTitle)
                        .foregroundColor(AppColors.darkGray)
                    
                    Text(product.description)
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.mediumGray)
                        .lineLimit(2)
                    
                    Text("₹\(String(format: "%.2f", product.price))")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryGreen)
                        .padding(.top, 4)
                }
                
                Spacer()
                
                // Active toggle
                Toggle("", isOn: Binding(
                    get: { product.isActive },
                    set: { onToggle($0) }
                ))
                .toggleStyle(SwitchToggleStyle(tint: AppColors.primaryGreen))
                .labelsHidden()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - ViewModel
class MenuViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var showErrorAlert: Bool = false
    
    @Published var showAddProductSheet: Bool = false
    @Published var selectedProduct: Product? = nil
    
    private var notificationObserver: NSObjectProtocol?
    
    init() {
        // Set up notification observer for product updates
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .productUpdated,
            object: nil,
            queue: .main) { [weak self] _ in
                self?.loadProducts()
            }
    }
    
    deinit {
        // Clean up notification observer
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // Computed property for filtered products
    var filteredProducts: [Product] {
        if searchText.isEmpty {
            return products
        } else {
            return products.filter { product in
                product.name.localizedCaseInsensitiveContains(searchText) ||
                product.description.localizedCaseInsensitiveContains(searchText) ||
                product.category.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // Load products from API
    func loadProducts() {
        isLoading = true
        
        Task {
            do {
                let fetchedProducts = try await ProductApi.shared.getAllProducts()
                
                DispatchQueue.main.async { [weak self] in
                    self?.products = fetchedProducts
                    self?.isLoading = false
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.isLoading = false
                    self?.errorMessage = error.localizedDescription
                    self?.showErrorAlert = true
                }
            }
        }
    }
    
    // Refresh products (for pull-to-refresh)
    func refreshProducts() async {
        do {
            let fetchedProducts = try await ProductApi.shared.getAllProducts()
            
            DispatchQueue.main.async { [weak self] in
                self?.products = fetchedProducts
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = error.localizedDescription
                self?.showErrorAlert = true
            }
        }
    }
    
    // Add product
    func addProductTapped() {
        showAddProductSheet = true
    }
    
    // Edit product
    func editProduct(_ product: Product) {
        selectedProduct = product
    }
    
    // Toggle product active status
    func toggleProductStatus(_ product: Product, isActive: Bool) {
        // Create a mutable copy of the product
        var updatedProduct = product
        updatedProduct.isActive = isActive
        
        Task {
            do {
                // Update product using ProductApi directly
                let _ = try await ProductApi.shared.createProduct(product: updatedProduct)
                
                // Update local product list
                await MainActor.run {
                    if let index = products.firstIndex(where: { $0.id == product.id }) {
                        products[index].isActive = isActive
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = error.localizedDescription
                    self?.showErrorAlert = true
                    
                    // Revert the toggle if there was an error
                    if let index = self?.products.firstIndex(where: { $0.id == product.id }) {
                        self?.products[index].isActive = !isActive
                    }
                }
            }
        }
    }
    
    // Delete product
    func deleteProduct(_ product: Product) {
        Task {
            do {
                // Delete product using ProductApi directly
                let success = try await ProductApi.shared.deleteProduct(productId: product.id)
                
                if success {
                    DispatchQueue.main.async { [weak self] in
                        self?.products.removeAll(where: { $0.id == product.id })
                    }
                } else {
                    throw NetworkError.serverError("Failed to delete product")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = error.localizedDescription
                    self?.showErrorAlert = true
                }
            }
        }
    }
} 