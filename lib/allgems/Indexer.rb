require 'nokogiri'

module AllGems
    class Indexer
        class << self
            # spec:: Gem::Specification
            # directory:: documentation directory
            # format:: format documentation is in
            # Builds an index of classes, modules, and methods and stores
            # them for searching
            def index_gem(spec, directory, format)
                return # not working yet
                return if format == :sdoc # not implemented yet
                @lock = Mutex.new
                @list = []
                return if self.already_processing?(spec)
                data = nil
                case format
                    when :hanna
                        data = self.index_hanna(directory)
                    when :rdoc
                        data = self.index_rdoc(directory)
                    when :sdoc
                        data = self.index_sdoc(directory)
                    else
                        raise "i don't know what i'm supposed to do here"
                end
                self.save(spec, data)
                AllGems.logger.info "Gem index is complete for #{spec.full_name}"
            end
            # dir:: path to documentation directory
            # Discovers Modules, Classes, and methods from a hanna installation
            # results: {:modclasses => [modclasses], :methods => {:method => 'name', :location => 'Some::Class'}}
            def index_hanna(dir)
                results = {:modclass => [], :methods => []}
                doc = Nokogiri::HTML(File.read("#{dir}/fr_method_index.html"))
                #       <ol class='methods' id='index-entries'>
                search = doc.search('//ol')
                search.shift
                search.shift.children.each do |l|
                    next if l.blank?
                    parts = l.content.scan(/^(\w+) \((\w+)\)$/)
                    results[:methods] << {:method => parts[0], :location => parts[1]}
                end
                doc = Nokogiri::HTML(File.read("#{dir}/fr_class_index.html"))
                search = doc.search('//li')
                search.children.each do |l|
                    next if l.blank? || l.content.slice(0) == ' '
                    results[:modclass] << l.content
                end
                results
            end
            # dir:: path to documentation directory
            # Discovers Modules, Classes, and methods from an rdoc installation
            # results: {:modclasses => [modclasses], :methods => {:method => 'name', :location => 'Some::Class'}}
            def index_rdoc(dir)
                results = {:modclass => [], :methods => []}
                doc = Nokogiri::HTML(File.read("#{dir}/index.html"))
                uls = doc.search('//ul')
                raise Error.new unless uls.size == 3
                uls.shift # no need for files
                [:modclass,:methods].each do |t|
                    uls.shift.children.each do |l|
                        next if l.blank?
                        if(t == :methods)
                            parts = l.content.scan(/^.*?(\w+).*?\w+$/)
                            results[t] << {:method => parts[0], :location => parts[1]}
                        else
                            results[t] << l.content
                        end
                    end
                end
                results
            end
            # dir:: path to documentation directory
            # Discovers Modules, Classes, and methods from an sdoc installation
            # results: {:modclasses => [modclasses], :methods => {:method => 'name', :location => 'Some::Class'}}
            # TODO: indexing this documentation is going to be a serious pain
            def index_sdoc(dir)
                {:modclass => [], :methods => []}
            end
            # data:: data returned from one of the index methods
            # Saves data to database
            def save(spec, data)
                vid = AllGems.db[:versions].join(:gems, :id => :gem_id)
                vid.join(:platforms, :id => :versions__platform_id)
                vid.filter(:name => spec.name, :version => spec.version, :platform => spec.platform)
                raise "I don't know what spec I am" if vid.first.nil?
                vid = vid.first[:versions__id]
                data[:modclass].each{|c| self.add_class(c, vid)}
                data[:methods].each do |mc|
                    cid = self.add_class(mc[:location], vid)
                    mid = self.add_method(mc[:method])
                    AllGems.db[:classes_methods] << {:class_id => id, :method_id => mid}
                end
            end

            # cls:: class name
            # vid:: version id from from versions table
            # Add a new class name and associate it with the gem it's from
            def self.add_class(cls, vid)
                id = AllGems.db[:classes].filter(:class => cls).first
                unless(id)
                    id = AllGems.db[:classes] << {:class => cls}
                    AllGems.db[:classes_gems] << {:class_id => id, :version_id => vid}
                else
                    id = id[:id]
                end
                id
            end

            # mthd:: method name
            # add a new method name to the database
            def self.add_method(mthd)
                id = AllGems.db[:methods].filter(:method => mthd).first
                unless(id)
                    id = AllGems.db[:methods] << {:method => mthd}
                else
                    id = id[:id]
                end
                id
            end
            
            # name:: Gem::Specification
            # Check if someone else already requested processing for this gem (common
            # if there are multiple documentation formats being used)
            def already_processing?(spec)
                @lock.synchronize do
                    return true @list.include?(spec.full_name)
                    @list << spec.full_name
                end
                false
            end
        end
    end
end