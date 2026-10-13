# frozen_string_literal: true

# One pull of one kind of data from one service (Google::Sync).
class Google::Snapshot < ApplicationRecord
  KEEP_FOR = 400.days

  serialize :data, coder: JSON

  scope :latest_first, -> { order(taken_at: :desc, id: :desc) }

  def self.latest(service, kind) = where(service: service.to_s, kind: kind.to_s).latest_first.first

  def self.keep(service, kind, data, target:, starts_on: nil, ends_on: nil)
    create!(service: service.to_s, kind: kind.to_s, data: data, target: target, starts_on: starts_on, ends_on: ends_on, taken_at: Time.current)
  end

  def self.prune = where(taken_at: ...KEEP_FOR.ago).delete_all
end
