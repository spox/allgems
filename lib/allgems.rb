module AllGems
    class << self
        attr_accessor :data_directory, :rdoc_format, :rdoc_version, :logger, :db
        def defaulterize
            @data_directory = nil
            @rdoc_format = 'darkfish'
            @rdoc_version = '2.3.0' # hanna is dependent on this
            @logger = nil
            @db = nil
        end
        # db: Sequel::Database
        # Run any migrations needed
        # NOTE: Call before using the database
        def initialize_db(db)
            require 'sequel/extensions/migration'
            Sequel::Migrator.apply(db, "#{File.expand_path(__FILE__).gsub(/\/[^\/]+$/, '')}/allgems/migrations")
            self.db = db
        end
    end
end