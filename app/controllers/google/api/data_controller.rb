# frozen_string_literal: true

module Google
  module Api
    # GET /api/google/search_console, /analytics, /business_profile: the latest synced data of one service.
    class DataController < BaseController
      requires_capability "google:read", only: [:search_console, :analytics, :business_profile]

      def search_console = answer(:search_console)
      def analytics = answer(:analytics)
      def business_profile = answer(:business_profile)

      private

      def answer(service)
        data = Google.public_send(service)
        return render(json: {error: "refused", message: "#{Google::SERVICES[service.to_s][:name]} isn't set up: connect Google and pick it in Settings › Google"}, status: :conflict) unless data

        render json: data.to_h
      end
    end
  end
end
