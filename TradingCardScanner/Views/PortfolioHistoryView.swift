import Accessibility
import Charts
import SwiftData
import SwiftUI
import UIKit

struct PortfolioHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var controller = PortfolioHistoryController()

    @Binding var mode: PortfolioHistoryMode
    let range: PortfolioHistoryRange
    let summary: PortfolioSummary?
    let factors: PortfolioPerformanceFactors
    let contributions: PortfolioContributionIndex
    let refreshRevision: UInt
    let onResultUpdated: (PortfolioHistoryResult?) -> Void

    @State private var selectedPointID: String?
    @State private var lastHapticPointID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("History mode", selection: Binding(
                get: { mode },
                set: { mode = $0 }
            )) {
                ForEach(PortfolioHistoryMode.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if let result = controller.result, !result.isEmpty {
                if let point = selectedPoint(in: result) {
                    pointInspector(point, result: result)
                }
                historyChart(result)
                    .frame(height: 190)

                if !result.hasTwoPublishedPoints {
                    Text("History is being recorded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let began = result.trackingBeganDate {
                    Text("Since tracking began \(began.formatted(date: .abbreviated, time: .omitted))")
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
        .task(id: refreshKey) {
            controller.recompute(
                context: modelContext,
                summary: summary,
                factors: factors,
                contributions: contributions,
                mode: mode,
                range: range
            )
            onResultUpdated(controller.result)
        }
        .onDisappear {
            onResultUpdated(nil)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: mode)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: range)
    }

    private var refreshKey: String {
        "\(refreshRevision)-\(mode.rawValue)-\(range.rawValue)"
    }

    @ViewBuilder
    private func historyChart(_ result: PortfolioHistoryResult) -> some View {
        let selectionID = selectedID(in: result)
        Chart {
            if result.mode == .value {
                ForEach(result.points) { point in
                    historyLine(point, result: result, selectionID: selectionID)
                }
            } else {
                ForEach(result.points.filter { $0.performanceFactor != nil }) { point in
                    historyLine(point, result: result, selectionID: selectionID)
                }
            }
        }
        .chartYScale(domain: yDomain(result))
        .chartYAxis { AxisMarks(position: .leading) }
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
        .accessibilityHint("Swipe across the plot to inspect each real point.")
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
            y: .value(result.mode.chartLabel, chartValue(point, mode: result.mode))
        )
        .foregroundStyle(result.mode == .performance ? Color.green : Color.accentColor)

        let isSelected = point.id == selectionID
        if isSelected {
            PointMark(
                x: .value("Date", point.instant),
                y: .value(result.mode.chartLabel, chartValue(point, mode: result.mode))
            )
            .foregroundStyle(result.mode == .performance ? Color.green : Color.accentColor)
            RuleMark(x: .value("Selected date", point.instant))
                .foregroundStyle(.secondary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
        }
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
                Text(point.isLive ? "Live portfolio value" : "Published daily close")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(inspectorValue(point, mode: result.mode))
                .font(.headline.monospacedDigit())
                .foregroundStyle(result.mode == .performance ? .green : .primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(point.isLive ? "Today" : "\(point.displayDay.formatted(date: .abbreviated, time: .omitted)) close")
        .accessibilityValue(inspectorValue(point, mode: result.mode))
    }

    private func inspectorValue(_ point: PortfolioHistoryPoint, mode: PortfolioHistoryMode) -> String {
        switch mode {
        case .value:
            return point.value.formatted()
        case .performance:
            guard let factor = point.performanceFactor else { return "Unavailable" }
            let percent = NSDecimalNumber(decimal: factor).doubleValue * 100 - 100
            return (percent / 100).formatted(.percent.precision(.fractionLength(2)))
        }
    }

    private func chartValue(_ point: PortfolioHistoryPoint, mode: PortfolioHistoryMode) -> Double {
        switch mode {
        case .value:
            return point.value.doubleValue
        case .performance:
            guard let factor = point.performanceFactor else { return 0 }
            return NSDecimalNumber(decimal: factor).doubleValue * 100 - 100
        }
    }

    private func yDomain(_ result: PortfolioHistoryResult) -> ClosedRange<Double> {
        let values = result.points.compactMap { point -> Double? in
            guard result.mode == .value || point.performanceFactor != nil else { return nil }
            return chartValue(point, mode: result.mode)
        }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        if low == high { return (low - 1)...(high + 1) }
        let padding = max((high - low) * 0.12, result.mode == .performance ? 0.5 : 1)
        return (low - padding)...(high + padding)
    }

    private func summaryValue(for result: PortfolioHistoryResult, accounting: PortfolioHistoryAccounting) -> String {
        switch result.mode {
        case .value:
            return signedCurrency(accounting.totalChange)
        case .performance:
            guard result.performanceAvailable, let factor = result.performanceFactor else { return "Unavailable" }
            let percent = NSDecimalNumber(decimal: factor).doubleValue * 100 - 100
            return (percent / 100).formatted(.percent.precision(.fractionLength(2)))
        }
    }

    private func chartSummary(_ result: PortfolioHistoryResult) -> String {
        guard let accounting = result.accounting else { return "No published history yet." }
        return "From \(accounting.anchorValue.formatted()) to \(accounting.endValue.formatted()). \(summaryValue(for: result, accounting: accounting)). \(result.points.count) real points."
    }

    private func signedCurrency(_ amount: Money) -> String {
        let prefix = amount.tenThousandths > 0 ? "+" : ""
        return prefix + amount.formatted()
    }
}

private struct PortfolioChartDescriptor: AXChartDescriptorRepresentable {
    let result: PortfolioHistoryResult

    func makeChartDescriptor() -> AXChartDescriptor {
        let pointValues = result.points.map { point -> Double? in
            switch result.mode {
            case .value: point.value.doubleValue
            case .performance: point.performanceFactor.map { NSDecimalNumber(decimal: $0).doubleValue * 100 - 100 }
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
                result.mode == .performance
                    ? (value / 100).formatted(.percent.precision(.fractionLength(1)))
                    : value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
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
        case .performance: (value / 100).formatted(.percent.precision(.fractionLength(1)))
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
