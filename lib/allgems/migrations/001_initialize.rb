Class.new(Sequel::Migration) do
    def up
#         AllGems.db << "CREATE TABLE gems (
#                         name VARCHAR NOT NULL UNIQUE COLLATE NOCASE,
#                         summary TEXT,
#                         description TEXT,
#                         id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT)"
        create_table(:gems) do
            String :name, :null => false, :unique => true
            String :summary
            String :description
            primary_key :id, :null => false
        end
        AllGems.db.create_table(:versions) do
            String :version, :null => false
            Time :release, :null => false
            foreign_key :gem_id, :table => :gems, :null => false
            index [:gem_id, :version], :unique => true
            primary_key :id, :null => false
        end
#         AllGems.db << "CREATE TABLE specs (
#                         full_name VARCHAR NOT NULL UNIQUE COLLATE NOCASE,
#                         spec TEXT NOT NULL,
#                         uri VARCHAR NOT NULL,
#                         version_id INTEGER NOT NULL REFERENCES versions,
#                         id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT)"
        AllGems.db.create_table(:specs) do
            String :full_name, :null => false, :unique => true
            String :spec, :null => false
            String :uri, :null => false
            foreign_key :version_id, :table => :versions, :null => false, :unique => true
            primary_key :id, :null => false
        end
        AllGems.db.create_table(:classes) do
            String :class, :null => false, :unique => true
            primary_key :id, :null => false
        end
        AllGems.db.create_table(:methods) do
            String :method, :null => false, :unique => true
            primary_key :id, :null => false
        end
        AllGems.db.create_table(:classes_methods) do
            foreign_key :method_id, :table => :methods
            foreign_key :class_id, :table => :classes
            foreign_key :version_id, :table => :versions
            primary_key [:method_id, :class_id, :version_id]
        end
        AllGems.db.create_table(:classes_gems) do
            foreign_key :class_id, :table => :classes
            foreign_key :version_id, :table => :versions
            primary_key [:class_id, :version_id]
        end
        AllGems.db.create_table(:lids) do
            String :uid, :null => false, :unique => true
            primary_key :id, :null => false
        end
        AllGems.db.create_table(:gems_lids) do
            foreign_key :lids_id, :null => false, :table => :lids
            foreign_key :version_id, :null => false, :table => :versions
            primary_key [:lids_id, :version_id]
        end
        AllGems.db.create_table(:docs) do
            String :name, :null => false, :unique => true
            primary_key :id, :null => false
        end
        AllGems.db.create_table(:docs_versions) do
            foreign_key :doc_id, :null => false, :table => :docs
            foreign_key :version_id, :null => false, :table => :versions
            primary_key [:doc_id, :version_id]
        end
    end
    def down
        AllGems.db.drop_table(:docs_versions)
        AllGems.db.drop_table(:docs)
        AllGems.db.drop_table(:gems_lids)
        AllGems.db.drop_table(:lids)
        AllGems.db.drop_table(:classes_gems)
        AllGems.db.drop_table(:methods)
        AllGems.db.drop_table(:classes)
        AllGems.db.drop_table(:specs)
        AllGems.db.drop_table(:versions)
        AllGems.db.drop_table(:platforms)
        AllGems.db.drop_table(:gems)
    end
end