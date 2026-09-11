//
//  DemoPhotos.swift
//  Click
//
//  Runtime demo photos for the seeded profiles. Nothing is committed to
//  the repo (it is public): AI-generated faces — no real person's likeness —
//  are fetched once from this-person-does-not-exist.com, downscaled through
//  the same ImageProcessing path as user photos, and cached into
//  ProfilePhoto storage so the app works offline thereafter. On any
//  failure a profile simply keeps its gradient card.
//

import Foundation
import SwiftData

enum DemoPhotos {

    private static let base = URL(string: "https://this-person-does-not-exist.com")!

    /// Fetch 2–4 gender-matched faces for every candidate profile that has
    /// none. Progressive: each profile's photos save as they arrive, so
    /// cards fill in while the app is used. Safe to call on every launch.
    private static let lastFailureKey = "demoPhotosLastFailure"

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) async {
        // UI tests seed their own deterministic photos.
        guard !CommandLine.arguments.contains(where: { $0.hasPrefix("--uitest") }) else { return }

        // Backoff: if the source was unreachable recently, don't burn a
        // long serial retry (dozens of 10–15s timeouts) on every launch.
        if let lastFailure = UserDefaults.standard.object(forKey: lastFailureKey) as? Date,
           Date.now.timeIntervalSince(lastFailure) < 6 * 60 * 60 {
            return
        }

        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { !$0.isCurrentUser && !$0.isBlocked }
        )
        guard let profiles = try? context.fetch(descriptor) else { return }

        var anySucceeded = false
        for profile in profiles where profile.photos.isEmpty {
            let count = photoCount(for: profile.name)
            var added = 0
            for index in 0..<count {
                guard let data = await fetchFace(gender: profile.gender) else { continue }
                guard let jpeg = ImageProcessing.downscaledJPEG(from: data) else { continue }
                context.insert(ProfilePhoto(data: jpeg, sortIndex: index, owner: profile))
                added += 1
            }
            if added > 0 {
                anySucceeded = true
                try? context.save()
            } else if !anySucceeded {
                // First profile got nothing: the source is down or we are
                // offline. Abort the whole pass and back off.
                UserDefaults.standard.set(Date.now, forKey: lastFailureKey)
                return
            }
        }

        if anySucceeded {
            UserDefaults.standard.removeObject(forKey: lastFailureKey)
        }
    }

    /// 2–4, stable per name so relaunches don't change a profile's layout.
    private static func photoCount(for name: String) -> Int {
        2 + Int(Theme.stableHash(name) % 3)
    }

    /// Two-step API: JSON with a generated image path, then the image bytes.
    private static func fetchFace(gender: Gender?) async -> Data? {
        var components = URLComponents(url: base.appendingPathComponent("new"), resolvingAgainstBaseURL: false)!
        let genderParam = switch gender {
        case .woman: "female"
        case .man: "male"
        default: "all"
        }
        components.queryItems = [
            .init(name: "gender", value: genderParam),
            .init(name: "age", value: "19-25"),
            .init(name: "etnic", value: "all")
        ]

        struct Response: Decodable { let src: String }

        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue("Click-demo/1.0", forHTTPHeaderField: "User-Agent")

        guard let (jsonData, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: jsonData),
              let imageURL = URL(string: decoded.src, relativeTo: base) else {
            return nil
        }

        var imageRequest = URLRequest(url: imageURL, timeoutInterval: 15)
        imageRequest.setValue("Click-demo/1.0", forHTTPHeaderField: "User-Agent")
        guard let (imageData, imageResponse) = try? await URLSession.shared.data(for: imageRequest),
              (imageResponse as? HTTPURLResponse)?.statusCode == 200,
              !imageData.isEmpty else {
            return nil
        }
        return imageData
    }
}
