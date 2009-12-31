Class.new(Sequel::Migration) do
    def up
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
        # Special note for these two tables:
        # The gems_lids table is the associations for what versions of gems
        # are associated with a lid
        # The lid_version table is the association of a lid to a particular
        # version of a gem. It is used when a lid is created through the web
        # interface for a particular gem.
        AllGems.db.create_table(:gems_lids) do
            foreign_key :lid_id, :null => false, :table => :lids
            foreign_key :version_id, :null => false, :table => :versions
            primary_key [:lid_id, :version_id]
        end
        AllGems.db.create_table(:lid_version) do
            foreign_key :version_id, :null => false, :table => :versions
            foreign_key :lid_id, :null => false, :table => :lids
            primary_key [:version_id, :lid_id]
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
        AllGems.db.drop_table(:lid_version)
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