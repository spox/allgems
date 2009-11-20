module AllGems
    class << self
        # uri:: URI of gem
        # depth:: number of times called
        # Fetch gem from given URI
        def fetch_remote(uri, depth=0)
            raise IOError.new("Depth too deep") if depth > 9
            response = Net::HTTP.get_response(uri)
            if(response.is_a?(Net::HTTPSuccess))
                response.body
            elsif(response.is_a?(Net::HTTPRedirection))
                self.fetch_remote(URI.parse(response['location']), depth + 1)
            else
                raise IOError.new("Unknown response type: #{response}")
            end
        end
    end
end