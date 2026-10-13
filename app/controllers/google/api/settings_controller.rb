# frozen_string_literal: true

module Google
  module Api
    # GET|PATCH /api/google/settings (the client secret and tokens are never read back).
    class SettingsController < BaseController
      requires_capability "settings:read", only: :show
      requires_capability "settings:write", only: :update

      def show
        render json: Google::Settings.current.to_h
      end

      def update
        settings = Google::Settings.update(params.require(:settings).permit(:client_id, :client_secret, :search_console_site, :analytics_property, :business_location, services: []))
        Event.record("settings.google_updated")
        render json: settings.to_h
      end
    end
  end
end
