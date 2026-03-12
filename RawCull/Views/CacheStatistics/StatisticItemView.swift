import SwiftUI

struct StatisticItemView: View {
    let imagelabel: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: imagelabel)
                .font(.system(size: 12, weight: .semibold))

            Text("\(value)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(color.opacity(0.1))
        .clipShape(.rect(cornerRadius: 6))
    }
}
