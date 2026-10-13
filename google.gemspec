# frozen_string_literal: true

require_relative "lib/google/version"

Gem::Specification.new do |spec|
  spec.name = "google"
  spec.version = Google::VERSION
  spec.summary = "Google for Libre Publish: Search Console, Analytics and Business Profile on one sign-in, for every plugin that wants them"
  spec.authors = ["Martin Business Consultants"]
  spec.license = "FSL-1.1-MIT"
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
