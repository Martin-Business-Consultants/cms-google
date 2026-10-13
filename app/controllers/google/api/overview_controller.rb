# frozen_string_literal: true

module Google
  module Api
    # GET /api/google: what's connected, the last sync, and each ready service's last 28 days beside the 28 before.
    class OverviewController < BaseController
      requires_capability "google:read", only: :show

      def show
        settings = Google::Settings.current
        render json: {connected: settings.connected?, email: settings.email, services: settings.services, ready: settings.to_h[:ready],
                      last_sync_at: settings.last_sync_at, last_sync_errors: settings.last_sync_errors,
                      search_console: Google.search_console&.then { {totals: it.totals, totals_before: it.totals_before, period: it.period} },
                      analytics: Google.analytics&.then { {totals: it.totals, totals_before: it.totals_before} },
                      business_profile: Google.business_profile&.then { {totals: it.totals, totals_before: it.totals_before, rating: it.reviews["average"], reviews: it.reviews["total"]} }}
      end
    end
  end
end
