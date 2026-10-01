import SwiftUI

// Skeleton loading (Skeleton.kt): grey shapes with a soft moving highlight where content will appear, so a screen has its final shape at
// once and nothing jumps when data or photos arrive. Screen readers hear one "Loading" instead of a list of empty boxes.

/// A soft highlight sweeping across the shape.
struct Shimmer: ViewModifier {
    @State private var x: CGFloat = -1
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { g in
                LinearGradient(colors: [BucksColor.surfaceContainer, BucksColor.surfaceContainerHigh, BucksColor.surfaceContainer],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * 3).offset(x: x * g.size.width * 1.5 - g.size.width)
            }
        }
        .background(BucksColor.surfaceContainer)
        .clipped()
        .onAppear {
            guard !bucksReduceMotion else { return }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { x = 1 }
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

struct SkeletonBox: View {
    var radius: CGFloat = 8
    var body: some View { Color.clear.shimmer().clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)).accessibilityHidden(true) }
}

struct SkeletonLines: View {
    var lines = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<lines, id: \.self) { i in
                GeometryReader { g in SkeletonBox(radius: 6).frame(width: g.size.width * (i == lines - 1 ? 0.6 : 1)) }.frame(height: 12)
            }
        }.accessibilityHidden(true)
    }
}

/// A photo that shows a shimmering box while it downloads, then the picture; a plain box when it fails.
struct ShimmerImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: contentMode)
                case .failure: BucksColor.surfaceContainer
                default: Color.clear.shimmer()
                }
            }
        } else { BucksColor.surfaceContainer }
    }
}

/// Cards where the product grid will be.
struct ProductGridSkeleton: View {
    var rows = 3
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<2, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 0) {
                            SkeletonBox(radius: 12).aspectRatio(1, contentMode: .fit)
                            GeometryReader { g in SkeletonBox(radius: 6).frame(width: g.size.width * 0.9) }.frame(height: 14).padding(.top, 8)
                            GeometryReader { g in SkeletonBox(radius: 6).frame(width: g.size.width * 0.5) }.frame(height: 14).padding(.top, 6)
                            SkeletonBox(radius: 10).frame(height: 40).padding(.top, 8)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Loading products")
    }
}

/// The whole store profile before it arrives: cover, name, stats, buttons, tabs and the first cards.
struct ProfileSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonBox(radius: 0).frame(height: 140)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    SkeletonBox(radius: 32).frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 8) {
                        GeometryReader { g in SkeletonBox(radius: 6).frame(width: g.size.width * 0.6) }.frame(height: 20)
                        GeometryReader { g in SkeletonBox(radius: 6).frame(width: g.size.width * 0.4) }.frame(height: 12)
                    }
                }.padding(.top, 14)
                HStack(spacing: 20) { ForEach(0..<3, id: \.self) { _ in SkeletonBox(radius: 6).frame(width: 72, height: 34) } }.padding(.top, 16)
                HStack(spacing: 8) { SkeletonBox(radius: 10).frame(height: 44); SkeletonBox(radius: 10).frame(height: 44); SkeletonBox(radius: 10).frame(width: 44, height: 44) }.padding(.top, 16)
                HStack(spacing: 18) { ForEach(0..<5, id: \.self) { _ in SkeletonBox(radius: 6).frame(width: 52, height: 16) } }.padding(.top, 18).padding(.bottom, 14)
                ProductGridSkeleton(rows: 2)
            }.padding(.horizontal, Gutter)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Loading")
    }
}
