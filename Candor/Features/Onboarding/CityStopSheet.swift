import SwiftUI

/// Adds or edits one city on the trip: which city (Google Maps search), when, and where you sleep.
/// A bottom sheet in three cards (city, dates, stay) with one pill to save.
struct CityStopSheet: View {
    /// The stop being edited, or nil to add a new one.
    let editing: CityStay?
    /// Arrival date to suggest for a new stop (the previous city's departure).
    let suggestedArrival: Date
    var onSave: (CityStay) -> Void
    var onDelete: (() -> Void)?

    private enum DateField { case arrival, departure }

    @Environment(\.dismiss) private var dismiss
    @State private var city: City?
    @State private var arrival = Date()
    @State private var departure = Date()
    @State private var stay: Stay?
    @State private var bookedChoice: Bool?
    @State private var editingDate: DateField?

    @State private var cityQuery = ""
    @State private var cityResults: [City] = []
    @State private var stayQuery = ""
    @State private var stayResults: [GooglePlace] = []
    @State private var searchError: String?
    @State private var didLoad = false
    @FocusState private var cityFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let city {
                        chosenCity(city)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        datesCard
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        stayCard
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        if let onDelete, editing != nil {
                            Button(role: .destructive) {
                                onDelete()
                                dismiss()
                            } label: {
                                Label(L("Remove this city"), systemImage: "trash")
                                    .font(.candor(.subheadline, .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.top, 4)
                        }
                    } else {
                        citySearch
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            if let city {
                Button(action: save) {
                    HStack(spacing: 8) {
                        Text(editing == nil ? L("Add %@ to my trip", L(city.name)) : L("Save changes"))
                        Image(systemName: "checkmark")
                    }
                }
                .buttonStyle(.pill)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .accessibilityIdentifier("cityStopDone")
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.canvas)
        .animation(.snappy, value: city)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .onAppear(perform: load)
        .task(id: cityQuery) { await searchCities() }
        .task(id: stayQuery) { await searchStays() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(editing == nil ? L("Add a city") : L("Edit city"))
                    .font(.heading(.title1))
                Text(city == nil ? L("Where to next?") : L("When, and where you'll sleep"))
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                CircleIcon(systemName: "xmark", size: 40)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(L("Cancel"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 14)
    }

    // MARK: City

    private var citySearch: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.saffron)
                TextField(L("Search a city"), text: $cityQuery)
                    .font(.candor(.headline))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($cityFocused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("citySearch")
                if !cityQuery.isEmpty {
                    Button { cityQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel(L("Clear"))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(Theme.surface, in: .capsule)
            .shadow(color: Theme.shadow, radius: 12, y: 6)

            let searching = !cityQuery.trimmingCharacters(in: .whitespaces).isEmpty
            Text(searching ? L("Results") : L("Popular"))
                .font(.candor(.footnote, .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if searching {
                VStack(spacing: 10) {
                    ForEach(cityResults) { option in
                        Button { pick(option) } label: { cityRow(option) }
                            .buttonStyle(.pressable)
                            .accessibilityLabel(option.displayName + ", " + option.coverage.title)
                    }
                }
                if let searchError {
                    Text(searchError).font(.candor(.caption1)).foregroundStyle(.secondary)
                }
                if !cityResults.isEmpty {
                    Text(verbatim: "Powered by Google").font(.candor(.caption2)).foregroundStyle(.tertiary)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(City.featured) { option in
                        Button { pick(option) } label: { cityTile(option) }
                            .buttonStyle(.pressable)
                            .accessibilityLabel(option.displayName + ", " + option.coverage.title)
                    }
                }
            }
        }
    }

    private func cityTint(_ city: City) -> Color {
        let palette = [Theme.saffron, Theme.rose, Theme.indigo, Theme.teal, Theme.mint, Color(hex: 0xC8743A)]
        let sum = city.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    private func cityBadge(_ city: City, size: CGFloat) -> some View {
        let tint = cityTint(city)
        return Text(String(L(city.name).prefix(1)))
            .font(.display(size: size * 0.45, .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: size * 0.3, style: .continuous))
    }

    /// A popular city: letter badge, name, coverage.
    private func cityTile(_ option: City) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cityBadge(option, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(L(option.name)).font(.heading(.headline)).foregroundStyle(.primary)
                CoverageLabel(coverage: option.coverage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.large))
        .shadow(color: Theme.shadow, radius: 10, y: 5)
    }

    private func cityRow(_ option: City) -> some View {
        HStack(spacing: 12) {
            cityBadge(option, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(option.displayName).font(.candor(.headline, .semibold)).foregroundStyle(.primary)
                CoverageLabel(coverage: option.coverage)
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.ink)
        }
        .padding(12)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.medium))
        .shadow(color: Theme.shadow, radius: 8, y: 4)
    }

    /// The chosen city as a small hero card, with a button to change it.
    private func chosenCity(_ city: City) -> some View {
        ZStack(alignment: .bottomLeading) {
            CityScene(animated: false, landmarks: city.id == City.delhi.id)
                .frame(height: 120)
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(city.displayName)
                        .font(.heading(.title2))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Image(systemName: city.coverage == .verified ? "checkmark.seal.fill" : "map")
                        Text(city.coverage.title)
                    }
                    .font(.candor(.caption1, .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Button(L("Change")) {
                    withAnimation(.snappy) {
                        self.city = nil
                        stay = nil
                        stayResults = []
                    }
                }
                .font(.candor(.subheadline, .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(.ultraThinMaterial, in: .capsule)
            }
            .padding(16)
        }
        .frame(height: 120)
        .clipShape(.rect(cornerRadius: Theme.Radius.large, style: .continuous))
        .shadow(color: Theme.shadow, radius: 12, y: 6)
    }

    // MARK: Dates

    private var datesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle(L("Dates"), icon: "calendar")
            HStack(spacing: 10) {
                dateTile(L("Arriving"), date: arrival, field: .arrival)
                VStack(spacing: 4) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.indigo)
                    Text(L("%@ days", dayCount))
                        .font(.candor(.caption2, .bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(dayCount)))
                }
                .frame(width: 54)
                dateTile(L("Leaving"), date: departure, field: .departure)
            }
            if let editingDate {
                Group {
                    switch editingDate {
                    case .arrival:
                        DatePicker(L("Arriving"), selection: $arrival, displayedComponents: .date)
                    case .departure:
                        DatePicker(L("Leaving"), selection: $departure, in: arrival..., displayedComponents: .date)
                    }
                }
                .datePickerStyle(.graphical)
                .tint(Theme.saffron)
                .id(editingDate)
                .transition(.candorReveal)
            }
        }
        .card(padding: 16)
        .onChange(of: arrival) { _, value in
            if departure < value { departure = value }
        }
        .animation(.candorExpand, value: editingDate)
        .animation(.snappy, value: dayCount)
    }

    private func dateTile(_ label: String, date: Date, field: DateField) -> some View {
        let selected = editingDate == field
        let locale = Localizer.shared.locale
        return Button {
            editingDate = selected ? nil : field
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label)
                        .font(.candor(.caption1, .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "chevron.up" : "pencil")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 22, height: 22)
                        .background(Theme.accentSoft, in: .circle)
                }
                Text(date.formatted(.dateTime.day().locale(locale)))
                    .font(.display(size: 30, .bold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(date.formatted(.dateTime.month(.abbreviated).weekday(.abbreviated).locale(locale)))
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
                Text(selected ? L("Pick a date below") : L("Tap to change"))
                    .font(.candor(.caption2, .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(selected ? Theme.accentSoft : Theme.canvas, in: .rect(cornerRadius: Theme.Radius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .strokeBorder(selected ? Theme.ink : Color.primary.opacity(0.15),
                                  style: StrokeStyle(lineWidth: selected ? 1.5 : 1, dash: selected ? [] : [5, 4]))
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label + ", " + date.formatted(date: .long, time: .omitted))
    }

    // MARK: Stay

    private var stayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle(L("Where are you staying?"), icon: "bed.double.fill")
            HStack(spacing: 8) {
                stayChoice(L("Already booked"), icon: "checkmark.seal.fill", tint: Theme.mint, value: true)
                stayChoice(L("Help me choose"), icon: "sparkles", tint: Theme.saffron, value: false)
                stayChoice(L("Not sure yet"), icon: "questionmark", tint: .gray, value: nil)
            }

            if bookedChoice == true {
                if let stay {
                    HStack(spacing: 12) {
                        Image(systemName: "house.fill")
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Theme.mint, in: .rect(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stay.name).font(.candor(.subheadline, .semibold))
                            if let address = stay.address {
                                Text(address).font(.candor(.caption1)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Button(L("Change")) { withAnimation(.snappy) { self.stay = nil } }
                            .font(.candor(.caption1, .semibold))
                    }
                    .padding(12)
                    .background(Theme.canvas, in: .rect(cornerRadius: Theme.Radius.medium))
                    Text(L("Your days here start from your stay."))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(L("Hotel name or address"), text: $stayQuery)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Theme.canvas, in: .capsule)
                    ForEach(stayResults.prefix(4)) { place in
                        Button {
                            withAnimation(.snappy) {
                                stay = Stay(name: place.name, address: place.address,
                                            latitude: place.latitude, longitude: place.longitude)
                                stayQuery = ""
                                stayResults = []
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "building.2.fill")
                                    .foregroundStyle(Theme.teal)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).font(.candor(.subheadline, .semibold)).foregroundStyle(.primary)
                                    if let address = place.address {
                                        Text(address).font(.candor(.caption1)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    if !stayResults.isEmpty {
                        Text(verbatim: "Powered by Google").font(.candor(.caption2)).foregroundStyle(.tertiary)
                    }
                }
            } else if bookedChoice == false {
                Label(L("Candor will suggest areas that suit your style and budget."), systemImage: "sparkles")
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
            } else {
                Label(L("No problem. Candor will keep asking so it can show you the way back home."),
                      systemImage: "house")
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
            }
        }
        .card(padding: 16)
        .animation(.snappy, value: bookedChoice)
    }

    private func stayChoice(_ title: String, icon: String, tint: Color, value: Bool?) -> some View {
        let selected = bookedChoice == value
        return Button {
            bookedChoice = value
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(selected ? .white : tint)
                    .frame(width: 38, height: 38)
                    .background(selected ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)), in: .circle)
                    .symbolEffect(.bounce, value: selected)
                Text(title)
                    .font(.candor(.caption1, .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(Theme.canvas, in: .rect(cornerRadius: Theme.Radius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .strokeBorder(selected ? Theme.ink : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func cardTitle(_ title: String, icon: String) -> some View {
        Label {
            Text(title).font(.heading(.headline))
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.saffron)
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
            departure = Calendar.current.date(byAdding: .day, value: 2, to: arrival) ?? arrival
        }
    }

    private func pick(_ option: City) {
        cityFocused = false
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
            cityResults = City.featured.filter { !q.isEmpty && $0.name.localizedCaseInsensitiveContains(q) }
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
        .font(.candor(.caption1))
        .foregroundStyle(coverage == .verified ? Theme.mint : .secondary)
    }
}
