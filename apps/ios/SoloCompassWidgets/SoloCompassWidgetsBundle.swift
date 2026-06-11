import SwiftUI
import WidgetKit

/// The widget extension's entry point. Holds only the Live Activity for now
/// (US-026). Home Screen / Lock Screen widgets can be added to this bundle later
/// without touching the activity.
@main
struct SoloCompassWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SoloCompassLiveActivity()
    }
}
