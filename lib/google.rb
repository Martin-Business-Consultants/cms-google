# frozen_string_literal: true

require "google/version"
require "google/engine"

# Google for the CMS: one sign-in (Settings › Google) to the business's
# Search Console property, Google Analytics 4 property and Business Profile
# location, synced every night into snapshots that other plugins read
# (Market's report and suggestions, the content calendar's posts) rather
# than each keeping a connection of its own. Installed from its own
# repository; off by default.
module Google
  class Error < StandardError; end

  # Plugin tables are prefixed with the plugin's key.
  def self.table_name_prefix = "google_"

  SERVICES = {
    "search_console" => {name: "Search Console", scope: "https://www.googleapis.com/auth/webmasters.readonly"},
    "analytics" => {name: "Analytics", scope: "https://www.googleapis.com/auth/analytics.readonly"},
    "business_profile" => {name: "Business Profile", scope: "https://www.googleapis.com/auth/business.manage"}
  }.freeze

  # Whether a service is switched on, connected and pointed at a property: `Google.ready?(:search_console)`.
  def self.ready?(service) = Cms::Plugins.enabled?(:google) && Google::Settings.current.ready?(service.to_s)

  # The latest synced data of a service, as Google::SearchConsole, Google::Analytics or Google::BusinessProfile; nil when it isn't ready.
  def self.search_console = ready?(:search_console) ? Google::SearchConsole.new : nil
  def self.analytics = ready?(:analytics) ? Google::Analytics.new : nil
  def self.business_profile = ready?(:business_profile) ? Google::BusinessProfile.new : nil
end
