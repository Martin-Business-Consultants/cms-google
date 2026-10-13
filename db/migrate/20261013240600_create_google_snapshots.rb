# frozen_string_literal: true

# What each sync pulled from Google, by service and kind ("search_console",
# "queries"), over the dates it covers: the latest of each is what the
# screens and other plugins read; older ones are kept a year to compare.
class CreateGoogleSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :google_snapshots do |t|
      t.string :service, null: false
      t.string :kind, null: false
      t.string :target
      t.date :starts_on
      t.date :ends_on
      t.text :data
      t.datetime :taken_at, null: false
      t.timestamps
    end
    add_index :google_snapshots, [:service, :kind, :taken_at]
  end
end
