require 'net/http'
require 'uri'
require 'rubygems/installer'
require 'allgems/DocIndexer'
require 'allgems/Specer'
require 'allgems/Helpers'

module AllGems
    class GemWorker
        def initialize(spec)
            AllGems.initialize_pool
            process(spec)
        end
        # spec:: Gem::Specification
        # Generate documentation for given gem specification
        def process(spec)
            AllGems.logger.info "Processing gem: #{spec.full_name}"
            basedir = "#{AllGems.data_directory}/#{spec.name}/#{spec.version.version}"
            FileUtils.mkdir_p basedir
            AllGems.logger.info "Created new directory: #{basedir}"
            gempath = fetch(spec, "#{basedir}/#{spec.full_name}.gem")
            unpack(gempath, basedir)
            generate_documentation(spec, basedir)
        end

        # spec:: Gem::Specification
        # save_path:: path to save gem
        # Fetch the gem file from the server. Returns the path to the gem
        # on the local machine
        def fetch(spec, save_path)
            uri = AllGems.db[:specs].filter(:full_name => spec.full_name).select(:uri).first[:uri]
            AllGems.logger.info "Fetching gem from: #{uri}/gems/#{spec.full_name}.gem"
            return save_path if File.exists?(save_path) # don't fetch if gem already exists
            FileUtils.touch(save_path)
            begin
                remote_path = "#{uri}/gems/#{spec.full_name}.gem"
                remote_uri = URI.parse(remote_path)
                file = File.open(save_path, 'wb')
                file.write(AllGems.fetch_remote(remote_uri))
                file.close
                save_path
            rescue StandardError => boom
                raise FetchError.new(spec.name, spec.version, remote_path, boom)
            end
        end

        # path:: path to the gem file
        # basedir:: directory to unpack in
        # depth:: number of times called
        # Unpacks the gem into the basedir under the 'unpack' directory
        def unpack(path, basedir, depth=0)
            AllGems.logger.info "Unpacking gem: #{path}"
            return if File.exists?("#{basedir}/unpack") # return if gem has been unpacked
            FileUtils.mkdir_p "#{basedir}/unpack"
            AllGems.logger.info "Created new directory: #{basedir}/unpack"
            begin
                Gem::Installer.new(path, :unpack => true).unpack "#{basedir}/unpack"
                FileUtils.chmod_R(0755, "#{basedir}/unpack") # fix any bad permissions
#                    FileUtils.rm(path) # maybe make this optional
            rescue
                if(File.size(path) < 1 || depth > 10)
                    raise IOError.new("Failed to unpack gem: #{path}") unless direct_unpack(path, basedir)
                else
                    unpack(path, basedir, depth+1)
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
            run_command("cd #{basedir} && gem unpack #{path} && mv #{unpackdir}/* #{basedir}/unpack/ && rm -rf #{unpackdir}")
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
                action = lambda do |spec, dir, command, args, format_type|
                    FileUtils.rm_r("#{dir}/doc/#{f}", :force => true) # make sure we are clean before we get dirty
                    result = run_command("#{command} #{args}")
                    AllGems.db.transaction do
                        vid = AllGems.db[:versions].join(:gems, :id => :gem_id).filter(:name => spec.name, :version => spec.version.version).select(:versions__id.as(:vid)).first[:vid]
                        AllGems.db[:docs_versions] << {:version_id => vid, :doc_id => AllGems.doc_hash[f.to_sym]}
                    end
                    raise DocError.new(spec.name, spec.version) unless result
                    AllGems.logger.info "Completed documentation for #{spec.full_name}"
                    FileUtils.chmod_R(0755, "#{dir}/doc/#{f}") # fix any bad permissions
                    DocIndexer.index_gem(spec, "#{dir}/doc/#{f}", format_type)
                end
                AllGems.pool << [action, [spec, dir.dup, command.dup, args.join(' '), f]]
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
                Process.setpriority(Process::PRIO_PROCESS, pro.pid, 19) unless ON_WINDOWS
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
    end
end