class CreateAvailabilityDashboardApps < ActiveRecord::Migration[7.0]
  def up
    base_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3000').chomp('/')

    Account.find_each do |account|
      next if account.dashboard_apps.where(title: 'Disponibilidade').exists?

      admin = account.account_users.where(role: :administrator).first
      next unless admin

      DashboardApp.create!(
        account: account,
        user_id: admin.user_id,
        title: 'Disponibilidade',
        content: [{ 'type' => 'frame', 'url' => "#{base_url}/agent-availability/#{account.id}" }]
      )
    end
  end

  def down
    DashboardApp.where(title: 'Disponibilidade').destroy_all
  end
end
