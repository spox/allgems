require 'sinatra'
require 'allgems/ViewHelpers'
require 'allgems/Specer'

module AllGems
    
    class App < ::Sinatra::Default

        include AllGems::ViewHelpers

        @@root = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
        set :root, @@root
        set :app_file, __FILE__

        before do
            @environment = options.environment
            @specer = AllGems::Specer.new
            if(request.cookies['lid'])
                @lid_name = AllGems.db[:lid_version].join(:versions, :id => :version_id).join(:gems, :id => :gem_id).select(:name, :version).first
                @lid_name = @lid_name ? "#{@lid_name[:name]}-#{@lid_name[:version]}" : nil
            else
                @lid_name = nil
            end
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
            set = gems_dataset.order(:name.asc).distinct(:name)
            @page = params[:page] ? params[:page].to_i : 1
            if(@search = params[:search])
                set = do_search(params[:search])
                if(set.count == 1 && @clsmth.nil?)
                    redirect "/gems/#{set.first[:name]}" # send user on their way if we only get one result
                end
            end
            @gems = set.paginate(@page, 30)
            haml "gems_#{@show_as}".to_sym, :layout => show_layout
        end

        # send the the correct place
        get %r{/gems/([\w\-\_]+)/?([\d\.]+)?/?} do
            gem = params[:captures][0]
            version = params[:captures].size > 1 ? params[:captures][1] : nil
            @gem = load_gem_spec(gem, version)
            @versions = versions_dataset.join(:gems, :id => :versions__gem_id).filter(:name => gem).order(:version.desc).select(:version, :release)
            haml :gem
        end

        get %r{/lid/(\w+)$} do
            lid = params[:captures][0]
            if(AllGems.db[:lids].filter(:uid => lid).count > 0)
                response.set_cookie('lid', :value => lid, :path => '/', :expires => Time.now + 99999)
            else
                # TODO: report error
            end
            redirect '/'
        end
            
        get %r{/glid/([\w\-\_]+)/([\d\.]+)/?} do
            name = params[:captures][0]
            version = params[:captures][1]
            vid = AllGems.db[:versions].join(:gems, :id => :gem_id).filter(:name => name, :version => version).select(:versions__id.as(:id)).first[:id]
            lv = AllGems.db[:lid_version].join(:lids, :id => :lid_id).filter(:version_id => vid).select(:lids__id.as(:lid)).first
            lid = nil
            unless(lv)
                spec = load_gem_spec(name, version)
                deps = spec.dependencies.map do |dep|
                    spec = Gem::SpecFetcher.fetcher.fetch dep, true
                    spec = spec[0][0]
                    [spec.name, spec.version.version]
                end
                deps << [name, version]
                lid = AllGems.uid
                lid_id = AllGems.db[:lids].filter(:uid => lid).select(:id).first[:id]
                AllGems.db[:lid_version] << {:lid_id => lid_id, :version_id => vid}
                AllGems.link_id(lid, deps)
            else
                lid = lv[:lid]
            end
            redirect "/lid/#{lid}" # change this to display URL with clickable link
        end

        get %r{/unlid/?} do
            response.delete_cookie('lid', :path => '/')
            redirect '/'
        end

