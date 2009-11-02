%w(allgems allgems/App haml sass sequel sequel/extensions/pagination).each{|f|require f}

data_dir = '/tmp/allgems'
db_file = "#{data_dir}/allgems.db"
AllGems.defaulterize

# SET THESE IF YOU DON'T WANT DEFAULTS #

AllGems.data_directory = ENV['DATA_DIR']
AllGems.initialize_db(Sequel.connect("sqlite://#{ENV['DATA_DB']}"))

disable :run
AllGems::App.set({
  :environment => :development
})
run AllGems::App