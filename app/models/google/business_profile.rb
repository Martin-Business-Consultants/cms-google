# frozen_string_literal: true

# The Google Business Profile location picked in Settings › Google: how
# often it's seen on Maps and Search and what people do (calls, website
# clicks, directions, bookings), by day for 90 days; the searches it was
# found for, by month; and its reviews. It can also publish a post to the
# profile (the content calendar does). Google grants the Business Profile
# APIs to a Cloud project on request; until then they answer 403 or 429.
class Google::BusinessProfile
  SERVICE = "business_profile"
  ACCOUNTS = "https://mybusinessaccountmanagement.googleapis.com/v1/accounts"
  INFO = "https://mybusinessbusinessinformation.googleapis.com/v1"
  PERFORMANCE = "https://businessprofileperformance.googleapis.com/v1"
  V4 = "https://mybusiness.googleapis.com/v4"
  METRICS = {
    "BUSINESS_IMPRESSIONS_MOBILE_MAPS" => "maps", "BUSINESS_IMPRESSIONS_DESKTOP_MAPS" => "maps",
    "BUSINESS_IMPRESSIONS_MOBILE_SEARCH" => "search", "BUSINESS_IMPRESSIONS_DESKTOP_SEARCH" => "search",
    "CALL_CLICKS" => "calls", "WEBSITE_CLICKS" => "website", "BUSINESS_DIRECTION_REQUESTS" => "directions",
    "BUSINESS_BOOKINGS" => "bookings", "BUSINESS_CONVERSATIONS" => "messages"
  }.freeze
  STARS = {"ONE" => 1, "TWO" => 2, "THREE" => 3, "FOUR" => 4, "FIVE" => 5}.freeze

  # [[label, "locations/2", "accounts/1"]] to pick from.
  def self.choices(client)
    Array(client.get(ACCOUNTS)["accounts"]).flat_map do |account|
      Array(client.get("#{INFO}/#{account["name"]}/locations", readMask: "name,title,storefrontAddress", pageSize: 100)["locations"]).map do |location|
        town = location.dig("storefrontAddress", "locality")
        ["#{location["title"]}#{" (#{town})" if town}", location["name"], account["name"]]
      end
    end.sort
  end

  def self.sync(client, location, account)
    ends = Date.yesterday
    starts = ends - 89
    range = {"dailyRange.start_date.year" => starts.year, "dailyRange.start_date.month" => starts.month, "dailyRange.start_date.day" => starts.day,
             "dailyRange.end_date.year" => ends.year, "dailyRange.end_date.month" => ends.month, "dailyRange.end_date.day" => ends.day}
    query = URI.encode_www_form(METRICS.keys.map { ["dailyMetrics", it] } + range.to_a)
    answer = client.get("#{PERFORMANCE}/#{location}:fetchMultiDailyMetricsTimeSeries?#{query}")
    days = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    Array(answer["multiDailyMetricTimeSeries"]).flat_map { Array(it["dailyMetricTimeSeries"]) }.each do |series|
      Array(series.dig("timeSeries", "datedValues")).each do |point|
        date = Date.new(point.dig("date", "year"), point.dig("date", "month"), point.dig("date", "day")).iso8601
        days[date][METRICS.fetch(series["dailyMetric"], series["dailyMetric"].downcase)] += point["value"].to_i
      end
    end
    Google::Snapshot.keep(SERVICE, "daily", days.sort.map { |date, values| {"date" => date, **values} }, target: location, starts_on: starts, ends_on: ends)

    month = Date.current.prev_month
    keywords = client.get("#{PERFORMANCE}/#{location}/searchkeywords/impressions/monthly",
      "monthlyRange.start_month.year" => (month << 2).year, "monthlyRange.start_month.month" => (month << 2).month,
      "monthlyRange.end_month.year" => month.year, "monthlyRange.end_month.month" => month.month, :pageSize => 100)
    Google::Snapshot.keep(SERVICE, "keywords", Array(keywords["searchKeywordsCounts"]).map { {"keyword" => it["searchKeyword"],
      "impressions" => it.dig("insightsValue", "value").to_i, "below" => it.dig("insightsValue", "threshold")&.to_i} }, target: location)

    reviews = client.get("#{V4}/#{account}/#{location}/reviews", pageSize: 50, orderBy: "updateTime desc")
    Google::Snapshot.keep(SERVICE, "reviews", {"average" => reviews["averageRating"], "total" => reviews["totalReviewCount"],
      "reviews" => Array(reviews["reviews"]).map { {"name" => it["name"], "reviewer" => it.dig("reviewer", "displayName"), "stars" => STARS[it["starRating"]],
        "comment" => it["comment"], "at" => it["createTime"], "replied" => it["reviewReply"].present?} }}, target: location)
  end

  # Publishes a post to the profile; answers its address on Google. `image_url` must be public.
  def self.post!(summary:, url: nil, image_url: nil, client: Google::Client.new)
    settings = Google::Settings.current
    raise Google::Error, "Business Profile isn't set up in Settings › Google" unless Google.ready?(:business_profile)

    body = {languageCode: "en", summary: summary.to_s.truncate(1500), topicType: "STANDARD"}
    body[:callToAction] = {actionType: "LEARN_MORE", url: url} if url.present?
    body[:media] = [{mediaFormat: "PHOTO", sourceUrl: image_url}] if image_url.present?
    answer = client.post("#{V4}/#{settings.business_account}/#{settings.business_location}/localPosts", body)
    answer["searchUrl"] || answer["name"]
  end

  def location = Google::Settings.current.business_location
  def location_name = Google::Settings.current.business_location_name
  def synced_at = snapshot("daily")&.taken_at

  # [{"date", "maps", "search", "calls", "website", "directions", …}].
  def daily = Array(snapshot("daily")&.data)

  def totals = sum(daily.last(28))
  def totals_before = (daily.size > 28) ? sum(daily.first(daily.size - 28).last(28)) : nil
  def keywords = Array(snapshot("keywords")&.data)
  def reviews = snapshot("reviews")&.data.to_h
  def unanswered_reviews = Array(reviews["reviews"]).reject { it["replied"] }

  def to_h
    {location: location, location_name: location_name, synced_at: synced_at, totals: totals, totals_before: totals_before,
     daily: daily, keywords: keywords.first(50), rating: reviews["average"], reviews_total: reviews["total"],
     reviews: Array(reviews["reviews"]).first(20), unanswered_reviews: unanswered_reviews.size}
  end

  private

  def snapshot(kind) = (@snapshots ||= {})[kind] ||= Google::Snapshot.latest(SERVICE, kind)

  def sum(days)
    return nil if days.empty?

    %w[maps search calls website directions bookings messages].index_with { |metric| days.sum { it[metric].to_i } }.symbolize_keys
  end
end
