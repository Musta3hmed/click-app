//
//  DefaultsKey.swift
//  Click
//
//  Every UserDefaults/@AppStorage key in one place. Raw strings scattered
//  across files let AccountEraser miss keys (visibility toggles leaked
//  across accounts — the exact class of bug phase 3 closed).
//

import Foundation

enum DefaultsKey {
    static let onboardingCompleted = "onboardingCompleted"
    static let onboardingStep = "onboardingStep"
    static let welcomePopupShown = "welcomePopupShown"
    static let showMyState = "showMyState"
    static let visibleInFindNewFriends = "visibleInFindNewFriends"
    static let demoPhotosLastFailure = "demoPhotosLastFailure"
    /// Device preference, not account data — AccountEraser leaves it alone.
    static let appearance = "appearanceSetting"

    // Phone verification gate (account-scoped; AccountEraser clears them).
    static let phoneVerified = "phoneVerified"
    static let phoneNumber = "phoneNumber"

    // Swipe deck filters (account-scoped; AccountEraser clears them).
    static let filterMinAge = "filterMinAge"
    static let filterMaxAge = "filterMaxAge"
    static let filterVerifiedOnly = "filterVerifiedOnly"
    static let filterInterests = "filterInterests"
    /// Whether an interest filter requires ANY shared pick (default) or ALL.
    static let filterInterestsMatchAll = "filterInterestsMatchAll"

    /// One-shot legacy-string -> canonical-id migration flag. Store
    /// metadata, not account data — AccountEraser leaves it alone (a
    /// fresh account on the same install is already migrated).
    static let interestsSchemaVersion = "interestsSchemaVersion"

    // Community join rate limit (account-scoped; AccountEraser clears
    // them via CommunityService.eraseUserCreated).
    static let communityJoinsDay = "communityJoinsDay"
    static let communityJoinsCount = "communityJoinsCount"
}
