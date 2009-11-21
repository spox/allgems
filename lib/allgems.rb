require 'logger'
require 'allgems/Exceptions'
module AllGems
    class << self
        # This is a utility hack for me so I don't have to add in stuff
        # for every little thing I want up here.
        def method_missing(*args)
            @config ||= {}
            if(args.size == 1)
                @config[args[0].to_sym]
            elsif(args.size == 2 && args[0].slice(-1) == '=')
                @config[args[0].slice(0,args[0].length-1).to_sym] = args[1]
            else
                raise NoMethodError.new("Sorry, this method: #{args[0]} does not live here")
            end
        end
        # Set our default values
        def defaulterize
            self.data_directory = nil
            self.doc_format = ['rdoc']
            self.logger = Logger.new(nil)
            self.db = nil
            self.tg = nil
            self.ti = nil
            self.allgems = true
            self.refresh = Time.now.to_i + 3600
            self.pool = nil
            self.timer = nil
            self.listen_port = 4000
            self.start_time = Time.now.to_i
            self.domain_name = 'localhost'
            self.doc_hash = {}
            self.valid_docs = [:hanna, :rdoc, :sdoc]
            self.sources = []
        end
        # db: Sequel::Database
        # Run any migrations needed
        # NOTE: Call before using the database
        def initialize_db
            self.logger.debug("Connecting to database using connection string: #{self.dbstring}")
            self.db = Sequel.connect("#{self.dbstring}", :max_connections => 50, :pool_timeout => 90)
            require 'sequel/extensions/migration'
            Sequel::Migrator.apply(db, "#{File.expand_path(__FILE__).gsub(/\/[^\/]+$/, '')}/allgems/migrations")
            save_default_docs
        end
        # Return array of sources to pull gems
        def sources
            self.sources = Gem.sources if @config[:sources].empty?
            @config[:sources]
        end
        # s:: source string or array
        # Set sources to given string or array
        def sources=(s)
            raise ArgumentError.new("Sources must be in an array") unless s.is_a?(Array)
            @config[:sources] = s
        end

        # f:: format
        # Sets format for documentation. Should be one of: hanna, rdoc, sdoc
        def doc_format=(f)
            @config[:doc_format] = []
            if(f.is_a?(String))
                f.split(',').each do |type|
                    type = type.to_sym
                    raise ArgumentError.new("Valid types: hanna, sdoc, rdoc") unless self.valid_docs.include?(type)
                    self.doc_format.push(type)
                end
            elsif(f.is_a?(Array))
                @config[:doc_format] = f
            else
                ArgumentError.new('Expecting a string or array')
            end
        end
        # Location of public directory
        def public_directory
            File.expand_path("#{__FILE__}/../../public")
        end
        # Total number of unique gem names installed
        def total_gems
            return 0 if self.db.nil?
            if(self.tg.nil? || Time.now.to_i > self.refresh)
                self.tg = self.db[:gems].count
                self.refresh = Time.now.to_i + 3600
            end
            self.tg
        end
        # Total number of actual gems installed
        def total_installs
            return 0 if self.db.nil?
            if(self.ti.nil? || Time.now.to_i > self.refresh)
                self.ti = self.db[:versions].count
                self.refresh = Time.now.to_i + 3600
            end
            self.ti
        end
        # Newest gem based on release date
        def newest_gem
            g = self.db[:versions].join(:gems, :id => :gem_id).order(:release.desc).limit(1).select(:name, :release).first
            {:name => g[:name], :release => g[:release]}
        end
        # Path to hanna hack
        def hanna_hack
            File.expand_path("#{__FILE__}/../allgems/hanna_hack.rb")
        end
        # runners:: Number of threads
        # Create a global use pool
        def initialize_pool(args=nil)
            args = {:a_to => 60*5, :max_threads => 20} unless args
            self.pool = ActionPool::Pool.new(args) if self.pool.nil?
        end
        # pool:: ActionPool to use. (Uses global pool if available)
        # Create a global use timer
        def initialize_timer(pool=nil)
            pool = self.pool unless pool
            self.timer = ActionTimer::Timer.new(:pool => pool) # make this adjustable
        end
        # Seconds program has been running
        def uptime
            Time.now.to_i - self.start_time
        end
        # id:: uid to be used
        # gems:: Array of gem names and versions [[name,version],[name,version]]
        # Links the given gem names and versions to the ID given
        def link_id(id, gems)
            gems.each do |info|
                vid = self..db[:versions].join(:gems, :id => :gem_id).filter(:name => info[0], :version => info[1]).select(:versions__id.as(:vid)).first
                next if vid.nil?
                vid = vid[:vid]
                lid = self.db[:lids].filter(:uid => id).first[:id]
                begin
                    self.db[:gems_lids] << {:version_id => vid, :lids_id => lid}
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
            if(self.db[:lids].filter(:uid => id).count > 0)
                id = uuid(length)
            end
            self.db[:lids] << {:uid => id}
            id
        end
        # Make sure the accepted documentation types are in the database
        def save_default_docs
            self.valid_docs.each do |doc|
                begin
                    self.db[:docs] << {:name => doc.to_s}
                rescue
                    #ignore
                end
            end
            self.db[:docs].all.each{|ds| self.doc_hash[ds[:name].to_sym] = ds[:id]}
        end
    end
end