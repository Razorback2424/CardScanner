import Accessibility
import Charts
import SwiftUI
import UIKit

struct PortfolioHistoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var history: PortfolioHistoryStore

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
                historyChart(result)

                if let disclosure = PortfolioHistoryDisplay.availableHistoryDisclosure(for: result) {
                    Text(disclosure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                } else if result.range != .oneDay, !result.hasTwoPublishedPoints {
                    Text("History is being recorded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

            } else {
                Text("History is being recorded.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: history.range)
        .onChange(of: history.range) { _, _ in
            resetSelection()
        }
        .onDisappear {
            resetSelection()
        }
    }

    /// The date rail sits *inside* the plot rather than under it, so the chart
    /// block is exactly its stated height and the range chips below it are not
    /// pushed down by a caption row.
    @ViewBuilder
    private func historyChart(_ result: PortfolioHistoryResult) -> some View {
        historyChartPlot(result)
            .frame(height: 196)
            .overlay(alignment: .bottom) {
                HStack {
                    if let firstPoint = result.points.first {
                        Text(firstPoint.displayDay.formatted(.dateTime.month(.abbreviated).day()))
                    }
                    Spacer()
                    if let lastPoint = result.points.last {
                        Text(
                            lastPoint.isLive
                                ? "today"
                                : lastPoint.displayDay.formatted(.dateTime.month(.abbreviated).day())
                        )
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private func historyChartPlot(_ result: PortfolioHistoryResult) -> some View {
        let selectionID = selectedID(in: result)
        let domain = yDomain(result)
        Chart {
            if let anchor = result.accounting?.anchorValue {
                RuleMark(y: .value("Period start", anchor.doubleValue))
                    .foregroundStyle(.secondary.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            ForEach(result.points) { point in
                historyLine(point, result: result, selectionID: selectionID)
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
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
        let periodStart = result.accounting?.anchorValue.doubleValue
            ?? result.points.first?.value.doubleValue
            ?? chartValue(point, in: result)
        AreaMark(
            x: .value("Date", point.instant),
            yStart: .value("Period start", periodStart),
            yEnd: .value("Market movement", chartValue(point, in: result))
        )
        .foregroundStyle(areaGradient(result))

        LineMark(
            x: .value("Date", point.instant),
            y: .value(
                "Market movement",
                chartValue(point, in: result)
            )
        )
        .foregroundStyle(seriesColor(result))
        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

        if let selectionID, point.id == selectionID {
            PointMark(
                x: .value("Date", point.instant),
                y: .value(
                    "Market movement",
                    chartValue(point, in: result)
                )
            )
            .foregroundStyle(seriesColor(result))
            RuleMark(x: .value("Selected date", point.instant))
                .foregroundStyle(.secondary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
        }
    }

    /// The line colour agrees with the hero's market movement.
    private func seriesColor(_ result: PortfolioHistoryResult) -> Color {
        PortfolioPalette.direction(result.accounting?.market ?? .zero)
    }

    /// The fill is densest against the plotted line and fades toward the
    /// period-start baseline. On a losing period the band hangs *below* that
    /// baseline, so the stops invert — otherwise the density would sit on the
    /// baseline and the shading would look detached from the line it belongs to.
    private func areaGradient(_ result: PortfolioHistoryResult) -> LinearGradient {
        let color = seriesColor(result)
        // 0 / 0.55 / 1 — the fade holds longer near the line than an even
        // three-stop ramp would.
        let stops = [
            Gradient.Stop(color: color.opacity(0.26), location: 0),
            Gradient.Stop(color: color.opacity(0.09), location: 0.55),
            Gradient.Stop(color: color.opacity(0), location: 1)
        ]
        let isLosing = (result.accounting?.market ?? .zero) < .zero
        let ordered = isLosing
            ? stops.reversed().enumerated().map { index, stop in
                Gradient.Stop(color: stop.color, location: [0, 0.45, 1][index])
            }
            : stops
        return .linearGradient(
            stops: ordered,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func selectedID(in result: PortfolioHistoryResult) -> String? {
        guard let selectedPointID,
              result.points.contains(where: { $0.id == selectedPointID }) else { return nil }
        return selectedPointID
    }

    private func resetSelection() {
        selectedPointID = nil
        lastHapticPointID = nil
    }

    private func chartValue(
        _ point: PortfolioHistoryPoint,
        in result: PortfolioHistoryResult
    ) -> Double {
        guard let anchorValue = result.accounting?.anchorValue else {
            return point.value.doubleValue
        }
        return (anchorValue + point.cumulativeMarketMovement).doubleValue
    }

    private func yDomain(_ result: PortfolioHistoryResult) -> ClosedRange<Double> {
        let values = result.points.map { chartValue($0, in: result) }
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        if minimum == maximum { return (minimum - 1)...(maximum + 1) }
        let padding = max((maximum - minimum) * 0.12, 1)
        return (minimum - padding)...(maximum + padding)
    }

    private func chartSummary(_ result: PortfolioHistoryResult) -> String {
        guard let first = result.points.first,
              let last = result.points.last else {
            return "No published history yet."
        }
        let firstValue = result.accounting?.anchorValue ?? first.value
        let lastValue = result.accounting.map {
            $0.anchorValue + last.cumulativeMarketMovement
        } ?? last.value
        return "Market movement from \(firstValue.formatted()) to \(lastValue.formatted()) across \(result.points.count) real points."
    }

}

private struct PortfolioChartDescriptor: AXChartDescriptorRepresentable {
    let result: PortfolioHistoryResult

    func makeChartDescriptor() -> AXChartDescriptor {
        let pointValues = result.points.map { point in
            result.accounting.map {
                ($0.anchorValue + point.cumulativeMarketMovement).doubleValue
            } ?? point.value.doubleValue
        }
        let lower = pointValues.min() ?? 0
        let upper = pointValues.max() ?? 0
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
                ? "Market movement today"
                : "Market movement on \($0.displayDay.formatted(date: .abbreviated, time: .omitted))"
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
            summary: chartSummary,
            xAxis: xAxis,
            yAxis: yAxis,
            series: [series]
        )
    }

    private func valueDescription(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private var chartSummary: String {
        guard let first = result.points.first,
              let last = result.points.last else {
            return "No published history yet."
        }
        let firstValue = result.accounting?.anchorValue ?? first.value
        let lastValue = result.accounting.map {
            $0.anchorValue + last.cumulativeMarketMovement
        } ?? last.value
        return "Market movement from \(firstValue.formatted()) to \(lastValue.formatted()) across \(result.points.count) real points."
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
