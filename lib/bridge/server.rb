require 'jaws/server'
require 'bridge/tcp_server'
require 'bridge/key_tools'

module Bridge
  # An HTTP Rack-based server based on the Jaws web server.
  class Server < Jaws::Server
    DefaultOptions = Jaws::Server::DefaultOptions.merge({
      :UseKeyFiles => true,
      :Keys => "",
      :Port => 8079,
    })
    
    # The host information to set up where to listen. It's formatted
    # as follows:
    # [listen.host1,listen.host2,...@]bridge.host
    # where each of the listen.hosts is a host that this server
    # should handle requests for and the bridge.host is the address
    # of the bridge host itself. Note that if you're only listening
    # on one host and it shares its ip with the bridge server itself,
    # you can simply give it that host (ie. pickles.oncloud.org will
    # connect to pickles.oncloud.org to server for pickles.oncloud.org)
    # An example of a more complicated example might be:
    # www.blah.com,blah.com@blorp.com
    # You can also have leading wildcards in the hosts:
    # *.blorp.com,blorp.com@blorp.com
    # Or more concisely (*. matches subdomains, *blah matches *.blah and blah):
    # *blorp.com@blorp.com
    # Or yet more concisely (without an @, wildcards are removed to find the address):
    # *blorp.com
    # And of course, to match everything on a bridge server:
    # *@blorp.com
    attr_accessor :host    
    # Whether or not the local key files (.bridge_keys in
    # the current app's directory, the user's homedir, and
    # /etc) should be searched for matching keys when connecting
    # to the server. Also set with options[:UseKeyFiles]
    attr_accessor :use_key_files
    # The keys that should be sent to the BRIDGE server.
    # Also set with options[:Keys]
    attr_accessor :keys
    
    # The hosts this server responds to. Derived from #host
    attr_reader :listen_hosts
    # The bridge server we intend to connect to. Derived from #host
    attr_reader :bridge_server
    
    def initialize(options = DefaultOptions)
      super(DefaultOptions.merge(options))

      @use_key_files = @options[:UseKeyFiles]

      hosts, @bridge_server = @host.split("@", 2)
      if (@bridge_server.nil?)
        # no bridge specified, we expect there to be a single host
        # and (once trimmed of wildcards) it becomes our bridge server
        # address.
        @bridge_server = hosts.gsub(%r{^\*\.?}, '')
        hosts = [hosts]
      else
        # there was a bridge, so we can allow multiple hosts and don't need
        # any magic for the bridge
        hosts = hosts.split(',')
      end
      @listen_hosts = hosts.collect do |h|
        # We need to expand *blah into *.blah and blah. This is a client-side
        # convenience, not something the server deals with.
        if (match = %r{^\*[^\.](.+)$}.match(h))
          ["*." << match[1], match[1]]
        else
          h
        end
      end.flatten

      @keys = @options[:Keys].split(",")
      @keys << ENV["BRIDGE_KEYS"] if (ENV["BRIDGE_KEYS"])
      if (@use_key_files)
        @keys << Bridge::KeyTools.load_keys(@listen_hosts)
      end
      @keys.flatten!
    end
    
    def create_listener(options)
      l = Bridge::TCPServer.new(bridge_server, port, listen_hosts, keys)
      # There's no shared state externally accessible, so we just make
      # synchronize on the listener a no-op.
      def l.synchronize
        yield
      end
      return l
    end
  end
end