import SwiftUI

/// The trip's cities on the profile, so a change of plan is one place away: edit a city's dates
/// or stay, swap it for another city, add or remove one, then have Candor plan the days again.
/// Edits stay a draft until the traveller saves or replans, so the current days aren't left
/// pointing at a city that's no longer on the trip.
struct TripCitiesCard: View {
    @Environment(AppState.self) private var app
    @State private var stops: [CityStay] = []
    @State private var didLoad = false
    @State private var addingStop = false
    @State private var editingStop: CityStay?
    @State private var confirmReplan = false
    @State private var isPlanning = false
    @State private var planLog: String?

    /// The draft differs from the saved trip.
    private var hasChanges: Bool { stops != (app.trip?.cities ?? []) }
    /// The saved trip already has days, so saving new cities means planning again.
    private var hasPlan: Bool { !(app.trip?.days.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L("Your trip"), systemImage: "map").font(.candor(.headline, .semibold))
                Spacer()
                if hasChanges {
                    Text(L("Not saved"))
                        .font(.candor(.caption1, .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.saffron.opacity(0.14), in: .capsule)
                        .transition(.opacity)
                }
            }
            Text(L("Change of plan? Edit a city, swap it for another, or add one, then let Candor plan your days again."))
                .font(.candor(.caption1))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(stops.enumerated()), id: \.element.id) { number, stop in
                Button { editingStop = stop } label: { cityRow(stop, number: number + 1) }
                    .buttonStyle(.pressable)
                    .disabled(isPlanning)
            }

            Button { addingStop = true } label: {
                Label(stops.isEmpty ? L("Add your first city") : L("Add another city"), systemImage: "plus")
                    .font(.candor(.subheadline, .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.bordered)
            .disabled(isPlanning)

            if isPlanning {
                HStack(spacing: 12) {
                    AgentMark(size: 36, isActive: true)
                    Text(planLog ?? L("Planning your days…"))
                        .font(.candor(.subheadline, .semibold))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            } else {
                Button {
                    if hasPlan { confirmReplan = true } else { replan() }
                } label: {
                    Label(L("Regenerate my plan"), systemImage: "sparkles")
                        .font(.candor(.subheadline, .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                .disabled(stops.isEmpty)

                if hasChanges {
                    HStack(spacing: 10) {
                        Button(L("Discard changes")) { withAnimation(.snappy) { load(force: true) } }
                            .buttonStyle(.bordered)
                        if !hasPlan {
                            Button(L("Save cities")) { save() }
                                .buttonStyle(.bordered)
                        }
                    }
                    .font(.candor(.subheadline, .semibold))
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                }
            }
        }
        .card()
        .animation(.smooth, value: hasChanges)
        .animation(.smooth, value: isPlanning)
        .onAppear { load(force: false) }
        .sheet(isPresented: $addingStop) {
            CityStopSheet(editing: nil, suggestedArrival: stops.last?.departure ?? .now) { stop in
                withAnimation(.snappy) {
                    stops.append(stop)
                    stops.sort { $0.arrival < $1.arrival }
                }
            }
        }
        .sheet(item: $editingStop) { stop in
            CityStopSheet(editing: stop, suggestedArrival: stop.arrival) { updated in
                if let index = stops.firstIndex(where: { $0.id == updated.id }) { stops[index] = updated }
                withAnimation(.snappy) { stops.sort { $0.arrival < $1.arrival } }
            } onDelete: {
                withAnimation(.snappy) { stops.removeAll { $0.id == stop.id } }
            }
        }
        .confirmationDialog(L("Plan your trip again?"), isPresented: $confirmReplan, titleVisibility: .visible) {
            Button(L("Regenerate my plan"), role: .destructive) { replan() }
        } message: {
            Text(L("Candor replaces your current days and places with a new plan for these cities and dates."))
        }
    }

    private func cityRow(_ stop: CityStay, number: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.candor(.subheadline, .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.saffron, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.city.displayName).font(.candor(.headline, .semibold)).foregroundStyle(.primary)
                Text(dateRange(stop) + " · " + L("%@ days", stop.dayCount))
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
                if let stay = stop.stay {
                    Label(stay.name, systemImage: "bed.double.fill")
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "pencil")
                .font(.candor(.footnote, .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Theme.surface.opacity(0.8), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func dateRange(_ stop: CityStay) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Localizer.shared.locale)
        return stop.arrival.formatted(style) + "–" + stop.departure.formatted(style)
    }

    // MARK: Actions

    private func load(force: Bool) {
        guard force || !didLoad else { return }
        didLoad = true
        stops = app.trip?.cities ?? []
    }

    /// The saved trip with the draft cities: same party and travellers, dates from the first city.
    private func editedTrip() -> Trip {
        var trip = app.trip ?? Trip(cities: [], party: nil, travellers: nil)
        trip.cities = stops
        trip.startDate = Calendar.current.startOfDay(for: stops.first?.arrival ?? .now)
        return trip
    }

    /// Cities only, for a trip with no days planned yet.
    private func save() {
        withAnimation(.smooth) { app.trip = editedTrip() }
    }

    /// Plans the days again for the draft cities, the same way onboarding does.
    private func replan() {
        var trip = editedTrip()
        trip.days = []
        trip.insights = []
        planLog = nil
        isPlanning = true
        Task {
            let planned = app.hasGemini
                ? await TripPlanner.suggestWithGemini(app: app, trip: trip, progress: { line in
                    withAnimation(.snappy) { planLog = line }
                })
                : TripPlanner.suggest(persona: app.persona, trip: trip)
            withAnimation(.smooth) {
                app.trip = planned
                stops = planned.cities
                isPlanning = false
            }
        }
    }
}
