if ENV['EMBED_SIDEKIQ'] == 'true'
  Rails.application.config.after_initialize do
    if defined?(Rails::Server) || $PROGRAM_NAME.include?('puma') || ARGV.include?('s') || ARGV.include?('server')
      Thread.new do
        begin
          require 'sidekiq'
          require 'sidekiq/cli'
          Rails.logger.info "[EmbeddedSidekiq] Starting embedded Sidekiq worker (concurrency=#{ENV.fetch('SIDEKIQ_CONCURRENCY', 2)})..."
          embed = Sidekiq.configure_embed do |config|
            config.logger.level = Logger::INFO
            config.concurrency = ENV.fetch('SIDEKIQ_CONCURRENCY', 2).to_i
            config.queues = %w[
              critical
              high
              medium
              default
              mailers
              action_mailbox_routing
              low
              scheduled_jobs
              deferred
              purgable
              housekeeping
              async_database_migration
              bulk_reindex_low
              active_storage_analysis
              active_storage_purge
              action_mailbox_incineration
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

