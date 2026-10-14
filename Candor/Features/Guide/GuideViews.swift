import SwiftUI

// MARK: - Pieces

/// A guide's initials on their colour, with the verified tick.
struct GuideAvatar: View {
    let guide: Guide
    var size: CGFloat = 52

    var body: some View {
        Text(guide.initials)
            .font(.display(size: size * 0.38, .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(guide.color, in: .circle)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size * 0.3))
                    .foregroundStyle(.white, Theme.mint)
                    .offset(x: 3, y: 3)
            }
            .accessibilityHidden(true)
    }
}

/// The guide illustration: a guide with a flag leading two travellers, on a soft gradient.
struct GuideArt: View {
    var size: CGFloat = 96

    var body: some View {
        let unit = size / 60
        ZStack(alignment: .bottom) {
            Circle().fill(Theme.violet.opacity(0.12))
            HStack(alignment: .bottom, spacing: -4 * unit) {
                ZStack(alignment: .topLeading) {
                    PersonFigure(shirt: Theme.coral, skin: Color(hex: 0xC68642), hair: Color(hex: 0x2B1D14), unit: unit * 1.05)
                    // The guide's little flag.
                    Rectangle().fill(.white).frame(width: 1.5 * unit, height: 22 * unit).offset(x: -4 * unit, y: -14 * unit)
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9 * unit))
                        .foregroundStyle(Theme.saffron)
                        .offset(x: -4 * unit, y: -16 * unit)
                }
                PersonFigure(shirt: Theme.sky, skin: Color(hex: 0xF1C27D), hair: Color(hex: 0x6B3E26), unit: unit * 0.85)
                PersonFigure(shirt: Theme.mint, skin: Color(hex: 0xE0AC69), hair: Color(hex: 0x3B2A20), unit: unit * 0.85, longHair: true)
            }
            .offset(y: size * 0.08)
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

// MARK: - Travel with the app, or with a guide

/// The choice on the Trip tab and Home: explore on your own with Candor, or with a verified guide.
struct TravelCompanionPicker: View {
    @Environment(AppState.self) private var app
    @State private var showBooking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let booking = app.guideBooking, booking.status() != .done {
                GuideStatusCard(booking: booking)
            } else {
                guideInvite
            }
        }
        .sheet(isPresented: $showBooking) { GuideBookingView() }
    }

    /// You're already travelling with the app; this offers a local by your side: a guide
    /// standing with a flag, a line about it, and one button.
    private var guideInvite: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Want a local by your side?"))
                    .font(.heading(.title3))
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Verified guides who know every lane, by the hour or for the day. %@.", GuidePlan.hourly.priceLine))
                    .font(.candor(.subheadline))
                    .foregroundStyle(Velvet.emerald.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showBooking = true } label: {
                    Label(L("Travel with a guide"), systemImage: "figure.wave")
                }
                .buttonStyle(PillButtonStyle(kind: .cream, height: 46))
                .accessibilityIdentifier("travelWithGuide")
            }
            GuideStandingArt()
                .frame(width: 96, height: 150)
        }
        .velvetCard(.emerald, padding: 18)
    }

    private func choice(title: String, detail: String, icon: String, colors: [Color], selected: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                SoftIcon(symbol: icon, tint: colors[0], size: 40, rounded: false)
                Spacer(minLength: 0)
                Text(title).font(.heading(.headline)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Text(detail).font(.candor(.caption1, .medium)).foregroundStyle(colors[0])
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
            .glossCard(colors[0], padding: 14)
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "arrow.up.right.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(colors[0])
                    .padding(12)
            }
        }
        .buttonStyle(.pressable)
    }
}

