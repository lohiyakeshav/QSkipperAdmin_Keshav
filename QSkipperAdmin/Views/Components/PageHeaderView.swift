import SwiftUI

struct PageHeaderView: View {
    let title: String
    let subtitle: String
    let iconName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 24))
                    .foregroundColor(Color(AppColors.primaryGreen))
                    .frame(width: 40, height: 40)
                    .background(Color(AppColors.primaryGreen).opacity(0.1))
                    .cornerRadius(10)
                
                // Title and subtitle
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppFonts.title)
                        .foregroundColor(Color(AppColors.darkGray))
                    
                    Text(subtitle)
                        .font(AppFonts.caption)
                        .foregroundColor(Color(AppColors.mediumGray))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 16)
    }
}

struct PageHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        PageHeaderView(
            title: "Products",
            subtitle: "Manage your product catalog",
            iconName: "cube.box.fill"
        )
        .previewLayout(.sizeThatFits)
    }
} 