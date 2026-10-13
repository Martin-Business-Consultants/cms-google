# frozen_string_literal: true

module Google
  # Loads the properties and locations to pick from again.
  class ChoicesController < ::Settings::BaseController
    include PluginGated
    plugin :google

    requires_capability "settings:write", only: :create

    def create
      errors = Google::Sync.load_choices
      redirect_to settings_google_path, (errors.any? ? :alert : :notice) => (errors.any? ? errors.values.to_sentence : "Lists loaded")
    rescue Google::Error => error
      redirect_to settings_google_path, alert: error.message
    end
  end
end
