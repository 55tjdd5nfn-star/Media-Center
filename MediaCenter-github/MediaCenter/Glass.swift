import SwiftUI

extension View {
    func liquidGlass(cornerRadius: CGFloat = 16) -> some View {
        Group {
            if #available(macOS 26, *) {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            }
        }
    }

    func liquidGlassButton(cornerRadius: CGFloat = 12) -> some View {
        Group {
            if #available(macOS 26, *) {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            }
        }
    }

    func bigGlassButton(cornerRadius: CGFloat = 14) -> some View {
        self
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 0)
            .frame(height: 36)
            .liquidGlassButton(cornerRadius: cornerRadius)
    }

    func playGlassButton(cornerRadius: CGFloat = 14) -> some View {
        self
            .font(.title3)
            .padding(.horizontal, 14)
            .padding(.vertical, 0)
            .frame(height: 44)
            .liquidGlassButton(cornerRadius: cornerRadius)
    }
}
