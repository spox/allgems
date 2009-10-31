%w(allgems allgems/App haml sass sequel sequel/extensions/pagination).each{|f|require f}

data_dir = '/tmp/allgems'
db_file = "#{data_dir}/allgems.db"
AllGems.defaulterize

# SET THESE IF YOU DON'T WANT DEFAULTS #

AllGems.data_directory = data_dir
AllGems.initialize_db(Sequel.connect("sqlite://#{db_file}"))

disable :run
AllGems::App.set({
  :environment => :development
})
run AllGems::App