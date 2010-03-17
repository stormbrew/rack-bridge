module Bridge
  module KeyTools
    # Finds a parent path with name in it recursively. Must pass
    # a normalized path in (see File.expand_path)
    def self.find_nearest(path, name)
      if (Dir.glob(File.join(path, name)).empty?)
        parent = File.dirname(path)
        if (parent == path) # can't collapse any further, no match
          return nil
        end
        return find_nearest(parent, name)
      else
        return path
      end
    end
    
    # Returns the path to a key file in the local site if it can be determined.
    # Specifically, it'll look for the nearest parent directory with any of the
    # following under it (in priority order)
    # script/server
    # *.ru
    # .git
    # .hg
    def self.site_path(path = Dir.getwd)
      nearest = find_nearest(path, "script/server") ||
                find_nearest(path, "*.ru") ||
                find_nearest(path, ".git") ||
                find_nearest(path, ".hg")
      return nearest && File.join(nearest, ".bridge_keys")
    end
    
    # Returns the path to a key file in the user's home directory if one exists.
    # Returns nil if not found
    def self.user_path
      File.join(ENV["HOME"], ".bridge_keys") if (ENV["HOME"])
    end
    
    # Returns the path to the global key file
    def self.global_path
      File.join("/etc", "bridge_keys")
    end      
    
    # Returns an array of saved keys for the hosts passed in. Note
    # that it will never load a key for a full wildcard host ("*")
    # as that would be a serious security concern.
    def self.load_keys(for_hosts)
      paths = [site_path, user_path, global_path].compact
      keys = []
      
      paths.each do |path|
        if (File.exists? path)
          lines = File.readlines(path)
          lines.each do |key|
            key.gsub!(%r{\n$}, '')
            key_string, timestamp, host = key.split(":", 3)
            next if host == '*'
            for_hosts.each do |for_host|
              if (%r{(^|\*|\.)#{Regexp.escape(host)}$}.match(for_host))
                keys << key
              end
            end
          end
        end
      end
      return keys.uniq 
    end
    
    # Saves +key+ in the path identified by +type+ (:global, :user, :site).
    # Will not save a key for host '*'
    def self.save_key(key, type = :user)
      key_string, timestamp, host = key.split(":", 3)
      return if host == '*'
      path = send(:"#{type}_path")
      if (path)
        File.open(path, "a") do |f|
          f.puts(key)
        end
      end
    end
  end
end