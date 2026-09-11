//
//  OnboardingMediaSteps.swift
//  Click
//
//  The photo and location steps. Both write straight into the current
//  user's profile row as the user acts, so killing the app loses nothing.
//

import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Step 5: photos

struct PhotosStep: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importFailed = false

    private let maxPhotos = 6
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(profile.orderedPhotos) { photo in
                    PhotoCell(
                        photo: photo,
                        isPrimary: photo.sortIndex == 0,
                        onDelete: { delete(photo) }
                    )
                    .draggable(photo.id.uuidString)
                    .dropDestination(for: String.self) { dropped, _ in
                        guard let idString = dropped.first else { return false }
                        move(idString: idString, before: photo)
                        return true
                    }
                }

                if profile.photos.count < maxPhotos {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: maxPhotos - profile.photos.count,
                        matching: .images
                    ) {
                        addTile
                    }
                    .accessibilityLabel("Add photos")
                }
            }

            if isImporting {
                ProgressView("adding…")
                    .font(.clickPlain(.footnote, weight: .medium))
            }

            if importFailed {
                Text("Some photos couldn't be added. Try different ones.")
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

            Spacer(minLength: 0)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            importPhotos(items)
        }
    }

    private var addTile: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Theme.separator, style: StrokeStyle(lineWidth: 2, dash: [6]))
            .background(
                Theme.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.secondary)
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }

    // MARK: Import / reorder / delete

    private func importPhotos(_ items: [PhotosPickerItem]) {
        isImporting = true
        importFailed = false
        Task {
            var nextIndex = (profile.orderedPhotos.last?.sortIndex ?? -1) + 1
            var anyFailed = false

            for item in items {
                guard profile.photos.count < maxPhotos else { break }
                if let raw = try? await item.loadTransferable(type: Data.self),
                   let jpeg = ImageProcessing.downscaledJPEG(from: raw) {
                    let photo = ProfilePhoto(data: jpeg, sortIndex: nextIndex, owner: profile)
                    context.insert(photo)
                    nextIndex += 1
                } else {
                    anyFailed = true
                }
            }

            try? context.save()
            pickerItems = []
            isImporting = false
            importFailed = anyFailed
            if !anyFailed { Haptics.notify(.success) }
        }
    }

    private func move(idString: String, before target: ProfilePhoto) {
        guard let id = UUID(uuidString: idString),
              let source = profile.photos.first(where: { $0.id == id }),
              source.id != target.id else { return }

        var ordered = profile.orderedPhotos
        ordered.removeAll { $0.id == source.id }
        let targetPosition = ordered.firstIndex { $0.id == target.id } ?? ordered.count
        ordered.insert(source, at: targetPosition)

        for (index, photo) in ordered.enumerated() {
            photo.sortIndex = index
        }
        try? context.save()
        Haptics.selection()
    }

    private func delete(_ photo: ProfilePhoto) {
        context.delete(photo)
        for (index, remaining) in profile.orderedPhotos.enumerated() {
            remaining.sortIndex = index
        }
        try? context.save()
        Haptics.impact(.light)
    }
}

private struct PhotoCell: View {
    let photo: ProfilePhoto
    let isPrimary: Bool
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: photo.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.separator
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .padding(6)
            .accessibilityLabel("Remove photo")
        }
        .overlay(alignment: .bottomLeading) {
            if isPrimary {
                Text("main")
                    .font(.click(.caption2, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.brandPink, in: Capsule())
                    .padding(6)
            }
        }
        .accessibilityLabel(isPrimary ? "Main photo" : "Photo")
        .accessibilityHint("Drag onto another photo to reorder")
    }
}

// MARK: - Step 6: location

