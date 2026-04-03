import SwiftUI

struct RatingPickerSection: View {
    @Binding var rating: Int

    var body: some View {
        VStack {
            Label("Minimum Rating", systemImage: "star.fill")
                .foregroundStyle(.secondary)

            Spacer()

            Picker("Rating", selection: $rating) {
                ForEach(2 ... 5, id: \.self) { number in
                    HStack {
                        ForEach(0 ..< number, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.caption)
                        }
                        Text("\(number)")
                    }
                    .tag(number)
                }
            }
            .pickerStyle(DefaultPickerStyle())
            .frame(width: 120)
        }
        .padding(.vertical, 4)
    }
}
