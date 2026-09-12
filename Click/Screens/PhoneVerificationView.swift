//
//  PhoneVerificationView.swift
//  Click
//
//  Every account verifies a phone number before onboarding. No SMS
//  backend exists yet, so the flow is honest-demo: the 6-digit code is
//  shown on screen instead of being sent, and says so.
//

import SwiftUI
import SwiftData

struct PhoneVerificationView: View {
    @Environment(\.modelContext) private var context
    @Environment(AuthSession.self) private var auth
    @Environment(\.motion) private var motion

    @AppStorage(DefaultsKey.phoneVerified) private var phoneVerified = false
    @AppStorage(DefaultsKey.phoneNumber) private var storedPhoneNumber = ""

    @State private var phone = ""
    @State private var sentCode: String?
    @State private var codeEntry = ""
    @State private var errorMessage: String?

    private var phoneValid: Bool {
        phone.filter(\.isNumber).count >= 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sign out stays reachable — nobody gets trapped at a gate.
            HStack {
                Spacer()
                Button {
                    Haptics.selection()
                    auth.signOut(erasing: context)
                } label: {
                    Text("sign out")
                        .font(.clickPlain(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(height: 44)
                }
                .accessibilityLabel("Sign out")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metric.Space.m) {
                    Image(systemName: "phone.badge.checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.brandPink)

                    Text("verify your number")
                        .font(.click(.largeTitle, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .accessibilityAddTraits(.isHeader)

                    Text("Click uses a phone number to keep accounts real. It never shows on your profile.")
                        .font(.clickPlain(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .padding(.bottom, Theme.Metric.Space.s)

                    if let code = sentCode {
                        codeStep(code: code)
                    } else {
                        phoneStep
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.clickPlain(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, Theme.Metric.Space.xl)
                .animation(motion.state, value: sentCode)
                .animation(motion.state, value: errorMessage)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .background(Theme.background.ignoresSafeArea())
    }

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.Space.m) {
            TextField("+61 400 000 000", text: $phone)
                .font(.click(.title3, weight: .heavy))
                .foregroundStyle(Theme.primary)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous))
                .onChange(of: phone) { _, newValue in
                    if newValue.count > 18 { phone = String(newValue.prefix(18)) }
                    errorMessage = nil
                }
                .accessibilityLabel("Phone number")

            Button {
                sentCode = String(format: "%06d", Int.random(in: 0..<1_000_000))
                codeEntry = ""
                errorMessage = nil
            } label: {
                Text("send code")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Metric.primaryButton)
                    .background(phoneValid ? Theme.primary : Theme.fillDisabled, in: Capsule())
            }
            .buttonStyle(.click)
            .disabled(!phoneValid)
            .accessibilityLabel("Send verification code")
        }
    }

    private func codeStep(code: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metric.Space.m) {
            Text("enter the 6-digit code sent to \(phone)")
                .font(.click(.headline, weight: .bold))
                .foregroundStyle(Theme.primary)

            // Honest demo: no SMS backend exists, so the code is shown
            // here instead of being sent.
            Label("demo build - no SMS is sent. Your code is \(code)", systemImage: "lock.fill")
                .font(.clickPlain(.footnote, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: Theme.Metric.chip, style: .continuous))

            TextField("verification code", text: $codeEntry)
                .font(.click(.title3, weight: .heavy))
                .foregroundStyle(Theme.primary)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous))
                .onChange(of: codeEntry) { _, newValue in
                    codeEntry = String(newValue.filter(\.isNumber).prefix(6))
                    errorMessage = nil
                }
                .accessibilityLabel("Verification code")

            Button {
                if codeEntry == code {
                    storedPhoneNumber = phone.trimmingCharacters(in: .whitespaces)
                    Haptics.notify(.success)
                    withAnimation(motion.screen) { phoneVerified = true }
                } else {
                    Haptics.notify(.error)
                    errorMessage = "That code doesn't match. Check the digits and try again."
                }
            } label: {
                Text("verify")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Metric.primaryButton)
                    .background(codeEntry.count == 6 ? Theme.primary : Theme.fillDisabled, in: Capsule())
            }
            .buttonStyle(.click)
            .disabled(codeEntry.count != 6)
            .accessibilityLabel("Verify")

            Button("change number") {
                sentCode = nil
                codeEntry = ""
                errorMessage = nil
            }
            .font(.clickPlain(.footnote, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Change phone number")
        }
    }
}

#Preview {
    PhoneVerificationView()
        .environment(AuthSession())
        .modelContainer(MockData.previewContainer)
}
