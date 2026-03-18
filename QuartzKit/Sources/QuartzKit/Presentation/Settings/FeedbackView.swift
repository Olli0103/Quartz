import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Creates a GitHub issue with pre-filled template for user feedback.
public struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackType: FeedbackType = .bug
    @State private var description = ""
    @State private var steps = ""

    private static let repo = "Olli0103/Quartz"
    private static let baseURL = "https://github.com/\(repo)/issues/new"

    public enum FeedbackType: String, CaseIterable {
        case bug
        case feature
        case question

        var label: String {
            switch self {
            case .bug: return "bug"
            case .feature: return "enhancement"
            case .question: return "question"
            }
        }

        var title: String {
            switch self {
            case .bug: return String(localized: "Bug Report", bundle: .module)
            case .feature: return String(localized: "Feature Request", bundle: .module)
            case .question: return String(localized: "Question", bundle: .module)
            }
        }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "Type", bundle: .module), selection: $feedbackType) {
                        ForEach(FeedbackType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(String(localized: "Feedback Type", bundle: .module))
                }

                Section {
                    TextField(
                        String(localized: "Describe your feedback…", bundle: .module),
                        text: $description,
                        axis: .vertical
                    )
                    .lineLimit(3...8)

                    if feedbackType == .bug {
                        TextField(
                            String(localized: "Steps to reproduce (optional)", bundle: .module),
                            text: $steps,
                            axis: .vertical
                        )
                        .lineLimit(2...6)
                    }
                } header: {
                    Text(String(localized: "Details", bundle: .module))
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "Opens GitHub in your browser", bundle: .module), systemImage: "safari")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "Send Feedback", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Create Issue", bundle: .module)) {
                        openGitHubIssue()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func openGitHubIssue() {
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let stepsText = steps.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = QuartzKit.version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        var body = """
        ## Description
        \(desc)

        """
        if feedbackType == .bug && !stepsText.isEmpty {
            body += """
            ## Steps to Reproduce
            \(stepsText)

            """
        }
        body += """
        ## Environment
        - Quartz: \(version)
        - OS: \(osVersion)
        """

        var components = URLComponents(string: Self.baseURL)!
        components.queryItems = [
            URLQueryItem(name: "title", value: "[\(feedbackType.rawValue.capitalized)] \(desc.prefix(60))\(desc.count > 60 ? "…" : "")"),
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "labels", value: feedbackType.label)
        ]
        if let url = components.url {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #elseif canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
}
