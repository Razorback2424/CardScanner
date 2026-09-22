import Charts
import SwiftUI

struct BrowsePriceHistoryChartSegment: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let source: BrowsePriceMarketSource
    let points: [BrowsePriceHistoryPoint]
}

struct BrowsePriceHistoryChartModel: Equatable, Sendable {
    let segments: [BrowsePriceHistoryChartSegment]
    let observationDays: [BrowsePriceDay]

    init(series: [BrowsePricePersistedSeries]) {
        var segments: [BrowsePriceHistoryChartSegment] = []
        var allDays = Set<BrowsePriceDay>()

        for persisted in series {
            let sorted = persisted.points.sorted { $0.day < $1.day }
            allDays.formUnion(sorted.map(\.day))
            guard !sorted.isEmpty else { continue }

            var segmentPoints: [BrowsePriceHistoryPoint] = []
            var segmentIndex = 0
            for point in sorted {
                if let previous = segmentPoints.last,
                   point.day != previous.day.adding(days: 1) {
                    segments.append(
                        Self.segment(
                            persisted: persisted,
                            points: segmentPoints,
                            index: segmentIndex
                        )
                    )
                    segmentIndex += 1
                    segmentPoints = []
                }
                segmentPoints.append(point)
            }
            if !segmentPoints.isEmpty {
                segments.append(
                    Self.segment(
                        persisted: persisted,
                        points: segmentPoints,
                        index: segmentIndex
                    )
                )
            }
        }

        self.segments = segments
        self.observationDays = allDays.sorted()
    }

    var hasSufficientHistory: Bool {
        observationDays.count >= 2
    }

    var metadataText: String? {
        guard let first = observationDays.first else { return nil }
        let count = observationDays.count
        return "\(count) observations since \(first.date.formatted(date: .abbreviated, time: .omitted))"
    }

    var containsScryfallDatasetStamp: Bool {
        segments.contains { $0.source == .scryfall }
    }

    private static func segment(
        persisted: BrowsePricePersistedSeries,
        points: [BrowsePriceHistoryPoint],
        index: Int
    ) -> BrowsePriceHistoryChartSegment {
        BrowsePriceHistoryChartSegment(
            id: "\(persisted.key.printingID)|\(persisted.key.variantDescriptor.value)|\(persisted.key.marketSource.rawValue)|\(index)",
            label: persisted.key.variantDescriptor.value
                .replacingOccurrences(of: "pokemon.", with: "")
                .replacingOccurrences(of: "magic.", with: "")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized,
            source: persisted.key.marketSource,
            points: points
        )
    }
}

struct BrowsePriceHistoryChartView: View {
    let model: BrowsePriceHistoryChartModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Browse price history")
                .font(.headline)

            if model.hasSufficientHistory {
                Chart {
                    ForEach(model.segments) { segment in
                        ForEach(segment.points, id: \.day) { point in
                            LineMark(
                                x: .value("Provider day", point.day.date),
                                y: .value("USD", point.amountUSD),
                                series: .value("Segment", segment.id)
                            )
                            .foregroundStyle(by: .value("Finish", segment.label))

                            PointMark(
                                x: .value("Provider day", point.day.date),
                                y: .value("USD", point.amountUSD)
                            )
                            .foregroundStyle(by: .value("Finish", segment.label))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount.formatted(.currency(code: "USD")))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 220)
                .accessibilityLabel("Browse price history chart")
                .accessibilityValue(model.metadataText ?? "No observations")

                if let metadata = model.metadataText {
                    Text(metadata)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.containsScryfallDatasetStamp {
                    Text("Magic dates use Scryfall's approximate dataset update day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Price history starts as this set is refreshed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}
