# frozen_string_literal: true

module Google
  # Connecting Google: off to Google's sign-in with the chosen services
  # (create), and forgetting the sign-in (destroy).
  class ConnectionsController < ::Settings::BaseController
    include PluginGated
    plugin :google

    requires_capability "settings:write", only: [:create, :destroy]

    def create
      settings = Google::Settings.current
      return redirect_to(settings_google_path, alert: "Add the OAuth client's ID and secret first") unless settings.client?

      session[:google_oauth_state] = SecureRandom.urlsafe_base64(24)
      redirect_to Google::Client.new(settings: settings).authorize_url(redirect_uri: settings_google_callback_url, state: session[:google_oauth_state]),
        allow_other_host: true
    end

    def destroy
      Google::Settings.disconnect
      Event.record("settings.google_disconnected")
      redirect_to settings_google_path, notice: "Google disconnected"
    end
  end
end
