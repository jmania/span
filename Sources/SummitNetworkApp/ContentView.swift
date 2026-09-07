import SwiftUI
#if canImport(SummitCore)
import SummitCore
#endif
import UniformTypeIdentifiers

private enum DirectoryFilter: String, CaseIterable {
    case all = "Everyone"
    case possible = "Possible connections"
    case confirmed = "Confirmed by you"
}
private enum DirectorySort: String, CaseIterable {
    case suggestions = "Possible connections first"
    case alphabetical = "A–Z"
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showingImporter = false
    @State private var dropTargeted = false
    @State private var confirmingReset = false
    @State private var showingAccessHelp = false
    @State private var showingLinkedInHelp = false
    @State private var showingInputs = false
    @State private var directoryFilter: DirectoryFilter = .all
    @State private var directoryQuery = ""
    @State private var directorySort: DirectorySort = .suggestions
    @State private var visibleIDs: [UUID] = []
    @State private var expandedIDs = Set<UUID>()
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your Summit list").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(ink)
                    Text("\(model.attendees.count) attendees · \(model.possibleCount) with possible connections · \(model.firstDegreeCount) confirmed by you")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Export list…", action: model.exportResults).buttonStyle(.bordered)
            }
            if model.isDemo {
                Text("DEMO · FICTIONAL ATTENDEES").font(.caption.bold()).foregroundStyle(accent)
            }
            if model.connections == nil {
                HStack {
                    Text("Your list is ready. Add your LinkedIn export to see possible connections.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add export…") { showingImporter = true }.disabled(model.isImporting)
                }.padding(12).background(.white.opacity(0.8)).cornerRadius(12)
            } else {
                Text("Suggestions are clues, not proof. Compare the details and confirm only people you recognize.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                TextField("Search attendees by name, company, or title", text: $directoryQuery)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search attendees")
                Picker("Sort", selection: $directorySort) {
                    ForEach(DirectorySort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(width: 245)
            }
            HStack(spacing: 8) {
                ForEach(DirectoryFilter.allCases, id: \.self) { filter in
                    Button(filter.rawValue) {
                        directoryFilter = filter
                        refreshVisibleRows()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(directoryFilter == filter ? .semibold : .regular))
                    .foregroundStyle(directoryFilter == filter ? ink : .secondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(directoryFilter == filter ? ink.opacity(0.1) : .clear)
                    .clipShape(Capsule())
                    .accessibilityAddTraits(directoryFilter == filter ? .isSelected : [])
                }
                Spacer()
                Text("\(visibleIDs.count) shown").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(model.lastClassificationMessage ?? "Your decisions are saved here. There’s no need to review everyone.")
                    .font(.caption).foregroundStyle(ink).lineLimit(2)
                    .accessibilityLabel(model.lastClassificationMessage ?? "Review is optional")
                Spacer()
                Button("Undo", action: model.undoLastClassification).buttonStyle(.link).disabled(!model.canUndoReview)
                Button("Refresh order", action: refreshVisibleRows).buttonStyle(.link)
                    .help("Apply the current filter and order again. Decisions never move rows automatically.")
            }.frame(height: 32)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visibleIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("No attendees in this view.").font(.headline)
                            Text(directoryFilter == .confirmed ? "People appear here after you confirm their identity." : "Try another search or choose Everyone. No suggestion does not mean you aren’t connected.")
                                .foregroundStyle(.secondary)
                        }.padding(24)
                    }
                    ForEach(visibleAttendees) { attendee in
                        directoryRow(attendee)
                        Divider().padding(.horizontal, 16)
                    }
                }
                .background(.white.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                if !creatorCardDismissed, let url = Brand.creatorURL {
                    creatorCard(url).padding(.top, 16)
                }
            }
        }
        .padding(24)
        .onAppear(perform: refreshVisibleRows)
        .onChange(of: directoryQuery) { _ in refreshVisibleRows() }
        .onChange(of: directorySort) { _ in refreshVisibleRows() }
        .onChange(of: model.inputRevision) { _ in refreshVisibleRows() }
    }

    private var visibleAttendees: [Attendee] {
        let lookup = Dictionary(model.attendees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return visibleIDs.compactMap { lookup[$0] }
    }

    // Freeze membership and order during decisions. Explicit filter/search/sort changes refresh it.
    private func refreshVisibleRows() {
        let query = normalizedName(directoryQuery)
        let lookup = Dictionary(model.results.map { ($0.attendee.id, $0) }, uniquingKeysWith: { first, _ in first })
        visibleIDs = model.attendees.filter { attendee in
            let result = lookup[attendee.id]
            if directoryFilter == .possible && result?.hasSuggestion != true { return false }
            if directoryFilter == .confirmed && result?.isConfirmed != true { return false }
            return query.isEmpty || normalizedName(attendee.name + " " + attendee.details).contains(query)
        }.sorted { left, right in
            if directorySort == .suggestions {
                let l = lookup[left.id], r = lookup[right.id]
                let ls = l?.hasSuggestion == true ? (l?.activeCandidates.first?.rank ?? 0) : -1
                let rs = r?.hasSuggestion == true ? (r?.activeCandidates.first?.rank ?? 0) : -1
                if ls != rs { return ls > rs }
            }
            if left.name != right.name { return left.name.localizedStandardCompare(right.name) == .orderedAscending }
            if left.details != right.details { return left.details < right.details }
            return left.id.uuidString < right.id.uuidString
        }.map(\.id)
    }

    private func directoryRow(_ attendee: Attendee) -> some View {
        let result = model.result(for: attendee)
        let expanded = expandedIDs.contains(attendee.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if expanded { expandedIDs.remove(attendee.id) } else { expandedIDs.insert(attendee.id) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold)).frame(width: 12).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(attendee.name).font(.headline).foregroundStyle(ink)
                            Text(attendee.details.isEmpty ? "No company or title supplied" : attendee.details)
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            Text(rowLabel(result)).font(.caption.weight(.medium))
                                .foregroundStyle(result?.isConfirmed == true ? ink : .secondary)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(attendee.name), \(rowLabel(result))")
                Spacer(minLength: 10)
                Button("Search LinkedIn") { model.openLinkedInSearch(for: attendee) }
                    .buttonStyle(.bordered).controlSize(.small)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(attendee.name + " " + attendee.details, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Copy search text").accessibilityLabel("Copy search text for \(attendee.name)")
            }
            if expanded {
                if let result {
                        HStack {
                            Text(result.isConfirmed ? "Identity confirmed by you." : "Event details above; your possible connections below.").font(.caption)
                            if result.isConfirmed, let url = linkedInProfileURL(result.linkedInURL), !model.isDemo {
                                Link("View confirmed profile", destination: url)
                            }
                            Spacer()
                            Button("Remove confirmation") { model.classify(attendee: attendee, as: .review) }.buttonStyle(.link)
                                .opacity(result.isConfirmed ? 1 : 0).disabled(!result.isConfirmed)
                                .accessibilityHidden(!result.isConfirmed)
                        }.frame(height: 24)
                    if !(result.candidates ?? []).isEmpty {
                        Text("FROM YOUR LINKEDIN EXPORT").font(.caption2.bold()).tracking(1.2).foregroundStyle(accent)
                        ForEach(result.candidates ?? []) { candidate in
                            candidateCard(candidate, result: result)
                        }
                    } else {
                        Text(model.connections == nil ? "Add your LinkedIn export to look for possible connections." : "No candidate in this export. You may still be connected—search LinkedIn to find this attendee.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                        Button("I’ve checked LinkedIn — confirm this attendee") { model.classify(attendee: attendee, as: .first) }
                            .buttonStyle(.link).font(.caption)
                            .opacity(result.isConfirmed ? 0 : 1).disabled(result.isConfirmed).accessibilityHidden(result.isConfirmed)
                        Button("Restore dismissed suggestions") { model.restoreSuggestions(for: attendee) }
                            .buttonStyle(.link).font(.caption)
                            .opacity((result.rejectedCandidateIDs ?? []).isEmpty ? 0 : 1)
                            .disabled((result.rejectedCandidateIDs ?? []).isEmpty)
                            .accessibilityHidden((result.rejectedCandidateIDs ?? []).isEmpty)
                    if result.reviewedAt != nil && result.degree != .first && result.degree != .review {
                        Text("Previously marked by you: \(result.degree.label).").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(16)
    }

    private func rowLabel(_ result: NetworkResult?) -> String {
        guard let result else { return "Attendee from the event" }
        if result.isConfirmed { return "Confirmed by you" }
        if result.hasSuggestion { return "Possible LinkedIn connection · \(result.activeCandidates.count) candidate\(result.activeCandidates.count == 1 ? "" : "s")" }
        if !(result.rejectedCandidateIDs ?? []).isEmpty { return "Suggestion dismissed · identity unconfirmed" }
        return "Attendee from the event"
    }

    private func candidateCard(_ candidate: MatchCandidate, result: NetworkResult) -> some View {
        let rejected = (result.rejectedCandidateIDs ?? []).contains(candidate.id)
        let confirmed = result.isConfirmed && result.confirmedCandidateID == candidate.id
        return VStack(alignment: .leading, spacing: 8) {
            Text(candidate.connection.name).font(.subheadline.weight(.semibold)).foregroundStyle(ink)
            Text(candidate.connection.details.isEmpty ? "No company or title in your export" : candidate.connection.details)
                .font(.subheadline).foregroundStyle(.secondary)
            Text(candidate.reason).font(.caption).foregroundStyle(.secondary)
            if candidate.otherAttendeeCount > 0 {
                Text("This contact is also a possibility for \(candidate.otherAttendeeCount) other attendee\(candidate.otherAttendeeCount == 1 ? "" : "s").")
                    .font(.caption).foregroundStyle(accent)
            }
            HStack {
                if let url = linkedInProfileURL(candidate.connection.url), !model.isDemo {
                    Link("View possible connection’s profile", destination: url).font(.subheadline)
                } else {
                    Text(model.isDemo ? "Profile link · fictional demo" : "No LinkedIn profile URL in this export")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Same person") { model.decide(attendee: result.attendee, candidate: candidate, samePerson: true) }
                    .buttonStyle(.bordered).disabled(confirmed)
                Button("Different person") { model.decide(attendee: result.attendee, candidate: candidate, samePerson: false) }
                    .buttonStyle(.bordered).disabled(rejected)
            }
            Text(confirmed ? "Confirmed by you" : (rejected ? "Dismissed — attendee remains in your list" : "Same person? Compare the details or search LinkedIn."))
                .font(.caption).foregroundStyle(ink).frame(height: 18, alignment: .leading)
        }.padding(14).background(Brand.paper).cornerRadius(12)
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
