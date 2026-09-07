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

    private let accent = Color(red: 0.91, green: 0.36, blue: 0.22)
    private let ink = Color(red: 0.08, green: 0.19, blue: 0.14)

    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.96, blue: 0.93).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                Group {
                    if model.attendees.isEmpty {
                        setupView
                    } else if model.results.isEmpty {
                        importView
                    } else {
                        resultsView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(accent)
        .alert("Something needs attention", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "zip")!],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first { model.importConnections(from: url) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Summit Network").font(.headline).foregroundStyle(ink)
                Text("Your conference connections, privately matched").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.statusMessage.isEmpty {
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Button("Start over", role: .destructive) { confirmingReset = true }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .opacity(model.attendees.isEmpty ? 0 : 1)
                .disabled(model.attendees.isEmpty)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(.white.opacity(0.72))
        .confirmationDialog("Start over?", isPresented: $confirmingReset) {
            Button("Delete saved session and start over", role: .destructive) { model.startOver() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the attendee list and review decisions saved by Summit Network on this Mac.")
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Find the people already close to your network")
                        .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(ink)
                    Text("Summit Network reads the attendee directory you can already access, then matches it against your own LinkedIn connections export. Nothing is uploaded.")
                        .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 16) {
                    prerequisiteCard
                    privacyCard
                }

                if model.isExtracting {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Collecting attendees…").font(.headline)
                            Spacer()
                            Text("\(model.extractionCount) found").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Text("Keep Lenny & Friends open on All attendees until this finishes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .cardStyle()
                } else {
                    VStack(spacing: 10) {
                        Button(action: model.extractAttendees) {
                            Label("Collect attendees", systemImage: "person.3.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!model.accessibilityTrusted || !model.appRunning)
                        Button("Preview with sample data") { model.loadDemo() }.buttonStyle(.link)
                    }
                }
            }
            .padding(38).frame(maxWidth: 920)
        }
    }

    private var prerequisiteCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before you begin").font(.headline).foregroundStyle(ink)
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
            Button("Check again") { model.refreshPrerequisites() }.buttonStyle(.link)
            Text("In Lenny & Friends, open Attendees → All attendees before collecting.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle().frame(maxWidth: .infinity, alignment: .top)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Private by design", systemImage: "lock.shield.fill")
                .font(.headline).foregroundStyle(ink)
            Text("Your attendee list, LinkedIn export, and decisions stay on this Mac.")
            privacyRow("No account password")
            privacyRow("No browser scraping")
            privacyRow("No cloud upload")
            privacyRow("No automatic messages")
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary).cardStyle().frame(maxWidth: .infinity, minHeight: 265, alignment: .top)
    }

    private var importView: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 46)).foregroundStyle(.green)
            Text("\(model.attendees.count) attendees collected")
                .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(ink)
            Text("Now add the archive LinkedIn gave you. You can drop the ZIP directly—there is no need to find Connections.csv inside it.")
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

            Text("Get it from LinkedIn: Settings & Privacy → Data privacy → Get a copy of your data.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
    }

    private var resultsView: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                metric("First degree", model.firstDegreeCount, color: .green)
                metric("Second degree", model.secondDegreeCount, color: .blue)
                metric("Needs review", model.reviewCount, color: accent)
                metric("Not connected", model.notConnectedCount, color: .secondary)
            }

            if let current = model.currentReview {
                reviewCard(current)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(.green)
                    Text("Review complete").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(ink)
                    Text("Your decisions are saved. Export the finished spreadsheet when you’re ready.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).cardStyle()
            }

            HStack {
                Text("Every decision is saved automatically on this Mac.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Export spreadsheet…") { model.exportResults() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding(28)
    }

    private func reviewCard(_ result: NetworkResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Review the remaining attendees").font(.headline).foregroundStyle(ink)
                Spacer()
                Text("\(model.reviewCount) remaining").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text(result.attendee.name).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(ink)
            Text(result.attendee.details.isEmpty ? "No company or title supplied" : result.attendee.details)
                .font(.title3).foregroundStyle(.secondary)
            Text([result.attendee.name, result.attendee.details].filter { !$0.isEmpty }.joined(separator: " "))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("Copy search text") { model.copyCurrentSearch() }.buttonStyle(.borderedProminent)
                Button("Open LinkedIn") { model.openLinkedIn() }
                Spacer()
            }
            Text("Paste the text into LinkedIn’s normal search, check the connection badge, then choose a result below. Summit Network never reads or controls LinkedIn.")
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

    private func metric(_ label: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.82)).clipShape(RoundedRectangle(cornerRadius: 14))
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
    func cardStyle() -> some View {
        self.padding(22)
            .background(.white.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06)))
    }
}
