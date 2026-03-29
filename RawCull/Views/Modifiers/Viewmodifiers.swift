//
//  Viewmodifiers.swift
//  RsyncSwiftUI
//
//  Created by Thomas Evensen on 19/02/2021.
//

import Foundation
import SwiftUI

struct ToggleViewDefault: View {
    @Environment(\.colorScheme) var colorScheme
    private var mytext: String?
    private var mybinding: Binding<Bool>

    var body: some View {
        HStack {
            Toggle(mytext ?? "", isOn: mybinding)
                .labelsHidden()
                // .toggleStyle(CheckboxToggleStyle())
                .toggleStyle(.switch)

            Text(mytext ?? "")
                .foregroundColor(mybinding.wrappedValue ? .blue : (colorScheme == .dark ? .white : .black))
                .toggleStyle(CheckboxToggleStyle())
        }
    }

    init(text: String, binding: Binding<Bool>) {
        mytext = text
        mybinding = binding
    }
}

