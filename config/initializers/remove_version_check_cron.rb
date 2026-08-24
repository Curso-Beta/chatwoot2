Rails.application.config.after_initialize do
  Sidekiq::Cron::Job.find('internal_check_new_versions_job')&.destroy
rescue StandardError
  nil
end
