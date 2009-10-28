require 'actionpool'
require 'actiontimer'
require 'allgems/IndexBuilder'
require 'allgems/GemWorker'

module AllGems
    class Runner
        # :db_path:: path to sqlite database
        # :runners:: maximum number of threads to use
        # :interval:: how often to update documents (useless if using cron)
        def initialize(args={})
            raise ArgumentError.new('Expecting path to database') unless args[:db_path]
            @db = Sequel.connect("sqlite://#{args[:db_path]}")
            AllGems.initialize_db(@db)
            @pool = ActionPool::Pool.new(:max_threads => args[:runners] ? args[:runners] : 10)
            @index = IndexBuilder.new(:database => @db)
            @interval = args[:interval] ? args[:interval] : nil
            @timer = nil
        end
        
        def do_sync
            if(@interval)
                @timer = ActionTimer::Timer.new(:pool => @pool)
                sync
                @timer.add(@interval){ sync }
            else
                sync
            end
        end
        # Get the list of gems we need and load up the pool. Then take a nap
        # until the pool gets bored and wakes us up
        def sync
            Gem.refresh
            Thread.new do
                @pool.add_jobs(@index.build_array(@index.local_array).collect{|x| lambda{GemWorker.process({:database => @db}.merge(x))}})
            end
            begin
                lock = Mutex.new
                guard = ConditionVariable.new
                @pool << lambda{lock.synchronize{guard.signal}}
                lock.synchronize{guard.wait(lock)}
            rescue Exception => boom
                AllGems.logger.error boom.to_s
                retry
            end
        end
        # Stop the runner
        def stop(now=false)
            @timer.clear if @timer
            @pool.shutdown(now)
        end

    end
end