/// A booked tour: matching (with the countdown to the guide being locked in), then the guide.
struct GuideStatusCard: View {
    let booking: GuideBooking
    @Environment(AppState.self) private var app
    @State private var confirmCancel = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let status = booking.status(at: now)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.wave.2.fill")
                    Text(statusTitle(status)).font(.candor(.caption1, .bold)).textCase(.uppercase)
                    Spacer()
                    Text(booking.start.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Localizer.shared.locale)))
                        .font(.candor(.caption1, .semibold))
                }
                .foregroundStyle(Theme.violet)

                if let guide = booking.guide(at: now) {
                    HStack(spacing: 12) {
                        GuideAvatar(guide: guide, size: 54)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(guide.name).font(.heading(.title3)).foregroundStyle(.primary)
                            Text(GuideViewText.summary(guide, languages: true))
                                .font(.candor(.caption1))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text(L("Meets you at %@", booking.meetingPoint))
                        .font(.candor(.subheadline, .medium))
                        .foregroundStyle(.primary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Your guide is locked in at %@", timeText(booking.assignAt)))
                            .font(.heading(.title3))
                            .foregroundStyle(.primary)
                        Text(L("%1$@ verified guides shortlisted · %2$@ to go", booking.shortlist.count,
                               durationText(max(Int(booking.assignAt.timeIntervalSince(now) / 60), 1))))
                            .font(.candor(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: -10) {
                        ForEach(booking.shortlist) { guide in
                            GuideAvatar(guide: guide, size: 38)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }

                HStack {
                    Text("\(booking.plan.title) · \(L("%@ h", booking.hours)) · \(inr(booking.price))")
                        .font(.candor(.caption1, .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if status == .matching || status == .assigned {
                        Button(L("Cancel")) { confirmCancel = true }
                            .font(.candor(.caption1, .bold))
                            .foregroundStyle(Theme.coral)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.coral.opacity(0.12), in: .capsule)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .trailing) {
                GuideArt(size: 110).opacity(0.5).offset(x: 20)
            }
            .velvetCard(.pearl, padding: 18)
            .clipShape(.rect(cornerRadius: Theme.Radius.large, style: .continuous))
        }
        .confirmationDialog(L("Cancel this tour?"), isPresented: $confirmCancel, titleVisibility: .visible) {
            Button(L("Cancel tour"), role: .destructive) { withAnimation(.smooth) { app.guideBooking = nil } }
        } message: {
            Text(L("Free until your guide is locked in, an hour before the start."))
        }
    }

    private func statusTitle(_ status: GuideBooking.Status) -> String {
        switch status {
        case .matching: L("Finding your guide")
        case .assigned: L("Guide assigned")
        case .live: L("Tour in progress")
        case .done: L("Tour done")
        }
    }
}

// MARK: - Booking

/// Book a verified guide: pick a plan, a time at least an hour away, how long, the language.
/// Candor shortlists guides now and locks in the best one an hour before the start.
/// Prototype: no payment is taken and no guide is contacted.
struct GuideBookingView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var plan: GuidePlan = .hourly
    @State private var start = GuideDesk.earliestStart
    @State private var hours = 3
    @State private var language = Persona.defaultLanguage
    @State private var interests: [String] = []
    @State private var shortlist: [Guide] = []
    @State private var searching = false
    @State private var didLoad = false

    private var city: String {
        L(app.trip?.cityStay(on: start)?.city.name ?? City.delhi.name)
    }

    private var meetingPoint: String {
        let index = app.trip.map { trip in
            max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: trip.startDate),
                                                   to: Calendar.current.startOfDay(for: start)).day ?? 0)
        } ?? 0
        return location.dayStart(trip: app.trip, day: index).name
    }

    private var effectiveHours: Int { plan == .dayPass ? 8 : hours }

    private var price: Double {
        plan.price(hours: effectiveHours, rate: shortlist.first?.hourlyINR ?? GuideDesk.lowestRate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero.reveal(0)
                    howItWorks.reveal(1)
                    planSection.reveal(2)
                    whenSection.reveal(3)
                    preferences.reveal(4)
                    if !shortlist.isEmpty {
                        shortlistSection
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
            .background(AppBackground())
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(L("Travel with a guide"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
            .onAppear(perform: load)
            .onChange(of: plan) { _, _ in shortlist = [] }
            .onChange(of: language) { _, _ in shortlist = [] }
            .onChange(of: interests) { _, _ in shortlist = [] }
            .animation(.snappy, value: shortlist)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        language = DelhiData.languages.contains(app.persona.languageCode) ? app.persona.languageCode : "en"
        interests = Array(app.persona.interests.prefix(3))
        if let trip = app.trip, let first = trip.cities.first, first.arrival > start {
            start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: first.arrival) ?? start
        }
    }

    private var hero: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("A local who knows %@", city))
                    .font(.heading(.title2))
                    .foregroundStyle(.primary)
                Text(L("Verified guides, by the hour or for the day. Fair prices, safe rides and the stories behind every place."))
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            GuideArt(size: 92)
        }
        .velvetCard(.pearl, padding: 18)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("How it works")).font(.heading(.title3))
            step(1, icon: "calendar.badge.clock", title: L("Pick a time at least an hour away"),
                 detail: L("Choose the plan, the hours and the language you'd like."))
            step(2, icon: "person.3.sequence.fill", title: L("Candor shortlists verified guides now"),
                 detail: L("Ranked by language, your interests and ratings."))
            step(3, icon: "lock.fill", title: L("The best guide is locked in an hour before"),
                 detail: L("Unlike a cab app, there's no last-minute search: your guide is set and on the way."))
        }
        .card(padding: 16)
    }

    private func step(_ number: Int, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SoftIcon(symbol: icon, tint: Theme.ink, size: 34, rounded: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.candor(.subheadline, .semibold))
                Text(detail).font(.candor(.caption1)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Choose a plan")).font(.heading(.title3))
            ForEach(GuidePlan.allCases) { option in
                let selected = plan == option
                Button { plan = option } label: {
                    HStack(spacing: 14) {
                        SoftIcon(symbol: option.icon, tint: option.colors[0], size: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(option.title).font(.candor(.headline, .semibold)).foregroundStyle(.primary)
                                Spacer()
                                Text(option.priceLine).font(.candor(.subheadline, .bold)).foregroundStyle(option.colors[0])
                            }
                            Text(option.subtitle)
                                .font(.candor(.caption1))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.medium + 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.medium + 4, style: .continuous)
                            .strokeBorder(selected ? Theme.ink : .clear, lineWidth: 2)
                    }
                    .shadow(color: Theme.shadow, radius: 10, y: 5)
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("When")).font(.heading(.title3))
            VStack(spacing: 12) {
                DatePicker(L("Start"), selection: $start, in: GuideDesk.earliestStart..., displayedComponents: [.date, .hourAndMinute])
                    .font(.candor(.subheadline, .semibold))
                    .tint(Theme.ink)
                Divider()
                if plan == .dayPass {
                    LabeledContent(L("Hours"), value: L("Up to %@ hours", 8))
                        .font(.candor(.subheadline, .semibold))
                } else {
                    Stepper(value: $hours, in: 2...10) {
                        Text(L("%@ hours", hours)).font(.candor(.subheadline, .semibold))
                    }
                }
                Divider()
                Label(L("Guide locked in at %1$@ · meets you at %2$@", timeText(start.addingTimeInterval(-3600)), meetingPoint),
                      systemImage: "lock.fill")
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .card(padding: 16)
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Your guide speaks")).font(.heading(.title3))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DelhiData.languages, id: \.self) { code in
                        Chip(title: Persona.nativeName(of: code), isSelected: language == code, tint: Theme.ink) {
                            language = code
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            Text(L("Show me")).font(.heading(.title3)).padding(.top, 4)
            FlowLayout(spacing: 8) {
                ForEach(DelhiData.interests, id: \.self) { interest in
                    Chip(title: L(interest), icon: InterestArt.icon(interest), isSelected: interests.contains(interest),
                         tint: InterestArt.tint(interest)) {
                        if let index = interests.firstIndex(of: interest) {
                            interests.remove(at: index)
                        } else {
                            interests.append(interest)
                        }
                    }
                }
            }
        }
    }

    private var shortlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Your shortlist")).font(.heading(.title3))
            Text(L("The best of these is locked in an hour before you start, so you're never left waiting."))
                .font(.candor(.subheadline))
                .foregroundStyle(.secondary)
            ForEach(Array(shortlist.enumerated()), id: \.element.id) { index, guide in
                guideCard(guide, best: index == 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Guide.checks, id: \.self) { check in
                    Label(L(check), systemImage: "checkmark.shield.fill")
                        .font(.candor(.caption1))
                        .foregroundStyle(Theme.mint)
                }
            }
            .padding(.top, 4)
        }
    }

    private func guideCard(_ guide: Guide, best: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                GuideAvatar(guide: guide)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(guide.name).font(.candor(.headline, .semibold))
                        if best {
                            Text(L("Best match"))
                                .font(.candor(.caption2, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.brandFill, in: .capsule)
                        }
                    }
                    Text(GuideViewText.summary(guide, languages: false))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(L("%@/h", inr(guide.hourlyINR)))
                    .font(.candor(.subheadline, .bold).monospacedDigit())
            }
            Text(L(guide.bio)).font(.candor(.subheadline)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(guide.languages, id: \.self) { code in
                    Text(Persona.nativeName(of: code))
                        .font(.candor(.caption2, .semibold))
                        .foregroundStyle(code == language ? .white : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(code == language ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.canvas), in: .capsule)
                }
            }
        }
        .card(padding: 14)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if shortlist.isEmpty {
                Button {
                    searching = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(900))
                        shortlist = GuideDesk.shortlist(language: language, interests: interests, plan: plan)
                        searching = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if searching { ProgressView().tint(.white) }
                        Text(searching ? L("Finding verified guides…") : L("Find my guide"))
                    }
                }
                .buttonStyle(.pill)
                .disabled(searching)
            } else {
                Button {
                    // The earliest start keeps moving while the sheet is open: never book inside the hour.
                    start = max(start, GuideDesk.earliestStart)
                    app.guideBooking = GuideBooking(city: city, start: start, hours: effectiveHours, plan: plan,
                                                    languageCode: language, interests: interests,
                                                    meetingPoint: meetingPoint, shortlist: shortlist)
                    dismiss()
                } label: {
                    Text(L("Book · %@", inr(price)))
                }
                .buttonStyle(.pill)
                .accessibilityIdentifier("bookGuide")
            }
            Text(L("Prototype: no payment is taken and no guide is contacted."))
                .font(.candor(.caption2))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }
}

