require 'allgems'
require 'allgems/App'

disable :run
AllGems::App.set({
  :environment => :production
})
run AllGems::App