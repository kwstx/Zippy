// MARK: - SplitMethodSegmentedControl.swift

import SwiftUI

/// A stark black-and-white segmented control built with pure text labels.
/// Allows switching between Equal, Itemized, Percentage, Shares, and Exact split methods
/// following Zippy's minimalist monochrome aesthetic.
struct SplitMethodSegmentedControl: View {
    @Binding var selectedMethod: SplitMethod
    var onMethodChanged: ((SplitMethod) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section Header
            HStack {
                Text("SPLIT METHOD")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(1.2)
                Spacer()
                Text(selectedMethod.title.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.7))
            }
            .padding(.top, 4)

            // Pure Text Segmented Control
            HStack(spacing: 0) {
                ForEach(SplitMethod.allCases) { method in
                    let isSelected = selectedMethod == method

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedMethod = method
                            onMethodChanged?(method)
                        }
                    }) {
                        Text(method.textLabel)
                            .font(.system(size: 10, weight: isSelected ? .bold : .regular, design: .monospaced))
                            .foregroundColor(isSelected ? .black : Color(white: 0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(isSelected ? Color.white : Color.black)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Subtle vertical divider between items (except last)
                    if method != SplitMethod.allCases.last {
                        Rectangle()
                            .fill(Color(white: 0.2))
                            .frame(width: 0.5, height: 32)
                    }
                }
            }
            .overlay(
                Rectangle()
                    .stroke(Color(white: 0.3), lineWidth: 0.5)
            )

            // Method Description
            Text(selectedMethod.description)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
                .padding(.top, 2)
        }
    }
}
