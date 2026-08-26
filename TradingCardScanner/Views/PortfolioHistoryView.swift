import Accessibility
import Charts
import SwiftData
import SwiftUI

struct PortfolioHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var controller = PortfolioHistoryController()
    @AppStorage("portfolioHistoryMode") private var modeRaw = PortfolioHistoryMode.performance.rawValue
    @AppStorage("portfolioHistoryRange") private var rangeRaw = PortfolioHistoryRange.oneMonth.rawValue

    let summary: PortfolioSummary?

    @State private var selectedPointID: String?

    private var mode: PortfolioHistoryMode {
        get { PortfolioHistoryMode(rawValue: modeRaw) ?? .performance }
        set { modeRaw = newValue.rawValue }
    }

    private var range: PortfolioHistoryRange {
        get { PortfolioHistoryRange(rawValue: rangeRaw) ?? .oneMonth }
        set { rangeRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(mode.title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let result = controller.result, let accounting = result.accounting {
                    Text(summaryValue(for: result, accounting: accounting))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(result.mode == .performance ? .green : .primary)
                        .monospacedDigit()
                }
            }

            Picker("History mode", selection: Binding(
                get: { mode },
                set: { modeRaw = $0.rawValue }
            )) {
                ForEach(PortfolioHistoryMode.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if let result = controller.result, !result.isEmpty {
                historyChart(result)
                    .frame(height: 190)

                Picker("History range", selection: Binding(
                    get: { range },
                    set: { rangeRaw = $0.rawValue }
                )) {
                    ForEach(PortfolioHistoryRange.allCases, id: \.self) { item in
                        Text(item.rawValue)
                            .accessibilityLabel(item.accessibilityName)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!result.hasTwoPublishedPoints)
                .accessibilityHint(result.hasTwoPublishedPoints ? "Choose the calendar range." : "Range selection becomes available after two published closes.")

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

                evidence(result)
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
                mode: mode,
                range: range
            )
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: modeRaw)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: rangeRaw)
    }

    private var refreshKey: String {
        "\(modeRaw)-\(rangeRaw)-\(summary?.currentValue.tenThousandths ?? -1)-\(summary?.closeDate?.timeIntervalSinceReferenceDate ?? -1)"
    }

    @ViewBuilder
    private func historyChart(_ result: PortfolioHistoryResult) -> some View {
        Chart {
            if result.mode == .value {
                ForEach(result.points) { point in
                    historyLine(point, result: result)
                }
            } else {
                ForEach(result.points.filter { $0.performanceFactor != nil }) { point in
                    historyLine(point, result: result)
                }
            }
        }
        .chartYScale(domain: yDomain(result))
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrameAnchor = proxy.plotFrame {
                    let plotFrame = geometry[plotFrameAnchor]
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                            guard plotFrame.contains(gesture.location),
                                  let date: Date = proxy.value(atX: gesture.location.x - plotFrame.minX)
                            else { return }
                            selectedPointID = result.points.min {
                                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                            }?.id
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
            if selectedPointID == nil { selectedPointID = result.points.last?.id }
        }
    }

    @ChartContentBuilder
    private func historyLine(_ point: PortfolioHistoryPoint, result: PortfolioHistoryResult) -> some ChartContent {
        LineMark(
            x: .value("Date", point.date),
            y: .value(result.mode.chartLabel, chartValue(point, mode: result.mode))
        )
        .foregroundStyle(result.mode == .performance ? Color.green : Color.accentColor)

        let isSelected = point.id == (selectedPointID ?? result.points.last?.id)
        if isSelected {
            PointMark(
                x: .value("Date", point.date),
                y: .value(result.mode.chartLabel, chartValue(point, mode: result.mode))
            )
            .foregroundStyle(result.mode == .performance ? Color.green : Color.accentColor)
            RuleMark(x: .value("Selected date", point.date))
                .foregroundStyle(.secondary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
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
            return (percent / 100).formatted(.percent.precision(.fractionLength(1)))
        }
    }

    private func evidence(_ result: PortfolioHistoryResult) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let accounting = result.accounting {
                switch result.mode {
                case .performance:
                    evidenceRow("Market-driven value change", accounting.market)
                    evidenceRow("Time-weighted market return", result.performanceAvailable ? summaryValue(for: result, accounting: accounting) : "Unavailable")
                    Text("Net collection activity, corrections, and pricing adjustments excluded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .value:
                    evidenceRow("Total value change", accounting.totalChange)
                    evidenceRow("Market movement", accounting.market)
                    evidenceRow("Net collection activity", accounting.netInventoryActivity)
                    evidenceRow("Corrections", accounting.corrections)
                    evidenceRow("Pricing adjustments", accounting.pricingAdjustments)
                    if !accounting.unexplained.isZero {
                        evidenceRow("Unexplained", accounting.unexplained, defect: true)
                    }
                }
            }

            let coverage = result.coverage
            Text("Coverage: \(coverage.completeDays) complete · \(coverage.partialDays) partial · \(coverage.unknownDays) unknown days")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let live = coverage.live {
                Text("Today: \(live.refreshed) checked · \(live.carriedForward) carried forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !result.revisions.isEmpty {
                Text("\(result.revisions.count) reconciled day\(result.revisions.count == 1 ? "" : "s") in this range")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Revision details") {
                    ForEach(result.revisions, id: \.date) { revision in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(revision.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption.weight(.semibold))
                            Text("Original \(revision.original.closeValue.formatted()) · Latest \(revision.latest.closeValue.formatted())")
                                .font(.caption)
                            if let note = revision.latest.revisionNote {
                                Text(note).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 3)
                    }
                }
                .font(.caption)
            }
        }
    }

    private func evidenceRow(_ label: String, _ amount: Money, defect: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(signedCurrency(amount)).monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(defect ? .orange : .primary)
    }

    private func evidenceRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func chartSummary(_ result: PortfolioHistoryResult) -> String {
        guard let accounting = result.accounting else { return "No published history yet." }
        return "From \(accounting.anchorValue.formatted()) to \(accounting.endValue.formatted()). (summaryValue(for: result, accounting: accounting)). (result.points.count) real points."
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
                    ? value.formatted(.percent.precision(.fractionLength(1)))
                    : value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
            }
        )
        let dateLabels = result.points.map { $0.date.formatted(date: .abbreviated, time: .omitted) }
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
