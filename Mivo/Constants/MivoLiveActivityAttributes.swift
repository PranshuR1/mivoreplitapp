/// MivoLiveActivityAttributes.swift
/// Shared ActivityAttributes type for the Mivo session Live Activity.
///
/// IMPORTANT — XCODE SETUP REQUIRED:
/// This file must be compiled into BOTH the main app target (mivoreplitapp)
/// AND the MivoWidgets widget extension target.  In Xcode, select this file in
/// the Project Navigator, open the File Inspector (⌥⌘1), and tick the
/// MivoWidgets target membership checkbox.
/// ActivityKit identifies the Live Activity by type name across process boundaries,
/// so both the app (Activity.request) and the widget (ActivityConfiguration) must
/// compile exactly the same declaration.

import Foundation
import ActivityKit

public struct MivoSessionLiveAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Exact moment the session ends — used for a live countdown.
        public var sessionEndsAt: Date
        /// Planned session length in minutes — used for the progress ring.
        public var planMinutes: Int
        /// Set only while Companion is on: the character's name and
        /// `CompanionState` raw value. Optional, so activities started by an
        /// older build (or with Companion off) decode and render as before.
        public var companionName: String? = nil
        public var companionState: String? = nil
    }
    /// When the session was started (static, never changes mid-activity).
    public var sessionStartedAt: Date
    /// User's intention label, e.g. "Relaxing" or "Kill time".
    public var intentionLabel: String
    /// `nil` for a Mivo scroll session; `"focus"` for a Mivo Still run.
    public var kind: String? = nil
}