struct LocationStep: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var service = LocationService()
    @State private var manualCity = ""
    @State private var manualRegionCode = Locale.current.region?.identifier ?? "AU"
    @State private var showManualEntry = false

    var body: some View {
        VStack(spacing: 16) {
            if let city = profile.city, let country = profile.country {
                confirmedCard(city: city, country: country)
            }

            switch service.phase {
            case .idle, .requestingPermission:
                if profile.city == nil {
                    locateButton
                }
            case .locating:
                ProgressView("finding your city…")
                    .font(.clickPlain(.footnote, weight: .medium))
            case .located:
                EmptyView()  // Saved via onChange below; card above shows it.
            case .denied:
                deniedCard
            case .failed(let message):
                Text(message)
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
            }

            if showManualEntry || service.phase == .denied || isFailedPhase {
                manualEntry
            } else if profile.city == nil {
                Button("enter my city manually") {
                    showManualEntry = true
                }
                .font(.clickPlain(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .accessibilityLabel("Enter my city manually")
            }

            Spacer(minLength: 0)
        }
        .onChange(of: service.phase) { _, phase in
            if case .located(let place) = phase {
                save(place)
            }
        }
    }

    private var isFailedPhase: Bool {
        if case .failed = service.phase { return true }
        return false
    }

    private var locateButton: some View {
        Button {
            service.requestLocation()
        } label: {
            Label("use my location", systemImage: "location.fill")
                .font(.click(.headline, weight: .bold))
                .foregroundStyle(Theme.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.primary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use my location")
    }

    private func confirmedCard(city: String, country: String) -> some View {
        HStack(spacing: 10) {
            Text(profile.countryFlag)
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text(city)
                    .font(.click(.headline, weight: .bold))
                    .foregroundStyle(Theme.primary)
                Text(country)
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button("change") {
                showManualEntry = true
            }
            .font(.clickPlain(.footnote, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .accessibilityLabel("Change location")
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Location: \(city), \(country)")
    }

    private var deniedCard: some View {
        VStack(spacing: 10) {
            Label("location is off for Click", systemImage: "location.slash.fill")
                .font(.click(.headline, weight: .bold))
                .foregroundStyle(Theme.primary)
            Text("No problem — pick your city below, or turn location on in Settings.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            Button("open settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.clickPlain(.subheadline, weight: .bold))
            .foregroundStyle(Theme.brandPink)
            .accessibilityLabel("Open Settings")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var manualEntry: some View {
        VStack(spacing: 12) {
            TextField("your city", text: $manualCity)
                .font(.clickPlain(.body, weight: .medium))
                .textContentType(.addressCity)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Theme.surface, in: Capsule())
                .accessibilityLabel("City")

            Picker("Country", selection: $manualRegionCode) {
                ForEach(Self.regionChoices, id: \.code) { choice in
                    Text(choice.name).tag(choice.code)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.primary)
            .accessibilityLabel("Country")

            PillButton(
                title: "save city",
                isEnabled: !manualCity.trimmingCharacters(in: .whitespaces).isEmpty
            ) {
                saveManual()
            }
        }
    }

    // MARK: Persistence

    private func save(_ place: CoarsePlace) {
        profile.city = place.city
        profile.country = place.country
        profile.countryCode = place.countryCode
        profile.countryFlag = UserProfile.flag(forCountryCode: place.countryCode)
        try? context.save()
        showManualEntry = false
        Haptics.notify(.success)
    }

    private func saveManual() {
        let name = Locale.current.localizedString(forRegionCode: manualRegionCode) ?? manualRegionCode
        save(CoarsePlace(
            city: manualCity.trimmingCharacters(in: .whitespaces),
            country: name,
            countryCode: manualRegionCode
        ))
    }

    /// All ISO regions the system knows, sorted by localized name.
    private static let regionChoices: [(code: String, name: String)] = {
        Locale.Region.isoRegions
            .filter { $0.subRegions.isEmpty }  // countries, not continents
            .compactMap { region in
                let code = region.identifier
                guard code.count == 2,
                      let name = Locale.current.localizedString(forRegionCode: code) else { return nil }
                return (code, name)
            }
            .sorted { $0.name < $1.name }
    }()
}
