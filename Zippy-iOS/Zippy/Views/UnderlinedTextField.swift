// MARK: - UnderlinedTextField.swift

import SwiftUI

/// A minimalist black-and-white text field with NO borders except a thin 1px underline.
/// Adheres strictly to the monochrome aesthetic for manual entry and AI correction.
struct UnderlinedTextField: View {
    let placeholder: String
    @Binding var text: String
    var label: String? = nil
    var prefix: String? = nil
    var keyboardType: UIKeyboardType = .default
    var alignment: TextAlignment = .leading
    var isBold: Bool = false
    var isMonospaced: Bool = true
    var underlineColor: Color = .black
    var textColor: Color = .black
    var placeholderColor: Color = Color(white: 0.6)
    var onCommit: (() -> Void)? = nil
    var onChange: ((String) -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: alignment == .trailing ? .trailing : .leading, spacing: 4) {
            if let label = label, !label.isEmpty {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(textColor.opacity(0.6))
                    .tracking(0.8)
            }

            HStack(spacing: 4) {
                if let prefix = prefix, !prefix.isEmpty {
                    Text(prefix)
                        .font(fieldFont)
                        .fontWeight(isBold ? .bold : .regular)
                        .foregroundColor(textColor)
                }

                TextField(
                    "",
                    text: $text,
                    prompt: Text(placeholder).foregroundColor(placeholderColor).font(fieldFont)
                )
                .font(fieldFont)
                .fontWeight(isBold ? .bold : .regular)
                .foregroundColor(textColor)
                .multilineTextAlignment(alignment)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    onCommit?()
                }
                .onChange(of: text) { newValue in
                    onChange?(newValue)
                }
            }
            .padding(.vertical, 4)

            // The signature thin black underline (1px height)
            Rectangle()
                .fill(isFocused ? underlineColor : underlineColor.opacity(0.8))
                .frame(height: isFocused ? 1.5 : 1.0)
        }
    }

    private var fieldFont: Font {
        if isMonospaced {
            return .system(isBold ? .body : .subheadline, design: .monospaced)
        } else {
            return .system(isBold ? .body : .subheadline)
        }
    }
}
