import Foundation

// `Grouping`, `MediaSection` and `SortOrder` live in `MediaTypes.swift`, so the
// grid, the sort menu and the analyzer can share them without this file having
// to be the home of three unrelated enums.

/// Pure functions over a `[MediaItem]` snapshot.
///
/// Everything here is `nonisolated` and allocation-light: it runs on whatever
/// actor the caller is on, and the caller decides when to run it (never inside
/// a view body — see `LibraryScreen`, which derives sections in a `.task`).
enum MediaAnalyzer {

    // MARK: Grouping

    static func sections(
        _ items: [MediaItem],
        by grouping: Grouping,
        sort: SortOrder,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [MediaSection] {
        switch grouping {
        case .month: monthSections(items, sort: sort, calendar: calendar, locale: locale)
        case .year: yearSections(items, sort: sort, calendar: calendar, locale: locale)
        case .size: sizeSections(items, sort: sort)
        case .type: typeSections(items, sort: sort)
        }
    }

    private static func monthSections(
        _ items: [MediaItem],
        sort: SortOrder,
        calendar: Calendar,
        locale: Locale
    ) -> [MediaSection] {
        let grouped = Dictionary(grouping: items) { item in
            let parts = calendar.dateComponents([.year, .month], from: item.creationDate)
            return YearMonth(year: parts.year ?? 0, month: parts.month ?? 0)
        }

        return grouped
            .keys
            .sorted { sort == .oldest ? $0 < $1 : $0 > $1 }
            .map { key in
                let bucket = sorted(grouped[key] ?? [], by: sort)
                return MediaSection(
                    id: "m-\(key.year)-\(key.month)",
                    title: key.title(locale: locale),
                    caption: caption(for: bucket),
                    items: bucket
                )
            }
    }

    private static func yearSections(
        _ items: [MediaItem],
        sort: SortOrder,
        calendar: Calendar,
        locale: Locale
    ) -> [MediaSection] {
        let grouped = Dictionary(grouping: items) { item in
            calendar.component(.year, from: item.creationDate)
        }

        return grouped
            .keys
            .sorted { sort == .oldest ? $0 < $1 : $0 > $1 }
            .map { year in
                let bucket = sorted(grouped[year] ?? [], by: sort)
                return MediaSection(
                    id: "y-\(year)",
                    title: String(year),
                    caption: caption(for: bucket),
                    items: bucket
                )
            }
    }

    /// Size buckets, because a literal sort by bytes produces a meaningless
    /// one-item-per-section list. Ranges are what a person can act on.
    ///
    /// The user's sort applies *inside* each bucket, like every other grouping.
    /// It used to be hardcoded to largest-first, so picking "Plus anciennes"
    /// silently did nothing as soon as you grouped by size.
    private static func sizeSections(_ items: [MediaItem], sort: SortOrder) -> [MediaSection] {
        // Half-open ranges. The previous version used closed ranges on both
        // sides, so an asset of exactly 24 or 40 Mpx matched two buckets and
        // appeared in two sections — which put the same `MediaItem.ID` in the
        // grid twice and made `LazyVGrid` lay out duplicate rows.
        let buckets: [(id: String, title: String, range: Range<Double>)] = [
            ("xxl", "Plus de 40 Mpx", 40..<(.infinity)),
            ("xl", "24 à 40 Mpx", 24..<40),
            ("l", "12 à 24 Mpx", 12..<24),
            ("m", "4 à 12 Mpx", 4..<12),
            ("s", "Moins de 4 Mpx", 0..<4)
        ]

        return buckets.compactMap { bucket in
            let matching = sorted(items.filter { bucket.range.contains($0.megapixels) }, by: sort)
            guard !matching.isEmpty else { return nil }
            return MediaSection(
                id: "s-\(bucket.id)",
                title: bucket.title,
                caption: caption(for: matching),
                items: matching
            )
        }
    }

    private static func typeSections(_ items: [MediaItem], sort: SortOrder) -> [MediaSection] {
        MediaKind.allCases.compactMap { kind in
            let bucket = sorted(items.filter { $0.mediaType == kind }, by: sort)
            guard !bucket.isEmpty else { return nil }
            return MediaSection(
                id: "t-\(kind.rawValue)",
                title: kind.label,
                caption: caption(for: bucket),
                items: bucket
            )
        }
    }

    // MARK: Sorting

    private static func sorted(_ items: [MediaItem], by sort: SortOrder) -> [MediaItem] {
        switch sort {
        case .newest: items.sorted { $0.creationDate > $1.creationDate }
        case .oldest: items.sorted { $0.creationDate < $1.creationDate }
        case .largest: items.sorted { $0.megapixels > $1.megapixels }
        case .smallest: items.sorted { $0.megapixels < $1.megapixels }
        }
    }

    private static func caption(for items: [MediaItem]) -> String {
        let videos = items.count(where: { $0.isVideo })
        let photos = items.count - videos
        var parts: [String] = []
        if photos > 0 { parts.append("\(photos) photo\(photos > 1 ? "s" : "")") }
        if videos > 0 { parts.append("\(videos) vidéo\(videos > 1 ? "s" : "")") }
        return parts.joined(separator: " · ")
    }

    // MARK: Search

    /// Matches the query against the facts a person can actually recall about a
    /// photo: when it was taken, whether it was a video, and how big it is.
    ///
    /// PhotoKit exposes no content or location text for privacy reasons, so the
    /// app is explicit about what it searches rather than pretending otherwise.
    static func search(
        _ items: [MediaItem],
        query: String,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [MediaItem] {
        let tokens = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !tokens.isEmpty else { return [] }

        return items.filter { item in
            let haystack = searchableText(for: item, calendar: calendar, locale: locale)
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    /// One folded string per asset, built from month names, year, kind and size
    /// bucket. Building it per query keeps the snapshot tiny; it is only done
    /// for the items that survive the fetch, and the string is short.
    private static func searchableText(
        for item: MediaItem,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: item.creationDate)
        var words: [String] = []

        if let year = parts.year { words.append(String(year)) }
        if let month = parts.month {
            words.append(monthName(month, locale: locale))
            words.append(String(format: "%02d", month))
        }
        if let day = parts.day { words.append(String(format: "%02d", day)) }

        words.append(item.isVideo ? "video" : "photo")
        if item.isScreenCapture { words.append("capture ecran screenshot") }
        if item.isFavorite { words.append("favori") }

        switch item.megapixels {
        case 40...: words.append("xxl enorme lourd")
        case 24..<40: words.append("xl grand")
        case 12..<24: words.append("l moyen")
        case 4..<12: words.append("m")
        default: words.append("s petit leger")
        }

        let raw = words.joined(separator: " ")
        return raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
    }

    private static func monthName(_ month: Int, locale: Locale) -> String {
        // The calendar's own month symbols avoid constructing a date just to
        // read its name, and they are already localised.
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let names = calendar.monthSymbols
        guard month >= 1, month <= names.count else { return "" }
        return names[month - 1]
    }

    // MARK: Cleanup

    /// Heuristics that surface the photos people actually regret keeping.
    ///
    /// Every suggestion is a *proposal*, never an action: the caller stages
    /// them into the bin where they still need a hold and a biometric check.
    static func cleanupSuggestions(
        _ items: [MediaItem],
        calendar: Calendar = .current
    ) -> [CleanupGroup] {
        var groups: [CleanupGroup] = []

        // 1. Screenshots — the highest-volume, lowest-value category on most
        //    phones, and unambiguous to detect.
        let screenshots = items.filter(\.isScreenCapture)
        if !screenshots.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "screenshots",
                    title: "Captures d'écran",
                    reason: "Des copies d'écran conservées depuis plus de 30 jours.",
                    symbol: "camera.viewfinder",
                    items: screenshots.filter {
                        $0.creationDate < calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
                    }
                )
            )
        }

        // 2. Big videos — the ones that actually fill the phone.
        let bigVideos = items
            .filter { $0.isVideo && $0.megapixels >= 8 }
            .sorted { $0.duration > $1.duration }
        if !bigVideos.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "bigVideos",
                    title: "Vidéos lourdes",
                    reason: "Plus de 8 Mpx par image et les plus longues en premier.",
                    symbol: "video.fill",
                    items: bigVideos
                )
            )
        }

        // 3. Bursts of near-identical shots: same minute, many frames. Keep the
        //    largest and propose the rest.
        let bursts = burstCandidates(items, calendar: calendar)
        if !bursts.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "bursts",
                    title: "Rafales",
                    reason: "Plusieurs photos prises dans la même minute. La plus nette est conservée.",
                    symbol: "square.stack.3d.down.right.fill",
                    items: bursts
                )
            )
        }

        // 4. Low-resolution leftovers — thumbnails, old messages, re-saves.
        let tiny = items
            .filter { !$0.isVideo && $0.megapixels < 1.2 }
            .sorted { $0.megapixels < $1.megapixels }
        if !tiny.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "tiny",
                    title: "Images minuscules",
                    reason: "Moins de 1,2 Mpx : souvent des images reçues puis enregistrées.",
                    symbol: "arrow.down.right.and.arrow.up.left",
                    items: tiny
                )
            )
        }

        return groups.filter { !$0.items.isEmpty }
    }

    /// Finds assets shot within the same minute and returns every frame except
    /// the largest one, which is kept as the best candidate.
    private static func burstCandidates(
        _ items: [MediaItem],
        calendar: Calendar
    ) -> [MediaItem] {
        let photos = items.filter { !$0.isVideo }

        let byMinute = Dictionary(grouping: photos) { item -> DateComponents in
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.creationDate)
        }

        var candidates: [MediaItem] = []
        for (_, bucket) in byMinute where bucket.count >= 3 {
            let ordered = bucket.sorted { $0.megapixels > $1.megapixels }
            candidates.append(contentsOf: ordered.dropFirst())
        }
        return candidates.sorted { $0.creationDate > $1.creationDate }
    }
}

// MARK: - Supporting types

/// A `Hashable` year+month key, so month sections can be sorted without
/// formatting a string first.
struct YearMonth: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    func title(locale: Locale) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard let date = Calendar.current.date(from: components) else {
            return "\(month)/\(year)"
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// One cleanup proposal.
struct CleanupGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let reason: String
    let symbol: String
    let items: [MediaItem]
}
