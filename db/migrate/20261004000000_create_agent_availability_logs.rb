class CreateAgentAvailabilityLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :agent_availability_logs do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.integer :availability, null: false, default: 0
      t.datetime :created_at, null: false
    end

    add_index :agent_availability_logs, [:account_id, :user_id, :created_at], name: 'idx_avail_logs_account_user_time'
    add_index :agent_availability_logs, [:account_id, :created_at], name: 'idx_avail_logs_account_time'
  end
end
