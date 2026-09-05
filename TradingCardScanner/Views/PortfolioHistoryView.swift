import Accessibility
import Charts
import SwiftUI
import UIKit

struct PortfolioHistoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var history: PortfolioHistoryStore
    let onOpenDetails: (PortfolioHistoryResult) -> Void

    @State private var selectedPointID: String?
    @State private var lastHapticPointID: String?
    /// Held and re-armed rather than built per tick, for the reason
    /// `ScanFeedback` documents: a cold generator answers late enough to break
    /// the coupling between the finger crossing a point and the click that
    /// reports it.
    @State private var selectionFeedback = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = history.activeResult, !result.isEmpty {
                historyHeader(result)
                historyChart(result)
                    .frame(height: 190)

                if !result.hasTwoPublishedPoints {
                    Text("History is being recorded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            } else {
                Text("History is being recorded.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: history.range)
        .onChange(of: history.range) { _, _ in
            resetSelection()
        }
        .onDisappear {
            resetSelection()
        }
    }

    private func historyHeader(_ result: PortfolioHistoryResult) -> some View {
        let point = selectedPoint(in: result)
        let amount = point?.cumulativeMarketMovement ?? result.accounting?.market ?? .zero

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(point.map(pointHeaderLabel) ?? "Market movement · \(result.range.rawValue)")
                    .font(.headline)
                Text(PortfolioHistoryDisplay.signedCurrency(amount))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(PortfolioPalette.direction(amount))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(point.map(pointHeaderLabel) ?? "Market movement · \(result.range.rawValue)")
            .accessibilityValue(PortfolioHistoryDisplay.signedCurrency(amount))

            Spacer(minLength: 8)

            PortfolioInfoButton(label: "About market movement") {
                PortfolioHistoryInfoPopover(
                    result: result,
                    onOpenDetails: onOpenDetails
                )
            }
        }
    }

    @ViewBuilder
    private func historyChart(_ result: PortfolioHistoryResult) -> some View {
        historyChartPlot(result)
    }

    @ViewBuilder
    private func historyChartPlot(_ result: PortfolioHistoryResult) -> some View {
        let selectionID = selectedID(in: result)
        let domain = yDomain(result)
        let fractionDigits = PortfolioHistoryDisplay.currencyFractionDigits(
            forSpan: domain.upperBound - domain.lowerBound
        )
        Chart {
            ForEach(result.points) { point in
                historyLine(point, result: result, selectionID: selectionID)
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount.formatted(.currency(code: "USD").precision(.fractionLength(fractionDigits))))
                    }
                }
            }
        }
        .chartXAxis {
            if chartSpansOnlyDays(result) {
                AxisMarks(values: .stride(by: .day))
            } else {
                AxisMarks(values: .automatic(desiredCount: 3))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrameAnchor = proxy.plotFrame {
                    let plotFrame = geometry[plotFrameAnchor]
                    let selectPoint: (CGPoint) -> Void = { location in
                        guard plotFrame.contains(location),
                              let date: Date = proxy.value(atX: location.x - plotFrame.minX)
                        else { return }
                        let nearestID = result.points.min {
                            abs($0.instant.timeIntervalSince(date)) < abs($1.instant.timeIntervalSince(date))
                        }?.id
                        guard nearestID != selectedPointID else { return }
                        selectedPointID = nearestID
                        if nearestID != lastHapticPointID {
                            selectionFeedback.selectionChanged()
                            // Re-arm for the next point the scrub crosses.
                            selectionFeedback.prepare()
                            lastHapticPointID = nearestID
                        }
                    }
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { gesture in
                            guard abs(gesture.translation.width) > abs(gesture.translation.height) else { return }
                            selectionFeedback.prepare()
                            selectPoint(gesture.location)
                        }.onEnded { _ in
                            resetSelection()
                        })
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Market movement")
        .accessibilityValue(chartSummary(result))
        .accessibilityChartDescriptor(PortfolioChartDescriptor(result: result))
    }

    @ChartContentBuilder
    private func historyLine(
        _ point: PortfolioHistoryPoint,
        result: PortfolioHistoryResult,
        selectionID: String?
    ) -> some ChartContent {
        LineMark(
            x: .value("Date", point.instant),
            y: .value(
                "Market movement",
                chartValue(point)
            )
        )
        .foregroundStyle(seriesColor(result))

        if let selectionID, point.id == selectionID {
            PointMark(
                x: .value("Date", point.instant),
                y: .value(
                    "Market movement",
                    chartValue(point)
                )
            )
            .foregroundStyle(seriesColor(result))
            RuleMark(x: .value("Selected date", point.instant))
                .foregroundStyle(.secondary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
        }
    }

    /// The line colour describes the selected period's net market movement.
    private func seriesColor(_ result: PortfolioHistoryResult) -> Color {
        PortfolioPalette.direction(result.accounting?.market ?? .zero)
    }

    private func selectedID(in result: PortfolioHistoryResult) -> String? {
        guard let selectedPointID,
              result.points.contains(where: { $0.id == selectedPointID }) else { return nil }
        return selectedPointID
    }

    private func selectedPoint(in result: PortfolioHistoryResult) -> PortfolioHistoryPoint? {
        guard let id = selectedID(in: result) else { return nil }
        return result.points.first { $0.id == id }
    }

    private func chartSpansOnlyDays(_ result: PortfolioHistoryResult) -> Bool {
        guard let first = result.points.first?.instant,
              let last = result.points.last?.instant else { return false }
        return last.timeIntervalSince(first) <= 7 * 24 * 60 * 60
    }

    private func pointHeaderLabel(_ point: PortfolioHistoryPoint) -> String {
        if point.isLive {
            return "Through today"
        }
        return "Through \(point.displayDay.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func resetSelection() {
        selectedPointID = nil
        lastHapticPointID = nil
    }

    private func chartValue(_ point: PortfolioHistoryPoint) -> Double {
        point.cumulativeMarketMovement.doubleValue
    }

    private func yDomain(_ result: PortfolioHistoryResult) -> ClosedRange<Double> {
        let values = result.points.map(chartValue)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let low = min(minimum, 0)
        let high = max(maximum, 0)
        if low == high { return (low - 1)...(high + 1) }
        let padding = max((high - low) * 0.12, 1)
        return (low - padding)...(high + padding)
    }

    private func chartSummary(_ result: PortfolioHistoryResult) -> String {
        guard let accounting = result.accounting else { return "No published history yet." }
        return "From $0.00 to \(PortfolioHistoryDisplay.signedCurrency(accounting.market)). \(result.points.count) real points."
    }

}

private struct PortfolioHistoryInfoPopover: View {
    let result: PortfolioHistoryResult
    let onOpenDetails: (PortfolioHistoryResult) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Price changes only. Cards added or removed are excluded.")
                .font(.body)
            Button("Full accounting") {
                dismiss()
                onOpenDetails(result)
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: 280, alignment: .leading)
        .padding()
    }
}

