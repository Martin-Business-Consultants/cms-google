# Google, a Libre Publish plugin — guide for AI agents

A Rails engine loaded into a CMS install from `plugins/google`. Read the core's `docs/plugins.md` and
`STYLE.md` first.

- `Google::Settings` lives in the core's Setting "google"; the client secret, refresh and access tokens are
  among its secrets (never rendered or read back).
- `Google::Client` does the OAuth web-server flow and JSON calls over Net::HTTP (only the core's gems);
  `Google::Client.transport` stands in for the network in specs (`spec/support/google_helpers.rb`).
- `Google::SearchConsole`, `Google::Analytics`, `Google::BusinessProfile` each list what to pick
  (`choices`), sync into `Google::Snapshot` (`sync`) and read the latest snapshots back. `Google::Sync`
  runs them one by one, keeping each service's error, nightly and on request.
- Other plugins check `defined?(::Google)` and read `Google.search_console` etc. (nil until ready).

Check: `bin/rspec plugins/google/spec`, `bin/rubocop plugins/google`, `bundle exec herb lint plugins/google/app/views`.
