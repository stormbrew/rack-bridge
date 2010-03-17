require 'socket'

module Bridge
  # This is the class returned by TCPServer.accept. It is a TCPSocket with a couple of extra features.
  class TCPSocket < ::TCPSocket
    class RetryError < RuntimeError
      attr_reader :timeout
      def initialize(msg, timeout = 5)
        super(msg)
        @timeout = timeout
      end
    end
    
    def initialize(cloud_host, cloud_port, listen_hosts, listen_keys)
      @cloud_host = cloud_host
      @cloud_port = cloud_port
      @listen_hosts = listen_hosts
      @listen_keys = listen_keys
      
      super(@cloud_host, @cloud_port)
    end
    
    def send_bridge_request()
			write("BRIDGE / HTTP/1.1\r\n")
			write("Expect: 100-continue\r\n")
			@listen_hosts.each {|host|
				write("Host: #{host}\r\n")
			}
			@listen_keys.each {|key|
				write("Host-Key: #{key}\r\n")
			}
			write("\r\n")      
    end
    
    # This just tries to determine if the server will honor
    # requests as specified above so that the TCPServer initializer
    # can error out early if it won't.
    def verify()
      send_bridge_request()
      begin
        line = gets()
        match = line.match(%r{^HTTP/1\.[01] ([0-9]{3,3}) (.*)$})
        if (!match)
          raise "HTTP BRIDGE error: bridge server sent incorrect reply to bridge request."
        end
        case code = match[1].to_i
        when 100, 101
          return true
  			when 401 # 401 Access Denied, key wasn't right.
  			  raise "HTTP BRIDGE error #{code}: host key was invalid or missing, but required."
  		  when 503, 504 # 503 Service Unavailable or 504 Gateway Timeout
  		    raise "HTTP BRIDGE error #{code}: could not verify server can handle requests because it's overloaded."
  	    else
  	      raise "HTTP BRIDGE error #{code}: #{match[2]} unknown error connecting to bridge server."
        end 
      ensure
        close() # once we do this, we just assume the connection is useless.
      end
    end
    
    # This does the full setup process on the request, returning only
    # when the connection is actually available.
    def setup()
      send_bridge_request
      code = nil
			name = nil
			headers = []
			while (line = gets())
				line = line.strip
				if (line == "")
					case code.to_i
					when 100 # 100 Continue, just a ping. Ignore.
						code = name = nil
						headers = []
						next
					when 101 # 101 Upgrade, successfuly got a connection.
						write("HTTP/1.1 100 Continue\r\n\r\n") # let the server know we're still here.
						return self
					when 401 # 401 Access Denied, key wasn't right.
					  close()
					  raise "HTTP BRIDGE error #{code}: host key was invalid or missing, but required."
					when 503, 504 # 503 Service Unavailable or 504 Gateway Timeout, just retry.
						close()
						sleep_time = headers.find {|header| header["Retry-After"] } || 5
						raise RetryError.new("BRIDGE server timed out or is overloaded, wait #{sleep_time}s to try again.", sleep_time)
					else
						raise "HTTP BRIDGE error #{code}: #{name} waiting for connection."
					end
				end
		
				if (!code && !name) # This is the initial response line
					if (match = line.match(%r{^HTTP/1\.[01] ([0-9]{3,3}) (.*)$}))
						code = match[1]
						name = match[2]
						next
					else
						raise "Parse error in BRIDGE request reply."
					end
				else
					if (match = line.match(%r{^(.+?):\s+(.+)$}))
						headers.push({match[1] => match[2]})
					else
						raise "Parse error in BRIDGE request reply's headers."
					end
				end
			end
			return nil
		end
  end
  
  # This class emulates the behaviour of TCPServer, but 'listens' on a cloudbridge
	# server rather than a local interface. Otherwise attempts to have a mostly identical
	# interface to ::TCPServer.
	class TCPServer
		def initialize(cloud_host, cloud_port, listen_hosts = ['*'], listen_keys = [])
			@cloud_host = cloud_host
			@cloud_port = cloud_port
			@listen_hosts = listen_hosts
			@listen_keys = listen_keys
			@closed = false
			begin
			  TCPSocket.new(@cloud_host, @cloud_port, @listen_hosts, @listen_keys).verify
		  rescue Errno::ECONNREFUSED
		    raise "HTTP BRIDGE Error: No Bridge server at #{@cloud_host}:#{@cloud_port}"
	    end
		end
	
		def accept()
			begin
				# Connect to the cloudbridge and let it know we're available for a connection.
				# This is all entirely syncronous.
				begin
					socket = TCPSocket.new(@cloud_host, @cloud_port, @listen_hosts, @listen_keys)
				rescue Errno::ECONNREFUSED
					sleep(0.5)
					retry
				end
				socket.setup
				return socket
			rescue RetryError => e
			  sleep(e.timeout)
			  retry
			end
		end
	
		def close()
			@closed = true
		end
		
		def closed?()
		  return @closed
	  end
	end
end