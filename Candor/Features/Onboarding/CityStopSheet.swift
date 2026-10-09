import SwiftUI

/// Adds or edits one city on the trip: which city (Google Maps search), when, and where you sleep.
struct CityStopSheet: View {
    /// The stop being edited, or nil to add a new one.
    let editing: CityStay?
    /// Arrival date to suggest for a new stop (the previous city's departure).
    let suggestedArrival: Date
    var onSave: (CityStay) -> Void
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var city: City?
    @State private var arrival = Date()
    @State private var departure = Date()
    @State private var stay: Stay?
    @State private var wantsSuggestions = false
    @State private var bookedChoice: Bool?

    @State private var cityQuery = ""
    @State private var cityResults: [City] = []
    @State private var stayQuery = ""
    @State private var stayResults: [GooglePlace] = []
    @State private var searchError: String?
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                citySection
                if city != nil {
                    datesSection
                    staySection
                }
                if let onDelete, editing != nil {
                    Section {
                        Button(L("Remove this city"), role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? L("Add a city") : L("Edit city"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done"), action: save)
                        .disabled(city == nil)
                        .accessibilityIdentifier("cityStopDone")
                }
            }
            .onAppear(perform: load)
            .task(id: cityQuery) { await searchCities() }
            .task(id: stayQuery) { await searchStays() }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var citySection: some View {
        Section {
            if let city {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.displayName).font(.headline)
                        CoverageLabel(coverage: city.coverage)
                    }
                    Spacer()
                    Button(L("Change")) {
                        withAnimation(.snappy) {
                            self.city = nil
                            stay = nil
                            stayResults = []
                        }
                    }
                }
            } else {
                TextField(L("Search a city"), text: $cityQuery)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("citySearch")
                ForEach(cityQuery.trimmingCharacters(in: .whitespaces).isEmpty ? City.featured : cityResults) { option in
                    Button { pick(option) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName).foregroundStyle(.primary)
                                CoverageLabel(coverage: option.coverage)
                            }
                            Spacer()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if let searchError {
                    Text(searchError).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L("City"))
        } footer: {
            if city == nil && !cityQuery.isEmpty && !cityResults.isEmpty {
                Text("Powered by Google")
            }
        }
    }

    private var datesSection: some View {
        Section(L("Dates")) {
            DatePicker(L("Arriving"), selection: $arrival, displayedComponents: .date)
            DatePicker(L("Leaving"), selection: $departure, in: arrival..., displayedComponents: .date)
            LabeledContent(L("Days"), value: "\(dayCount)")
        }
        .onChange(of: arrival) { _, value in
            if departure < value { departure = value }
        }
    }

    @ViewBuilder
    private var staySection: some View {
        Section {
            Picker(L("Where are you staying?"), selection: $bookedChoice) {
                Text(L("Not sure yet")).tag(Bool?.none)
                Text(L("Already booked")).tag(Bool?.some(true))
                Text(L("Help me choose")).tag(Bool?.some(false))
            }
            if bookedChoice == true {
                if let stay {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stay.name)
                            if let address = stay.address {
                                Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Button(L("Change")) { self.stay = nil }
                    }
                } else {
                    TextField(L("Hotel name or address"), text: $stayQuery)
                    ForEach(stayResults.prefix(4)) { place in
                        Button {
                            stay = Stay(name: place.name, address: place.address,
                                        latitude: place.latitude, longitude: place.longitude)
                            stayQuery = ""
                            stayResults = []
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).foregroundStyle(.primary)
                                if let address = place.address {
                                    Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text(L("Stay"))
        } footer: {
            if bookedChoice == true {
                Text(stay == nil ? "Powered by Google" : L("Your days here start from your stay."))
            } else if bookedChoice == false {
                Text(L("Candor will suggest areas that suit your style and budget."))
            }
        }
    }

    // MARK: Actions

    private var dayCount: Int {
        max((Calendar.current.dateComponents([.day], from: arrival, to: departure).day ?? 0) + 1, 1)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let editing {
            city = editing.city
            arrival = editing.arrival
            departure = editing.departure
            stay = editing.stay
            bookedChoice = editing.stay != nil ? true : (editing.wantsStaySuggestions ? false : nil)
        } else {
            arrival = Calendar.current.startOfDay(for: suggestedArrival)
            departure = Calendar.current.date(byAdding: .day, value: 1, to: arrival) ?? arrival
        }
    }

    private func pick(_ option: City) {
        withAnimation(.snappy) {
            city = option
            cityQuery = ""
            cityResults = []
        }
    }

    private func save() {
        guard let city else { return }
        let calendar = Calendar.current
        var result = editing ?? CityStay(city: city, arrival: arrival, departure: departure)
        result.city = city
        result.arrival = calendar.startOfDay(for: arrival)
        result.departure = calendar.startOfDay(for: max(departure, arrival))
        result.stay = bookedChoice == true ? stay : nil
        result.wantsStaySuggestions = bookedChoice == false
        onSave(result)
        dismiss()
    }

    private func searchCities() async {
        let q = cityQuery.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            cityResults = []
            searchError = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            let found = try await GooglePlaces.searchCities(q)
            guard !Task.isCancelled else { return }
            cityResults = found
            searchError = found.isEmpty ? L("No cities found.") : nil
        } catch {
            guard !Task.isCancelled else { return }
            // Without search, the suggested cities still work.
            cityResults = City.featured.filter { $0.name.localizedCaseInsensitiveContains(q) }
            searchError = cityResults.isEmpty ? error.localizedDescription : nil
        }
    }

    private func searchStays() async {
        let q = stayQuery.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, let city else {
            stayResults = []
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let found = (try? await GooglePlaces.search(q, in: city)) ?? []
        guard !Task.isCancelled else { return }
        stayResults = found
    }
}

/// "Verified guide" or "AI guide", small, under a city name.
struct CoverageLabel: View {
    let coverage: Coverage

    var body: some View {
        // An HStack, not a Label: inside a List a Label's icon moves into the row's icon column.
        HStack(spacing: 4) {
            Image(systemName: coverage == .verified ? "checkmark.seal.fill" : "map")
            Text(coverage.title)
        }
        .font(.caption)
        .foregroundStyle(coverage == .verified ? Theme.mint : .secondary)
    }
}
