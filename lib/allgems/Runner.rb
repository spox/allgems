require 'actionpool'
require 'actiontimer'
require 'allgems/Specer'
require 'allgems/GemWorker'

module AllGems
    class Runner
        # :db_path:: path to sqlite database
        # :runners:: maximum number of threads to use
        # :interval:: how often to update documents (useless if using cron)
        attr_accessor :pool
        def initialize(args={})
            raise ArgumentError.new('Expecting path to database') unless args[:db_path]
            AllGems.initialize_db(Sequel.connect("sqlite://#{args[:db_path]}"))
            @pool = ActionPool::Pool.new(:max_threads => args[:runners] ? args[:runners] : 10) # use our own pool since we will overflow it
            @interval = args[:interval] ? args[:interval] : nil
            @timer = nil
            @stop = false
            @running = false
            @specer = Specer.new
            @self = Thread.current
        end
        
        def do_sync
            if(@interval)
                AllGems.initialize_timer
                sync
                AllGems.timer.add(@interval){ sync unless @running }
            else
                sync
            end
        end
        # Get the list of gems we need and load up the pool. Then take a nap
        # until the pool gets bored and wakes us up
        def sync
            @running = true
            @self = Thread.current
#             @specer.load_specs
            @pool.add_jobs @specer.missing_docs.map{|x| [lambda{|x| GemWorker.new(x)}, [x.dup]]}
            begin
                @pool << lambda{@self.raise Wakeup.new}
                sleep
            rescue Wakeup
                AllGems.logger.info("Runner got woken up. We are done here")
                # okay, we're done
            rescue StandardError => boom
                AllGems.logger.error boom.to_s
                retry unless @stop
            ensure
                @running = false
            end
        end
        # Stop the runner
        def stop(now=false)
            @timer.clear if @timer
            @stop = true
            @self.raise Wakeup.new unless Thread.current == @self
            @pool.shutdown(now)
            AllGems.pool.shutdown(now)
        end
    end
end