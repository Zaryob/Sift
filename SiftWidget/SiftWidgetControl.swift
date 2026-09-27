//
//  SiftWidgetControl.swift
//  SiftWidget
//
//  Created by Süleyman Poyraz on 25.09.2026.
//

import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center / Lock Screen control that opens the Sift main window.
@available(iOS 18.0, macOS 15.0, *)
struct SiftWidgetControl: ControlWidget {
    static let kind: String = "io.github.zaryob.sift.control.open"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenSiftIntent()) {
                Label("Open Sift", systemImage: "dot.radiowaves.up.forward")
            }
        }
        .displayName("Open Sift")
        .description("Opens the Sift RSS reader.")
    }
}
