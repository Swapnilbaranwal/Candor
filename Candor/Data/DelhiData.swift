import Foundation
import CoreLocation

/// Curated, source-labelled reference data for the Delhi pilot.
/// Ranges are indicative for the prototype; verify before relying on them.
enum DelhiData {
    static let center = CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090)
    static let connaughtPlace = CLLocationCoordinate2D(latitude: 28.6315, longitude: 77.2167)

    // MARK: Emergency

    static let emergencyNumber = "112"
    static let tourismHelpline = "1800111363"
    static let tourismHelplineDisplay = "1800-11-1363"

    // MARK: Places

    static let spots: [Spot] = [
        Spot(id: "cp", name: "Connaught Place", category: .market, latitude: 28.6315, longitude: 77.2167,
             blurb: "Georgian-style circles of shops, cafés and the Palika Bazaar underground market.",
             tip: "Ignore strangers who offer to take you to a 'tourist office'. CP has none.",
             aliases: ["connaught", "rajiv chowk"]),
        Spot(id: "indiagate", name: "India Gate", category: .sight, latitude: 28.6129, longitude: 77.2295,
             blurb: "War memorial arch on Kartavya Path; lovely at dusk.",
             tip: "Free to visit. Balloons and snacks are sold at fixed, low prices.",
             aliases: ["india gate", "kartavya"]),
        Spot(id: "redfort", name: "Red Fort", category: .sight, latitude: 28.6562, longitude: 77.2410,
             blurb: "17th-century Mughal fort and UNESCO site. Closed on Mondays.",
             tip: "Buy tickets at the official ASI counter or online. Ignore 'closed today' claims.",
             aliases: ["red fort", "lal qila"]),
        Spot(id: "humayun", name: "Humayun's Tomb", category: .sight, latitude: 28.5933, longitude: 77.2507,
             blurb: "Garden tomb that inspired the Taj Mahal. Quiet in the morning.",
             tip: "Official ASI tickets only; card and UPI accepted at the counter.",
             aliases: ["humayun"]),
        Spot(id: "qutub", name: "Qutub Minar", category: .sight, latitude: 28.5245, longitude: 77.1855,
             blurb: "73 m sandstone minaret from 1193 with intricate carvings.",
             tip: "Take the Metro to Qutub Minar station, then a short auto ride.",
             aliases: ["qutub", "qutb"]),
        Spot(id: "lotus", name: "Lotus Temple", category: .sight, latitude: 28.5535, longitude: 77.2588,
             blurb: "Bahá'í house of worship shaped like a lotus. Free entry, closed Mondays.",
             tip: "Entry is free. Anyone charging for entry or 'fast lane' is a tout.",
             aliases: ["lotus"]),
        Spot(id: "akshardham", name: "Akshardham", category: .sight, latitude: 28.6127, longitude: 77.2773,
             blurb: "Huge carved temple complex with an evening water show.",
             tip: "Phones aren't allowed inside; use the free cloakroom.",
             aliases: ["akshardham"]),
        Spot(id: "chandnichowk", name: "Chandni Chowk", category: .market, latitude: 28.6506, longitude: 77.2303,
             blurb: "Old Delhi's spice, textile and street-food lanes.",
             tip: "Agree on cycle-rickshaw prices before you sit down.",
             aliases: ["chandni chowk", "old delhi", "paranthe wali"]),
        Spot(id: "dillihaat", name: "Dilli Haat (INA)", category: .market, latitude: 28.5733, longitude: 77.2079,
             blurb: "Open-air crafts and regional food market run by Delhi Tourism.",
             tip: "Prices are often marked; bargaining is gentle here.",
             aliases: ["dilli haat"]),
        Spot(id: "khan", name: "Khan Market", category: .market, latitude: 28.6003, longitude: 77.2270,
             blurb: "Upmarket bookstores, boutiques and cafés.",
             tip: "Mostly fixed prices and card payments.",
             aliases: ["khan market"]),
        Spot(id: "emporium", name: "Central Cottage Industries Emporium", category: .fixedPrice, latitude: 28.6238, longitude: 77.2190,
             blurb: "Government-run crafts store on Janpath with fixed, marked prices.",
             tip: "Use it as a price benchmark before bargaining elsewhere.",
             aliases: ["cottage", "emporium", "janpath"]),
        Spot(id: "itb", name: "International Tourist Bureau", category: .transport, latitude: 28.6430, longitude: 77.2194,
             blurb: "Official foreign-tourist train booking office, 1st floor of New Delhi Railway Station.",
             tip: "It's inside the station. Offices outside claiming to be it are fake.",
             aliases: ["tourist bureau", "railway station", "new delhi station"]),
        Spot(id: "prepaid", name: "Prepaid Auto Booth · NDLS", category: .transport, latitude: 28.6421, longitude: 77.2215,
             blurb: "Police-run prepaid auto booth at New Delhi Railway Station.",
             tip: "Pay at the booth, hand the slip to the driver at the end of the ride.",
             aliases: ["prepaid"]),
        Spot(id: "airport", name: "IGI Airport T3", category: .transport, latitude: 28.5562, longitude: 77.0870,
             blurb: "Main international terminal. Airport Express Metro runs to New Delhi.",
             tip: "Use the official prepaid taxi counter or app cabs from the marked pickup bays.",
             aliases: ["airport", "igi", "terminal 3", "t3"])
    ]

    static func spot(matching text: String) -> Spot? {
        let q = text.lowercased()
        return spots.first { spot in
            q.contains(spot.name.lowercased()) || spot.aliases.contains { q.contains($0) }
        }
    }

    // MARK: Prices

    static let prices: [ReferencePrice] = [
        ReferencePrice(item: "Packaged drinking water (1 L)", keywords: ["water", "bisleri", "aquafina", "kinley", "bottle"],
                       low: 20, high: 20, unit: "bottle", source: "Printed MRP (legal maximum)",
                       note: "MRP is printed on the bottle and includes tax. Paying more is illegal."),
        ReferencePrice(item: "Packaged drinking water (500 ml)", keywords: ["500 ml", "small water", "half litre"],
                       low: 10, high: 10, unit: "bottle", source: "Printed MRP (legal maximum)",
                       note: "Check the MRP printed on the label."),
        ReferencePrice(item: "Soft drink (750 ml bottle)", keywords: ["coke", "cola", "pepsi", "sprite", "thums up", "soft drink", "soda"],
                       low: 40, high: 50, unit: "bottle", source: "Printed MRP (legal maximum)",
                       note: "Chilled drinks must still be sold at or below MRP."),
        ReferencePrice(item: "Masala chai (street stall)", keywords: ["chai", "tea"],
                       low: 10, high: 25, unit: "cup", source: "Typical Delhi street price (indicative)",
                       note: "Cafés charge ₹80–250."),
        ReferencePrice(item: "Samosa (street)", keywords: ["samosa"],
                       low: 15, high: 30, unit: "piece", source: "Typical Delhi street price (indicative)",
                       note: "Usually sold with chutney at no extra cost."),
        ReferencePrice(item: "Golgappa / pani puri", keywords: ["golgappa", "pani puri", "panipuri", "gol gappa"],
                       low: 30, high: 60, unit: "plate of 6", source: "Typical Delhi street price (indicative)",
                       note: "Fixed per plate at most stalls."),
        ReferencePrice(item: "Lassi", keywords: ["lassi"],
                       low: 40, high: 100, unit: "glass", source: "Typical Delhi street price (indicative)",
                       note: "Kulhad (clay cup) lassi in Old Delhi is at the upper end."),
        ReferencePrice(item: "Chole bhature", keywords: ["chole", "bhature"],
                       low: 80, high: 180, unit: "plate", source: "Typical Delhi eatery price (indicative)",
                       note: "Famous shops in Old Delhi and CP are at the upper end."),
        ReferencePrice(item: "Veg thali (local restaurant)", keywords: ["thali"],
                       low: 150, high: 350, unit: "plate", source: "Typical Delhi restaurant price (indicative)",
                       note: "Hotel restaurants charge more; check the printed menu."),
        ReferencePrice(item: "Butter chicken (mid-range restaurant)", keywords: ["butter chicken", "chicken curry", "tikka"],
                       low: 300, high: 550, unit: "portion", source: "Typical Delhi restaurant price (indicative)",
                       note: "Menus must show prices; GST is added on the bill."),
        ReferencePrice(item: "Fresh lime soda", keywords: ["lime soda", "nimbu", "lemon soda"],
                       low: 40, high: 100, unit: "glass", source: "Typical Delhi price (indicative)",
                       note: "Street carts are at the low end."),
        ReferencePrice(item: "Bananas", keywords: ["banana", "kela"],
                       low: 50, high: 80, unit: "dozen", source: "Typical Delhi market price (indicative)",
                       note: "Fruit is priced per dozen or per kg; ask which."),
        ReferencePrice(item: "Delhi Metro single journey", keywords: ["metro"],
                       low: 11, high: 64, unit: "token", source: "DMRC fare table",
                       note: "Price depends on distance; the token machine shows the fare."),
        ReferencePrice(item: "Cycle rickshaw (1–2 km, Old Delhi)", keywords: ["cycle rickshaw", "e-rickshaw", "erickshaw", "rickshaw"],
                       low: 30, high: 80, unit: "ride", source: "Typical Delhi price (indicative)",
                       note: "No meter. Agree on the price before you sit down."),
        ReferencePrice(item: "Cotton kurta (street market)", keywords: ["kurta", "shirt", "clothes", "janpath", "sarojini"],
                       low: 300, high: 800, unit: "piece", source: "Typical Delhi market price after bargaining (indicative)",
                       note: "Check the Cottage Emporium for a fixed-price benchmark.")
    ]

    static func lookup(_ query: String) -> [ReferencePrice] {
        let q = query.lowercased()
        return prices
            .map { price in (price, price.keywords.filter { q.contains($0) }.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    // MARK: Scams

    static let scams: [Scam] = [
        Scam(id: "hotel", title: "\"Your hotel is closed\"", icon: "bed.double.fill",
             howItWorks: "A driver or stranger says your hotel has burned down, flooded or is overbooked, then takes you to another hotel that pays them a commission.",
             redFlags: ["They won't let you call the hotel", "They already know a 'better' hotel", "Story changes when questioned"],
             whatToDo: "Call the hotel yourself using the number from your booking. Insist on the original address, or take a prepaid or app cab.",
             keywords: ["hotel", "closed", "burned", "fire", "flood", "overbooked", "full"]),
        Scam(id: "office", title: "Fake tourist office", icon: "building.2.fill",
             howItWorks: "Near New Delhi Railway Station, touts say the station or your ticket is 'cancelled' and steer you to a private office posing as the government tourist bureau.",
             redFlags: ["Office is outside the station", "'Your ticket is cancelled'", "Pressure to book a tour package"],
             whatToDo: "The real International Tourist Bureau is inside the station on the 1st floor. Check tickets on IRCTC yourself.",
             keywords: ["tourist office", "office", "ticket", "cancelled", "canceled", "station", "bureau", "travel agent"]),
        Scam(id: "meter", title: "\"Meter is broken\"", icon: "gauge.with.needle",
             howItWorks: "The auto or taxi driver says the meter doesn't work and quotes a fixed price several times the fare.",
             redFlags: ["Refuses the meter", "Quote much higher than Candor's estimate", "Rushes you to decide"],
             whatToDo: "Check the fare in Candor, say \"Meter se chaliye\", or use the prepaid booth or an app cab.",
             keywords: ["meter", "broken", "fixed price", "no meter"]),
        Scam(id: "gems", title: "Gem export deal", icon: "diamond.fill",
             howItWorks: "A friendly stranger offers a profit if you carry gems or jewellery abroad 'to avoid tax'. The stones are near-worthless.",
             redFlags: ["Promise of easy profit", "Needs your credit card as 'guarantee'", "Very friendly very fast"],
             whatToDo: "Never buy goods for resale from strangers. Walk away.",
             keywords: ["gem", "gems", "jewel", "export", "profit", "customs", "carry"]),
        Scam(id: "gift", title: "Free gift, then payment", icon: "gift.fill",
             howItWorks: "Someone ties a bracelet, gives a flower or a tilak blessing, then demands money or a 'donation'.",
             redFlags: ["Item pressed into your hand", "'It's free, it's free'", "Donation book appears"],
             whatToDo: "Politely say \"Nahin, dhanyavaad\" and keep your hands to yourself. Don't accept the item.",
             keywords: ["free", "bracelet", "flower", "tilak", "blessing", "gift", "donation", "thread"]),
        Scam(id: "detour", title: "Commission shopping detour", icon: "bag.fill",
             howItWorks: "A cheap or ₹10 city tour that stops at 'government' shops which pay the driver commission on your purchase.",
             redFlags: ["Tour price far too low", "'Just look, no need to buy'", "Shop claims to be government-run"],
             whatToDo: "Say \"Koi dukaan nahin jaana hai\" (no shops). For a fixed-price benchmark visit the Central Cottage Industries Emporium.",
             keywords: ["shop", "emporium", "friend", "cousin", "detour", "stop", "tour", "commission", "10 rupee"]),
        Scam(id: "shoe", title: "Dirty shoe distraction", icon: "shoeprints.fill",
             howItWorks: "Someone flicks dirt on your shoe, then a nearby 'cleaner' offers to clean it and demands a large fee. Sometimes a pickpocket works alongside.",
             redFlags: ["Sudden dirt on your shoe", "A cleaner appears instantly", "Crowding around you"],
             whatToDo: "Keep walking, hold your bag in front, clean it yourself later.",
             keywords: ["shoe", "dirt", "ear", "cleaning", "spilled", "distraction", "pickpocket"]),
        Scam(id: "monument", title: "Monument 'closed' or fake guide", icon: "building.columns.fill",
             howItWorks: "Touts outside a monument say it's closed or sell unofficial tickets and guided entry.",
             redFlags: ["Tickets sold outside the gate", "'Closed today, come with me'", "Guide without an ASI badge"],
             whatToDo: "Walk to the official ASI ticket counter or buy online. Check opening days in Candor.",
             keywords: ["guide", "monument", "closed today", "fake ticket", "entry", "fast lane"])
    ]

    static func matchScams(_ text: String) -> [Scam] {
        let q = text.lowercased()
        return scams
            .map { scam in (scam, scam.keywords.filter { q.contains($0) }.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    // MARK: Phrases

    static let phrases: [Phrase] = [
        Phrase(english: "How much is this?", hindi: "यह कितने का है?", roman: "Yeh kitne ka hai?", category: "Prices"),
        Phrase(english: "That's too expensive.", hindi: "यह बहुत महँगा है।", roman: "Yeh bahut mehenga hai.", category: "Prices"),
        Phrase(english: "Please give it at MRP.", hindi: "MRP पर दीजिए।", roman: "MRP par dijiye.", category: "Prices"),
        Phrase(english: "Please reduce the price a little.", hindi: "थोड़ा कम कीजिए।", roman: "Thoda kam kijiye.", category: "Prices"),
        Phrase(english: "What is the final price?", hindi: "आख़िरी दाम क्या है?", roman: "Aakhri daam kya hai?", category: "Prices"),
        Phrase(english: "No, thank you.", hindi: "नहीं, धन्यवाद।", roman: "Nahin, dhanyavaad.", category: "Prices"),
        Phrase(english: "Please go by the meter.", hindi: "मीटर से चलिए।", roman: "Meter se chaliye.", category: "Rides"),
        Phrase(english: "Take me to this address.", hindi: "मुझे इस पते पर ले चलिए।", roman: "Mujhe is pate par le chaliye.", category: "Rides"),
        Phrase(english: "Stop here, please.", hindi: "यहाँ रोकिए।", roman: "Yahan rokiye.", category: "Rides"),
        Phrase(english: "No shopping stops, please.", hindi: "कोई दुकान नहीं जाना है।", roman: "Koi dukaan nahin jaana hai.", category: "Rides"),
        Phrase(english: "Not spicy, please.", hindi: "कम तीखा, प्लीज़।", roman: "Kam teekha, please.", category: "Food"),
        Phrase(english: "Vegetarian, please.", hindi: "शाकाहारी, प्लीज़।", roman: "Shakahari, please.", category: "Food"),
        Phrase(english: "The bill, please.", hindi: "बिल दीजिए।", roman: "Bill dijiye.", category: "Food"),
        Phrase(english: "Where is the toilet?", hindi: "शौचालय कहाँ है?", roman: "Shauchalay kahan hai?", category: "Help"),
        Phrase(english: "I need a doctor.", hindi: "मुझे डॉक्टर चाहिए।", roman: "Mujhe doctor chahiye.", category: "Help"),
        Phrase(english: "Please call the police.", hindi: "पुलिस को बुलाइए।", roman: "Police ko bulaiye.", category: "Help"),
        Phrase(english: "Help!", hindi: "बचाओ!", roman: "Bachao!", category: "Help")
    ]

    static let phraseCategories = ["Prices", "Rides", "Food", "Help"]

    static func phrase(_ english: String) -> Phrase? {
        phrases.first { $0.english == english }
    }

    static var meterPhrase: Phrase? { phrase("Please go by the meter.") }
    static var mrpPhrase: Phrase? { phrase("Please give it at MRP.") }
    static var reducePhrase: Phrase? { phrase("Please reduce the price a little.") }

    // MARK: Login

    static let countryCodes: [CountryCode] = [
        CountryCode(region: "US", flag: "🇺🇸", dial: "+1"),
        CountryCode(region: "GB", flag: "🇬🇧", dial: "+44"),
        CountryCode(region: "DE", flag: "🇩🇪", dial: "+49"),
        CountryCode(region: "FR", flag: "🇫🇷", dial: "+33"),
        CountryCode(region: "ES", flag: "🇪🇸", dial: "+34"),
        CountryCode(region: "IT", flag: "🇮🇹", dial: "+39"),
        CountryCode(region: "JP", flag: "🇯🇵", dial: "+81"),
        CountryCode(region: "KR", flag: "🇰🇷", dial: "+82"),
        CountryCode(region: "CN", flag: "🇨🇳", dial: "+86"),
        CountryCode(region: "RU", flag: "🇷🇺", dial: "+7"),
        CountryCode(region: "BR", flag: "🇧🇷", dial: "+55"),
        CountryCode(region: "AU", flag: "🇦🇺", dial: "+61"),
        CountryCode(region: "AE", flag: "🇦🇪", dial: "+971"),
        CountryCode(region: "IN", flag: "🇮🇳", dial: "+91")
    ]

    static var defaultCountry: CountryCode {
        let region = Locale.current.region?.identifier ?? "US"
        return countryCodes.first { $0.region == region } ?? countryCodes[0]
    }

    // MARK: Onboarding

    static let interests = ["Heritage", "Street food", "Markets", "Spiritual", "Art & crafts", "Nightlife", "Nature", "Photography"]

    static let languages = ["en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh", "ar", "he", "nl", "tr", "th", "vi", "id", "pl"]
}

extension CurrencyOption {
    /// Fallback INR-per-unit rates, used until live rates load. Indicative only.
    static let all: [CurrencyOption] = [
        CurrencyOption(code: "USD", name: "US Dollar", flag: "🇺🇸", fallbackINR: 88.5),
        CurrencyOption(code: "EUR", name: "Euro", flag: "🇪🇺", fallbackINR: 103),
        CurrencyOption(code: "GBP", name: "British Pound", flag: "🇬🇧", fallbackINR: 118),
        CurrencyOption(code: "JPY", name: "Japanese Yen", flag: "🇯🇵", fallbackINR: 0.59),
        CurrencyOption(code: "AUD", name: "Australian Dollar", flag: "🇦🇺", fallbackINR: 58),
        CurrencyOption(code: "CAD", name: "Canadian Dollar", flag: "🇨🇦", fallbackINR: 63),
        CurrencyOption(code: "CHF", name: "Swiss Franc", flag: "🇨🇭", fallbackINR: 110),
        CurrencyOption(code: "CNY", name: "Chinese Yuan", flag: "🇨🇳", fallbackINR: 12.4),
        CurrencyOption(code: "KRW", name: "Korean Won", flag: "🇰🇷", fallbackINR: 0.063),
        CurrencyOption(code: "SGD", name: "Singapore Dollar", flag: "🇸🇬", fallbackINR: 68),
        CurrencyOption(code: "AED", name: "UAE Dirham", flag: "🇦🇪", fallbackINR: 24.1),
        CurrencyOption(code: "RUB", name: "Russian Ruble", flag: "🇷🇺", fallbackINR: 1.08),
        CurrencyOption(code: "BRL", name: "Brazilian Real", flag: "🇧🇷", fallbackINR: 16.3),
        CurrencyOption(code: "MXN", name: "Mexican Peso", flag: "🇲🇽", fallbackINR: 4.8),
        CurrencyOption(code: "SEK", name: "Swedish Krona", flag: "🇸🇪", fallbackINR: 9.4),
        CurrencyOption(code: "THB", name: "Thai Baht", flag: "🇹🇭", fallbackINR: 2.7),
        CurrencyOption(code: "ZAR", name: "South African Rand", flag: "🇿🇦", fallbackINR: 5.0),
        CurrencyOption(code: "NZD", name: "New Zealand Dollar", flag: "🇳🇿", fallbackINR: 51)
    ]

    static func option(_ code: String) -> CurrencyOption? {
        all.first { $0.code == code }
    }
}
