# frozen_string_literal: true

require "rails_helper"
require_relative "../support/google_helpers"

RSpec.describe "Google", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user) }

  def api_headers(user) = {"Authorization" => "Bearer #{user.api_token!.token}", "Accept" => "application/json"}

  before do
    switch_plugin :google, on: true
    fake_google
  end

  it "is a 404 while the plugin is off" do
    switch_plugin :google, on: false
    sign_in_as admin
    get settings_google_path
    expect(response).to have_http_status(:not_found)
  end

  describe "Settings › Google" do
    before { sign_in_as admin }

    it "saves the OAuth client without reading its secret back, and shows the redirect URI" do
      patch settings_google_path, params: {google: {client_id: "id.apps.googleusercontent.com", client_secret: "shh", services: ["", "search_console", "analytics"]}}
      expect(Google::Settings.current).to have_attributes(client_id: "id.apps.googleusercontent.com", client_secret: "shh", services: %w[search_console analytics])

      get settings_google_path
      expect(response.body).to include("/settings/google/callback", "Connect Google")
      # A link, not a form: the admin's form-action 'self' would stop the redirect to Google.
      expect(Nokogiri::HTML5(response.body).at("a[href$='/settings/google/connection/new']")).to be_present
      expect(response.body).not_to include("shh")
    end

    it "signs in with Google and back, checking the state, then loads what to pick from and syncs" do
      Google::Settings.update("client_id" => "id.apps.googleusercontent.com", "client_secret" => "shh", "services" => %w[search_console analytics business_profile])

      get new_settings_google_connection_path
      location = URI(response.location)
      expect(location.host).to eq("accounts.google.com")
      query = Rack::Utils.parse_query(location.query)
      expect(query).to include("access_type" => "offline", "prompt" => "consent", "client_id" => "id.apps.googleusercontent.com")
      expect(query["scope"]).to include("webmasters.readonly", "analytics.readonly", "business.manage")

      get settings_google_callback_path, params: {code: "4/code", state: "forged"}
      expect(flash[:alert]).to include("didn't start here")
      expect(Google::Settings.current).not_to be_connected

      get new_settings_google_connection_path
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]
      expect { get settings_google_callback_path, params: {code: "4/code", state: state} }.to have_enqueued_job(Google::SyncJob)
      expect(flash[:notice]).to include("owner@acme.example")
      expect(Google::Settings.current).to have_attributes(connected?: true, search_console_site: "sc-domain:acme.example", analytics_property: "properties/42")
      expect(Google::Settings.current.refresh_token).to eq("1//refresh")

      perform_enqueued_jobs { post settings_google_sync_path }
      get settings_google_path
      expect(response.body).to include("280 clicks", "560 sessions", "84 calls")
      expect(response.body).not_to include("1//refresh", "ya29.access")
    end

    it "disconnects" do
      connect_google
      delete settings_google_connection_path
      expect(Google::Settings.current).not_to be_connected
    end
  end

  describe "the API" do
    it "answers each service's data, refuses one that isn't set up, and never reads secrets back" do
      connect_google
      Google::Sync.load_choices
      Google::Sync.run!

      get "/api/google", headers: api_headers(admin)
      expect(response.parsed_body).to include("connected" => true)
      expect(response.parsed_body.dig("search_console", "totals", "clicks")).to eq(280)

      get "/api/google/search_console", headers: api_headers(admin)
      expect(response.parsed_body["striking_distance"].first["keys"]).to eq(["emergency plumber"])
      get "/api/google/analytics", headers: api_headers(admin)
      expect(response.parsed_body["leaky_pages"].first["key"]).to eq("/emergency")
      get "/api/google/business_profile", headers: api_headers(admin)
      expect(response.parsed_body).to include("rating" => 4.6)

      get "/api/google/settings", headers: api_headers(admin)
      expect(response.body).not_to include("shh", "1//refresh")

      Google::Settings.update("services" => %w[search_console])
      get "/api/google/analytics", headers: api_headers(admin)
      expect(response).to have_http_status(:conflict)

      expect { post "/api/google/syncs", headers: api_headers(admin) }.to have_enqueued_job(Google::SyncJob)
    end

    it "is listed in the manifest" do
      get "/api/manifest", headers: api_headers(admin)
      expect(response.body).to include("/api/google/search_console")
    end
  end
end
