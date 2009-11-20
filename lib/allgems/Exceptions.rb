module AllGems
    # Make a parent error class that we can specialize
    class Error < StandardError
        attr_reader :original
        def initialize(e=nil)
            @original = e.nil? ? self : e
        end
    end
    # Exception class for failed documentation creation
    class DocError < Error
        attr_reader :gem_name, :gem_version
        def initialize(gn, gv, e=nil)
            super(e)
            @gem_name = gn
            @gem_version = gv
        end
        def to_s
            "Failed to create documentation for: #{@gem_name}-#{@gem_version}."
        end
    end
    
    # Exception class for failed gem fetching
    class FetchError < Error
        attr_reader :gem_name, :gem_version, :uri
        def initialize(gn, gv, u, e=nil)
            super(e)
            @gem_name = gn
            @gem_version = gv
            @uri = u
        end
        def to_s
            "Failed to fetch #{@gem_name}-#{@gem_version}.gem from #{uri}"
        end
    end
    class Wakeup < Exception
    end
end