# frozen_string_literal: true

module Google
  # Where Google sends the person back after signing in: the code exchanged
  # for a refresh token, then the properties and locations loaded to pick from.
  class CallbacksController < ::Settings::BaseController
    include PluginGated
    plugin :google

    requires_capability "settings:write", only: :show

    def show
      state = session.delete(:google_oauth_state)
      return redirect_to(settings_google_path, alert: "Google said: #{params[:error].to_s.humanize}") if params[:error].present?
      return redirect_to(settings_google_path, alert: "That sign-in didn't start here; connect again") if state.blank? || !ActiveSupport::SecurityUtils.secure_compare(state, params[:state].to_s)

      answer = Google::Client.new.exchange(code: params.require(:code), redirect_uri: settings_google_callback_url)
      Google::Settings.connect(**answer)
      Event.record("settings.google_connected")
      errors = Google::Sync.load_choices
      Google::SyncJob.perform_later
      redirect_to settings_google_path, notice: "Connected as #{answer[:email] || "your Google account"}#{". Some lists couldn't load" if errors.any?}"
    rescue Google::Error => error
      redirect_to settings_google_path, alert: error.message
    end
  end
end
