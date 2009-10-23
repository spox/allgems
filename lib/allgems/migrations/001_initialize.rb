Class.new(Sequel::Migration) do
    def up
        create_table(:gems) do
            String :name, :null => false, :unique => true
            String :summary
            primary_key :id, :null => false
        end
        create_table(:platforms) do
            String :platform, :null => false, :unique => true
            primary_key :id, :null => false
        end
        create_table(:versions) do
            String :version, :null => false
            foreign_key :gem_id, :table => :gems, :null => false
            foreign_key :platform_id, :table => :platforms, :null => false
            index [:gem_id, :version, :platform_id], :unique => true
            primary_key :id, :null => false
        end
    end
    def down
        drop_table(:versions)
        drop_table(:platforms)
        drop_table(:gems)
    end
end