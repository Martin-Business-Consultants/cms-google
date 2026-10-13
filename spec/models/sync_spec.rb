# frozen_string_literal: true

require "rails_helper"
require_relative "../support/google_helpers"

RSpec.describe Google::Sync do
  before do
    switch_plugin :google, on: true
    fake_google
    connect_google
    described_class.load_choices
  end

  it "loads what to pick from, picking the only one of each" do
    settings = Google::Settings.current
    expect(settings).to have_attributes(search_console_site: "sc-domain:acme.example", analytics_property: "properties/42",
      business_location: "locations/9", business_account: "accounts/1", business_location_name: "Acme Plumbing (Springfield)")
    expect(settings.choices("search_console")).to eq([["acme.example (domain)", "sc-domain:acme.example"]])
  end

  it "syncs Search Console: totals from the days, searches it's close on, pages clicked little" do
    described_class.run!
    console = Google.search_console
    expect(console.totals).to include(clicks: 280, impressions: 11_200, position: 8.0)
    expect(console.totals_before).to include(clicks: 280, impressions: 11_200)
    expect(console.striking_distance.map { it["keys"] }).to eq([["emergency plumber"]])
    expect(console.low_click_pages.map { it["keys"] }).to eq([["https://acme.example/emergency"]])
    expect(console.queries_for("emergency").map { it["keys"][0] }).to eq(["emergency plumber"])
    expect(google_requests.find { it[:url].include?("searchAnalytics") }[:url]).to include("sc-domain%3Aacme.example")
    expect(google_requests.find { it[:url].include?("searchAnalytics") }[:headers]["Authorization"]).to eq("Bearer ya29.access")
  end

  it "syncs Analytics: sessions and key events by day, landing pages beside the period before, and those that convert nobody" do
    described_class.run!
    analytics = Google.analytics
    expect(analytics.totals).to eq(sessions: 560, users: 280, key_events: 28)
    page = analytics.landing_pages.find { it["key"] == "/emergency" }
    expect(page["now"]["sessions"]).to eq(90)
    expect(page["before"]["sessions"]).to eq(60)
    expect(analytics.leaky_pages.map { it["key"] }).to eq(["/emergency"])
  end

  it "syncs Business Profile: views, calls, the searches it was found for, and reviews; and posts to it" do
    described_class.run!
    profile = Google.business_profile
    expect(profile.totals).to include(calls: 84, maps: 84)
    expect(profile.keywords.first).to include("keyword" => "plumber near me", "impressions" => 120)
    expect(profile.reviews).to include("average" => 4.6, "total" => 38)
    expect(profile.unanswered_reviews.size).to eq(1)

    expect(Google::BusinessProfile.post!(summary: "Same-day repairs", url: "https://acme.example/emergency")).to eq("https://local.google.com/place?id=77")
    post = google_requests.last
    expect(post[:url]).to end_with("/v4/accounts/1/locations/9/localPosts")
    expect(post[:body]).to include(summary: "Same-day repairs", callToAction: {actionType: "LEARN_MORE", url: "https://acme.example/emergency"})
  end

  it "keeps going when one service fails, and says why" do
    fake_google(failing: {":runReport" => "Google Analytics Data API has not been used in project 1 before or it is disabled."})
    errors = described_class.run!
    expect(errors.keys).to eq(["analytics"])
    expect(Google::Settings.current.last_sync_errors["analytics"]).to include("Google refused", "Analytics Data API")
    expect(Google.search_console.totals).to be_present
  end

  it "refreshes the access token when it runs out, and says when the sign-in is gone" do
    Google::Settings.remember_access_token("", 0)
    described_class.run!
    expect(google_requests.count { it[:url].include?("oauth2.googleapis.com/token") }).to be >= 1

    Google::Settings.remember_access_token("", 0)
    Google::Client.transport = ->(*) { [400, JSON.generate("error" => "invalid_grant")] }
    expect(described_class.run!["search_console"]).to include("connect it again")
  end
end
