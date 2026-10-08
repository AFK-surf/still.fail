import SwiftUI

enum Size {
  static let handle: CGFloat = 26
  /// The edge's sliver while something waits: thin, the loudest mark's colour in its glass.
  static let sliver = CGSize(width: 7, height: 72)
  static let peek = CGSize(width: 320, height: 64)
  static let card: CGFloat = 340
  /// Between the card and the handle at rest: wider than the glass's blending distance, so the two stand apart.
  static let gap: CGFloat = 22
  static let margin: CGFloat = 12
  /// Glass shapes closer than this melt together (GlassEffectContainer): the card pulls a neck off the handle as it goes.
  static let blend: CGFloat = 18
}

/// still.fail's accent (web/src/styles/global.css.ts `--accent`, oklch(68% .175 39)).
let accent = Color(red: 0.91, green: 0.455, blue: 0.231)

/// The dock along the screen's right edge, all of it one glass container: the handle (a half circle, flush with the
/// edge), which stretches into the peek; and the card, a second piece that pours out of it and is drawn back in.
struct DockView: View {
  @Bindable var model: DockModel
  var send: (Outgoing) -> Void
  /// The card's measured height, and whether it is out: its glass is in the tree while it opens and closes, at the
  /// handle's size and place when closed, so both ways are one continuous change of shape.
  @State private var cardHeight: CGFloat = 220
  @State private var cardShown = false
  @State private var cardOut = false
  @State private var grab: CGFloat = 0

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width, height = proxy.size.height
      let handleY = clampY(model.handleY == 0 ? height * 0.42 : model.handleY, half: handleSize.height / 2, height: height)
      let cardY = clampY(handleY, half: cardHeight / 2, height: height)

      glassGroup {
        ZStack(alignment: .topLeading) {
          if cardShown {
            let size = cardOut ? CGSize(width: Size.card, height: cardHeight) : closedCard
            CardView(model: model, send: send)
              .frame(width: Size.card)
              .fixedSize(horizontal: false, vertical: true)
              .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
              .opacity(cardOut ? 1 : 0)
              .frame(width: size.width, height: size.height, alignment: .topLeading)
              .clipped()
              .glass(RoundedRectangle(cornerRadius: cardOut ? 26 : size.height / 2, style: .continuous), clear: false)
              .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.cardRect = $0 }
              .position(x: cardOut ? width - Size.handle - Size.gap - Size.card / 2 : width - size.width / 2,
                        y: cardOut ? cardY : handleY)
          }
          handle
            .glass(UnevenRoundedRectangle(topLeadingRadius: handleRadius, bottomLeadingRadius: handleRadius,
                                          bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous), clear: true, tint: sliverTint)
            .opacity(handleSize.width > 0 ? 1 : 0)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.handleRect = $0 }
            .position(x: width - handleSize.width / 2, y: handleY)
            .gesture(drag(height: height))
            .contextMenu { Button(model.words.hide) { send(.off) } }
        }
        .frame(width: width, height: height)
      }
      .onChange(of: model.phase) { old, phase in
        if phase == .card { open(from: old) } else if cardShown { close() }
      }
    }
  }

  private var peeking: Bool { model.phase == .peek && model.peeking != nil }
  /// Nothing waiting: no glass at all. Something: a sliver on the edge. A peek: the capsule it stretches into.
  private var handleSize: CGSize {
    peeking ? Size.peek : model.items.isEmpty ? CGSize(width: 0, height: Size.sliver.height) : Size.sliver
  }
  private var handleRadius: CGFloat { peeking ? Size.peek.height / 2 : Size.sliver.width / 2 }
  private var sliverTint: Color? {
    guard !peeking, let loudest = model.items.first?.tone else { return nil }
    return loudest == "alert" ? MarkView.red : MarkView.blue
  }
  /// The card's shape before it comes out and after it goes back: the peek's it came from, or the handle's.
  @State private var closedCard = Size.sliver

  private func clampY(_ y: CGFloat, half: CGFloat, height: CGFloat) -> CGFloat {
    min(max(y, half + Size.margin), height - half - Size.margin)
  }

  private func open(from old: Phase) {
    closedCard = old == .peek ? Size.peek : Size.sliver
    cardShown = true
    // A frame later, so it starts from the closed shape.
    DispatchQueue.main.async {
      withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) { cardOut = true }
    }
  }

  private func close() {
    closedCard = Size.sliver
    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { cardOut = false } completion: {
      if model.phase != .card { cardShown = false; model.cardRect = .zero }
    }
  }

  @ViewBuilder private var handle: some View {
    ZStack {
      if peeking, let item = model.peeking {
        HStack(spacing: 10) {
          MarkView(tone: item.tone).frame(width: 12)
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
              Text(item.station).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
              Spacer(minLength: 0)
              if model.unseen > 1 {
                Text("+\(model.unseen - 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
              }
            }
            Text(item.ask.map { "\(model.words.waiting) · \($0)" } ?? item.text)
              .font(.system(size: 12)).lineLimit(1)
              .foregroundStyle(item.ask != nil ? Color.blue : .secondary)
          }
        }
        .padding(.leading, 20).padding(.trailing, 14)
        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
      }
    }
    .frame(width: handleSize.width, height: handleSize.height)
    .contentShape(Rectangle())
  }

  private func drag(height: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .global)
      .onChanged { value in
        // Pushed back to the edge, the peek goes in; otherwise the handle moves along the edge.
        if peeking, value.translation.width > 36, abs(value.translation.width) > abs(value.translation.height) {
          withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { model.putAway() }
          return
        }
        if !model.dragging {
          model.dragging = true
          grab = value.startLocation.y - (model.handleY == 0 ? height * 0.42 : model.handleY)
        }
        model.handleY = min(max(value.location.y - grab, 40), height - 40)
      }
      .onEnded { _ in model.dragging = false }
  }
}

