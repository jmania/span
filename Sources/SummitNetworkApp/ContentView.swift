import SwiftUI
#if canImport(SummitCore)
import SummitCore
#endif
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showingImporter = false
    @State private var dropTargeted = false
    @State private var confirmingReset = false
    @State private var showingAccessHelp = false
    @State private var showingLinkedInHelp = false
    @State private var showingInputs = false
    @State private var directoryQuery = ""
    @State private var showingSearch = false
    @FocusState private var searchFocused: Bool
    @State private var listPresentation = SummitListPresentation(attendees: [], results: [], connectionCount: nil)
    @State private var expandedIDs = Set<UUID>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let prerequisiteTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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
                    navigationButton("Attendees", active: !showingInputs && !model.attendees.isEmpty,
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
                        Text("Build your attendee list. Add your LinkedIn export to spot people you might already know. Your data stays on your Mac.")
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
                Text("Browse right after collection. Add your LinkedIn export whenever you’re ready; suggestions need your confirmation.")
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
                Text(model.connections == nil ? "Your list is ready to browse. Add an archive to see possible connections." : "Both inputs are ready. Browse your list in Attendees.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .cardStyle(padding: 16).frame(maxWidth: .infinity, alignment: .top)
    }

    private var preparationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("02 / Add context from LinkedIn").font(.headline).foregroundStyle(ink)
            if let connections = model.connections {
                Label("\(connections.count) connections ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
                Text("Saved on this Mac. Matching starts when the attendee list is ready.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Optional for browsing: add your LinkedIn connections ZIP or Connections.csv to find possible connections.")
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
            Text(model.connections == nil ? "These are attendees, not confirmed connections. You can add your LinkedIn archive while collection continues." : "Your LinkedIn archive is ready. Matching will start when collection finishes.")
                .font(.callout).foregroundStyle(.secondary)
            archiveScanButton
            linkedInExportHelpButton
            Button("Stop collection", action: model.cancelExtraction).buttonStyle(.link)
            Spacer(minLength: 0)
        }
        .padding(28).frame(maxWidth: 920, maxHeight: .infinity, alignment: .topLeading)
    }

    private var resultsView: some View {
        let suggestions = listPresentation.filtered(listPresentation.suggested, query: directoryQuery)
        let others = listPresentation.filtered(listPresentation.others, query: directoryQuery)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.connections == nil ? "Summit attendees" : "Summit attendees you may know")
                        .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(ink)
                    Text(listPresentation.summary)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    showingSearch.toggle()
                    if showingSearch { searchFocused = true } else { directoryQuery = "" }
                } label: {
                    Label(showingSearch ? "Close search" : "Search", systemImage: showingSearch ? "xmark" : "magnifyingglass")
                }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                .keyboardShortcut("f", modifiers: .command)
                .padding(.top, 5)
            }
            if showingSearch {
                TextField("Search attendees by name, company, or title", text: $directoryQuery)
                    .textFieldStyle(.roundedBorder).focused($searchFocused)
                    .accessibilityLabel("Search attendees")
                    .onExitCommand { directoryQuery = ""; showingSearch = false }
            }
            if model.connections == nil {
                Button("Add LinkedIn export…") { showingImporter = true }
                    .buttonStyle(.plain).foregroundStyle(ink).disabled(model.isImporting)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if suggestions.isEmpty && others.isEmpty {
                        Text("No attendees match this search.").foregroundStyle(.secondary).padding(20)
                    }
                    if !suggestions.isEmpty {
                        attendeeSection(suggestions)
                    }
                    if !others.isEmpty {
                        if listPresentation.hasArchive {
                            Text("Other attendees").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                                .padding(.top, suggestions.isEmpty ? 0 : 22).padding(.bottom, 10)
                        }
                        attendeeSection(others)
                    }
                    HStack {
                        if model.isDemo {
                            Text("DEMO · FICTIONAL ATTENDEES").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Export list…", action: model.exportResults)
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 18)
                }
            }
        }
        .padding(24)
        .onAppear(perform: refreshList)
        .onChange(of: model.inputRevision) { _ in refreshList() }
    }

    private func refreshList() {
        listPresentation = SummitListPresentation(attendees: model.attendees, results: model.results,
                                                  connectionCount: model.connections?.count)
    }

    private func attendeeSection(_ people: [Attendee]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(people) { attendee in
                directoryRow(attendee)
                if attendee.id != people.last?.id { Divider().padding(.horizontal, 20) }
            }
        }
        .background(.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ink.opacity(0.08)))
    }

    private func toggleAttendee(_ id: UUID) {
        if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
    }

    private func directoryRow(_ attendee: Attendee) -> some View {
        let result = model.result(for: attendee)
        let expanded = expandedIDs.contains(attendee.id)
        let candidates = result?.candidates ?? []
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    attendeeHeading(attendee)
                    Spacer(minLength: 12)
                    if expanded { attendeeSearch(attendee) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    attendeeHeading(attendee)
                    if expanded { attendeeSearch(attendee) }
                }
            }
            if let result, !candidates.isEmpty || result.isConfirmed {
                VStack(alignment: .leading, spacing: 7) {
                    Button { toggleAttendee(attendee.id) } label: {
                        HStack(spacing: 6) {
                            Text(rowLabel(result)).multilineTextAlignment(.leading)
                            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                        }.font(.caption.weight(.medium)).foregroundStyle(connectionGreen)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(expanded ? "Collapse" : "Review") connections for \(attendee.name): \(rowLabel(result))")
                    if expanded {
                        ForEach(candidates) { candidate in
                            candidateDetails(candidate, result: result)
                        }
                        if candidates.isEmpty {
                            Text("You confirmed this attendee independently.").font(.caption).foregroundStyle(.secondary)
                        }
                        if result.isConfirmed && candidates.isEmpty {
                            Button("Remove confirmation") { model.classify(attendee: attendee, as: .review) }
                                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(candidateSummary(result)).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(connectionGreen.opacity(0.3)).frame(width: 2) }
                .padding(.leading, 3)
            } else if expanded {
                Text(model.connections == nil
                     ? "Add your LinkedIn export to look for possible connections."
                     : "No possible match in this export. You may still be connected.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("I checked LinkedIn — same person") { model.classify(attendee: attendee, as: .first) }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(ink)
            }
        }
        .padding(20)
        .contextMenu {
            Button("Search LinkedIn for the attendee") { model.openLinkedInSearch(for: attendee) }
            Button("Copy attendee details") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(attendee.name + " " + attendee.details, forType: .string)
            }
            if model.canUndoReview(for: attendee) {
                Button("Undo last change for this attendee", action: model.undoLastClassification)
            }
            if result?.isConfirmed == true {
                Button("Remove confirmation") { model.classify(attendee: attendee, as: .review) }
            }
        }
    }

    private let connectionGreen = Color(red: 0.22, green: 0.43, blue: 0.30)

    private func attendeeHeading(_ attendee: Attendee) -> some View {
        Button { toggleAttendee(attendee.id) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(attendee.name).font(.headline).foregroundStyle(ink)
                Text(attendee.details.isEmpty ? "No company or title supplied" : attendee.details)
                    .font(.subheadline).foregroundStyle(.secondary)
            }.multilineTextAlignment(.leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(expandedIDs.contains(attendee.id) ? "Collapse" : "Open") \(attendee.name), \(attendee.details)")
    }

    private func attendeeSearch(_ attendee: Attendee) -> some View {
        Button { model.openLinkedInSearch(for: attendee) } label: {
            Label("Search LinkedIn for the attendee", systemImage: "arrow.up.right")
        }
        .buttonStyle(.plain).font(.caption).foregroundStyle(ink).fixedSize()
        .help("Search for \(attendee.name) using the details from the summit.")
    }

    private func rowLabel(_ result: NetworkResult) -> String {
        if result.isConfirmed { return "Confirmed by you" }
        let count = result.activeCandidates.count
        if count == 0 { return "You marked these as different people" }
        return count == 1 ? "Possible match in your LinkedIn connections"
            : "\(count) possible matches in your LinkedIn connections"
    }

    private func candidateSummary(_ result: NetworkResult) -> String {
        let candidates: [MatchCandidate]
        if let confirmedID = result.confirmedCandidateID,
           let confirmed = result.candidates?.first(where: { $0.id == confirmedID }) {
            candidates = [confirmed]
        } else {
            candidates = result.activeCandidates.isEmpty ? (result.candidates ?? []) : result.activeCandidates
        }
        let summaries = candidates.prefix(2).map {
            [$0.connection.name, $0.connection.position, $0.connection.company].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return summaries.joined(separator: " / ") + (candidates.count > 2 ? " · +\(candidates.count - 2) more" : "")
    }

    private func candidateDetails(_ candidate: MatchCandidate, result: NetworkResult) -> some View {
        let rejected = (result.rejectedCandidateIDs ?? []).contains(candidate.id)
        let confirmed = result.isConfirmed && result.confirmedCandidateID == candidate.id
        return VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    candidateIdentity(candidate)
                    Spacer(minLength: 12)
                    candidateProfile(candidate)
                }
                VStack(alignment: .leading, spacing: 7) {
                    candidateIdentity(candidate)
                    candidateProfile(candidate)
                }
            }
            if candidate.otherAttendeeCount > 0 {
                Text("This connection could also match \(candidate.otherAttendeeCount) other attendee\(candidate.otherAttendeeCount == 1 ? "" : "s").")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Same person") { model.decide(attendee: result.attendee, candidate: candidate, samePerson: true) }
                    .buttonStyle(.bordered).tint(ink).disabled(confirmed)
                Button("Different person") { model.decide(attendee: result.attendee, candidate: candidate, samePerson: false) }
                    .buttonStyle(.bordered).tint(ink).disabled(rejected)
                Spacer(minLength: 0)
            }.controlSize(.small).frame(height: 24)
            // Reserve one line for local feedback, including undo: no moving cards.
            HStack(spacing: 10) {
                Text(confirmed ? "Confirmed by you" : rejected ? "Different person · attendee kept in your list" : " ")
                    .font(.caption).foregroundStyle(ink)
                Button("Undo", action: model.undoLastClassification)
                    .buttonStyle(.plain).font(.caption).foregroundStyle(ink)
                    .opacity(model.canUndoReview(for: result.attendee) ? 1 : 0)
                    .disabled(!model.canUndoReview(for: result.attendee))
                    .accessibilityHidden(!model.canUndoReview(for: result.attendee))
                Spacer(minLength: 0)
            }.frame(height: 20)
        }
        .padding(.top, 2)
    }

    private func candidateIdentity(_ candidate: MatchCandidate) -> some View {
        Text([candidate.connection.name, candidate.connection.position, candidate.connection.company].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func candidateProfile(_ candidate: MatchCandidate) -> some View {
        Group {
            if let url = linkedInProfileURL(candidate.connection.url), !model.isDemo {
                Link(destination: url) { Label("Open your connection’s profile", systemImage: "arrow.up.right") }
                    .buttonStyle(.plain).foregroundStyle(ink)
                    .help("Open the person from your LinkedIn export—not a verified attendee profile.")
            } else {
                Text(model.isDemo ? "Open your connection’s profile ↗ · demo" : "No profile link in this export")
                    .foregroundStyle(.secondary)
            }
        }.font(.caption).fixedSize()
    }

    private func navigationButton(_ title: String, active: Bool, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain).font(.caption.weight(active ? .semibold : .regular))
            .foregroundStyle(active ? ink : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(active ? ink.opacity(0.08) : .clear).cornerRadius(5)
            .disabled(disabled).accessibilityAddTraits(active ? .isSelected : [])
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
