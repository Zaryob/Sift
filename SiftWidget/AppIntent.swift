//
//  AppIntent.swift
//  SiftWidget
//
//  Created by Süleyman Poyraz on 25.09.2026.
//

import WidgetKit
import AppIntents

/// Opens Sift and navigates to the "All Articles" view.
struct OpenSiftIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Sift"
    static var description = IntentDescription("Opens the Sift RSS reader.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
