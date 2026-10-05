class AgentAvailabilityPollJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.active.find_each do |account|
      poll_account(account)
    rescue StandardError => e
      Rails.logger.error("[AvailabilityPoll] Account #{account.id}: #{e.message}")
    end
  end

  private

  def poll_account(account)
    account.account_users.includes(:user).find_each do |account_user|
      next if account_user.user.blank?

      last_log = AgentAvailabilityLog.where(account_id: account.id, user_id: account_user.user_id)
                                     .order(created_at: :desc).first

      next if last_log && last_log.availability == account_user.availability

      AgentAvailabilityLog.create!(
        account_id: account.id,
        user_id: account_user.user_id,
        availability: account_user.availability,
        created_at: Time.current
      )
    end
  end
end
