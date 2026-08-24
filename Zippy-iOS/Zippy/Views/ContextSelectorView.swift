// MARK: - ContextSelectorView.swift

import SwiftUI

/// A single black-and-white context selector consisting of four plain text options under a thin black header.
/// Supports selecting context for restaurants, trips, roommates, and everyday purchases
/// while preserving Zippy's stark monochrome visual language.
struct ContextSelectorView: View {
    @Binding var selectedCategory: ReceiptCategory?
    
    /// Whether the surrounding screen has a dark (black) background or light (white) background.
    var isDarkBackground: Bool = true
    
    /// Optional header title (defaults to "CONTEXT")
    var headerTitle: String = "CONTEXT"
    
    /// Optional callback when a category selection changes
    var onSelectionChanged: ((ReceiptCategory?) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Thin Black / Monochrome Header
            HStack(spacing: 8) {
                Text(headerTitle)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(isDarkBackground ? Color(white: 0.45) : Color(white: 0.55))
                    .tracking(1.2)
                
                Spacer()
                
                if selectedCategory != nil {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategory = nil
                            onSelectionChanged?(nil)
                        }
                    }) {
                        Text("CLEAR")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(isDarkBackground ? Color(white: 0.5) : Color(white: 0.5))
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)

            thinHeaderDivider()

            // MARK: - Four Plain Text Options
            // Organized in a clean 2x2 grid or horizontal wrap with plain text styling
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(ReceiptCategory.allCases) { category in
                    contextOptionButton(category)
                }
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Plain Text Option Button

    @ViewBuilder
    private func contextOptionButton(_ category: ReceiptCategory) -> some View {
        let isSelected = selectedCategory == category

        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                if selectedCategory == category {
                    // Tap again to deselect (optional tag)
                    selectedCategory = nil
                } else {
                    selectedCategory = category
                }
                onSelectionChanged?(selectedCategory)
            }
        }) {
            HStack(spacing: 6) {
                Text(category.displayName)
                    .font(.system(size: 12, weight: isSelected ? .bold : .regular, design: .monospaced))
                    .foregroundColor(textColor(isSelected: isSelected))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                if isSelected {
                    Text("●")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(textColor(isSelected: isSelected))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(backgroundColor(isSelected: isSelected))
            .overlay(
                Rectangle()
                    .stroke(borderColor(isSelected: isSelected), lineWidth: isSelected ? 1.0 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dynamic Black-and-White Theme Styling

    private func textColor(isSelected: Bool) -> Color {
        if isDarkBackground {
            return isSelected ? .black : .white
        } else {
            return isSelected ? .white : .black
        }
    }

    private func backgroundColor(isSelected: Bool) -> Color {
        if isDarkBackground {
            return isSelected ? .white : Color(white: 0.08)
        } else {
            return isSelected ? .black : Color(white: 0.96)
        }
    }

    private func borderColor(isSelected: Bool) -> Color {
        if isDarkBackground {
            return isSelected ? .white : Color(white: 0.25)
        } else {
            return isSelected ? .black : Color(white: 0.8)
        }
    }

    @ViewBuilder
    private func thinHeaderDivider() -> some View {
        Rectangle()
            .fill(isDarkBackground ? Color(white: 0.2) : Color.black)
            .frame(height: 0.5)
    }
}
