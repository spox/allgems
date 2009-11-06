module AllGems
    class IndexBuilder
        def initialize(args={})
            raise ArgumentError.new('Expecting a Sequel::Database to be passed') unless args[:database] && args[:database].is_a?(Sequel::Database)
            @db = args[:database]
        end
        def build_array(filter=[])
            b = []
            list = Gem::SpecFetcher.fetcher.list(AllGems.allgems).to_a.map{|x|x[1].map{|y|{:name => y[0],:version => y[1]}}}
            list.size.times{|i| b = b | list[i]} # list.flatten(1) would be great but it's only on >=1.9. alas
            AllGems.logger.debug("List size: #{b.size}")
            b.reject{|x|filter.include?(x)}
        end
        def local_array
            la = @db[:versions].join(:gems, :id => :gem_id).select(:name, :version).all.collect{|x|x.values}
            la.map{|a| {:name => a[0], :version => Gem::Version.new(a[1])}}
        end
    end
end