require 'logger'
module AllGems
    class << self
        attr_accessor :data_directory, :logger, :db
        def defaulterize
            @data_directory = nil
            @doc_format = ['darkfish']
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

    end
end