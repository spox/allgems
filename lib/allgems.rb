require 'logger'
module AllGems
    class << self
        attr_accessor :data_directory, :rdoc_format, :rdoc_version, :logger, :db
        def defaulterize
            @data_directory = nil
            @rdoc_format = 'darkfish'
            @rdoc_version = '2.3.0' # hanna is dependent on this
            @logger = Logger.new(nil)
            @db = nil
            @tg = nil
            @ti = nil
            @refresh = Time.now.to_i + 3600
        end
        # db: Sequel::Database
        # Run any migrations needed
        # NOTE: Call before using the database
        def initialize_db(db)
            require 'sequel/extensions/migration'
            Sequel::Migrator.apply(db, "#{File.expand_path(__FILE__).gsub(/\/[^\/]+$/, '')}/allgems/migrations")
            self.db = db
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

    end
end