import SwiftUI
import Charts

struct GroupStatsView: View {
    let expenses: [Expense]
    let members:  [User]
    let currency: String

    // MARK: - Derived Data

    private var totalSpend: Decimal {
        expenses.reduce(.zero) { $0 + $1.amount }
    }

    private var categoryData: [(category: Expense.Category, total: Decimal)] {
        Dictionary(grouping: expenses, by: \.category)
            .mapValues { $0.reduce(.zero) { $0 + $1.amount } }
            .map { ($0.key, $0.value) }
            .sorted { $0.total > $1.total }
    }

    private var monthlyData: [(month: Date, total: Decimal)] {
        let cal = Calendar.current
        return Dictionary(grouping: expenses) { expense -> Date in
            cal.dateInterval(of: .month, for: expense.createdAt)?.start ?? expense.createdAt
        }
        .map { (month: $0.key, total: $0.value.reduce(.zero) { $0 + $1.amount }) }
        .sorted { $0.month < $1.month }
        .suffix(6)
        .map { $0 }
    }

    private var memberData: [(name: String, total: Decimal)] {
        let nameMap = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
        return Dictionary(grouping: expenses, by: \.payerID)
            .mapValues { $0.reduce(.zero) { $0 + $1.amount } }
            .map { (name: nameMap[$0.key] ?? "Unknown", total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    // MARK: - Body

    var body: some View {
        List {
            summaryHeader

            if !categoryData.isEmpty {
                categorySection
            }

            if monthlyData.count > 1 {
                monthlySection
            }

            if !memberData.isEmpty {
                memberSection
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        Section {
            VStack(spacing: 6) {
                Text("Total Spent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(totalSpend.formatted(currencyCode: currency))
                    .font(.largeTitle.bold())
                Text("\(expenses.count) expense\(expenses.count == 1 ? "" : "s") across \(categoryData.count) categor\(categoryData.count == 1 ? "y" : "ies")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Category Donut Chart

    private var categorySection: some View {
        Section("By Category") {
            Chart(categoryData, id: \.category) { item in
                SectorMark(
                    angle: .value("Amount", item.total.chartValue),
                    innerRadius: .ratio(0.55),
                    angularInset: 2
                )
                .foregroundStyle(item.category.chartColor)
                .cornerRadius(4)
            }
            .frame(height: 200)
            .padding(.vertical, 8)

            ForEach(categoryData, id: \.category) { item in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.category.chartColor)
                        .frame(width: 12, height: 12)
                    Label(item.category.displayName, systemImage: item.category.systemImage)
                        .font(.subheadline)
                    Spacer()
                    Text(item.total.formatted(currencyCode: currency))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Monthly Bar Chart

    private var monthlySection: some View {
        Section("Monthly Spending") {
            Chart(monthlyData, id: \.month) { item in
                BarMark(
                    x: .value("Month", item.month, unit: .month),
                    y: .value("Amount", item.total.chartValue)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(Decimal(d).formatted(currencyCode: currency))
                                .font(.caption2)
                        }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 180)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Per-Member Bar Chart

    private var memberSection: some View {
        Section("Paid By Member") {
            Chart(memberData, id: \.name) { item in
                BarMark(
                    x: .value("Amount", item.total.chartValue),
                    y: .value("Member", item.name)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(item.total.formatted(currencyCode: currency))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: max(100, CGFloat(memberData.count) * 48))
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Decimal chart helper

private extension Decimal {
    var chartValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

// MARK: - Category chart color

extension Expense.Category {
    var chartColor: Color {
        switch self {
        case .food:          return .orange
        case .transport:     return .blue
        case .accommodation: return .purple
        case .entertainment: return .pink
        case .utilities:     return .yellow
        case .shopping:      return .green
        case .health:        return .red
        case .other:         return .gray
        }
    }
}

#Preview {
    NavigationStack {
        GroupStatsView(
            expenses: [
                Expense(id: UUID(), groupID: UUID(), title: "Dinner", amount: 80, currency: "USD",
                        payerID: UUID(), category: .food, notes: nil, receiptURL: nil, recurrence: .none, createdAt: Date()),
                Expense(id: UUID(), groupID: UUID(), title: "Taxi", amount: 30, currency: "USD",
                        payerID: UUID(), category: .transport, notes: nil, receiptURL: nil, recurrence: .none, createdAt: Date())
            ],
            members: [],
            currency: "USD"
        )
    }
}
