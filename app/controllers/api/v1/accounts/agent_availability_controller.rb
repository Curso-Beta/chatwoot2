class Api::V1::Accounts::AgentAvailabilityController < Api::V1::Accounts::BaseController
  def live
    account_users = Current.account.account_users.includes(:user)
    render json: account_users.map { |au|
      {
        id: au.user_id,
        name: au.user.name,
        avatar_url: au.user.avatar_url,
        availability: au.availability,
        role: au.role
      }
    }
  end

  def history
    logs = Current.account.agent_availability_logs
                  .where(created_at: history_range)
                  .order(created_at: :desc)
                  .limit(500)
                  .includes(:user)

    render json: logs.map { |l|
      {
        id: l.id,
        user_id: l.user_id,
        agent_name: l.user.name,
        availability: l.availability,
        created_at: l.created_at.iso8601
      }
    }
  end

  def sessions
    logs = Current.account.agent_availability_logs
                  .where(created_at: history_range)
                  .order(:user_id, :created_at)
                  .includes(:user)

    sessions = build_sessions(logs)
    render json: sessions
  end

  def summary
    logs = Current.account.agent_availability_logs
                  .where(created_at: history_range)
                  .order(:user_id, :created_at)
                  .includes(:user)

    sessions = build_sessions(logs)
    totals = {}
    sessions.each do |s|
      next unless s[:duration_minutes]

      totals[s[:agent_name]] ||= { online: 0, busy: 0, offline: 0 }
      totals[s[:agent_name]][s[:availability].to_sym] += s[:duration_minutes]
    end
    render json: totals
  end

  private

  def history_range
    days = (params[:days] || 7).to_i.clamp(1, 30)
    days.days.ago..Time.current
  end

  def build_sessions(logs)
    grouped = logs.group_by(&:user_id)
    sessions = []

    grouped.each do |_user_id, user_logs|
      user_logs.each_cons(2) do |current_log, next_log|
        duration = ((next_log.created_at - current_log.created_at) / 60.0).round(1)
        sessions << {
          agent_name: current_log.user.name,
          availability: current_log.availability,
          started_at: current_log.created_at.iso8601,
          ended_at: next_log.created_at.iso8601,
          duration_minutes: duration
        }
      end

      last = user_logs.last
      sessions << {
        agent_name: last.user.name,
        availability: last.availability,
        started_at: last.created_at.iso8601,
        ended_at: nil,
        duration_minutes: nil
      }
    end

    sessions.sort_by { |s| s[:started_at] }.reverse
  end
end
