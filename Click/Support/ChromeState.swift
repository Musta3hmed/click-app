//
//  ChromeState.swift
//  Click
//
//  App-chrome visibility shared down the view tree (same pattern as
//  AuthSession — preference keys don't cross the NavigationStack push
//  boundary reliably). ConversationView hides the floating tab bar on
//  appear and restores it on disappear.
//

import Observation

@Observable
final class ChromeState {
    var tabBarHidden = false
}
