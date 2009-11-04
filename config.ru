%w(allgems allgems/App haml sass sequel sequel/extensions/pagination).each{|f|require f}

AllGems.defaulterize
AllGems.data_directory = ENV['DATA_DIR']
AllGems.initialize_db(Sequel.connect("sqlite://#{ENV['DATA_DB']}"))

disable :run
AllGems::App.set({
  :environment => :development
})
run AllGems::App