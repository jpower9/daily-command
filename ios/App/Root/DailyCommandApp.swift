import SwiftUI

@main
struct DailyCommandApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(DC.gold)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.state {
        case .notConfigured:
            VStack(spacing: 12) {
                Kicker("Daily Command")
                Text("This build isn't set up to reach the service.").foregroundStyle(DC.text2)
                Text("Add Config/Local.xcconfig and rebuild.").font(DC.Font.small).foregroundStyle(DC.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DC.bg)
        case .signedOut:
            SignInView()
        case .signedIn:
            MainTabs()
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            Tab("Day", systemImage: "sun.max") { NavigationStack { DayView() } }
            Tab("Week", systemImage: "calendar") { NavigationStack { WeekView() } }
            Tab("Quarter", systemImage: "chart.bar") { NavigationStack { QuarterView() } }
            Tab("Goals", systemImage: "target") { NavigationStack { GoalsView() } }
            Tab("Journal", systemImage: "book.closed") { NavigationStack { JournalView() } }
        }
        .toolbarBackground(DC.panel, for: .tabBar)
    }
}
