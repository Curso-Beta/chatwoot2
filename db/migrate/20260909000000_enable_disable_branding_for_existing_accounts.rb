class EnableDisableBrandingForExistingAccounts < ActiveRecord::Migration[7.0]
  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('disable_branding') }
    end
  end
end