# This stuff is for if I can ever get frames to work properly with sdoc (doubtful)
#         get %r{/doc/(.+)} do
#             parts = params[:captures][0].split('/')
#             @gem_name = parts[0]
#             @gem_version = parts[1]
#             @path = "/docs/#{params[:captures][0]}"
#             haml :doc, :layout => false
#         end
# 
#         get %r{/load/([^/]+)/(.+)/?} do
#             @gem_name = params[:captures][0]
#             @gem_version = params[:captures][1]
#             haml :load, :layout => false
#         end

        private

        # Returns the gems table dataset filtered if the lid is set
        def gems_dataset
            lid = request.cookies['lid']
            if(lid)
                AllGems.db[:versions].join(:gems, :id => :gem_id).join(:gems_lids, :version_id => :versions__id).join(:lids, :id => :gems_lids__lid_id).select(:gems__name.as(:name), :gems__id.as(:id)).order(:id)
            else
                AllGems.db[:gems]
            end
        end

        # Returns the versions table dataset filtered if the lid is set
        def versions_dataset
            lid = request.cookies['lid']
            if(lid)
                AllGems.db[:versions].join(:gems_lids, :version_id => :versions__id).join(:lids, :id => :gems_lids__lid_id).select(:versions__id.as(:id), :versions__version.as(:version), :versions__release.as(:release), :versions__gem_id.as(:gem_id))
            else
                AllGems.db[:versions]
            end
        end

        # Finds a gem specifcation
        def load_gem_spec(gem, version=nil)
            version ||= get_latest(gem)
            raise 'failed gem' unless version
            @specer.get_spec(gem, version)
        end

        # gem:: name of the gem
        # Returns the latest version of the given gem or nil
        def get_latest(gem)
            versions_dataset.join(:gems, :gems__id => :versions__gem_id).filter(:name => gem).order(:version.desc).limit(1).select(:version).map(:version)[0]
        end

        # terms:: terms to search on
        # Search terms will be parsed and limited to a class/method reduced subset if given. This means
        # search terms given like:
        #   "class:Timer thread"
        # will search for all gems containing a Timer class, then search that subset using the term "thread". 
        # TODO: This needs to be redone to provide proper searching. Hopefully with FTS support
        def do_search(terms)
            terms, methods, classes, cls_mth = parse_terms(terms)
            set = nil
            unless(methods.empty?)
                set = search_methods(methods)
            end
            unless(classes.empty?)
                res = search_classes(classes)
                if(set)
                    set.union(res) unless res.nil?
                else
                    set = res
                end
            end
            unless(cls_mth.empty?)
                res = search_classes_methods(cls_mth)
                if(set)
                    set.union(res) unless res.nil?
                else
                    set = res
                end
            end
            set = gems_dataset unless set
            unless(terms.empty?)
                names = set.filter("#{[].fill('name LIKE ?', 0, terms.size).join(' OR ')}", *terms).order(:name.asc)
                desc = set.filter("#{[].fill('description LIKE ?', 0, terms.size).join(' OR ')}", *terms).order(:name.asc)
                summ = set.filter("#{[].fill('summary LIKE ?', 0, terms.size).join(' OR ')}", *terms).order(:name.asc)
                names.union(desc).union(summ)
            else
                set
            end
        end

        # ms:: Array of terms to search
        # Searches for any methods matching terms
        def search_methods(ms)
            ms.map!{|x|x.gsub('*', '%')}
            res = AllGems.db[:methods].join(:classes_methods, :method_id => :id).join(:versions, :id => :version_id).filter("#{[].fill('method LIKE ?', 0, ms.size).join(' OR ')}", *ms)
            return nil if res.empty?
            res = gems_dataset.filter(:id => res.map(:gem_id))
            res.empty? ? nil : res
        end

        # ms:: Array of terms to search
        # Searches for any classes matching terms
        def search_classes(ms)
            ms.map!{|x|x.gsub('*', '%')}
            res = AllGems.db[:classes].join(:classes_gems, :class_id => :id).join(:versions, :id => :version_id).filter("#{[].fill('class LIKE ?', 0, ms.size).join(' OR ')}", *ms)
            return nil if res.empty?
            res = gems_dataset.filter(:id => res.map(:gem_id))
            res.empty? ? nil : res
        end

        # ms:: Array of class/method pairs
        # Searches for gems containing the Class#method pairs
        # TODO: join Gems table and grab name to throw in clsmth results for ease in displaying
        def search_classes_methods(ms)
            res = AllGems.db[:methods].join(:classes_methods, :method_id => :id).join(:versions, :id => :version_id).join(:gems, :id => :versions__gem_id).join(:classes, :id => :classes_methods__class_id).filter("#{[].fill('(class LIKE ? AND method LIKE ?)', 0, ms.to_a.size).join(' OR ')}", *ms.flatten).select(:class, :method, :gem_id, :name, :version)
            return nil if res.empty?
            @clsmth = {}
            res.each do |row|
                key = "#{row[:class]}##{row[:method]}-#{row[:gem_id]}"
                @clsmth[key] = {:class => row[:class], :method => row[:method], :gem => row[:name], :versions => []} unless @clsmth[key]
                @clsmth[key][:versions] <<  row[:version]
            end
            res = gems_dataset.filter(:id => res.map(:gem_id))
            res.empty? ? nil : res
        end

        # terms:: search terms
        # Parses the terms to figure out how search should be performed. 
        # Class searches:
        #   class:MyClass -> classes => ['MyClass']
        #   MyClass::Fubar -> classes => ['MyClass::Fubar']
        # Method searches: 
        #   method:fubar -> methods => ['fubar']
        # Class method searches:
        #   ClassName#method_name -> classes_methods => [{:class => 'ClassName', :method => 'method_name'}]
        def parse_terms(terms)
            terms = terms.split
            del = []
            methods = []
            classes = []
            classes_methods = []
            terms.each do |x|
                [[methods, 'method:'], [classes, 'class:']].each do |y|
                    if(x.downcase.slice(0, y[1].length) == y[1])
                        del << x
                        y[0] << x.slice(y[1].length, x.length)
                    end
                end
                if(x =~ /^([\w:]+\w)[\.#](\w+[\?\!]?)$/)
                    del << x
                    classes_methods << [$1, $2]
                elsif(x =~ /^([\w:]+:\w+)$/)
                    del << x
                    classes << x
                end
            end
            terms = (terms - del).map{|x| "%#{x}%"}
            [terms,methods,classes,classes_methods]
        end

    end
end