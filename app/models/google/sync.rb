# frozen_string_literal: true

# Pulls every ready service (Search Console first, then Analytics, then
# Business Profile) into snapshots, each on its own: one failing leaves the
# others, and what went wrong is kept per service for Settings › Google.
# Run nightly and on request (Google::SyncJob).
class Google::Sync
  def self.run!(client: Google::Client.new)
    settings = Google::Settings.current
    Google::Settings.remember("syncing_since" => Time.current.iso8601)
    errors = {}
    Google::SERVICES.each_key do |service|
      next unless settings.ready?(service)

      case service
      when "search_console" then Google::SearchConsole.sync(client, settings.search_console_site)
      when "analytics" then Google::Analytics.sync(client, settings.analytics_property)
      when "business_profile" then Google::BusinessProfile.sync(client, settings.business_location, settings.business_account)
      end
    rescue Google::Error => error
      errors[service] = error.message
    rescue => error
      Rails.logger.error("[google] #{service}: #{error.class}: #{error.message}")
      errors[service] = "#{error.class.name.demodulize}: #{error.message}".truncate(300)
    end
    Google::Snapshot.prune
    Google::Settings.remember("syncing_since" => nil, "last_sync_at" => Time.current.iso8601, "last_sync_errors" => errors)
    errors
  end

  # Loads the properties, sites and locations to pick from for each service granted, picking one when there's only one.
  def self.load_choices(client: Google::Client.new)
    settings = Google::Settings.current
    choices = {}
    errors = {}
    {"search_console" => Google::SearchConsole, "analytics" => Google::Analytics, "business_profile" => Google::BusinessProfile}.each do |service, source|
      next unless settings.service?(service) && settings.granted?(service)

      choices[service] = source.choices(client)
    rescue Google::Error => error
      errors[service] = error.message
    end
    Google::Settings.remember("choices" => settings.all_choices.merge(choices), "last_sync_errors" => errors)
    picks = {}
    picks["search_console_site"] = choices["search_console"][0][1] if choices["search_console"]&.one? && !settings.search_console_site
    picks["analytics_property"] = choices["analytics"][0][1] if choices["analytics"]&.one? && !settings.analytics_property
    picks["business_location"] = choices["business_profile"][0][1] if choices["business_profile"]&.one? && !settings.business_location
    Google::Settings.update(picks) if picks.any?
    errors
  end
end
