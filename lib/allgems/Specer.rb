require 'zlib'
require 'allgems/Helpers'
require 'rubygems/specification'
module AllGems
    class Specer
        def initialize
        end
        # Retrieve gem spec from database
        def get_spec(gem, version=nil, uri=false)
            spec = AllGems.db[:specs].join(:versions, :id => :version_id).join(:gems, :id => :gem_id).filter(:name => gem)
            spec = spec.filter(:version => version) if version
            spec = spec.order(:version.desc).limit(1).first
            result = nil
            if(spec)
                if(uri)
                    result = [Marshal.load(spec[:spec].unpack('m')[0]), spec[:uri]]
                else
                    result = Marshal.load(spec[:spec].unpack('m')[0])
                end
            end
            result
        end

        # Pull full gem index and load specs into database
        def load_specs
            AllGems.sources.each do |s|
                do_spec_load(s)
            end
        end

        # source:: string to source location
        # Fetches gem spec index and loads it into the database
        # TODO: we can save to the database much much faster if we wrap
        # all the inserts into a single transaction.
        def do_spec_load(source)
            specs = []
            begin
                remote_path = "#{source}/Marshal.4.8.Z"
                remote_uri = URI.parse(remote_path)
                AllGems.logger.info("Grabbing specification index at: #{remote_uri}")
                specs = Marshal.load(Zlib::Inflate.inflate(AllGems.fetch_remote(remote_uri)))
            rescue StandardError => boom
                AllGems.logger.error "Failed to load spec index from: #{source}. Reason: #{boom}"
                raise boom
            end
            to_load = []
            AllGems.logger.info("Index for #{source} contains #{specs.size} gem specifications. Checking for currently stored specs.")
            specs.map!{|x|{:spec => x[1], :source => source} unless spec_saved?(x[1])}.compact!
            AllGems.logger.info("Number of gem specifcations to save for #{source}: #{specs.size}")
            save_spec_data(specs) unless specs.empty?
            AllGems.logger.info("Loading of gem specifications for source #{source} is complete")
        end

        # spec:: Gem::Specification
        # Check if a spec is already saved in the database
        def spec_saved?(spec)
            AllGems.db[:specs].filter(:full_name => spec.full_name).count > 0
        end

        # args:: Hash or array of hashes with :spec and :source
        # Save data to the database about this gem
        def save_spec_data(args)
            args = [args] unless args.is_a?(Array)
            AllGems.db.transaction do
                args.each do |info|
                    AllGems.logger.info("Saving data about gem: #{info[:spec].full_name}")
                    gid = AllGems.db[:gems].filter(:name => info[:spec].name).first
                    gid = gid.nil? ? AllGems.db[:gems].insert(:name => info[:spec].name) : gid[:id]
                    if(AllGems.db[:versions].filter(:gem_id => gid, :version => info[:spec].version.version).count == 0)
                        vid = AllGems.db[:versions] << {:version => info[:spec].version.version, :gem_id => gid, :release => info[:spec].date}
                        AllGems.db[:specs] << {:version_id => vid, :spec => [Marshal.dump(info[:spec])].pack('m'), :uri => info[:source], :full_name => info[:spec].full_name}
                        #TODO: only update to latest version
                        AllGems.db[:gems].filter(:id => gid).update(:summary => info[:spec].summary)
                        AllGems.db[:gems].filter(:id => gid).update(:description => info[:spec].description)
                    end
                end
            end
            true
        end

        # Returns an array of Gem::Specification files for gems that do not
        # have all the documentation completed listed in the format
        # select full_name from specs inner join versions on specs.version_id = versions.id where versions.id not in (select version_id from docs_versions where doc_id not in (1,2,3));
        # I believe that's what we need ^^
        # No, we need left joins here. see the terminal session. should be easy to fix.
        def missing_docs
            AllGems.db.transaction do
                ids = []
                AllGems.logger.debug("Searching for gems with missing docs")
                AllGems.db[:versions].map(:id).each do |id|
                    add = false
                    AllGems.doc_format.map{|x| AllGems.doc_hash[x.to_sym]}.each do |doc_id|
                        add = true if AllGems.db[:docs_versions].filter(:doc_id => doc_id, :version_id => id).count < 1
                    end
                    if(add)
                        ids.push(id)
                        AllGems.logger.debug("Added gem with version id: #{id} for document generation")
                    end
                end
                specs = AllGems.db[:specs].filter(:version_id => ids).select(:spec)
                specs.all.map{|x| Marshal.load(x[:spec].unpack('m')[0])}
            end
        end
    end
end