# frozen_string_literal: true

module Google
  # Syncs every ready service now, in the background.
  class SyncsController < ::Settings::BaseController
    include PluginGated
    plugin :google

    requires_capability "settings:write", only: :create

    def create
      Google::Settings.remember("syncing_since" => Time.current.iso8601)
      Google::SyncJob.perform_later
      redirect_to settings_google_path, notice: "Syncing: a minute or so"
    end
  end
end
