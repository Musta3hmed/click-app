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
}
