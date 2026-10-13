# frozen_string_literal: true

# Settings › Google, kept in the core's Setting "google": the OAuth client
# the install signs in with (its secret among the Setting's secrets), which
# services to use, the account connected (its refresh token a secret too),
# and the property, stream and location each service reads, with the lists
# they were picked from and how the last sync went.
class Google::Settings
  KEY = "google"

  def self.current = new(Setting.get(KEY))

  def initialize(data)
    @data = data.to_h.stringify_keys
  end

  def client_id = @data["client_id"].presence
  def client_secret = Setting.secret(KEY, "client_secret").presence
  def refresh_token = Setting.secret(KEY, "refresh_token").presence
  def client? = client_id.present? && client_secret.present?
  def connected? = refresh_token.present?
  def email = @data["email"]
  def connected_at = @data["connected_at"].presence&.then { Time.zone.parse(it) }

  # The services chosen, in the order they were built: Search Console, Analytics, Business Profile.
  def services = Array(@data["services"]).select { Google::SERVICES.key?(it) }.presence || %w[search_console]
  def service?(service) = services.include?(service.to_s)
  def scopes = ["openid", "email", *services.map { Google::SERVICES.dig(it, :scope) }]

  # Whether the account was granted a service's scope when it connected.
  def granted?(service) = Array(@data["granted_scopes"]).include?(Google::SERVICES.dig(service.to_s, :scope))

  def search_console_site = @data["search_console_site"].presence
  def analytics_property = @data["analytics_property"].presence
  def analytics_property_name = @data["analytics_property_name"].presence
  def business_account = @data["business_account"].presence
  def business_location = @data["business_location"].presence
  def business_location_name = @data["business_location_name"].presence

  # What a service reads, picked: nil until it is.
  def target(service)
    {"search_console" => search_console_site, "analytics" => analytics_property, "business_profile" => business_location}[service.to_s]
  end

  def ready?(service) = connected? && service?(service) && granted?(service) && target(service).present?

  # The lists to pick from, as loaded after connecting: [[label, value]].
  def choices(service) = Array(@data.dig("choices", service.to_s))
  def all_choices = @data["choices"].to_h

  def last_sync_at = @data["last_sync_at"].presence&.then { Time.zone.parse(it) }
  def last_sync_errors = @data["last_sync_errors"].to_h
  def syncing? = @data["syncing_since"].present? && Time.zone.parse(@data["syncing_since"]) > 15.minutes.ago

  # From Settings › Google's form or the API's PATCH: only what was sent changes.
  def self.update(params)
    params = params.to_h.stringify_keys
    data = {}
    data["client_id"] = params["client_id"].to_s.strip.presence if params.key?("client_id")
    data["services"] = Array(params["services"]).select { Google::SERVICES.key?(it) } if params.key?("services")
    data["search_console_site"] = params["search_console_site"].to_s.strip.presence if params.key?("search_console_site")
    if params.key?("analytics_property")
      data["analytics_property"] = params["analytics_property"].to_s.strip.presence
      data["analytics_property_name"] = current.choices("analytics").find { it[1] == data["analytics_property"] }&.first
    end
    if params.key?("business_location")
      data["business_location"] = params["business_location"].to_s.strip.presence
      account, name = current.choices("business_profile").find { it[1] == data["business_location"] }&.values_at(2, 0)
      data["business_account"] = account
      data["business_location_name"] = name
    end
    Setting.set(KEY, data) if data.any?
    Setting.set_secret(KEY, "client_secret" => params["client_secret"].to_s.strip) if params["client_secret"].present?
    current
  end

  def self.remember(data) = Setting.set(KEY, data.stringify_keys)

  # Signed in: the refresh token, who, and the scopes granted.
  def self.connect(refresh_token:, email:, scopes:)
    Setting.set_secret(KEY, "refresh_token" => refresh_token) if refresh_token.present?
    remember("email" => email, "connected_at" => Time.current.iso8601, "granted_scopes" => scopes, "access_token_expires_at" => nil)
    Setting.set_secret(KEY, "access_token" => "")
  end

  def self.disconnect
    Setting.set_secret(KEY, "refresh_token" => "", "access_token" => "")
    remember("email" => nil, "connected_at" => nil, "granted_scopes" => [], "choices" => {}, "last_sync_errors" => {})
  end

  def access_token
    token = Setting.secret(KEY, "access_token").presence
    expires = @data["access_token_expires_at"].presence&.then { Time.zone.parse(it) }
    token if expires && expires > 1.minute.from_now
  end

  def self.remember_access_token(token, expires_in)
    Setting.set_secret(KEY, "access_token" => token)
    remember("access_token_expires_at" => expires_in.to_i.seconds.from_now.iso8601)
  end

  def to_h
    {client_set: client?, connected: connected?, email: email, connected_at: connected_at, services: services,
     granted: Google::SERVICES.keys.select { granted?(it) }, search_console_site: search_console_site,
     analytics_property: analytics_property, analytics_property_name: analytics_property_name,
     business_location: business_location, business_location_name: business_location_name,
     ready: Google::SERVICES.keys.to_h { [it, ready?(it)] }, last_sync_at: last_sync_at, last_sync_errors: last_sync_errors}
  end
end
