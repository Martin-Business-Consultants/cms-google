# frozen_string_literal: true

# Google Analytics 4 for the property picked in Settings › Google: sessions,
# users, key events (what GA4 now calls conversions) and engagement by day for
# 90 days, by channel and by landing page for the last 28 beside the 28
# before. Read from the latest snapshots; synced by Google::Sync.
class Google::Analytics
  SERVICE = "analytics"
  ADMIN = "https://analyticsadmin.googleapis.com/v1beta/accountSummaries"
  DATA = "https://analyticsdata.googleapis.com/v1beta"
  METRICS = %w[sessions totalUsers keyEvents engagementRate].freeze

  # [[label, "properties/123"]] to pick from.
  def self.choices(client)
    Array(client.get(ADMIN, pageSize: 200)["accountSummaries"]).flat_map do |account|
      Array(account["propertySummaries"]).map { ["#{it["displayName"]} (#{account["displayName"]})", it["property"]] }
    end.sort
  end

  def self.sync(client, property)
    report = ->(dimension, ranges, limit) { rows(client, property, dimension, ranges, limit) }
    Google::Snapshot.keep(SERVICE, "daily", report.call("date", [{startDate: "90daysAgo", endDate: "yesterday"}], 100), target: property,
      starts_on: Date.current - 90, ends_on: Date.yesterday)
    ranges = [{startDate: "28daysAgo", endDate: "yesterday", name: "now"}, {startDate: "56daysAgo", endDate: "29daysAgo", name: "before"}]
    {"channels" => "sessionDefaultChannelGroup", "landing_pages" => "landingPage", "sources" => "sessionSourceMedium"}.each do |kind, dimension|
      Google::Snapshot.keep(SERVICE, kind, report.call(dimension, ranges, 250), target: property, starts_on: Date.current - 28, ends_on: Date.yesterday)
    end
  end

  # Rows as {"key", "now" => {metric => value}, "before" => {…}}; one range gives "now" only.
  def self.rows(client, property, dimension, ranges, limit)
    answer = client.post("#{DATA}/#{property}:runReport", {dimensions: [{name: dimension}], metrics: METRICS.map { {name: it} },
                                                           dateRanges: ranges, limit: limit, keepEmptyRows: false})
    names = Array(answer["dimensionHeaders"]).map { it["name"] }
    Array(answer["rows"]).group_by { it["dimensionValues"][names.index(dimension) || 0]["value"] }.map do |key, rows|
      by_range = rows.to_h do |row|
        range = names.include?("dateRange") ? row["dimensionValues"][names.index("dateRange")]["value"] : "now"
        [range, METRICS.each_with_index.to_h { |metric, index| [metric, row["metricValues"][index]["value"].to_f] }]
      end
      {"key" => key, "now" => by_range["now"] || METRICS.to_h { [it, 0.0] }, "before" => by_range["before"]}
    end.sort_by { -it["now"]["sessions"] }
  end

  def property = Google::Settings.current.analytics_property
  def property_name = Google::Settings.current.analytics_property_name
  def synced_at = snapshot("daily")&.taken_at

  # [[Date, sessions, users, key events]].
  def daily
    Array(snapshot("daily")&.data).map { [Date.strptime(it["key"], "%Y%m%d"), it["now"]["sessions"].to_i, it["now"]["totalUsers"].to_i, it["now"]["keyEvents"].to_i] }.sort_by(&:first)
  end

  def totals = sum(daily.last(28))
  def totals_before = (daily.size > 28) ? sum(daily.first(daily.size - 28).last(28)) : nil
  def channels = Array(snapshot("channels")&.data)
  def landing_pages = Array(snapshot("landing_pages")&.data)
  def sources = Array(snapshot("sources")&.data)

  # Landing pages with visits but no key events: where the site loses people.
  def leaky_pages(limit: 10) = landing_pages.select { it["now"]["sessions"] >= 30 && it["now"]["keyEvents"].zero? }.first(limit)

  def to_h
    {property: property, property_name: property_name, synced_at: synced_at, totals: totals, totals_before: totals_before,
     daily: daily.map { |date, sessions, users, events| {date: date, sessions: sessions, users: users, key_events: events} },
     channels: channels, landing_pages: landing_pages.first(50), sources: sources.first(30), leaky_pages: leaky_pages}
  end

  private

  def snapshot(kind) = (@snapshots ||= {})[kind] ||= Google::Snapshot.latest(SERVICE, kind)

  def sum(days)
    return nil if days.empty?

    {sessions: days.sum { it[1] }, users: days.sum { it[2] }, key_events: days.sum { it[3] }}
  end
end
