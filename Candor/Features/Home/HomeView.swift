import SwiftUI

struct HomeView: View {
    @Binding var tab: AppTab
    @Binding var checkPath: [CheckRoute]
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(CandorAgent.self) private var agent

    /// Opens the demo: one tap from Home to the agent's trail and a verdict card.
    private let demoPrompt = "Auto to India Gate, driver wants ₹300"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    tripCard
                    checkCard
                    scamOfTheDay
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Opens a tool on the Check tab.
    private func openCheck(_ route: CheckRoute) {
        checkPath = [route]
        tab = .check
    }

    /// Sends a ready-made prompt to the agent. The bubble shows it in the traveller's language;
    /// the offline agent, which matches English keywords, gets the English original.
    private func ask(_ prompt: String) {
        tab = .agent
        Task { await agent.send(L(prompt), canonical: prompt) }
    }

    // MARK: Sections

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return L("Good morning")
        case 12..<17: return L("Good afternoon")
        default: return L("Good evening")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Namaste, %@", app.persona.firstName))
                    .font(.heading(.largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").foregroundStyle(Theme.saffron)
                    Text(location.placeLabel)
                    Text("·")
                    Text(greeting)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button { tab = .profile } label: {
                Text(app.persona.initials)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Theme.accent, in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    /// Candor's one job, first on the screen: judge the price you're being quoted right now.
    private var checkCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L("Fair-price check"), systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                // Shown only when it changes what the traveller gets: offline answers are more limited.
                if !app.hasGemini {
                    Text(L("Offline mode"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.saffron.opacity(0.14), in: .capsule)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("What are you being asked to pay?"))
                    .font(.heading(.title2))
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Candor tells you the fair price, how far over the ask is, and what to say."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                HStack(spacing: 10) {
                    Button { openCheck(.scan) } label: {
                        Label(L("Scan a price"), systemImage: "camera.viewfinder")
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.saffron)

                    Button { openCheck(.ride) } label: {
                        Label(L("Check a ride"), systemImage: "car.fill")
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.subheadline.weight(.semibold))
            }

            // The quickest way to see what Candor does. A plain tinted row, not glass:
            // glass on a glass card has nothing to refract and disappears.
            Button { ask(demoPrompt) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(Theme.saffron)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Try an example"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(L(demoPrompt))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Theme.saffron.opacity(0.12), in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeExample")
        }
        .padding(20)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }

    /// One line a day about a trick worth knowing. Opens Scam radar on the Check tab.
    private var scamOfTheDay: some View {
        let scams = DelhiData.scams
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        let scam = scams[day % scams.count]
        return Button { openCheck(.scams) } label: {
            HStack(spacing: 12) {
                Image(systemName: scam.icon)
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.rose, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("SCAM OF THE DAY")).font(.caption2.weight(.bold)).foregroundStyle(Theme.rose)
                    Text(L(scam.title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card(cornerRadius: 16, padding: 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: Trip

    /// Today's plan at a glance, or an invitation to plan the trip.
    @ViewBuilder
    private var tripCard: some View {
        if let trip = app.trip, !trip.days.isEmpty {
            let index = trip.todayIndex
            let day = trip.days[index]
            let start = location.dayStart(trip: trip, day: index)
            let plan = TripPlanner.dayPlan(day, date: trip.date(ofDay: index), origin: start.coordinate,
                                           originName: start.name, style: app.persona.travelStyle,
                                           city: trip.cityStay(ofDay: index)?.city,
                                           likesWalking: app.persona.hasTaste("Happy to walk"))
            Button { tab = .trip } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(tripCityLine(trip, index: index), systemImage: "map.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(trip.date(ofDay: index).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Localizer.shared.locale)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(day.displayTitle)
                        .font(.heading(.title3))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if plan.entries.isEmpty {
                        Text(L("Nothing planned yet. Add places in Trip."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(plan.entries.prefix(3).enumerated()), id: \.element.id) { number, entry in
                                tripRow(number: number + 1, entry: entry)
                            }
                        }
                        if plan.entries.count > 3 {
                            Text(L("+ %@ more", plan.entries.count - 3))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .card(padding: 20)
            }
            .buttonStyle(.plain)
        } else {
            Button { tab = .trip } label: {
                HStack(spacing: 14) {
                    Image(systemName: "map.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Theme.accent, in: .rect(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Plan your days in %@", L((app.trip?.cities.first?.city ?? .delhi).name))).font(.headline).foregroundStyle(.primary)
                        Text(L("Places, travel times and fair fares between them."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homePlanTrip")
        }
    }

    /// "Delhi · Day 2 of 3"
    private func tripCityLine(_ trip: Trip, index: Int) -> String {
        let day = L("Day %1$@ of %2$@", index + 1, trip.days.count)
        guard let city = trip.cityStay(ofDay: index)?.city else { return day }
        return L(city.name) + " · " + day
    }

    private func tripRow(number: Int, entry: DayPlan.Entry) -> some View {
        let option = entry.leg.bestOption
        return HStack(spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.accent, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(entry.stop.name))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: option.mode.icon).foregroundStyle(option.mode.color)
                    Text("\(option.mode.title) · \(durationText(option.minutes)) · \(option.fareText)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(timeText(entry.arrival))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct RecordRow: View {
    @Environment(AppState.self) private var app
    let record: PriceCheckRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind.icon)
                .foregroundStyle(record.verdict.color)
                .frame(width: 40, height: 40)
                .background(record.verdict.color.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(record.title)).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(record.date.formatted(.relative(presentation: .named).locale(Localizer.shared.locale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.askedINR.map(inr) ?? inr(record.fairHighINR))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text(record.verdict.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.verdict.color)
            }
        }
        .card(cornerRadius: 16, padding: 12)
    }
}
