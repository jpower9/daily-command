import SwiftUI

@main
struct DailyCommandApp: App {
    @State private var model = AppModel()
    @State private var nav = Navigator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(nav)
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
        case let .twoStep(session):
            TwoStepView(session: session)
        }
    }
}

struct MainTabs: View {
    @Environment(Navigator.self) private var nav
    var body: some View {
        @Bindable var nav = nav
        TabView(selection: $nav.tab) {
            Tab("Day", systemImage: "sun.max", value: AppTab.day) { NavigationStack { DayView() } }
            Tab("Week", systemImage: "calendar", value: AppTab.week) { NavigationStack { WeekView() } }
            Tab("Quarter", systemImage: "chart.bar", value: AppTab.quarter) { NavigationStack { QuarterView() } }
            Tab("Goals", systemImage: "target", value: AppTab.goals) { NavigationStack { GoalsView() } }
            Tab("Journal", systemImage: "book.closed", value: AppTab.journal) { NavigationStack { JournalView() } }
        }
        .toolbarBackground(DC.panel, for: .tabBar)
    }
}
