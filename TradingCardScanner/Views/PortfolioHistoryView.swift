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
            Picker("History mode", selection: Binding(
                get: { history.mode },
                set: { history.mode = $0 }
            )) {
                ForEach(PortfolioHistoryMode.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if let result = history.activeResult, !result.isEmpty {
                if let point = selectedPoint(in: result),
                   hasInspectableValue(point, in: result) {
                    pointInspector(point, result: result)
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: history.mode)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: history.range)
    }

    @ViewBuilder
    private func historyChart(_ result: PortfolioHistoryResult) -> some View {
        if result.mode == .performance && !hasPlottableChartValues(result) {
            Text("Not enough data to plot")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            historyChartPlot(result)
        }
    }

    @ViewBuilder
    private func historyChartPlot(_ result: PortfolioHistoryResult) -> some View {
        let selectionID = selectedID(in: result)
        let domain = yDomain(result)
        let fractionDigits = PortfolioHistoryDisplay.currencyFractionDigits(
            forSpan: domain.upperBound - domain.lowerBound
        )
        Chart {
            if result.mode == .value {
                ForEach(result.points) { point in
                    historyLine(point, result: result, selectionID: selectionID)
                }
            } else {
                ForEach(result.points.filter {
                    $0.performanceFactor != nil
                        && result.accounting?.anchorValue.isZero == false
                }) { point in
                    historyLine(point, result: result, selectionID: selectionID)
                }
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
        .accessibilityLabel(result.mode.title)
        .accessibilityValue(chartSummary(result))
        .accessibilityChartDescriptor(PortfolioChartDescriptor(result: result))
        .onAppear {
            selectedPointID = selectionID
            lastHapticPointID = selectionID
        }
    }

    private func hasPlottableChartValues(_ result: PortfolioHistoryResult) -> Bool {
        guard result.mode == .performance,
              let anchorValue = result.accounting?.anchorValue,
              !anchorValue.isZero else { return false }
        return result.points.contains {
            PortfolioHistoryDisplay.performanceDollars(
                factor: $0.performanceFactor,
                anchorValue: anchorValue
            ) != nil
        }
    }

    private func hasInspectableValue(
        _ point: PortfolioHistoryPoint,
        in result: PortfolioHistoryResult
    ) -> Bool {
        guard result.mode == .performance else { return true }
        guard let dollars = PortfolioHistoryDisplay.performanceDollars(
            factor: point.performanceFactor,
            anchorValue: result.accounting?.anchorValue
        ) else { return false }
        return Money(rounding: dollars) != nil
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
                result.mode.chartLabel,
                chartValue(
                    point,
                    mode: result.mode,
                    anchorValue: result.accounting?.anchorValue
                )
            )
        )
        .foregroundStyle(seriesColor(result))

        let isSelected = point.id == selectionID
        if isSelected {
            PointMark(
                x: .value("Date", point.instant),
                y: .value(
                    result.mode.chartLabel,
                    chartValue(
                        point,
                        mode: result.mode,
                        anchorValue: result.accounting?.anchorValue
                    )
                )
            )
            .foregroundStyle(seriesColor(result))
            RuleMark(x: .value("Selected date", point.instant))
                .foregroundStyle(.secondary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
        }
    }

    /// Green only when the period actually gained.
    ///
    /// A permanently green performance line makes green mean "this is
    /// performance" rather than "this went up", which is exactly the ambiguity
    /// the palette exists to remove. Collection Value stays on the neutral
    /// accent: a level is not a direction.
    private func seriesColor(_ result: PortfolioHistoryResult) -> Color {
        guard result.mode == .performance else { return Color.accentColor }
        guard let factor = result.performanceFactor, factor != 1 else { return .secondary }
        return factor > 1 ? PortfolioPalette.gain : PortfolioPalette.loss
    }

    /// The colour for one plotted point, judged on that point rather than on
    /// the period, so scrubbing back to a losing day shows a losing colour.
    private func pointColor(_ point: PortfolioHistoryPoint, mode: PortfolioHistoryMode) -> Color {
        guard mode == .performance else { return .primary }
        guard let factor = point.performanceFactor, factor != 1 else { return .secondary }
        return factor > 1 ? PortfolioPalette.gain : PortfolioPalette.loss
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

    private func pointInspector(_ point: PortfolioHistoryPoint, result: PortfolioHistoryResult) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(point.isLive ? "Today" : "\(point.displayDay.formatted(date: .abbreviated, time: .omitted)) close")
                    .font(.caption.weight(.semibold))
                Text(inspectorSubtitle(point, mode: result.mode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(inspectorValue(
                point,
                mode: result.mode,
                anchorValue: result.accounting?.anchorValue
            ))
                .font(.headline.monospacedDigit())
                .foregroundStyle(pointColor(point, mode: result.mode))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(point.isLive ? "Today" : "\(point.displayDay.formatted(date: .abbreviated, time: .omitted)) close")
        .accessibilityValue(
            inspectorValue(
                point,
                mode: result.mode,
                anchorValue: result.accounting?.anchorValue
            )
        )
    }

    /// "Live portfolio value" under a percentage described the wrong quantity.
    /// The subtitle names what the number above it actually is.
    private func inspectorSubtitle(
        _ point: PortfolioHistoryPoint,
        mode: PortfolioHistoryMode
    ) -> String {
        switch (mode, point.isLive) {
        case (.value, true): return "Live portfolio value"
        case (.value, false): return "Published daily close"
        case (.performance, true): return "Return so far today"
        case (.performance, false): return "Return through this close"
        }
    }

    private func inspectorValue(
        _ point: PortfolioHistoryPoint,
        mode: PortfolioHistoryMode,
        anchorValue: Money?
    ) -> String {
        switch mode {
        case .value:
            return point.value.formatted()
        case .performance:
            guard let factor = point.performanceFactor,
                  let dollarChange = PortfolioHistoryDisplay.performanceDollars(
                      factor: factor,
                      anchorValue: anchorValue
                  ),
                  let moneyChange = Money(rounding: dollarChange)
            else { return "Unavailable" }
            let dollarText = PortfolioHistoryDisplay.signedCurrency(moneyChange)
            guard let ratio = PortfolioHistoryDisplay.percentChange(
                amount: moneyChange,
                anchor: anchorValue ?? .zero
            ) else {
                return dollarText
            }
            return "\(dollarText) (\(PortfolioHistoryDisplay.signedPercent(ratio)))"
        }
    }

    private func chartValue(
        _ point: PortfolioHistoryPoint,
        mode: PortfolioHistoryMode,
        anchorValue: Money?
    ) -> Double {
        switch mode {
        case .value:
            return point.value.doubleValue
        case .performance:
            return PortfolioHistoryDisplay.performanceDollars(
                factor: point.performanceFactor,
                anchorValue: anchorValue
            ) ?? 0
        }
    }

    private func yDomain(_ result: PortfolioHistoryResult) -> ClosedRange<Double> {
        let values = result.points.compactMap { point -> Double? in
            guard result.mode == .value
                    || (point.performanceFactor != nil && result.accounting?.anchorValue.isZero == false)
            else { return nil }
            return chartValue(
                point,
                mode: result.mode,
                anchorValue: result.accounting?.anchorValue
            )
        }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        if low == high { return (low - 1)...(high + 1) }
        let padding = max((high - low) * 0.12, 1)
        return (low - padding)...(high + padding)
    }

    private func summaryValue(for result: PortfolioHistoryResult, accounting: PortfolioHistoryAccounting) -> String {
        switch result.mode {
        case .value:
            return PortfolioHistoryDisplay.signedCurrency(accounting.totalChange)
        case .performance:
            guard result.performanceAvailable,
                  let dollars = PortfolioHistoryDisplay.performanceDollars(
                      factor: result.performanceFactor,
                      anchorValue: accounting.anchorValue
                  ),
                  let money = Money(rounding: dollars)
            else { return "Unavailable" }
            return PortfolioHistoryDisplay.signedCurrency(money)
        }
    }

    private func chartSummary(_ result: PortfolioHistoryResult) -> String {
        guard let accounting = result.accounting else { return "No published history yet." }
        return "From \(accounting.anchorValue.formatted()) to \(accounting.endValue.formatted()). \(summaryValue(for: result, accounting: accounting)). \(result.points.count) real points."
    }

}

private struct PortfolioChartDescriptor: AXChartDescriptorRepresentable {
    let result: PortfolioHistoryResult

    func makeChartDescriptor() -> AXChartDescriptor {
        let pointValues = result.points.map { point -> Double? in
            switch result.mode {
            case .value: point.value.doubleValue
            case .performance:
                PortfolioHistoryDisplay.performanceDollars(
                    factor: point.performanceFactor,
                    anchorValue: result.accounting?.anchorValue
                )
            }
        }
        let values = pointValues.compactMap { $0 }
        let lower = values.min() ?? 0
        let upper = values.max() ?? 1
        let yRange = lower == upper ? (lower - 1)...(upper + 1) : lower...upper
        let yAxis = AXNumericDataAxisDescriptor(
            title: result.mode.chartLabel,
            range: yRange,
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
            }
        )
        let dateLabels = result.points.map {
            $0.isLive ? "Today" : "\($0.displayDay.formatted(date: .abbreviated, time: .omitted)) close"
        }
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Date", categoryOrder: dateLabels)
        let points = result.points.enumerated().compactMap { index, point -> AXDataPoint? in
            guard let value = pointValues[index] else { return nil }
            return AXDataPoint(
                x: dateLabels[index],
                y: value,
                label: point.isLive ? "Today, \(valueDescription(value))" : "\(dateLabels[index]), \(valueDescription(value))"
            )
        }
        let series = AXDataSeriesDescriptor(name: result.mode.title, isContinuous: true, dataPoints: points)
        return AXChartDescriptor(
            title: result.mode.title,
            summary: "\(result.mode.title) across \(result.points.count) real points.",
            xAxis: xAxis,
            yAxis: yAxis,
            series: [series]
        )
    }

    private func valueDescription(_ value: Double) -> String {
        switch result.mode {
        case .value: value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
        case .performance: value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
