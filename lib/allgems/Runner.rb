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
            AllGems.initialize_db(Sequel.connect("sqlite://#{args[:db_path]}"))
            @pool = ActionPool::Pool.new(:max_threads => args[:runners] ? args[:runners] : 10) # use our own pool since we will overflow it
            GemWorker.setup
            @index = IndexBuilder.new
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
            spec_jobs = []
            doc_jobs = []
            @index.build_array(@index.local_array).each do |x|
                spec_jobs << lambda{GemWorker.save_data(GemWorker.get_spec(x[:name], x[:version])[0])}
                doc_jobs << lambda{GemWorker.process(x)}
            end
            @pool.add_jobs(spec_jobs)
            @pool.add_jobs(doc_jobs)
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