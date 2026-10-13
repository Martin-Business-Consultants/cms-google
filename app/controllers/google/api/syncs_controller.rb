# frozen_string_literal: true

module Google
  module Api
    # POST /api/google/syncs: sync every ready service now, in the background.
    class SyncsController < BaseController
      requires_capability "settings:write", only: :create

      def create
        return render(json: {error: "refused", message: "Google isn't connected: connect it in Settings › Google"}, status: :conflict) unless Google::Settings.current.connected?

        Google::SyncJob.perform_later
        render json: {status: "syncing"}, status: :accepted
      end
    end
  end
end
