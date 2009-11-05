Class.new(Sequel::Migration) do
    def up
        AllGems.db << "CREATE TABLE gems (
                        name VARCHAR NOT NULL UNIQUE COLLATE NOCASE,
                        summary TEXT,
                        description TEXT,
                        id INTEGER NOT NULL PRIMARY KEY)"
#         create_table(:gems) do
#             String :name, :null => false, :unique => true
#             String :summary
#             String :description
#             primary_key :id, :null => false
#         end
        AllGems.db.create_table(:platforms) do
            String :platform, :null => false, :unique => true
            primary_key :id, :null => false
        end
        AllGems.db.create_table(:versions) do
            String :version, :null => false
            Time :release, :null => false
            foreign_key :gem_id, :table => :gems, :null => false
            foreign_key :platform_id, :table => :platforms, :null => false
            index [:gem_id, :version, :platform_id], :unique => true
            primary_key :id, :null => false
        end
        AllGems.db.create_table(:specs) do
            String :spec, :null => false
            foreign_key :version_id, :table => :versions, :null => false
            index [:spec, :version_id], :unique => true
            primary_key :id, :null => false
        end
    end
    def down
        AllGems.db.drop_table(:specs)
        AllGems.db.drop_table(:versions)
        AllGems.db.drop_table(:platforms)
        AllGems.db.drop_table(:gems)
    end
end