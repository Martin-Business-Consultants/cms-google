# frozen_string_literal: true

module Google
  module Api
    # The plugin's API (/api/google…): a 404 while it's off, every action declaring its capability.
    class BaseController < ::Api::BaseController
      include PluginGated
      plugin :google
      enforce_authorization
    end
  end
end
