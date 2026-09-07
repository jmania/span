import SwiftUI
#if canImport(SummitCore)
import SummitCore
#endif
import UniformTypeIdentifiers

private enum ResultTab { case connections, directory }
private enum DirectoryFilter: String, CaseIterable {
    case all = "Everyone"
    case first = "Connected"
    case review = "To explore"
    case second = "Second degree"
    case notConnected = "Not connected"
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showingImporter = false
    @State private var dropTargeted = false
    @State private var confirmingReset = false
    @State private var showingAccessHelp = false
    @State private var showingLinkedInHelp = false
    @State private var showingInputs = false
    @State private var selectedCategory: ConnectionDegree? = .first
    @State private var resultTab: ResultTab = .connections
    @State private var directoryFilter: DirectoryFilter = .all
    @State private var directoryQuery = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let prerequisiteTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    @State private var creatorCardDismissed = false
    private let accent = Brand.accent
    private let ink = Brand.ink

    init() {}

    init(model: AppModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ZStack {
            Brand.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                Group {
                    if model.isExtracting {
                        collectionView
                    } else if !model.attendees.isEmpty && !showingInputs {
                        resultsView
                    } else {
                        setupView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                legalFooter
            }
        }
        .preferredColorScheme(.light)
        .tint(accent)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPrerequisites()
        }
        .onReceive(prerequisiteTimer) { _ in
            if !model.isExtracting {
                model.refreshPrerequisites()
            }
        }
        .alert("Something needs attention", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("Start over?", isPresented: $confirmingReset) {
            Button("Delete saved session and start over", role: .destructive) { model.startOver() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes Span’s saved attendee list, imported connections, and review decisions on this Mac. Your original LinkedIn archive is not deleted.")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "zip")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.importConnections(from: url) }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandMark()
            VStack(alignment: .leading, spacing: 1) {
                Text(Brand.name).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(ink)
                    .help("Span \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")")
                Text(Brand.tagline).font(.caption).foregroundStyle(.secondary)
                if !model.statusMessage.isEmpty {
                    Text(model.statusMessage).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let url = Brand.creatorURL {
                    Link("Made by \(Brand.creatorName)", destination: url)
                        .font(.caption).foregroundStyle(ink)
                }
                HStack(spacing: 3) {
                    navigationButton("Inputs", active: showingInputs || model.attendees.isEmpty) { showingInputs = true }
                    Text("|").foregroundStyle(.tertiary)
                    navigationButton("Results", active: !showingInputs && !model.attendees.isEmpty,
                                     disabled: model.attendees.isEmpty || model.isExtracting || model.isImporting) { showingInputs = false }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(.white.opacity(0.72))
    }

    private var legalFooter: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Independent, unofficial software. Not affiliated with or endorsed by Lenny & Friends Summit, Lenny’s Newsletter, Zuddl, LinkedIn, or any other event or platform. Results are provided as-is; no warranties are made about accuracy, completeness, or fitness for purpose.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if model.hasInputs {
                Button("Start over…", role: .destructive) { confirmingReset = true }
                    .buttonStyle(.plain).font(.caption2)
                    .disabled(model.isExtracting || model.isImporting)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 7)
        .background(.white.opacity(0.56))
    }

    private var setupView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FAMILIAR FACES. NEW INTRODUCTIONS.")
                            .font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(accent)
                        Text("Know who’s there.\nFind your next conversation.")
                            .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(ink)
                        Text("Add these two inputs in either order. Span matches them when both are ready. Your data stays on your Mac.")
                            .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        prerequisiteCard
                        preparationCard
                    }
                }
                .padding(20).frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 8) {
                Text("Then: find first-degree matches automatically; review second-degree connections on LinkedIn.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Preview with sample data") { model.loadDemo() }.buttonStyle(.link)
                    .disabled(model.isImporting || model.hasInputs)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    private var prerequisiteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("01 / Get the guest list").font(.headline).foregroundStyle(ink)
            if model.attendees.isEmpty {
            statusRow("Lenny & Friends installed", ready: model.appInstalled)
            statusRow("App is open", ready: model.appRunning)
            statusRow("Attendee access allowed", ready: model.accessibilityTrusted)
            Divider()
            if !model.appRunning {
                Button("Open Lenny & Friends") { model.openEventApp() }
            }
            if !model.accessibilityTrusted {
                Button("Allow attendee access") { model.requestAccessibility() }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                if !model.guestListReady {
                    Button("Check again") { model.refreshPrerequisites() }
                        .buttonStyle(.link).font(.caption).foregroundStyle(.secondary)
                }
                if !model.accessibilityTrusted {
                    Button("Already enabled?") { showingAccessHelp = true }
                        .buttonStyle(.link)
                        .popover(isPresented: $showingAccessHelp) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Permission not being recognized?").font(.headline)
                                Text("Span checks automatically when you return from System Settings. If access still isn't recognized, quit and reopen Span.")
                                Text("After replacing a preview build, macOS may retain permission for the old copy. In Accessibility settings, remove only the old Span entry, then add and enable the copy you are running now.")
                                Text(Bundle.main.bundleURL.path).font(.caption).textSelection(.enabled)
                                HStack {
                                    Button("Show this app in Finder") { model.revealCurrentApp() }
                                    Button("Open Accessibility settings") { model.openAccessibilitySettings() }
                                }
                            }.padding(20).frame(width: 390)
                        }
                }
            }
            Text("In Lenny & Friends, open Attendees → All attendees before collecting.")
                .font(.caption).foregroundStyle(.secondary)
            Button(action: model.extractAttendees) {
                Label("Collect attendees", systemImage: "person.3.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!model.guestListReady || model.isExtracting || model.isImporting)
            } else {
                Label("\(model.attendees.count) attendees ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
                Text("Saved on this Mac. You can refresh the list without importing your LinkedIn archive again.")
                    .foregroundStyle(.secondary)
                if !model.accessibilityTrusted {
                    Button("Allow attendee access", action: model.requestAccessibility).buttonStyle(.link)
                } else {
                    Button("Collect attendees again", action: model.extractAttendees)
                        .buttonStyle(.link)
                        .disabled(model.isExtracting || model.isImporting)
                }
                Text(model.connections == nil ? "Add your LinkedIn archive in the other box to find your matches." : "Both inputs are ready. Your matches are available in Back to results.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .cardStyle(padding: 16).frame(maxWidth: .infinity, alignment: .top)
    }

    private var preparationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("02 / Bring your LinkedIn connections").font(.headline).foregroundStyle(ink)
            if let connections = model.connections {
                Label("\(connections.count) connections ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
                Text("Saved on this Mac. Matching starts when the attendee list is ready.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Add your LinkedIn connections ZIP or Connections.csv—before or after collecting attendees.")
                Text("LinkedIn quotes 24 hours for larger archives, but yours may arrive much sooner. Request it now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            linkedInExportHelpButton
            archiveScanButton
            Text(dropTargeted ? "Drop your archive here" : "Or drop your ZIP / CSV into this box.")
                .font(.caption).foregroundStyle(dropTargeted ? accent : .secondary)
        }
        .cardStyle(padding: 16).frame(maxWidth: .infinity, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(dropTargeted ? accent : .clear, lineWidth: 2))
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.isImporting, let url = urls.first else { return false }
            model.importConnections(from: url)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var archiveScanButton: some View {
        Group {
            if model.connections == nil {
                Button { showingImporter = true } label: {
                    HStack {
                        if model.isImporting { ProgressView().controlSize(.small) }
                        Label(model.isImporting ? "Scanning archive…" : "Scan archive…", systemImage: "doc.zipper")
                    }.frame(maxWidth: .infinity).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isImporting)
            } else {
                Button("Replace archive…") { showingImporter = true }
                    .buttonStyle(.link).disabled(model.isImporting)
            }
        }
    }

    private var linkedInExportHelpButton: some View {
        Button("How to get your LinkedIn export") { showingLinkedInHelp = true }
            .buttonStyle(.link)
            .popover(isPresented: $showingLinkedInHelp) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Get your connections export").font(.headline)
                    Text("1. In LinkedIn on your computer, open Settings & Privacy → Data privacy → Download your data (sometimes called Get a copy of your data).")
                    Text("2. Request an archive that includes Connections—not just Contacts. If needed, choose the larger archive.")
                    Text("3. Wait for LinkedIn’s email, download the ZIP, then use Scan archive or drop it into Span. Either input can come first. An existing Connections.csv works too.")
                    Text("LinkedIn quotes 24 hours for the larger archive; it can arrive sooner. Its data table also lists Connections under data available within 48 hours, so allow extra time if needed.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Completed collection and imported connections are saved locally, so you can quit while waiting. Span never uploads the archive.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Open LinkedIn’s data download settings", destination: URL(string: "https://www.linkedin.com/mypreferences/d/download-my-data")!)
                    Link("LinkedIn’s official export instructions", destination: URL(string: "https://www.linkedin.com/help/linkedin/answer/a1339364")!)
                }.padding(20).frame(width: 420)
            }
    }

    private var collectionView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Building your guest list").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(ink)
                    Text("Keep Lenny & Friends open on All attendees.").foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView().controlSize(.small)
            }
            Text(model.extractionStage).font(.subheadline).foregroundStyle(ink)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(model.extractionCount)").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(ink)
                Text("attendees found").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("JUST ADDED").font(.caption.bold()).tracking(1.5).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 10) {
                    if model.recentCollectedAttendees.isEmpty {
                        Text("Names will appear after the beginning is confirmed.").foregroundStyle(.secondary)
                    }
                    ForEach(model.recentCollectedAttendees) { attendee in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                            Text(attendee.name).font(.headline).foregroundStyle(ink).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .transition(reduceMotion ? .identity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                }
                .frame(height: 86, alignment: .top).clipped()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.recentCollectedAttendees.map(\.id))
            }
            .frame(maxWidth: .infinity, alignment: .leading).cardStyle(padding: 18)
            Text(model.connections == nil ? "These are attendees, not confirmed connections yet. You can scan your LinkedIn archive while collection continues." : "Your LinkedIn archive is ready. Matching will start when collection finishes.")
                .font(.callout).foregroundStyle(.secondary)
            archiveScanButton
            linkedInExportHelpButton
            Button("Stop collection", action: model.cancelExtraction).buttonStyle(.link)
            Spacer(minLength: 0)
        }
        .padding(28).frame(maxWidth: 920, maxHeight: .infinity, alignment: .topLeading)
    }

    private var importView: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 46)).foregroundStyle(.green)
            Text("\(model.attendees.count) attendees collected")
                .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(ink)
            Text("02 / Find your familiar faces")
                .font(.headline).foregroundStyle(accent)
            Text("Drop in the archive LinkedIn gave you. We’ll find the connections file inside and compare it with the guest list.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 560)

            VStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 34)).foregroundStyle(accent)
                Text(model.isImporting ? "Reading your archive…" : "Drop LinkedIn’s ZIP or Connections.csv here")
                    .font(.headline)
                if model.isImporting { ProgressView().controlSize(.small) }
                Button("Choose file…") { showingImporter = true }.disabled(model.isImporting)
            }
            .frame(maxWidth: 520, minHeight: 190)
            .background(dropTargeted ? accent.opacity(0.12) : .white.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(style: StrokeStyle(lineWidth: 2, dash: [7])).foregroundStyle(dropTargeted ? accent : Color.gray.opacity(0.35)))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.importConnections(from: url)
                return true
            } isTargeted: { dropTargeted = $0 }

            linkedInExportHelpButton
        }
        .padding(40)
    }

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your summit network").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(ink)
                    Text(model.connections == nil
                         ? "Your guest list is ready. Add your LinkedIn connections export to see who you already know."
                         : "Start with the people you already know, or explore the full attendee directory.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    resultTabButton("People you know", active: resultTab == .connections) { resultTab = .connections }
                    resultTabButton("All attendees", active: resultTab == .directory) { resultTab = .directory }
                }

                if resultTab == .connections {
                    connectionsDashboard
                } else {
                    attendeeDirectory
                }

                if !creatorCardDismissed, let url = Brand.creatorURL {
                    creatorCard(url)
                }
            }
            .padding(28)
        }
    }

    private var connectionsDashboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.connections == nil {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add your LinkedIn connections export").font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                        Text("That’s how Span identifies the people you already know.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add export") { showingInputs = true }
                        .buttonStyle(.borderedProminent)
                }
                .cardStyle(padding: 14)
            }
            HStack(spacing: 12) {
                categoryMetric(.first, "First degree", model.firstDegreeCount, color: .green)
                categoryMetric(.second, "Second degree", model.secondDegreeCount, color: .blue)
                categoryMetric(.review, "Needs review", model.reviewCount, color: accent)
                categoryMetric(.notConnected, "Not connected", model.notConnectedCount, color: .secondary)
            }
            categorySummary

            // Keep the manual review flow opt-in. A fresh match should land on
            // the useful summary, not immediately put the user in a queue.
            if let current = model.currentReview, model.focusedReviewID != nil {
                reviewCard(current)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").foregroundStyle(accent)
                    Text("Review is optional. Browse All attendees when someone catches your eye.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Browse attendees") { resultTab = .directory }
                        .buttonStyle(.bordered)
                }
                .cardStyle(padding: 16)
            }

            exportBar
        }
    }

    private var exportBar: some View {
        HStack {
            Text(model.isDemo ? "Sample data — explore freely. Nothing is saved." : "Every decision is saved automatically on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Export spreadsheet…") { model.exportResults() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var attendeeDirectory: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Everyone attending").font(.headline).foregroundStyle(ink)
                    Text("Search by name, company, or title. Choose what you want to do next.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(filteredDirectoryAttendees.count) shown").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Search attendees", text: $directoryQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 460)
            HStack(spacing: 6) {
                ForEach(DirectoryFilter.allCases, id: \.self) { filter in
                    Button(filter.rawValue) { directoryFilter = filter }
                        .buttonStyle(.plain)
                        .font(.caption.weight(directoryFilter == filter ? .semibold : .regular))
                        .foregroundStyle(directoryFilter == filter ? ink : .secondary)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(directoryFilter == filter ? ink.opacity(0.1) : .clear)
                        .clipShape(Capsule())
                }
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredDirectoryAttendees) { attendee in
                    directoryRow(attendee)
                    if attendee.id != filteredDirectoryAttendees.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(.white.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06)))
        }
    }

    private var filteredDirectoryAttendees: [Attendee] {
        let query = directoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: .diacriticInsensitive, locale: .current).lowercased()
        return model.attendees.filter { attendee in
            let result = model.result(for: attendee)
            let categoryMatches: Bool
            switch directoryFilter {
            case .all: categoryMatches = true
            case .first: categoryMatches = result?.degree == .first
            case .second: categoryMatches = result?.degree == .second
            case .review: categoryMatches = result?.degree == .review || result?.degree == .skip || result == nil
            case .notConnected: categoryMatches = result?.degree == .notConnected
            }
            guard categoryMatches else { return false }
            guard !query.isEmpty else { return true }
            return [attendee.name, attendee.details].joined(separator: " ").folding(options: .diacriticInsensitive, locale: .current).lowercased().contains(query)
        }
    }

    private func directoryRow(_ attendee: Attendee) -> some View {
        let result = model.result(for: attendee)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: result?.degree == .first ? "checkmark.circle.fill" : "person.circle.fill")
                .foregroundStyle(result?.degree == .first ? .green : accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(attendee.name).font(.headline).foregroundStyle(ink)
                Text(attendee.details.isEmpty ? "No company or title supplied" : attendee.details)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let result {
                    Text(result.degree.label).font(.caption2.weight(.semibold)).foregroundStyle(result.degree == .first ? .green : .secondary)
                } else {
                    Text("Awaiting LinkedIn export").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button { model.openLinkedInSearch(for: attendee) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered).help("Search LinkedIn")
                Menu {
                    directoryClassificationMenu(for: attendee)
                } label: {
                    Image(systemName: "tag")
                }
                .menuStyle(.borderlessButton)
                .help("Set connection status")
            }
        }
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func directoryClassificationMenu(for attendee: Attendee) -> some View {
        Button("Second degree") { model.classify(attendee: attendee, as: .second) }
        Button("Actually first") { model.classify(attendee: attendee, as: .first) }
        Button("Not connected") { model.classify(attendee: attendee, as: .notConnected) }
        Button("Skip for now") { model.classify(attendee: attendee, as: .skip) }
    }

    private func resultTabButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.subheadline.weight(active ? .semibold : .regular))
            .foregroundStyle(active ? ink : .secondary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(active ? ink.opacity(0.1) : .clear)
            .clipShape(Capsule())
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var categorySummary: some View {
        let category = selectedCategory ?? .first
        let people = model.results(for: category)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(categorySummaryTitle(category)).font(.headline).foregroundStyle(ink)
                    Text(categorySummaryDescription(category, count: people.count))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(people.count) shown").font(.headline).monospacedDigit().foregroundStyle(categoryColor(category))
            }

            if people.isEmpty {
                Label(category == .review ? "Nothing needs review right now." : "No people are in this category yet.", systemImage: "person.2")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(people) { result in
                            Group {
                                if category == .review {
                                    Button { model.focusReview(result.id) } label: {
                                        categoryPersonRow(result, category: category)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    categoryPersonRow(result, category: category)
                                }
                            }
                            if result.id != people.last?.id { Divider() }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
        .cardStyle(padding: 18)
    }

    private func categoryMetric(_ category: ConnectionDegree, _ label: String, _ value: Int, color: Color) -> some View {
        Button {
            selectedCategory = selectedCategory == category ? nil : category
        } label: {
            metric(label, value, color: color, selected: selectedCategory == category)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
        .accessibilityHint("Show people in this category")
    }

    private func categoryPersonRow(_ result: NetworkResult, category: ConnectionDegree) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: category == .first ? "checkmark.circle.fill" : "person.circle.fill")
                .foregroundStyle(categoryColor(category))
            VStack(alignment: .leading, spacing: 2) {
                Text(result.attendee.name).font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                if !result.attendee.details.isEmpty {
                    Text(result.attendee.details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if category == .first {
                if let url = URL(string: result.linkedInURL), !result.linkedInURL.isEmpty {
                    Link("Profile", destination: url).font(.caption)
                }
            } else if category == .second, model.linkedInSearchURL(for: result.attendee) != nil {
                Button("Profile") { model.openLinkedInSearch(for: result.attendee) }
                    .buttonStyle(.link).font(.caption)
                    .accessibilityLabel("Open LinkedIn profile search for \(result.attendee.name)")
            }
            if category == .review {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func categorySummaryTitle(_ category: ConnectionDegree) -> String {
        switch category {
        case .first: return "Your first-degree connections"
        case .second: return "Second-degree connections"
        case .review: return "People needing review"
        case .notConnected: return "Not connected"
        case .skip: return "Skipped"
        }
    }

    private func categorySummaryDescription(_ category: ConnectionDegree, count: Int) -> String {
        switch category {
        case .first: return count == 0 ? "No exact first-degree matches were found in your export." : "These people are already connected to you on LinkedIn."
        case .second: return "People you marked as second degree during review."
        case .review: return "Possible matches waiting for your LinkedIn check."
        case .notConnected: return "People you marked as not connected."
        case .skip: return "People you set aside for later."
        }
    }

    private func categoryColor(_ category: ConnectionDegree) -> Color {
        switch category {
        case .first: return .green
        case .second: return .blue
        case .review: return accent
        case .notConnected: return .secondary
        case .skip: return .secondary
        }
    }

    private func navigationButton(_ title: String, active: Bool, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption.weight(active ? .semibold : .regular))
            .foregroundStyle(active ? ink : Color.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(active ? ink.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityAddTraits(active ? .isSelected : [])
            .disabled(disabled)
    }

    private func creatorCard(_ url: URL) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 27)).foregroundStyle(accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("One more connection?").font(.headline).foregroundStyle(ink)
                Text("I’m \(Brand.creatorName). I built this to make meeting people at the summit a little easier. If it helped, add me on LinkedIn and come say hello. I promise I’m easier to find than the export button.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: url) {
                    Label("Find me on LinkedIn", systemImage: "arrow.up.right")
                }
                .buttonStyle(.bordered).tint(ink)
            }
            Spacer(minLength: 0)
            Button { creatorCardDismissed = true } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss creator invitation")
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.16)))
    }

    private func reviewCard(_ result: NetworkResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Review the remaining attendees").font(.headline).foregroundStyle(ink)
                Spacer()
                Text("\(model.reviewCount) remaining").font(.caption).foregroundStyle(.secondary)
                if model.canUndoReview {
                    Button("Undo previous") { model.undoLastClassification() }
                        .buttonStyle(.link).font(.caption)
                }
            }
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(result.attendee.name).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(ink)
                Button { model.copyCurrentSearch() } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy search text")
                .accessibilityLabel("Copy search text for \(result.attendee.name)")
            }
            Text(result.attendee.details.isEmpty ? "No company or title supplied" : result.attendee.details)
                .font(.title3).foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                if let message = model.lastClassificationMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                }
            }
            .frame(height: 20, alignment: .leading)
            HStack {
                if model.linkedInSearchURL(for: result.attendee) != nil {
                    Button {
                        model.openLinkedInSearch(for: result.attendee)
                    } label: {
                        Label("Search LinkedIn", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            Text("Search LinkedIn opens a people search with this attendee’s name and details pre-filled. Check the connection badge, then choose a result below. Span never reads or controls LinkedIn.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                classificationButton("Second degree", icon: "person.2.fill", degree: .second)
                classificationButton("Not connected", icon: "person.crop.circle.badge.questionmark", degree: .notConnected)
                classificationButton("Actually first", icon: "person.crop.circle.badge.checkmark", degree: .first)
                classificationButton("Skip for now", icon: "forward.fill", degree: .skip)
            }
        }
        .cardStyle().frame(maxHeight: .infinity, alignment: .top)
    }

    private func classificationButton(_ title: String, icon: String, degree: ConnectionDegree) -> some View {
        Button { model.classifyCurrent(as: degree) } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity)
        }.controlSize(.large)
    }

    private func metric(_ label: String, _ value: Int, color: Color, selected: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? color.opacity(0.12) : .white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? color.opacity(0.45) : .clear, lineWidth: 1.5))
    }

    private func statusRow(_ title: String, ready: Bool) -> some View {
        Label(title, systemImage: ready ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(ready ? Color.green : Color.secondary)
    }

    private func privacyRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark").font(.subheadline)
    }
}

private extension View {
    func cardStyle(padding: CGFloat = 22) -> some View {
        self.padding(padding)
            .background(.white.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06)))
    }
}
