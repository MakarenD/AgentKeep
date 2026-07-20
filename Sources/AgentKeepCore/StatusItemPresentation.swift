struct StatusItemPresentation: Equatable {
    let title: String
    let fallbackTitle: String
    let processSummary: String

    init(localServerCount: Int?) {
        guard let localServerCount else {
            title = "–"
            fallbackTitle = "AK –"
            processSummary = "Local server count unavailable"
            return
        }

        title = String(localServerCount)
        fallbackTitle = "AK \(localServerCount)"
        processSummary = localServerCount == 1
            ? "1 local server running"
            : "\(localServerCount) local servers running"
    }
}
