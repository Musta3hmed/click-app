//
//  PromptCatalog.swift
//  Click
//
//  Profile prompts: curated questions only (no user-written questions —
//  the same moderation posture as the interest taxonomy), answers up to
//  100 characters, at most 3 per profile. Stored on UserProfile as
//  JSON-encoded Data with a declared default (migration-safe), decoded
//  through the computed `promptAnswers` accessor.
//

import Foundation

struct Prompt: Identifiable, Hashable, Codable {
    /// Canonical slug, stable forever.
    let id: String
    /// Lowercase per the casing rule — Click draws this.
    let question: String
}

struct PromptAnswer: Codable, Equatable, Identifiable {
    let promptID: String
    var answer: String

    var id: String { promptID }

    var prompt: Prompt? { PromptCatalog.byID[promptID] }
}

enum PromptCatalog {
    static let maxAnswered = 3
    static let maxAnswerLength = 100

    static let all: [Prompt] = [
        Prompt(id: "two-truths", question: "two truths and a lie"),
        Prompt(id: "perfect-sunday", question: "my perfect sunday"),
        Prompt(id: "green-flags", question: "green flags i look for"),
        Prompt(id: "weirdly-good-at", question: "i'm weirdly good at"),
        Prompt(id: "way-to-my-heart", question: "the way to my heart"),
        Prompt(id: "best-meal", question: "best meal i've ever had"),
        Prompt(id: "hill-to-die-on", question: "a hill i'll die on"),
        Prompt(id: "dream-trip", question: "dream trip"),
        Prompt(id: "song-on-repeat", question: "song on repeat right now"),
        Prompt(id: "talk-for-hours", question: "i could talk for hours about"),
        Prompt(id: "simple-pleasures", question: "my simple pleasures"),
        Prompt(id: "first-round", question: "first round's on me if"),
        Prompt(id: "make-me-laugh", question: "the fastest way to make me laugh"),
        Prompt(id: "unpopular-opinion", question: "my most defensible unpopular opinion"),
        Prompt(id: "never-shut-up", question: "i'll never shut up about"),
    ]

    static let byID: [String: Prompt] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    // MARK: - Codec (UserProfile.promptsData)

    static func encode(_ answers: [PromptAnswer]) -> Data {
        (try? JSONEncoder().encode(answers)) ?? Data()
    }

    static func decode(_ data: Data) -> [PromptAnswer] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([PromptAnswer].self, from: data)) ?? []
    }
}

extension UserProfile {
    /// Answered prompts, capped and validated at write time.
    var promptAnswers: [PromptAnswer] {
        get { PromptCatalog.decode(promptsData) }
        set {
            let cleaned = newValue
                .filter { PromptCatalog.byID[$0.promptID] != nil }
                .map { PromptAnswer(
                    promptID: $0.promptID,
                    answer: String($0.answer
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                        .prefix(PromptCatalog.maxAnswerLength))
                ) }
                .filter { !$0.answer.isEmpty }
            promptsData = PromptCatalog.encode(Array(cleaned.prefix(PromptCatalog.maxAnswered)))
        }
    }
}
