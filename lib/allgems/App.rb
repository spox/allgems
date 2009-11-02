require 'sinatra'
require 'allgems/ViewHelpers'
require 'allgems/Specer'
require 'rubygems/specification'

module AllGems
    
    class App < ::Sinatra::Default

        include AllGems::ViewHelpers

        @@root = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
        set :root, @@root
        set :app_file, __FILE__

        before do
            @environment = options.environment
        end
        
        get '/stylesheets/:stylesheet.css' do
            sass params[:stylesheet].to_sym
        end
        
        # root is nothing, so redirect people on their way
        get '/' do
            redirect '/gems'
        end

        # generate the gem listing
        get '/gems/?' do
            show_layout = params[:layout] != 'false'
            @show_as = params[:as] && params[:as] == 'table' ? 'table' : 'columns'
            if(@search = params[:search])
                @gems = do_search(params[:search])
                if(@gems.size == 1)
                    redirect "/gems/#{@gems[:name]}" # send user on their way if we only get one result
                end
            else
                page = params[:page] ? params[:page].to_i : 1
                @gems = AllGems.db[:gems].paginate(page, 30)
                puts "we have #{@gems.count} gems"
            end
            haml "gems_#{@show_as}".to_sym, :layout => show_layout
        end

        # send the the correct place
        get %r{/gems/([\w\-\_]+)/?([\d\.]+)?/?} do
            gem = params[:captures][0]
            version = params[:captures].size > 1 ? params[:captures][1] : nil
            @gem = load_gem_spec(gem, version)
            @versions = AllGems.db[:versions].join(:gems, :id => :gem_id).filter(:name => gem).order(:version.desc).select(:version, :release)
            haml :gem
        end

        private

        def load_gem_spec(gem, version=nil)
            version ||= get_latest(gem)
            raise 'failed gem' unless version
            Specer.get_spec(gem, version)
        end

        # gem:: name of the gem
        # Returns the latest version of the given gem or nil
        def get_latest(gem)
            AllGems.db[:versions].join(:gems, :id => :gem_id).filter(:name => gem).order(:version.desc).limit(1).select(:version).map(:version)[0]
        end
    end
end