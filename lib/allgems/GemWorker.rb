require 'net/http'
require 'uri'
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
            gempath = self.fetch(spec, uri, "#{basedir}/#{spec.full_name}.gem")
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
        # save_path:: path to save gem
        # Fetch the gem file from the server. Returns the path to the gem
        # on the local machine
        def self.fetch(spec, uri, save_path)
            FileUtils.touch(save_path)
            begin
                remote_path = "#{uri}/gems/#{spec.full_name}.gem"
                remote_uri = URI.parse(remote_path)
                file = File.open(save_path, 'w')
                file.write(self.fetch_remote(remote_uri))
                save_path
            rescue Exception => boom
            puts "ERROR: #{boom}\n#{boom.backtrace.join("\n")}"
                raise FetchError.new(spec.name, spec.version, remote_path)
            end
        end

        # uri:: URI of gem
        # depth:: number of times called
        # Fetch gem from given URI
        def self.fetch_remote(uri, depth=0)
            raise IOError.new("Depth too deep") if depth > 9
            response = Net::HTTP.get_response(uri)
            if(response.is_a?(Net::HTTPSuccess))
                response.body
            elsif(response.is_a?(Net::HTTPRedirection))
                puts "Location: #{response['location']} : #{response}"
                self.fetch_remote(URI.parse(response['location']), depth + 1)
            else
                raise IOError.new("Unknown response type: #{response}")
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
        # depth:: number of times called
        # Unpacks the gem into the basedir under the 'unpack' directory
        def self.unpack(path, basedir, depth=0)
            begin
                Gem::Installer.new(path, :unpack => true).unpack "#{basedir}/unpack"
                FileUtils.chmod_R(0755, "#{basedir}/unpack") # fix any bad permissions
                FileUtils.rm(path)
            rescue
                raise IOError.new("Failed to unpack gem: #{path}") if File.size(path) < 1 || depth > 10
                self.unpack(path, basedir, depth+1)
            end
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

        class FetchError < StandardError
            attr_reader :gem_name
            attr_reader :gem_version
            attr_reader :uri
            def initialize(gn, gv, u)
                @gem_name = gn
                @gem_version = gv
                @uri = u
            end
        end
    end
end