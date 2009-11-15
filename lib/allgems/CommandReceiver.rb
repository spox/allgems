require 'spockets'
require 'json'
module AllGems
    class CommandReceiver
        # Initialize object
        def initialize(r)
            @runner = r
            @listener = nil
            @listen_thread = nil
            @kill = false
            AllGems.initialize_pool
            @spockets = Spockets::Spockets.new(:pool => AllGems.pool)
        end
        # Shortcut method that calls #setup and #listen
        def start
            setup
            listen
        end
        # Sets up the server
        def setup
            @listener.close unless @listener.nil?
            @listener = TCPServer.new(AllGems.listen_port)
        end
        # Starts the thread to process connections
        def listen
            @listen_thread = Thread.new do
                begin
                    loop do
                        s = @listener.accept
                        AllGems.logger.info("New socket connected: #{s}")
                        @spockets.add(s) do |string|
                            string.chomp!
                            begin
                                AllGems.logger.debug "Received string: #{string} for #{s}"
                                process_command(string, s)
                            rescue Exception => boom
                                AllGems.logger.error "Processing error: #{boom}"
                            end
                        end
                    end
                rescue StandardError => boom
                    AllGems.logger.error "CommandReceiver encountered an error: #{boom}"
                rescue Exception => boom
                    @kill = true
                    raise boom
                ensure
                    unless(@kill)
                        setup
                        listen
                    end
                end
            end
        end
        # string:: string
        # socket:: user socket
        # Processes the given string to determine what actions, if any, to take. Will
        # output results to the given socket (this method just splits stuff up)
        def process_command(string, socket)
            AllGems.logger.debug("Received #{string} from socket: #{socket}")
            command = nil
            arguments = nil
            if(index = string.index(' '))
                command = string.slice!(0,index)
                string.slice!(0)
                arguments = string
            else
                command = string
            end
            run_command(command.to_sym, arguments, socket)
        end

        # command:: command in symbol form
        # argument:: string argument. generally json string
        # socket:: socket to respond to
        def run_command(command, argument, socket)
            case command
            when :status
                output_to_socket(socket, status)
            when :limit_gems
                output_to_socket(socket, list_gems(argument))
            when :runner_queue
                output_to_socket(socket, @runner.pool.action_size)
            when :global_queue
                output_to_socket(socket, AllGems.pool.action_size)
            when :uptime
                output_to_socket(socket, AllGems.uptime)
            end
        end

        # Return current status
        def status
            {:runner_queue => @runner.pool.action_size, :runner_pool_size => @runner.pool.size, :uptime => AllGems.uptime,
             :gem_total => AllGems.total_gems, :version_total => AllGems.total_installs, :newest_gem => AllGems.newest_gem,
             :global_queue => AllGems.pool.action_size, :global_pool_size => AllGems.pool.size}
        end
        
        # args:: json dumped array
        # Create a database entry for limited gem dataset. Return customized url.
        def limit_gems(args)
            lid = AllGems.uid
            array = JSON.parse(args)
            AllGems.link_id(lid, array)
            "http://#{AllGems.domain_name}/lid/#{lid}"
        end

        # socket:: Socket to send to
        # Object:: Object to send that can be JSON dumped
        def output_to_socket(socket, object)
            AllGems.logger.debug("Sending object: #{object} to socket: #{socket}")
            socket.puts object.to_json
        end

    end
end