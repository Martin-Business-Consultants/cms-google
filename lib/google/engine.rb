# frozen_string_literal: true

module Google
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it. Other plugins read it through
  # Google.search_console, Google.analytics and Google.business_profile
  # (each nil until that service is ready), checking defined?(::Google) first.
  class Engine < ::Rails::Engine
    initializer "google.migrations" do |app|
      config.paths["db/migrate"].expanded.each { |path| app.config.paths["db/migrate"] << path }
    end

    initializer "google.routes" do |app|
      app.routes.append do
        admin = proc do
          scope "settings", as: "settings" do
            resource :google, only: [:show, :update], controller: "google/settings" do
              # Connecting is a link (new), not a form: the admin's policy lets a form go only to the CMS
              # itself, and browsers hold a form's redirect to Google's sign-in to that too.
              resource :connection, only: [:new, :create, :destroy], controller: "google/connections"
              resource :callback, only: :show, controller: "google/callbacks"
              resource :choices, only: :create, controller: "google/choices"
              resource :sync, only: :create, controller: "google/syncs"
            end
          end
        end
        defined?(Cms::PATH) ? scope(path: Cms::PATH, &admin) : admin.call

        scope "api", defaults: {format: :json} do
          get "google", to: "google/api/overview#show", as: :api_google
          scope "google", module: "google/api", as: "api_google" do
            resource :settings, only: [:show, :update]
            get "search_console", to: "data#search_console", as: :search_console
            get "analytics", to: "data#analytics", as: :analytics
            get "business_profile", to: "data#business_profile", as: :business_profile
            resources :syncs, only: :create
          end
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :google, name: "Google", version: Google::VERSION, author: "Martin Business Consultants",
        enabled_by_default: false, requires: ">= 1.32", homepage: "https://github.com/Martin-Business-Consultants/cms-google",
        description: "One Google sign-in for the business's Search Console, Analytics and Business Profile, synced every night " \
                     "for Market's report and suggestions and the content calendar's posts."

      Cms::Plugins.permissions :google, "Google", %w[google:read],
        after: ["Market", "Leads", "Forms", "Globals"],
        defaults: {editor: %w[google:read], author: %w[google:read], agent: %w[google:read]}
      Cms::Plugins.settings :google, "Google", -> { settings_google_path },
        description: "Sign in to Google once, choose the Search Console property, Analytics property and Business Profile location, and see how each sync went.",
        capability: "settings:read"
      Cms::Plugins.nightly :google, -> { Google::SyncJob.perform_later if Google::Settings.current.connected? }

      Cms::Plugins.api :google, "/api/google", description: "Google at a glance: what's connected, the last sync, and each service's figures for the last 28 days beside the 28 before."
      Cms::Plugins.api :google, "/api/google/search_console",
        description: "Search Console: clicks, impressions, CTR and position by day (90 days), the top queries and pages (28 days, with the 28 before), searches it's close on (striking_distance) and pages shown a lot but clicked little (low_click_pages)."
      Cms::Plugins.api :google, "/api/google/analytics",
        description: "Google Analytics 4: sessions, users and key events by day (90 days), by channel, source and landing page (28 days, with the 28 before), and landing pages with visits but no key events (leaky_pages)."
      Cms::Plugins.api :google, "/api/google/business_profile",
        description: "Business Profile: Maps and Search views, calls, website clicks and directions by day (90 days), the searches it was found for, and its reviews."
      Cms::Plugins.api :google, "/api/google/syncs", description: "POST syncs every ready service now (settings:write)."
      Cms::Plugins.api :google, "/api/google/settings", description: "Settings › Google (read with settings:read, change with settings:write; the client secret and tokens are never read back)."
    end
  end
end
