require 'logger'
module AllGems
    class << self
        attr_accessor :data_directory, :logger, :db, :allgems, :pool, :timer, :listen_port, :domain_name
        def defaulterize
            @data_directory = nil
            @doc_format = ['rdoc']
            @logger = Logger.new(nil)
            @db = nil
            @tg = nil
            @ti = nil
            @allgems = true
            @refresh = Time.now.to_i + 3600
            @pool = nil
            @timer = nil
            @listen_port = 4000
            @start_time = Time.now.to_i
            @domain_name = 'localhost'
        end
        # db: Sequel::Database
        # Run any migrations needed
        # NOTE: Call before using the database
        def initialize_db(db)
            self.db = db
            require 'sequel/extensions/migration'
            Sequel::Migrator.apply(db, "#{File.expand_path(__FILE__).gsub(/\/[^\/]+$/, '')}/allgems/migrations")
        end
        # Format for documentation
        def doc_format
            @doc_format
        end
        # f:: format
        # Sets format for documentation. Should be one of: hanna, rdoc, sdoc
        def doc_format=(f)
            @doc_format = []
            f.split(',').each do |type|
                type = type.to_sym
                raise ArgumentError.new("Valid types: hanna, sdoc, rdoc") unless [:hanna,:sdoc,:rdoc].include?(type)
                @doc_format << type
            end
        end
        # Location of public directory
        def public_directory
            File.expand_path("#{__FILE__}/../../public")
        end
        # Total number of unique gem names installed
        def total_gems
            return 0 if self.db.nil?
            if(@tg.nil? || Time.now.to_i > @refresh)
                @tg = self.db[:gems].count
                @refresh = Time.now.to_i + 3600
            end
            @tg
        end
        # Total number of actual gems installed
        def total_installs
            return 0 if self.db.nil?
            if(@ti.nil? || Time.now.to_i > @refresh)
                @ti = self.db[:versions].count
                @refresh = Time.now.to_i + 3600
            end
            @ti
        end
        # Newest gem based on release date
        def newest_gem
            g = AllGems.db[:versions].join(:gems, :id => :gem_id).order(:release.desc).limit(1).select(:name, :release).first
            {:name => g[:name], :release => g[:release]}
        end
        # Path to hanna hack
        def hanna_hack
            File.expand_path("#{__FILE__}/../allgems/hanna_hack.rb")
        end
        # runners:: Number of threads
        # Create a global use pool
        def initialize_pool(args=nil)
            args = {:a_to => 60*5} unless args
            @pool = ActionPool::Pool.new(args) if @pool.nil?
        end
        # pool:: ActionPool to use. (Uses global pool if available)
        # Create a global use timer
        def initialize_timer(pool=nil)
            pool = @pool unless pool
            @timer = ActionTimer::Timer.new(:pool => pool)
        end
        # Seconds program has been running
        def uptime
            Time.now.to_i - @start_time
        end
        # id:: uid to be used
        # gems:: Array of gem names and versions [[name,version],[name,version]]
        # Links the given gem names and versions to the ID given
        def link_id(id, gems)
            gems.each do |info|
                vid = AllGems.db[:versions].join(:gems, :id => :gem_id).filter(:name => info[0], :version => info[1]).select(:versions__id.as(:vid)).first
                next if vid.nil?
                vid = vid[:vid]
                lid = AllGems.db[:lids].filter(:uid => id).first[:id]
                begin
                    AllGems.db[:gems_lids] << {:version_id => vid, :lids_id => lid}
                rescue
                    #ignore duplicates
                end
            end
        end
        
        # length:: max length of ID (defaults to 50)
        # Returns a unique ID that is not currently in use
        # TODO: synchronzie access and use transactions to prevent duplicates
        def uid(length = 50)
            id = rand(36**length).to_s(36)
            if(AllGems.db[:lids].filter(:uid => id).count > 0)
                id = uuid(length)
            end
            AllGems.db[:lids] << {:uid => id}
            id
        end
    end
end