/// "★ 4.9 · 412 tours · English, हिन्दी, Français"
enum GuideViewText {
    static func summary(_ guide: Guide, languages: Bool) -> String {
        let rating = "★ " + guide.rating.formatted(.number.precision(.fractionLength(1)))
        let tours = L("%@ tours", guide.tours)
        let tail: String
        if languages {
            tail = guide.languages.prefix(3).map { Persona.nativeName(of: $0) }.joined(separator: ", ")
        } else {
            tail = L("%@ years", guide.years)
        }
        return [rating, tours, tail].joined(separator: " · ")
    }
}

/// A friendly guide standing tall with a little flag, waving the traveller over. Drawn in code.
struct GuideStandingArt: View {
    @State private var wave = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .bottom) {
                // Ground shadow.
                Ellipse().fill(Color.black.opacity(0.08)).frame(width: w * 0.7, height: h * 0.05)
                VStack(spacing: h * 0.01) {
                    // Head with hair and a cap.
                    ZStack(alignment: .top) {
                        Circle().fill(Color(hex: 0xC68642)).frame(width: w * 0.28, height: w * 0.28)
                        Capsule().fill(Theme.ink).frame(width: w * 0.34, height: w * 0.1).offset(y: -w * 0.02)
                    }
                    // Body: shirt, satchel strap, trousers.
                    ZStack {
                        UnevenRoundedRectangle(topLeadingRadius: w * 0.16, bottomLeadingRadius: w * 0.04,
                                               bottomTrailingRadius: w * 0.04, topTrailingRadius: w * 0.16)
                            .fill(Theme.saffron)
                            .frame(width: w * 0.5, height: h * 0.32)
                        Rectangle().fill(Color(hex: 0x8D5A3B)).frame(width: w * 0.06, height: h * 0.36).rotationEffect(.degrees(28))
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: w * 0.11))
                            .foregroundStyle(.white, Theme.mint)
                            .offset(x: -w * 0.1, y: -h * 0.05)
                    }
                    HStack(spacing: w * 0.05) {
                        Capsule().fill(Color(hex: 0x3B4A6B)).frame(width: w * 0.13, height: h * 0.24)
                        Capsule().fill(Color(hex: 0x3B4A6B)).frame(width: w * 0.13, height: h * 0.24)
                    }
                }
                .padding(.bottom, h * 0.02)
                // The raised arm with the flag.
                ZStack(alignment: .bottomLeading) {
                    Capsule().fill(Theme.saffron).frame(width: w * 0.1, height: h * 0.2)
                    Rectangle().fill(Color.primary.opacity(0.6)).frame(width: 2, height: h * 0.3).offset(x: w * 0.04, y: -h * 0.17)
                    Image(systemName: "flag.fill")
                        .font(.system(size: w * 0.16))
                        .foregroundStyle(Theme.coral)
                        .offset(x: w * 0.05, y: -h * 0.4)
                }
                .rotationEffect(.degrees(wave ? -18 : -6), anchor: .bottom)
                .offset(x: w * 0.3, y: -h * 0.42)
            }
            .frame(width: w, height: h)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            // One friendly wave when it appears, then still: an endless loop cost frames while scrolling.
            withAnimation(.easeInOut(duration: 0.45).repeatCount(3, autoreverses: true)) { wave = true }
        }
    }
}
