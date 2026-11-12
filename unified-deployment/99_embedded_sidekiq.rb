ENV['SAFE_FETCH_ALLOW_PRIVATE_NETWORK'] ||= 'true'

Rails.application.config.to_prepare do
  # 1. Fix iOS Mobile App 500 error on POST /api/v1/notification_subscriptions (subscription_type: "apns_voip")
  if defined?(NotificationSubscriptionBuilder)
    NotificationSubscriptionBuilder.prepend(Module.new do
      def perform
        if params[:subscription_type].to_s == 'apns_voip'
          dev_id = params.dig(:subscription_attributes, :device_id) || params.dig('subscription_attributes', 'device_id') || 'ios'
          @identifier = "apns_voip:#{dev_id}"
          params[:subscription_type] = 'fcm'
        end
        super
      end
    end)
  end

  # 2. Ensure PushNotificationService delivers via ChatwootHub (App Store iOS app) & Firebase without deleting subscriptions
  if defined?(Notification::PushNotificationService)
    Notification::PushNotificationService.prepend(Module.new do
      def perform
        return unless user_subscribed_to_notification?

        notification_subscriptions.each do |subscription|
          next if subscription.identifier.to_s.start_with?('apns_voip:')

          send_browser_push(subscription)
          if subscription.fcm?
            begin
              ChatwootHub.send_push(fcm_options(subscription)) if chatwoot_hub_enabled?
            rescue => e
              Rails.logger.warn("[PushNotification] ChatwootHub push error: #{e.message}")
            end
            begin
              if firebase_credentials_present?
                fcm_service = Notification::FcmService.new(
                  GlobalConfigService.load('FIREBASE_PROJECT_ID', nil),
                  GlobalConfigService.load('FIREBASE_CREDENTIALS', nil)
                )
                fcm_service.fcm_client.send_v1(fcm_options(subscription))
              end
            rescue => e
              Rails.logger.warn("[PushNotification] FCM push error: #{e.message}")
            end
          end
        end
      end
    end)
  end

  # 3. Auto-open and auto-assign conversations in Account 1 to mukira@lipagas.co (user_id=1) so mobile app notifications always fire
  if defined?(Conversation)
    Conversation.prepend(Module.new do
      def set_active_bot_conversation
        self.status = :open
        self.assignee_id ||= 1 if account_id == 1
      end

      def determine_conversation_status
        super
        if account_id == 1
          self.status = :open if status.to_s == 'pending'
          self.assignee_id ||= 1
        end
      end
    end)
  end
end

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


