# frozen_string_literal: true

# Syncs Google off the request (Google::Sync).
class Google::SyncJob < ApplicationJob
  def perform = Google::Sync.run!
end
