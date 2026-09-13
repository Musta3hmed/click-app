//
//  CreateCommunitySheet.swift
//  Click
//
//  A creation REQUEST, not a creation: the community starts pending and
//  is invisible to everyone except its creator and the admin panel until
//  a human approves it. Symbols and tints come from curated lists — the
//  only user-written text is the name and summary, and neither renders
//  to other people before approval.
//

import SwiftUI
import SwiftData

struct CreateCommunitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var summary = ""
    @State private var symbolName = Self.symbols[0]
    @State private var tintToken = Self.tints[0]
    @State private var interestIDs: Set<String> = []
    @State private var submitted = false

    /// Curated pickable symbols — a bad SF Symbol name renders as
    /// nothing, so free entry is not offered.
    static let symbols = [
        "sparkles", "music.note.house.fill", "film.fill", "gamecontroller.fill",
        "book.fill", "figure.run", "cup.and.saucer.fill", "paintbrush.fill",
        "airplane", "leaf.fill", "camera.fill", "soccerball",
    ]

    static let tints = [
        "brandPink", "brandOrange", "brandViolet", "brandGold",
        "brandMagenta", "brandCoral", "online", "verified",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if submitted {
                    submittedState
                } else {
                    form
                }
            }
            .background(Theme.background)
            .navigationTitle("new community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel") { dismiss() }
                        .font(.clickPlain(.body, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .accessibilityLabel("Cancel")
                }
            }
        }
        .presentationDetents([.large])
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("every new community is reviewed by an admin before anyone can see or join it.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("name")
                TextField("lowercase, short and clear", text: $name)
                    .font(.click(.title3, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous))
                    .accessibilityLabel("Community name")
                    .onChange(of: name) { _, newValue in
                        if newValue.count > CommunityService.maxNameLength {
                            name = String(newValue.prefix(CommunityService.maxNameLength))
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("what it's about")
                TextField("one line", text: $summary)
                    .font(.clickPlain(.body, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous))
                    .accessibilityLabel("Community summary")
                    .onChange(of: summary) { _, newValue in
                        if newValue.count > CommunityService.maxSummaryLength {
                            summary = String(newValue.prefix(CommunityService.maxSummaryLength))
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("icon")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button {
                            symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundStyle(symbolName == symbol ? Theme.onPrimary : Theme.primary)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(symbolName == symbol ? Theme.primary : Theme.surface))
                        }
                        .buttonStyle(.clickQuiet)
                        .accessibilityLabel("Icon \(symbol)")
                        .accessibilityAddTraits(symbolName == symbol ? [.isSelected, .isButton] : .isButton)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("colour")
                HStack(spacing: 10) {
                    ForEach(Self.tints, id: \.self) { token in
                        Button {
                            tintToken = token
                        } label: {
                            Circle()
                                .fill(CommunityService.tint(token))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if tintToken == token {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .heavy))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.clickQuiet)
                        .accessibilityLabel("Colour \(token)")
                        .accessibilityAddTraits(tintToken == token ? [.isSelected, .isButton] : .isButton)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("related interests")
                Text("helps people with those interests find it.")
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                InterestPicker(selected: interestIDs, limit: 5) { id in
                    if interestIDs.contains(id) {
                        interestIDs.remove(id)
                    } else if interestIDs.count < 5 {
                        interestIDs.insert(id)
                    }
                }
            }

            Button {
                submit()
            } label: {
                Text("send for approval")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.click)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send for approval")
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.top, 20)
        .padding(.bottom, 40)
    }

    private var submittedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.brandPink)
                .accessibilityHidden(true)
            Text("sent for approval")
                .font(.click(.title2, weight: .heavy))
                .foregroundStyle(Theme.primary)
            Text("an admin reviews every new community. you'll see it in your list as waiting until then.")
                .font(.clickPlain(.subheadline, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            Button {
                dismiss()
            } label: {
                Text("done")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.click)
            .padding(.top, 8)
            .accessibilityLabel("Done")
        }
        .padding(Theme.Metric.gutter)
        .padding(.top, 56)
    }

    private func submit() {
        let created = CommunityService.requestCreation(
            name: name,
            summary: summary,
            symbolName: symbolName,
            tintToken: tintToken,
            interestIDs: Array(interestIDs),
            in: context
        )
        guard created != nil else { return }
        Haptics.notify(.success)
        submitted = true
    }
}

#Preview {
    CreateCommunitySheet()
        .modelContainer(MockData.previewContainer)
}
