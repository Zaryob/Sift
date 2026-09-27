import WidgetKit
import SwiftUI

@main
struct SiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        SiftWidget()
        if #available(iOS 18.0, macOS 15.0, *) {
            SiftWidgetControl()
        }
    }
}
