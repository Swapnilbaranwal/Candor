import SwiftUI
import CoreLocation

/// Map of verified places with fair-price tips; tap a pin for actions.
struct ExploreView: View {
    @Binding var tab: AppTab
    @Environment(LocationService.self) private var location
    @Environment(CandorAgent.self) private var agent
    @Environment(AskCandorRouter.self) private var askCandor
    @State private var camera: GoogleMapView.Camera = .region(
        latitude: DelhiData.center.latitude, longitude: DelhiData.center.longitude, zoom: 11
    )
    @State private var selectedID: String?
    @State private var category: SpotCategory?
    @State private var rideDestination: String?

    private var spots: [Spot] {
        DelhiData.spots.filter { category == nil || $0.category == category }
    }

    private var selected: Spot? {
        DelhiData.spots.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack {
            GoogleMapView(
                markers: spots.map { spot in
                    .init(id: spot.id, spot.coordinate, title: L(spot.name),
                          style: .symbol(spot.category.icon, UIColor(spot.category.color)))
                },
                camera: camera,
                showsMyLocation: true,
                onSelect: { selectedID = $0 }
            )
            .safeAreaInset(edge: .top) { filterBar }
            .safeAreaInset(edge: .bottom) {
                if let spot = selected {
                    spotCard(spot)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: selectedID)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $rideDestination) { destination in
                RideCheckView(initialDestination: destination)
            }
            .onChange(of: selectedID) { _, id in
                guard let spot = DelhiData.spots.first(where: { $0.id == id }) else { return }
                withAnimation(.smooth) {
                    camera = .focus(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude, zoom: 15, tilt: 45)
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                HStack(spacing: 8) {
                    Chip(title: L("All"), isSelected: category == nil) {
                        withAnimation(.snappy) { category = nil }
                    }
                    ForEach(SpotCategory.allCases) { item in
                        Chip(title: item.title, icon: item.icon, isSelected: category == item, tint: item.color) {
                            withAnimation(.snappy) { category = category == item ? nil : item }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private func spotCard(_ spot: Spot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(spot.category.title, systemImage: spot.category.icon)
                        .font(.candor(.caption1, .bold))
                        .foregroundStyle(spot.category.color)
                    Text(L(spot.name)).font(.heading(.title3))
                }
                Spacer()
                Text("\(location.distanceKm(to: spot.coordinate).formatted(.number.precision(.fractionLength(1)))) km")
                    .font(.candor(.caption1, .semibold).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.surface, in: .capsule)
                Button {
                    selectedID = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }
            Text(L(spot.blurb)).font(.candor(.subheadline))
            Label(L(spot.tip), systemImage: "lightbulb.fill")
                .font(.candor(.subheadline))
                .foregroundStyle(.secondary)

            Group {
                HStack(spacing: 10) {
                    Button {
                        rideDestination = spot.name
                    } label: {
                        Label(L("Fair fare"), systemImage: "car.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        askCandor.open()
                        let question = "I'm going to %@. What should I know, what should things cost, and how do I avoid getting overcharged?"
                        Task {
                            await agent.send(L(question, L(spot.name)),
                                             canonical: question.replacingOccurrences(of: "%@", with: spot.name))
                        }
                    } label: {
                        Label(L("Ask Candor"), systemImage: "text.bubble").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .font(.candor(.subheadline, .semibold))
            }
        }
        .padding(18)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }
}
