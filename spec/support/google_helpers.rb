# frozen_string_literal: true

# Google, answered without the network: each request is matched by a
# fragment of its address, and recorded.
module GoogleHelpers
  ANSWERS = {
    "oauth2.googleapis.com/token" => {"access_token" => "ya29.access", "expires_in" => 3599, "refresh_token" => "1//refresh",
                                      "scope" => "openid email https://www.googleapis.com/auth/webmasters.readonly https://www.googleapis.com/auth/analytics.readonly https://www.googleapis.com/auth/business.manage"},
    "openidconnect.googleapis.com/v1/userinfo" => {"email" => "owner@acme.example"},
    "webmasters/v3/sites/" => :search_analytics,
    "webmasters/v3/sites" => {"siteEntry" => [{"siteUrl" => "sc-domain:acme.example", "permissionLevel" => "siteOwner"}]},
    "accountSummaries" => {"accountSummaries" => [{"displayName" => "Acme", "propertySummaries" => [{"property" => "properties/42", "displayName" => "acme.example"}]}]},
    ":runReport" => :run_report,
    "mybusinessaccountmanagement.googleapis.com/v1/accounts" => {"accounts" => [{"name" => "accounts/1", "accountName" => "Acme"}]},
    "/locations?" => {"locations" => [{"name" => "locations/9", "title" => "Acme Plumbing", "storefrontAddress" => {"locality" => "Springfield"}}]},
    ":fetchMultiDailyMetricsTimeSeries" => :performance,
    "searchkeywords/impressions/monthly" => {"searchKeywordsCounts" => [{"searchKeyword" => "plumber near me", "insightsValue" => {"value" => "120"}}]},
    "/reviews" => {"averageRating" => 4.6, "totalReviewCount" => 38, "reviews" => [{"name" => "r1", "reviewer" => {"displayName" => "Pat"}, "starRating" => "FIVE", "comment" => "Fast", "createTime" => "2026-10-01T00:00:00Z"}]},
    "/localPosts" => {"name" => "accounts/1/locations/9/localPosts/77", "searchUrl" => "https://local.google.com/place?id=77"}
  }.freeze

  def google_requests = (@google_requests ||= [])

  def fake_google(failing: {})
    Google::Client.transport = lambda do |method, url, headers, body|
      google_requests << {method: method, url: url, headers: headers, body: body}
      fragment = failing.keys.find { url.include?(it) }
      next [403, JSON.generate({"error" => {"message" => failing[fragment]}})] if fragment

      _, answer = ANSWERS.find { |key, _| url.include?(key) }
      answer = send(:"google_#{answer}", body) if answer.is_a?(Symbol)
      answer ? [200, JSON.generate(answer)] : [404, "{}"]
    end
  end

  def connect_google(services: %w[search_console analytics business_profile])
    Google::Settings.update("client_id" => "id.apps.googleusercontent.com", "client_secret" => "shh", "services" => services)
    Google::Settings.connect(refresh_token: "1//refresh", email: "owner@acme.example", scopes: GoogleHelpers::ANSWERS.dig("oauth2.googleapis.com/token", "scope").split)
  end

  def google_search_analytics(body)
    dimensions = body[:dimensions]
    if dimensions == %w[date]
      {"rows" => (1..60).map { {"keys" => [(Date.current - 3 - it).iso8601], "clicks" => 10, "impressions" => 400, "ctr" => 0.025, "position" => 8.0} }}
    elsif dimensions == %w[query]
      {"rows" => [{"keys" => ["emergency plumber"], "clicks" => 12, "impressions" => 900, "ctr" => 0.013, "position" => 9.4},
        {"keys" => ["acme plumbing"], "clicks" => 80, "impressions" => 120, "ctr" => 0.66, "position" => 1.1}]}
    elsif dimensions == %w[page]
      {"rows" => [{"keys" => ["https://acme.example/emergency"], "clicks" => 3, "impressions" => 1500, "ctr" => 0.002, "position" => 6.0}]}
    else
      {"rows" => [{"keys" => ["emergency plumber", "https://acme.example/emergency"], "clicks" => 3, "impressions" => 700, "ctr" => 0.004, "position" => 7.0}]}
    end
  end

  def google_run_report(body)
    dimension = body[:dimensions].first[:name]
    metrics = ->(sessions, events) { [{"value" => sessions.to_s}, {"value" => (sessions / 2).to_s}, {"value" => events.to_s}, {"value" => "0.6"}] }
    if dimension == "date"
      {"dimensionHeaders" => [{"name" => "date"}], "rows" => (1..40).map { {"dimensionValues" => [{"value" => (Date.current - it).strftime("%Y%m%d")}], "metricValues" => metrics.call(20, 1)} }}
    else
      {"dimensionHeaders" => [{"name" => dimension}, {"name" => "dateRange"}],
       "rows" => [{"dimensionValues" => [{"value" => "/emergency"}, {"value" => "now"}], "metricValues" => metrics.call(90, 0)},
         {"dimensionValues" => [{"value" => "/emergency"}, {"value" => "before"}], "metricValues" => metrics.call(60, 0)},
         {"dimensionValues" => [{"value" => "/"}, {"value" => "now"}], "metricValues" => metrics.call(300, 12)}]}
    end
  end

  def google_performance(_body)
    days = (1..40).map { Date.current - it }
    {"multiDailyMetricTimeSeries" => [{"dailyMetricTimeSeries" => %w[CALL_CLICKS BUSINESS_IMPRESSIONS_MOBILE_MAPS].map do |metric|
      {"dailyMetric" => metric, "timeSeries" => {"datedValues" => days.map { {"date" => {"year" => it.year, "month" => it.month, "day" => it.day}, "value" => "3"} }}}
    end}]}
  end
end

RSpec.configure do |config|
  config.include GoogleHelpers
  config.after { Google::Client.transport = nil }
end
