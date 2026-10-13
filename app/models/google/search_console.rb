# frozen_string_literal: true

# Search Console for the property picked in Settings › Google: what people
# searched to find the site, its clicks, impressions, click-through rate
# and average position, by day, by query, by page and by both, for the last
# 28 days beside the 28 before (Search Console's data runs ~3 days behind).
# Read from the latest snapshots; synced by Google::Sync.
class Google::SearchConsole
  SERVICE = "search_console"
  API = "https://www.googleapis.com/webmasters/v3/sites"
  LAG = 3
  PERIOD = 28

  # [[label, site url]] to pick from.
  def self.choices(client)
    Array(client.get(API)["siteEntry"]).reject { it["permissionLevel"] == "siteUnverifiedUser" }
      .map { |entry| [entry["siteUrl"].start_with?("sc-domain:") ? "#{entry["siteUrl"].delete_prefix("sc-domain:")} (domain)" : entry["siteUrl"], entry["siteUrl"]] }.sort
  end

  def self.sync(client, site)
    ends = Date.current - LAG
    starts = ends - (PERIOD - 1)
    before = [starts - PERIOD, starts - 1]
    query = ->(dimensions, from, to, limit) { rows(client, site, dimensions, from, to, limit) }

    Google::Snapshot.keep(SERVICE, "daily", query.call(%w[date], ends - 89, ends, 100), target: site, starts_on: ends - 89, ends_on: ends)
    {"queries" => %w[query], "pages" => %w[page]}.each do |kind, dimensions|
      now = query.call(dimensions, starts, ends, 500)
      was = query.call(dimensions, *before, 1000).index_by { it["keys"] }
      data = now.map { it.merge("before" => was[it["keys"]]&.slice("clicks", "impressions", "ctr", "position")) }
      Google::Snapshot.keep(SERVICE, kind, data, target: site, starts_on: starts, ends_on: ends)
    end
    Google::Snapshot.keep(SERVICE, "query_pages", query.call(%w[query page], starts, ends, 1000), target: site, starts_on: starts, ends_on: ends)
  end

  def self.rows(client, site, dimensions, from, to, limit)
    answer = client.post("#{API}/#{ERB::Util.url_encode(site)}/searchAnalytics/query",
      {startDate: from.iso8601, endDate: to.iso8601, dimensions: dimensions, rowLimit: limit, type: "web"})
    Array(answer["rows"]).map { it.slice("keys", "clicks", "impressions", "ctr", "position") }
  end

  def site = Google::Settings.current.search_console_site
  def synced_at = snapshot("daily")&.taken_at
  def period = snapshot("queries")&.then { [it.starts_on, it.ends_on] }

  # Clicks and impressions by day: [[Date, clicks, impressions, position]].
  def daily = Array(snapshot("daily")&.data).map { [Date.parse(it["keys"][0]), it["clicks"].to_i, it["impressions"].to_i, it["position"].to_f.round(1)] }

  # The last 28 days and the 28 before, from the daily figures (which, unlike the queries, count the searches Google keeps private): {clicks:, impressions:, ctr:, position:}.
  def totals = sum(daily.last(PERIOD))
  def totals_before = (daily.size > PERIOD) ? sum(daily.last(PERIOD * 2).first(daily.size.clamp(0, PERIOD * 2) - PERIOD)) : nil

  def queries = rows_of("queries")
  def pages = rows_of("pages")
  def query_pages = rows_of("query_pages")

  # Searches it's close on: on average 4th to 20th, with impressions to win.
  def striking_distance(limit: 25)
    queries.select { it["position"].to_f.between?(4, 20) && it["impressions"].to_i >= 20 }.sort_by { -it["impressions"].to_i }.first(limit)
  end

  # Pages shown a lot but clicked little for where they sit: the title and meta description to rewrite.
  def low_click_pages(limit: 15)
    pages.select { it["impressions"].to_i >= 100 && it["ctr"].to_f < expected_ctr(it["position"]) * 0.6 }.sort_by { -it["impressions"].to_i }.first(limit)
  end

  # The searches a page is found for.
  def queries_for(path, limit: 15)
    query_pages.select { page_path(it["keys"][1]) == path.to_s.delete_prefix("/") }.sort_by { -it["impressions"].to_i }.first(limit)
  end

  # Roughly the share of clicks a result gets at a position.
  def expected_ctr(position)
    position = position.to_f
    if position <= 1.5 then 0.3
    elsif position <= 3 then 0.15
    elsif position <= 5 then 0.07
    elsif position <= 10 then 0.03
    else 0.01
    end
  end

  def page_path(url)
    URI.parse(url.to_s).path.to_s.delete_prefix("/").chomp("/").presence || "home"
  rescue URI::InvalidURIError
    nil
  end

  def to_h
    {site: site, synced_at: synced_at, period: period, totals: totals, totals_before: totals_before,
     daily: daily.map { |date, clicks, impressions, position| {date: date, clicks: clicks, impressions: impressions, position: position} },
     queries: queries.first(100), pages: pages.first(100), striking_distance: striking_distance, low_click_pages: low_click_pages}
  end

  private

  def snapshot(kind) = (@snapshots ||= {})[kind] ||= Google::Snapshot.latest(SERVICE, kind)
  def rows_of(kind) = Array(snapshot(kind)&.data).map { it.merge("key" => Array(it["keys"]).join(" · ")) }

  # Days ([date, clicks, impressions, position]) added up.
  def sum(days)
    return nil if days.empty?

    clicks = days.sum { it[1] }
    impressions = days.sum { it[2] }
    {clicks: clicks, impressions: impressions, ctr: impressions.positive? ? (clicks.to_f / impressions).round(4) : 0,
     position: impressions.positive? ? (days.sum { it[3] * it[2] } / impressions).round(1) : nil}
  end
end
