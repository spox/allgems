module AllGems
    class IndexBuilder
        def initialize(args={})
            raise ArgumentError.new('Expecting a Sequel::Database to be passed') unless args[:database] && args[:database].is_a?(Sequel::Database)
            @db = args[:database]
        end
        def build_array(filter=[])
            b = []
            Gem::SpecFetcher.fetcher.list(true).each_pair{|uri, x| b = b | x.reject{|a|filter.include?(a)}.map{|c|{:name => c[0], :version => c[1]}}}
            b
        end
        def local_array
            @db[:versions].join(:gems, :id => :gem_id).join(:platforms, :id => :versions__platform_id).select(:name, :version, :platform).all.collect{|x|x.values}
        end
    end
end