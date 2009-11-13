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
    end
end