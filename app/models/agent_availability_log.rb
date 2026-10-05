class AgentAvailabilityLog < ApplicationRecord
  belongs_to :account
  belongs_to :user

  enum :availability, { online: 0, offline: 1, busy: 2 }
end
