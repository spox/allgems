require 'net/http'
require 'uri'
require 'rubygems/installer'

module AllGems
    class GemWorker
        class << self
            # Get the worker ready to go
            def setup
                @glock = Mutex.new
                @slock = Mutex.new
                @pool = ActionPool::Pool.new(:max_threads => 10, :a_to => 60*5)
            end
            # :name:: name of the gem
            # :version:: version of the gem
            # :database:: database connection
            def process(args)
                AllGems.logger.info "Processing gem: #{args[:name]}-#{args[:version]}"
                spec,uri = self.get_spec(args[:name], args[:version])
                raise NameError.new("Name not found: #{args[:name]} - #{args[:version]}") if spec.nil?
                basedir = "#{AllGems.data_directory}/#{spec.name}/#{spec.version.version}"
                FileUtils.mkdir_p "#{basedir}/unpack"
                AllGems.logger.info "Created new directory: #{basedir}/unpack"
                gempath = self.fetch(spec, uri, "#{basedir}/#{spec.full_name}.gem")
                self.unpack(gempath, basedir)
                self.generate_documentation(spec, basedir)
                self.save_data(spec, args[:database])
            end

            # name:: name of gem
            # version:: version of gem
            # Fetches the Gem::Specification for the given gem
            def get_spec(name, version)
                AllGems.logger.info "Fetching gemspec for #{name}-#{version}"
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
            def fetch(spec, uri, save_path)
                AllGems.logger.info "Fetching gem from: #{uri}/gems/#{spec.full_name}.gem"
                FileUtils.touch(save_path)
                begin
                    remote_path = "#{uri}/gems/#{spec.full_name}.gem"
                    remote_uri = URI.parse(remote_path)
                    file = File.open(save_path, 'wb')
                    file.write(self.fetch_remote(remote_uri))
                    file.close
                    save_path
                rescue Exception => boom
                    raise FetchError.new(spec.name, spec.version, remote_path, boom)
                end
            end

            # uri:: URI of gem
            # depth:: number of times called
            # Fetch gem from given URI
            def fetch_remote(uri, depth=0)
                raise IOError.new("Depth too deep") if depth > 9
                response = Net::HTTP.get_response(uri)
                if(response.is_a?(Net::HTTPSuccess))
                    response.body
                elsif(response.is_a?(Net::HTTPRedirection))
                    self.fetch_remote(URI.parse(response['location']), depth + 1)
                else
                    raise IOError.new("Unknown response type: #{response}")
                end
            end

            # gempath:: path to gem file
            # newname:: path to move gem file to
            # Moves the gem to the given location
            def save(gempath, newpath)
                AllGems.logger.info "Moving #{gempath} to #{newpath}"
                FileUtils.mv gempath, newpath
                newpath
            end

            # path:: path to the gem file
            # basedir:: directory to unpack in
            # depth:: number of times called
            # Unpacks the gem into the basedir under the 'unpack' directory
            def unpack(path, basedir, depth=0)
                AllGems.logger.info "Unpacking gem: #{path}"
                begin
                    Gem::Installer.new(path, :unpack => true).unpack "#{basedir}/unpack"
                    FileUtils.chmod_R(0755, "#{basedir}/unpack") # fix any bad permissions
                    FileUtils.rm(path)
                rescue
                    if(File.size(path) < 1 || depth > 10)
                        raise IOError.new("Failed to unpack gem: #{path}") unless self.direct_unpack(path, basedir)
                    else
                        self.unpack(path, basedir, depth+1)
                    end
                end
                true
            end

            # path:: path to the gem file
            # basedir:: directory to unpack in
            # Last ditch effort to unpack the gem
            def direct_unpack(path, basedir)
                AllGems.logger.warn "Attempting forcible unpack on: #{path}"
                unpackdir = path.slice(0, path.rindex('.'))
                self.run_command("cd #{basedir} && gem unpack #{path} && mv #{unpackdir}/* #{basedir}/unpack/ && rm -rf #{unpackdir}")
            end

            # dir:: base directory location of gem contents
            # Generates the documentation of the given directory of ruby code. Appends
            # 'unpack' to the given directory for code discovery. Documentation will
            # be output in "#{dir}/doc"
            def generate_documentation(spec, dir)
                AllGems.logger.info "Generating documentation for #{spec.full_name}"
                AllGems.doc_format.each do |f|
                    command = nil
                    args = []
                    case f.to_sym
                        when :rdoc
                            command = 'rdoc'
                            args << '--format=darkfish' << '-aFNqH' << "--op=#{dir}/doc/rdoc" << "#{dir}/unpack"
                        when :sdoc
                            command = 'sdoc'
                            args << '-T direct' << "-o #{dir}/doc/sdoc" << "#{dir}/unpack"
                        when :hanna
                            command = "ruby #{AllGems.hanna_hack}"
                            args << "-o #{dir}/doc/hanna" << "#{dir}/unpack"
                        else
                            next # if we don't know what to do with it, skip it
                    end
                    action = lambda do |dir, command, args, f|
                        FileUtils.rm_r("#{dir}/doc/#{f}", :force => true) # make sure we are clean before we get dirty
                        result = self.run_command("#{command} #{args}")
                        raise DocError.new(spec.name, spec.version) unless result
                        AllGems.logger.info "Completed documentation for #{spec.full_name}"
                        FileUtils.chmod_R(0755, "#{dir}/doc/#{f}") # fix any bad permissions
                    end
                    @pool << [action, [dir.dup, command.dup, args.join(' '), f]]
                end
            end

            # command:: command to run
            # return_output:: return output
            # Runs a command. Returns true if status returns 0. If return_output is true,
            # return value is: [status, output]
            def run_command(command, return_output=false)
                AllGems.logger.debug "Command to be executed: #{command}"
                pro = nil
                output = []
                status = nil
                begin
                    pro = IO.popen(command)
                    Process.setpriority(Process::PRIO_PROCESS, pro.pid, 19) unless OS.windows?
                    until(pro.closed? || pro.eof?)
                        output << pro.gets
                    end
                ensure
                    unless(pro.nil?)
                        pid, status = Process.waitpid2(pro.pid)
                    else
                        status = 1
                    end
                end
                return return_output ? [status == 0, output.join] : status == 0
            end

            # spec:: Gem::Specification
            # Save data to the database about this gem
            def save_data(spec, db)
                AllGems.logger.info "Saving meta data for #{spec.full_name}"
                @slock.synchronize do
                    gid = db[:gems].filter(:name => spec.name).first
                    gid = gid.nil? ? db[:gems].insert(:name => spec.name) : gid[:id]
                    pid = db[:platforms].filter(:platform => spec.platform).first
                    pid = pid.nil? ? db[:platforms].insert(:platform => spec.platform) : pid[:id]
                    vid = db[:versions] << {:version => spec.version.version, :gem_id => gid, :platform_id => pid, :release => spec.date}
                    db[:specs] << {:version_id => vid, :spec => [Marshal.dump(spec)].pack('m')}
                    db[:gems].filter(:id => gid).update(:summary => spec.summary)
                    db[:gems].filter(:id => gid).update(:description => spec.description)
                end
                AllGems.logger.info "Meta data saving complete for #{spec.full_name}"
                true
            end

            # Make a parent error class that we can specialize
            class Error < StandardError
                attr_reader :original
                def initialize(e=nil)
                    @original = e.nil? ? self : e
                end
            end

            # Exception class for failed documentation creation
            class DocError < Error
                attr_reader :gem_name, :gem_version
                def initialize(gn, gv, e=nil)
                    super(e)
                    @gem_name = gn
                    @gem_version = gv
                end
                def to_s
                    "Failed to create documentation for: #{@gem_name}-#{@gem_version}."
                end
            end

            # Exception class for failed gem fetching
            class FetchError < Error
                attr_reader :gem_name, :gem_version, :uri
                def initialize(gn, gv, u, e=nil)
                    super(e)
                    @gem_name = gn
                    @gem_version = gv
                    @uri = u
                end
                def to_s
                    "Failed to fetch #{@gem_name}-#{@gem_version}.gem from #{uri}"
                end
            end
        end
    end
end