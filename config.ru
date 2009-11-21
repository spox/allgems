%w(allgems allgems/App haml sass sequel sequel/extensions/pagination).each{|f|require f}

AllGems.defaulterize
AllGems.data_directory = ENV['DATA_DIR']
AllGems.dbstring = ENV['DB_STRING']
AllGems.initialize_db

disable :run
AllGems::App.set({
  :environment => :development
})
run AllGems::App