# frozen_string_literal: true

require "net/http"

# Talks to Google over Net::HTTP (a plugin may use only the gems the core
# bundles): the OAuth web-server flow (the address a person signs in at, the
# code exchanged for a refresh token, the access token refreshed when it
# runs out) and JSON calls to the APIs with it. The transport is injectable:
# specs answer without the network.
class Google::Client
  AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
  TOKEN_URL = "https://oauth2.googleapis.com/token"
  USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"
  TIMEOUT = 30

  # A stand-in for the network, for specs: ->(method, url, headers, body) { [status, body] }.
  class << self
    attr_accessor :transport
  end

  def initialize(settings: Google::Settings.current, transport: nil)
    @settings = settings
    @transport = transport || self.class.transport || method(:http)
  end

  # Where a person signs in and grants the chosen services; offline, so a refresh token comes back.
  def authorize_url(redirect_uri:, state:)
    query = {client_id: @settings.client_id, redirect_uri: redirect_uri, response_type: "code", scope: @settings.scopes.join(" "),
             access_type: "offline", prompt: "consent", include_granted_scopes: "true", state: state}
    "#{AUTH_URL}?#{URI.encode_www_form(query)}"
  end

  # The code from the callback for tokens: {refresh_token:, email:, scopes:}.
  def exchange(code:, redirect_uri:)
    answer = token(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
    Google::Settings.remember_access_token(answer["access_token"], answer["expires_in"])
    status, body = @transport.call(:get, USERINFO_URL, {"Authorization" => "Bearer #{answer["access_token"]}"}, nil)
    email = (status.to_i == 200) ? parse(body)["email"] : nil
    {refresh_token: answer["refresh_token"], email: email, scopes: answer["scope"].to_s.split}
  end

  def get(url, query = {})
    url = "#{url}?#{URI.encode_www_form(query)}" if query.any?
    call(:get, url, nil)
  end

  def post(url, body) = call(:post, url, body)
  def patch(url, body) = call(:patch, url, body)

  private

  def call(method, url, body, retried: false)
    status, response = @transport.call(method, url, {"Authorization" => "Bearer #{access_token}", "Content-Type" => "application/json"}, body)
    if status.to_i == 401 && !retried
      Google::Settings.remember_access_token("", 0)
      @settings = Google::Settings.current
      return call(method, url, body, retried: true)
    end
    answer = parse(response)
    raise Google::Error, failure(status, answer) unless status.to_i.between?(200, 299)

    answer
  end

  def access_token
    @settings.access_token || refresh
  end

  def refresh
    raise Google::Error, "Google isn't connected: connect it in Settings › Google" unless @settings.connected?

    answer = token(grant_type: "refresh_token", refresh_token: @settings.refresh_token)
    Google::Settings.remember_access_token(answer["access_token"], answer["expires_in"])
    @settings = Google::Settings.current
    answer["access_token"]
  end

  def token(**fields)
    raise Google::Error, "Add the OAuth client's ID and secret in Settings › Google first" unless @settings.client?

    form = URI.encode_www_form(fields.merge(client_id: @settings.client_id, client_secret: @settings.client_secret))
    status, body = @transport.call(:post_form, TOKEN_URL, {"Content-Type" => "application/x-www-form-urlencoded"}, form)
    answer = parse(body)
    return answer if status.to_i == 200 && answer["access_token"].present?

    raise Google::Error, (answer["error"] == "invalid_grant") ? "Google no longer accepts this sign-in: connect it again in Settings › Google" : failure(status, answer)
  end

  def failure(status, answer)
    detail = answer.dig("error", "message") || answer["error_description"] || (answer["error"].is_a?(String) ? answer["error"] : nil)
    case status.to_i
    when 401 then "Google didn't accept the sign-in#{": #{detail}" if detail}"
    when 403 then "Google refused#{": #{detail}" if detail}"
    when 404 then "Google doesn't know that property#{": #{detail}" if detail}"
    when 429 then "Google is limiting requests#{": #{detail}" if detail}"
    else "Google answered #{status}#{": #{detail.to_s.truncate(300)}" if detail}"
    end
  end

  def parse(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    {}
  end

  def http(method, url, headers, body)
    uri = URI(url)
    request = {get: Net::HTTP::Get, post: Net::HTTP::Post, post_form: Net::HTTP::Post, patch: Net::HTTP::Patch}.fetch(method).new(uri)
    headers.each { |name, value| request[name] = value }
    request.body = (method == :post_form) ? body : JSON.generate(body) if body
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: TIMEOUT) do |connection|
      response = connection.request(request)
      [response.code.to_i, response.body]
    end
  rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::ProtocolError => problem
    raise Google::Error, "Couldn't reach Google: #{problem.class.name.demodulize}"
  end
end
