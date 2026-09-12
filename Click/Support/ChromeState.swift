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
    /// Set by screens that want to switch tabs (e.g. the chats empty state
    /// jumping to swipe); RootView consumes it.
    var requestedTab: AppTab?
    /// A conversation another screen wants opened (the celebration's
    /// "say hi"); ChatsView consumes it after the tab switch.
    var requestedConversationID: UUID?
}
