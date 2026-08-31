import Accessibility
import Charts
import SwiftUI
import UIKit

struct PortfolioHistoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var history: PortfolioHistoryStore

    @State private var selectedPointID: String?
    @State private var lastHapticPointID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = history.activeResult, !result.isEmpty {
                if let point = selectedPoint(in: result) {
                    pointInspector(point)
                }
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
                            UISelectionFeedbackGenerator().selectionChanged()
                            lastHapticPointID = nearestID
                        }
                    }
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(SpatialTapGesture().onEnded { gesture in
                            selectPoint(gesture.location)
                        })
                        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { gesture in
                            guard abs(gesture.translation.width) > abs(gesture.translation.height) else { return }
                            selectPoint(gesture.location)
                        })
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Market movement")
        .accessibilityValue(chartSummary(result))
        .accessibilityChartDescriptor(PortfolioChartDescriptor(result: result))
        .onAppear {
            selectedPointID = selectionID
            lastHapticPointID = selectionID
        }
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

        let isSelected = point.id == selectionID
        if isSelected {
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

    /// The colour for one plotted point reflects the cumulative movement at
    /// that point rather than the final period total.
    private func pointColor(_ point: PortfolioHistoryPoint) -> Color {
        PortfolioPalette.direction(point.cumulativeMarketMovement)
    }

    private func selectedID(in result: PortfolioHistoryResult) -> String? {
        guard let selectedPointID,
              result.points.contains(where: { $0.id == selectedPointID }) else {
            return result.points.last?.id
        }
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

    private func pointInspector(_ point: PortfolioHistoryPoint) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pointLabel(point))
                    .font(.caption.weight(.semibold))
                Text("Cumulative market movement")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(inspectorValue(point))
                .font(.headline.monospacedDigit())
                .foregroundStyle(pointColor(point))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pointLabel(point))
        .accessibilityValue(inspectorValue(point))
    }

    private func pointLabel(_ point: PortfolioHistoryPoint) -> String {
        if point.isLive {
            return "Market movement through today"
        }
        return "Market movement through \(point.displayDay.formatted(date: .abbreviated, time: .omitted))"
    }

    private func inspectorValue(_ point: PortfolioHistoryPoint) -> String {
        PortfolioHistoryDisplay.signedCurrency(point.cumulativeMarketMovement)
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