private struct PortfolioChartDescriptor: AXChartDescriptorRepresentable {
    let result: PortfolioHistoryResult

    func makeChartDescriptor() -> AXChartDescriptor {
        let pointValues = result.points.map { $0.cumulativeMarketMovement.doubleValue }
        let lower = min(pointValues.min() ?? 0, 0)
        let upper = max(pointValues.max() ?? 0, 0)
        let yRange = lower == upper ? (lower - 1)...(upper + 1) : lower...upper
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Market movement",
            range: yRange,
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
            }
        )
        let dateLabels = result.points.map {
            $0.isLive
                ? "Market movement through today"
                : "Market movement through \($0.displayDay.formatted(date: .abbreviated, time: .omitted))"
        }
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Date", categoryOrder: dateLabels)
        let points = result.points.enumerated().compactMap { index, point -> AXDataPoint? in
            let value = pointValues[index]
            return AXDataPoint(
                x: dateLabels[index],
                y: value,
                label: "\(dateLabels[index]), \(valueDescription(value))"
            )
        }
        let series = AXDataSeriesDescriptor(name: "Market movement", isContinuous: true, dataPoints: points)
        return AXChartDescriptor(
            title: "Market movement",
            summary: "Cumulative market movement from $0.00 across \(result.points.count) real points. The final point is \(PortfolioHistoryDisplay.signedCurrency(result.accounting?.market ?? .zero)).",
            xAxis: xAxis,
            yAxis: yAxis,
            series: [series]
        )
    }

    private func valueDescription(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
