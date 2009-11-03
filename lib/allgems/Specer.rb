module AllGems
    class Specer
        class << self
            def get_spec(gem, version=nil)
                spec = AllGems.db[:specs].join(:versions, :id => :version_id).join(:gems, :id => :gem_id).filter(:name => gem)
                spec = spec.filter(:version => version) if version
                spec = spec.order(:version.desc).limit(1).first
                return spec ? Marshal.load(spec[:spec].unpack('m')[0]) : nil
            end            
        end
    end
end