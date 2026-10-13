# Google

A [Libre Publish](https://github.com/Martin-Business-Consultants/libre-publish) plugin: one sign-in to the
business's own Google account for **Search Console**, **Google Analytics 4** and **Google Business Profile**,
synced every night, for every plugin that wants them. [Market](https://github.com/Martin-Business-Consultants/cms-market)
reads it for its findings, report, Maps and AI suggestions; the content calendar posts to the Business
Profile through it.

- **Search Console**: clicks, impressions, click-through and position by day (90 days); the top searches and
  pages, the last 28 days beside the 28 before; the searches the site is close on (4th to 20th) and the
  pages shown a lot but clicked little.
- **Analytics**: sessions, users and key events (enquiries, bookings) by day; by channel, source and landing
  page; landing pages that bring visits but no key events.
- **Business Profile**: views on Maps and Search, calls, website clicks, directions, bookings by day; the
  searches it was found for; its reviews and which aren't answered; and posting to the profile.

## Setting it up

1. In the [Google Cloud console](https://console.cloud.google.com), create a project, then
   **APIs & Services › OAuth consent screen** (External; add the business's Google account as a test user
   until it's published), and **Credentials › Create credentials › OAuth client ID › Web application**.
   Add the **authorised redirect URI** Settings › Google shows (`https://<your CMS>/cms/settings/google/callback`).
2. Enable the **Google Search Console API**, the **Google Analytics Data API** and the **Google Analytics
   Admin API**. For the Business Profile, [request access](https://developers.google.com/my-business/content/prereqs)
   to the Business Profile APIs for the project; once granted, enable the **My Business Account Management
   API**, **My Business Business Information API** and **Business Profile Performance API**. Until then
   the Business Profile answers 403 and the other two work as usual.
3. In **Settings › Google**, paste the client ID and secret, tick the services, save, and **Connect Google**
   with the account that owns the property and the profile. Pick the Search Console property, the Analytics
   property and the location (picked for you when there's only one). It syncs at once and every night.

The client secret and the tokens are kept among the Setting's encrypted secrets and never read back.

## For other plugins and a local harness

    Google.ready?(:search_console)       # switched on, connected, granted and pointed at a property
    Google.search_console&.striking_distance
    Google.analytics&.leaky_pages
    Google::BusinessProfile.post!(summary: "…", url: "https://…", image_url: "https://…")

    cms get /api/google                       # what's connected, the last sync, each service's last 28 days
    cms get /api/google/search_console        # daily, queries, pages, striking_distance, low_click_pages
    cms get /api/google/analytics             # daily, channels, sources, landing_pages, leaky_pages
    cms get /api/google/business_profile      # daily, keywords, reviews
    cms post /api/google/syncs '{}'           # sync now (settings:write)

Reading takes `google:read` (editors, authors and the Agent role have it); settings take `settings:read`
and `settings:write`.

Install it into a CMS checkout (core 1.32 or newer):

    bin/rails "plugins:install[https://github.com/Martin-Business-Consultants/cms-google]"

or add it from Settings › Plugins, then switch it on. Its specs run inside the CMS:

    bin/rspec plugins/google/spec

To release, bump `lib/google/version.rb`, commit, and tag `vX.Y.Z`.
