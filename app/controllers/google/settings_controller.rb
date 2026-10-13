# frozen_string_literal: true

module Google
  # Settings › Google (Google::Settings).
  class SettingsController < ::Settings::BaseController
    include PluginGated
    plugin :google

    requires_capability "settings:read", only: :show
    requires_capability "settings:write", only: :update

    def show
      @settings = Google::Settings.current
      @search_console = Google::SearchConsole.new if @settings.ready?("search_console")
      @analytics = Google::Analytics.new if @settings.ready?("analytics")
      @business_profile = Google::BusinessProfile.new if @settings.ready?("business_profile")
    end

    def update
      before = Google::Settings.current
      settings = Google::Settings.update(params.require(:google).permit(:client_id, :client_secret, :search_console_site, :analytics_property, :business_location, services: []))
      Event.record("settings.google_updated")
      notice = (settings.connected? && settings.services.any? { !before.granted?(it) && settings.service?(it) }) ? "Saved. Connect Google again to grant the services added" : "Saved"
      Google::SyncJob.perform_later if settings.connected? && Google::SERVICES.keys.any? { settings.ready?(it) && settings.target(it) != before.target(it) }
      redirect_to settings_google_path, notice: notice
    end
  end
end
