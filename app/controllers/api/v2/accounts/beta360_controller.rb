class Api::V2::Accounts::Beta360Controller < Api::V1::Accounts::BaseController
  before_action :set_date_range

  def index
    render json: {
      overview: overview_metrics,
      teams: team_metrics,
      ai: ai_metrics,
      timeline: timeline_data
    }
  end

  private

  def set_date_range
    @since = params[:since].present? ? Time.zone.parse(params[:since]).beginning_of_day : 30.days.ago.beginning_of_day
    @until = params[:until].present? ? Time.zone.parse(params[:until]).end_of_day : Time.zone.now
  end

  def base_conversations
    @base_conversations ||= Current.account.conversations.where(created_at: @since..@until)
  end

  def overview_metrics
    total = base_conversations.count
    resolved = base_conversations.where(status: :resolved).count
    open_count = base_conversations.where(status: :open).count
    pending = base_conversations.where(status: :pending).count

    avg_frt = base_conversations
      .where.not(first_reply_created_at: nil)
      .average(Arel.sql("EXTRACT(EPOCH FROM (first_reply_created_at - created_at))"))
      &.to_f&.round(0)

    resolved_convs = base_conversations.where(status: :resolved).where.not(status_changed_at: nil)
    avg_rt = resolved_convs
      .average(Arel.sql("EXTRACT(EPOCH FROM (status_changed_at - created_at))"))
      &.to_f&.round(0)

    csat = CsatSurveyResponse.where(account_id: Current.account.id, created_at: @since..@until)

    {
      total_conversations: total,
      resolved_conversations: resolved,
      open_conversations: open_count,
      pending_conversations: pending,
      avg_first_response_time: avg_frt,
      avg_resolution_time: avg_rt,
      csat_avg: csat.average(:rating)&.to_f&.round(2),
      csat_count: csat.count,
      resolution_rate: total.positive? ? (resolved * 100.0 / total).round(1) : 0
    }
  end

  def team_metrics
    Current.account.teams.map do |team|
      convs = base_conversations.where(team_id: team.id)
      total = convs.count
      resolved = convs.where(status: :resolved).count

      avg_frt = convs
        .where.not(first_reply_created_at: nil)
        .average(Arel.sql("EXTRACT(EPOCH FROM (first_reply_created_at - created_at))"))
        &.to_f&.round(0)

      {
        id: team.id,
        name: team.name,
        total: total,
        resolved: resolved,
        open: convs.where(status: :open).count,
        pending: convs.where(status: :pending).count,
        resolution_rate: total.positive? ? (resolved * 100.0 / total).round(1) : 0,
        avg_first_response_time: avg_frt
      }
    end
  end

  def ai_metrics
    msgs = Message.joins(:conversation)
      .where(conversations: { account_id: Current.account.id })
      .where(messages: { created_at: @since..@until })

    bot_msgs = msgs.where(sender_type: 'AgentBot')
    human_msgs = msgs.where(sender_type: 'User', message_type: :outgoing)
    incoming = msgs.where(message_type: :incoming)

    bot_conv_count = bot_msgs.select(:conversation_id).distinct.count

    {
      bot_messages: bot_msgs.count,
      human_messages: human_msgs.count,
      incoming_messages: incoming.count,
      bot_conversations: bot_conv_count,
      total_conversations: base_conversations.count
    }
  end

  def timeline_data
    base_conversations
      .group(Arel.sql("DATE(created_at)"))
      .order(Arel.sql("DATE(created_at)"))
      .count
      .map { |date, count| { date: date.to_s, count: count } }
  end
end
