ENV['SAFE_FETCH_ALLOW_PRIVATE_NETWORK'] ||= 'true'

if ENV['EMBED_SIDEKIQ'] == 'true'
  Rails.application.config.after_initialize do
    if defined?(Rails::Server) || $PROGRAM_NAME.include?('puma') || ARGV.include?('s') || ARGV.include?('server')
      Thread.new do
        begin
          require 'sidekiq'
          require 'sidekiq/cli'

          # 1. Prevent SidekiqAlive from forking a duplicate 290MB Ruby subprocess on :startup
          if defined?(SidekiqAlive)
            SidekiqAlive.singleton_class.prepend(Module.new do
              def start; end
              def register_current_instance; end
            end)
          end

          # 2. Remove noisy 1-minute sidekiq-cron jobs (IMAP polling, SLA checks, etc.) that thrash swap
          if defined?(Sidekiq::Cron::Job)
            begin
              Sidekiq::Cron::Job.destroy_all!
            rescue => _e
              nil
            end
          end

          Rails.logger.info "[EmbeddedSidekiq] Starting embedded Sidekiq worker (concurrency=#{ENV.fetch('SIDEKIQ_CONCURRENCY', 2)})..."
          embed = Sidekiq.configure_embed do |config|
            config.logger.level = Logger::INFO
            config.concurrency = ENV.fetch('SIDEKIQ_CONCURRENCY', 2).to_i
            config[:lifecycle_events][:startup]&.clear if config[:lifecycle_events]
            config.queues = %w[
              critical
              high
              medium
              default
              mailers
              low
            ]
          end
          embed.run
        rescue => e
          Rails.logger.error "[EmbeddedSidekiq] Error starting embedded Sidekiq: #{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
        end
      end
    end
  end
end


