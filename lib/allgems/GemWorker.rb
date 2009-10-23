require 'rubygems/installer'

module AllGems
    class GemWorker
        @glock = Mutex.new
        @slock = Mutex.new
        # :name:: name of the gem
        # :version:: version of the gem
        # :database:: database connection
        def self.process(args)
            spec,uri = self.get_spec(args[:name], args[:version])
            raise NameError.new("Name not found: #{args[:name]} - #{args[:version]}") if spec.nil?
            basedir = "#{AllGems.data_directory}/#{spec.name}/#{spec.version.version}"
            FileUtils.mkdir_p basedir
            gempath = self.fetch(spec, uri)
            gempath = self.save(gempath, "#{basedir}/#{spec.full_name}.gem")
            self.unpack(gempath, basedir)
            self.generate_documentation(spec, basedir)
            self.save_data(spec, args[:database])
        end

        # name:: name of gem
        # version:: version of gem
        # Fetches the Gem::Specification for the given gem
        def self.get_spec(name, version)
            dep = Gem::Dependency.new(name, version)
            spec = nil
            @glock.synchronize{spec = Gem::SpecFetcher.fetcher.fetch dep, true}
            spec[0]
        end
        
        # spec:: Gem::Specification
        # uri:: URI of gem files home
        # Fetch the gem file from the server. Returns the path to the gem
        # on the local machine
        def self.fetch(spec, uri)
            begin
                path = nil
                @glock.synchronize{path = Gem::RemoteFetcher.fetcher.download spec, uri}
                return path
            rescue Gem::RemoteFetcher::FetchError
                retry
            end
        end

        # gempath:: path to gem file
        # newname:: path to move gem file to
        # Moves the gem to the given location
        def self.save(gempath, newpath)
            FileUtils.mv gempath, newpath
            newpath
        end

        # path:: path to the gem file
        # basedir:: directory to unpack in
        # Unpacks the gem into the basedir under the 'unpack' directory
        def self.unpack(path, basedir)
            Gem::Installer.new(path, :unpack => true).unpack "#{basedir}/unpack"
            FileUtils.rm(path)
            true
        end

        # dir:: base directory location of gem contents
        # Generates the documentation of the given directory of ruby code. Appends
        # 'unpack' to the given directory for code discovery. Documentation will
        # be output in "#{dir}/doc"
        def self.generate_documentation(spec, dir)
            args = []
            args << "--format=#{AllGems.rdoc_format}" unless AllGems.rdoc_format.nil?
            args << '-aFNqH' << "--op=#{dir}/doc" << "#{dir}/unpack"
            result = self.build_docs(args.join(' '))
            raise DocError.new(spec.name, spec.version) unless result
            result
        end

        # args:: arguments to send to rdoc
        # Here we kick the rdoc generation out to a process. I tried, in vain, to
        # generate the rdoc using the rdoc API, and it was inconsistent at best. This
        # works, so, yay, I guess.
        def self.build_docs(args)
            pro = nil
            output = []
            begin
                pro = IO.popen("rdoc #{args}")
                until(pro.closed? || pro.eof?)
                    output << pro.gets
                end
            ensure
                if(pro.nil?)
                    return false
                else
                    pid, status = Process.waitpid2(pro.pid)
                    return status == 0
                end
            end
        end

        # spec:: Gem::Specification
        # Save data to the database about this gem
        def self.save_data(spec, db)
            @slock.synchronize do
                gid = db[:gems].filter(:name => spec.name).first
                gid = gid.nil? ? db[:gems].insert(:name => spec.name) : gid[:id]
                pid = db[:platforms].filter(:platform => spec.platform).first
                pid = pid.nil? ? db[:platforms].insert(:platform => spec.platform) : pid[:id]
                db[:versions] << {:version => spec.version.version, :gem_id => gid, :platform_id => pid}
                db[:gems].filter(:id => gid).update(:summary => spec.summary)
            end
            true
        end

        # Exception class for failed documentation creation
        class DocError < StandardError
            attr_reader :gem_name
            attr_reader :gem_version
            def initialize(gn, gv)
                @gem_name = gn
                @gem_version = gv
            end
            def to_s
                "Failed to create documentation for: #{@gem_name}-#{@gem_version}."
            end
        end
    end
end