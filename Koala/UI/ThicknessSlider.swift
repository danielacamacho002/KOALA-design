//
//  ThicknessSlider.swift
//  Koala
//

import SwiftUI

struct ThicknessSlider: View {
    @Binding var strokeWidth: CGFloat
    var units: MeasurementUnit = .inches

    private let range: ClosedRange<CGFloat> = 0.5...48
    private let trackHeight: CGFloat = 120

    private var normalized: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (strokeWidth - range.lowerBound) / span
    }

    var body: some View {
        VStack(spacing: 12) {
            strokePreview

            verticalTrack

            Text(formattedWidth)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
    }

    private var strokePreview: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.primary)
            .frame(width: previewWidth, height: 32)
            .animation(.snappy(duration: 0.2), value: strokeWidth)
    }

    private var previewWidth: CGFloat {
        min(22, max(1.5, strokeWidth * 0.85))
    }

    private var formattedWidth: String {
        let display = units.fromDocumentUnits(strokeWidth)
        let label = units.shortLabel
        if display.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(display)) \(label)"
        }
        return "\(units.formatted(display, extraDigits: -1)) \(label)"
    }

    private var verticalTrack: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let thumbY = height * (1 - normalized)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 3)

                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 3, height: max(4, height * normalized))

                Circle()
                    .fill(Color(.systemBackground))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .position(x: geometry.size.width / 2, y: thumbY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        setWidth(fromY: value.location.y, in: height)
                    }
            )
        }
        .frame(width: 28, height: trackHeight)
    }

    private func setWidth(fromY y: CGFloat, in height: CGFloat) {
        let clampedY = min(max(0, y), height)
        let t = 1 - (clampedY / height)
        let raw = range.lowerBound + t * (range.upperBound - range.lowerBound)
        strokeWidth = (raw * 2).rounded() / 2
        strokeWidth = min(range.upperBound, max(range.lowerBound, strokeWidth))
    }
}

#if DEBUG
#Preview {
    struct PreviewWrapper: View {
        @State private var width: CGFloat = 4
        var body: some View {
            ThicknessSlider(strokeWidth: $width, units: .inches)
                .padding()
        }
    }
    return PreviewWrapper()
}
#endif