/// The messages one under another, scrolled as any list is and settling on one at a time (the system's scrolling,
/// aligned to each); the card is as tall as the one it settled on.
struct CardView: View {
  @Bindable var model: DockModel
  var send: (Outgoing) -> Void
  @State private var heights: [String: CGFloat] = [:]
  @State private var position: String?

  var body: some View {
    if model.items.isEmpty {
      Text(model.words.empty).font(.system(size: 13)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity).padding(.vertical, 26)
    } else {
      let shown = model.items.indices.contains(model.current) ? model.items[model.current].id : model.items[0].id
      ScrollView(.vertical) {
        VStack(spacing: 0) {
          ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
            content(item, index: index)
              .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[item.id] = $0 }
              .id(item.id)
          }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.viewAligned)
      .scrollPosition(id: $position, anchor: .top)
      .scrollIndicators(.never)
      .frame(height: heights[shown] ?? 200)
      .animation(.spring(response: 0.35, dampingFraction: 0.8), value: heights[shown])
      .onAppear { position = shown }
      // One dealt with leaves the list: settle on what is now in its place.
      .onChange(of: model.items.map(\.id)) { position = shown }
      .onChange(of: position) { _, id in
        if let id, let index = model.items.firstIndex(where: { $0.id == id }) { model.current = index }
      }
    }
  }

  private func content(_ item: Item, index: Int) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        MarkView(tone: item.tone).frame(width: 10)
        Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        Text("\(item.station) · \(ago(item.at))").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        Spacer(minLength: 4)
        if model.items.count > 1 {
          Text("\(index + 1) / \(model.items.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
        }
      }
      VStack(alignment: .leading, spacing: 3) {
        if let who = item.who { Text(who).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
        Text(item.text).font(.system(size: 13)).lineSpacing(3).lineLimit(7).fixedSize(horizontal: false, vertical: true)
      }
      if let ask = item.ask {
        Text(ask).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
      }
      actions(item)
    }
    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
  }

  @ViewBuilder private func actions(_ item: Item) -> some View {
    let later = Button(model.words.later) { send(.later) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
    if let options = item.options, !options.isEmpty {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 6) {
          ForEach(options, id: \.self) { o in option(o, item) }
          Spacer(minLength: 4)
          Button(model.words.open) { send(.open(item)) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
          later
        }
        VStack(alignment: .leading, spacing: 6) {
          ForEach(options, id: \.self) { o in option(o, item) }
          HStack(spacing: 12) {
            Button(model.words.open) { send(.open(item)) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            later
          }
        }
      }
    } else {
      HStack(spacing: 6) {
        Button(model.words.open) { send(.open(item)) }.glassButton(prominent: false)
        // A card to write an answer to is answered in its chat: nothing to mark read here.
        if item.tone != "wait" { Button(model.words.read) { send(.read(item)) }.glassButton(prominent: false) }
        Spacer(minLength: 4)
        later
      }
    }
  }

  private func option(_ o: Option, _ item: Item) -> some View {
    Button(o.label) { send(.answer(item, o.label)) }.glassButton(prominent: o.recommended == true)
  }

  private func ago(_ ms: Double) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: model.words.locale)
    f.unitsStyle = .short
    let date = Date(timeIntervalSince1970: ms / 1000)
    return Date().timeIntervalSince(date) < 60 ? f.localizedString(fromTimeInterval: 0) : f.localizedString(for: date, relativeTo: Date())
  }
}

/// ChatMark's dot in a line (web/src/ChatMark.css.ts chatMarkInline): blue dot unread, red failed, blue ring waiting.
struct MarkView: View {
  let tone: String
  static let blue = Color(red: 0x3b / 255, green: 0x82 / 255, blue: 0xf6 / 255)
  static let red = Color(red: 0xe5 / 255, green: 0x48 / 255, blue: 0x4d / 255)

  var body: some View {
    switch tone {
    case "wait": Circle().strokeBorder(Self.blue, lineWidth: 2).frame(width: 10, height: 10)
    case "alert":
      Circle().fill(Self.red).frame(width: 8, height: 8)
        .background(Circle().fill(Self.red.opacity(0.25)).frame(width: 14, height: 14))
    default: Circle().fill(Self.blue).frame(width: 8, height: 8)
    }
  }
}

extension View {
  /// Liquid Glass on macOS 26: clear (the most see-through, for the handle) or regular (for the card's text); a
  /// material before it.
  @ViewBuilder func glass<S: Shape>(_ shape: S, clear: Bool, tint: Color? = nil) -> some View {
    if #available(macOS 26, *) {
      glassEffect((clear ? Glass.clear : .regular).tint(tint?.opacity(0.55)).interactive(clear), in: shape)
    } else {
      background(tint.map { AnyShapeStyle($0.opacity(0.5)) } ?? AnyShapeStyle(.ultraThinMaterial), in: shape)
    }
  }

  @ViewBuilder func glassButton(prominent: Bool) -> some View {
    if #available(macOS 26, *) {
      if prominent { buttonStyle(.glassProminent).tint(accent) } else { buttonStyle(.glass) }
    } else {
      if prominent { buttonStyle(.borderedProminent).tint(accent) } else { buttonStyle(.bordered) }
    }
  }
}

/// The glass container on macOS 26 (shapes near each other melt together), plain before it.
@ViewBuilder func glassGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
  if #available(macOS 26, *) {
    GlassEffectContainer(spacing: Size.blend) { content() }
  } else {
    content()
  }
}
