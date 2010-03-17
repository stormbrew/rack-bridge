require 'bridge/server'

module Rack
  module Handler
    class Bridge
      def self.run(app, options = Bridge::Server::DefaultOptions)
        ::Bridge::Server.new(options).run(app)
      end
    end
  end
end