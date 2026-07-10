import Foundation

/// Pure page math for the kit matrix's 16-step bar pager, extracted from
/// `DrumKitMatrixView` so it can be unit-tested without SwiftUI or a model.
///
/// The pager shows one page per `stepsPerBar`-step bar. `pageCount` answers how
/// many pages a row of `length` steps needs (always at least one), and
/// `clampedPage` keeps a possibly-stale `barPage` index inside the valid range
/// after the row length (and therefore the page count) shrinks.
///
/// No SwiftUI import: this is plain integer arithmetic the view delegates to.
enum DrumKitBarPaging {
    static let indicatorCount = 8

    struct Indicator: Equatable {
        enum State: Equatable {
            case current
            case available
            case unavailable
        }

        let page: Int
        let state: State
    }

    /// Number of `stepsPerBar`-step pages needed for `length` steps, at least 1.
    ///
    /// - `length <= 0` → 1 (the matrix always renders one bar window).
    /// - `length` an exact multiple of `stepsPerBar` → that many pages.
    /// - otherwise the partial final bar rounds up to its own page.
    static func pageCount(length: Int, stepsPerBar: Int) -> Int {
        guard stepsPerBar > 0 else { return 1 }
        let usableLength = max(0, length)
        return max(1, (usableLength + stepsPerBar - 1) / stepsPerBar)
    }

    /// `page` clamped to `0 ..< pageCount(length:stepsPerBar:)`.
    ///
    /// A negative page clamps to 0; a page beyond the last valid index (e.g. a
    /// stale selection after the row shrank) clamps to the last page.
    static func clampedPage(_ page: Int, length: Int, stepsPerBar: Int) -> Int {
        let pages = pageCount(length: length, stepsPerBar: stepsPerBar)
        return min(max(0, page), pages - 1)
    }

    /// A compact bank of eight page indicators. Normal clips always show bars
    /// 1...8, dimming bars beyond their length. Legacy clips longer than 128
    /// steps move through additional eight-bar banks without widening the UI.
    static func indicators(
        pageCount: Int,
        currentPage: Int,
        count: Int = indicatorCount
    ) -> [Indicator] {
        guard count > 0 else { return [] }
        let availablePageCount = max(1, pageCount)
        let current = min(max(0, currentPage), availablePageCount - 1)
        let bankStart = (current / count) * count

        return (0..<count).map { offset in
            let page = bankStart + offset
            let state: Indicator.State
            if page == current {
                state = .current
            } else if page < availablePageCount {
                state = .available
            } else {
                state = .unavailable
            }
            return Indicator(page: page, state: state)
        }
    }

    static func previousBankPage(currentPage: Int, count: Int = indicatorCount) -> Int? {
        guard count > 0 else { return nil }
        let bankStart = (max(0, currentPage) / count) * count
        guard bankStart > 0 else { return nil }
        return max(0, bankStart - count)
    }

    static func nextBankPage(
        pageCount: Int,
        currentPage: Int,
        count: Int = indicatorCount
    ) -> Int? {
        guard count > 0 else { return nil }
        let bankStart = (max(0, currentPage) / count) * count
        let next = bankStart + count
        return next < max(1, pageCount) ? next : nil
    }
}
