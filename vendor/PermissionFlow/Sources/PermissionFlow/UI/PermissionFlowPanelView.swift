#if os(macOS)
import SwiftUI

@available(macOS 13.0, *)
struct PermissionFlowPanelView: View {
    @ObservedObject var controller: PermissionFlowController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let primaryApp = controller.preferredAppURL {
                AppDragItemView(url: primaryApp) { isDragging in
                    controller.setPanelDragging(isDragging)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
                )
        )
    }

    /// Keeps the header logic isolated from the drag card layout.
    private var header: some View {
        HStack(alignment: .top, spacing: 3) {
            VStack(alignment: .leading, spacing: 7) {
                if controller.guidanceSteps.isEmpty {
                    Text(headerTitle).font(.system(size: 14)).lineLimit(1)
                } else {
                    ForEach(controller.guidanceSteps.indices, id: \.self) { index in
                        let step = controller.guidanceSteps[index]
                        let active = controller.currentPane == step.pane && !step.granted
                        HStack(spacing: 7) {
                            Group {
                                if step.granted {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                } else if active {
                                    HeaderDirectionIcon(isDragging: controller.isDraggingApp)
                                } else {
                                    Image(systemName: "circle").foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 18, height: 18)
                            Text(stepTitle(index + 1))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                            Text(step.pane.localizedTitle(localeIdentifier: controller.localeIdentifier))
                                .font(.system(size: 13, weight: active ? .semibold : .regular))
                                .foregroundStyle(step.granted ? .secondary : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    Text(headerTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .help(String(headerTitle.characters))
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 3) {
                Button {
                    controller.reopenCurrentSettingsPane()
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, .secondary.opacity(0.35))
                }
                .buttonStyle(.borderless)
                .opacity(controller.isSettingsFrontmost ? 0 : 1)
                .allowsHitTesting(!controller.isSettingsFrontmost)
                .accessibilityHidden(controller.isSettingsFrontmost)
                Button {
                    controller.closePanel(returnToPreviousApp: true)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, .secondary.opacity(0.35))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func stepTitle(_ step: Int) -> String {
        let template = PermissionFlowLocalizer.string(
            "permission_flow.panel.step",
            defaultValue: "Step %d",
            localeIdentifier: controller.localeIdentifier
        )
        return String(format: template, locale: localizationLocale, step)
    }

    /// Builds a markdown-backed localized title such as:
    /// "Drag **Example** to the list above to allow **Accessibility**."
    private var headerTitle: AttributedString {
        let localizedTemplate = PermissionFlowLocalizer.string(
            "permission_flow.panel.title",
            defaultValue: "Drag the app above to allow **%2$@**.",
            localeIdentifier: controller.localeIdentifier
        )

        let markdown = String(
            format: localizedTemplate,
            locale: localizationLocale,
            appDisplayName,
            paneDisplayTitle
        )

        return (try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    /// Prefers the Finder-style display name so the title reads naturally even
    /// when the URL contains a plain bundle filename.
    private var appDisplayName: String {
        guard let appURL = controller.preferredAppURL else {
            return PermissionFlowLocalizer.string(
                "permission_flow.app.this_app",
                defaultValue: "This App",
                localeIdentifier: controller.localeIdentifier
            )
        }

        return FileManager.default.displayName(atPath: appURL.path)
    }

    /// Uses the current pane's localized title so each permission can render a
    /// specific instruction in the shared panel title template.
    private var paneDisplayTitle: String {
        controller.currentPane?.localizedTitle(localeIdentifier: controller.localeIdentifier)
            ?? PermissionFlowLocalizer.string(
                "permission_flow.pane.permission",
                defaultValue: "Permission",
                localeIdentifier: controller.localeIdentifier
            )
    }

    /// Uses the explicitly injected panel locale when available.
    private var localizationLocale: Locale {
        controller.localeIdentifier.map(Locale.init(identifier:)) ?? .current
    }
}

@available(macOS 13.0, *)
private struct HeaderDirectionIcon: View {
    let isDragging: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wigglePhase = false
    @State private var scalePhase = false

    var body: some View {
        Image(systemName: "arrowshape.up.fill")
            .font(.system(size: 14, weight: .bold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .rotationEffect(.degrees(0))
            .offset(y: reduceMotion || isDragging ? 0 : (wigglePhase ? -2 : 1))
            .scaleEffect(!reduceMotion && isDragging ? (scalePhase ? 1.08 : 0.96) : 1)
            .animation(
                reduceMotion ? nil : isDragging
                    ? .easeInOut(duration: 0.68).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.65).repeatForever(autoreverses: true),
                value: isDragging ? scalePhase : wigglePhase
            )
            .onAppear {
                wigglePhase = true
            }
            .onChange(of: isDragging) { dragging in
                if dragging {
                    scalePhase = true
                    wigglePhase = false
                } else {
                    scalePhase = false
                    wigglePhase = true
                }
            }
    }
}
#endif
