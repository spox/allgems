require 'actionpool'
require 'actiontimer'
require 'allgems/IndexBuilder'
require 'allgems/GemWorker'

module AllGems
    class Runner
        # :db_path:: path to sqlite database
        # :runners:: maximum number of threads to use
        # :interval:: how often to update documents (useless if using cron)
        attr_accessor :pool
        def initialize(args={})
            raise ArgumentError.new('Expecting path to database') unless args[:db_path]
            @db = Sequel.connect("sqlite://#{args[:db_path]}")
            AllGems.initialize_db(@db)
            @pool = ActionPool::Pool.new(:max_threads => args[:runners] ? args[:runners] : 10) # use our own pool since we will overflow it
            GemWorker.setup
            @index = IndexBuilder.new(:database => @db)
            @interval = args[:interval] ? args[:interval] : nil
            @timer = nil
            @stop = false
            @self = Thread.current
        end
        
        def do_sync
            if(@interval)
                AllGems.initialize_timer
                sync
                AllGems.timer.add(@interval){ sync }
            else
                sync
            end
        end
        # Get the list of gems we need and load up the pool. Then take a nap
        # until the pool gets bored and wakes us up
        def sync
            @self = Thread.current
            Gem.refresh
            @pool.add_jobs(@index.build_array(@index.local_array).map{|x| lambda{GemWorker.process({:database => @db}.merge(x))}})
            begin
                @pool << lambda{@self.raise Wakeup.new}
                sleep
            rescue Wakeup
                AllGems.logger.info("Runner got woken up. We are done here")
                # okay, we're done
            rescue StandardError => boom
                AllGems.logger.error boom.to_s
                retry unless @stop
            end
        end
        # Stop the runner
        def stop(now=false)
            @timer.clear if @timer
            @stop = true
            @self.raise Wakeup unless Thread.current == @self
            AllGems.pool.shutdown(now)
            GemWorker.pool.shutdown(now)
        end

        class Wakeup < Exception
        end

    end
end