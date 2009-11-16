module AllGems
    class IndexBuilder
        def initialize(args={})
            raise ArgumentError.new('Expecting a Sequel::Database to be passed') unless args[:database] && args[:database].is_a?(Sequel::Database)
        end
        def build_array(filter=[])
            b = []
            list = Gem::SpecFetcher.fetcher.list(AllGems.allgems).to_a.map{|x|x[1].map{|y|{:name => y[0],:version => y[1]}}}
            list.size.times{|i| b = b | list[i]} # list.flatten(1) would be great but it's only on >=1.9. alas
            AllGems.logger.debug("List size: #{b.size}")
            b.reject{|x|filter.include?(x)}
        end
        # Generate array of all gem versions that does not have all documentation generated
        def local_array
            AllGems.db.transaction do
                la = AllGems.db[:versions].join(:gems, :id => :gem_id).join(:docs_versions, :version_id, :versions__id)
                la.join(:docs, :id => :docs_versions__doc_id).filter(~{:docs__name => AllGems.doc_format.map{|x|x.to_s}})
                la.select(:gems__name.as(:name), :versions__version.as(:version))
                la.all.collect{|x| {:name => x[:name], :version => Gem::Version.new(x[:version])}}
            end
        end
    end
end