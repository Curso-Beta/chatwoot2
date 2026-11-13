# Relatório do dia para cada atendente humano, no fim do expediente dele (13/11/2026).
#
# Roda de hora em hora; manda o relatório de quem termina o expediente nessa hora
# (horário de São Paulo). Em DAILY_REPORT_MODE=preview (padrão) tudo vai só para
# quem aprova (DAILY_REPORT_ADMIN_SLACK); em "live", cada atendente recebe o seu
# por mensagem direta (Slack achado pelo e-mail) e quem aprova recebe uma cópia.
#
# DAILY_REPORT_AGENTS = "13:9-18,14:13-22,15:13-22,8:9-18,7:13-22" (user_id:início-fim)
# DAILY_REPORT_DAYS   = "seg-sex" (padrão) ou "todos"
# Metas: chat 1 min (espera por humano depois da IA), e-mail 2 h (1ª resposta),
# 90% dentro, online 7 h, satisfação 4,5, nenhum estouro de SLA.
class DailyAgentReportJob < ApplicationJob
  queue_as :scheduled_jobs

  TIME_ZONE = 'America/Sao_Paulo'.freeze
  AI_USER_IDS = [1, 11, 12].freeze
  WEEKDAYS = %w[domingo segunda terça quarta quinta sexta sábado].freeze
  GOALS = { chat_seconds: 60, email_seconds: 2.hours.to_i, within_pct: 90, online_hours: 7, csat: 4.5 }.freeze

  def perform(force_user_ids: nil)
    now = Time.current.in_time_zone(TIME_ZONE)
    return if force_user_ids.blank? && !working_day?(now)

    schedules.each do |user_id, (start_hour, end_hour)|
      next unless force_user_ids ? force_user_ids.include?(user_id) : end_hour == now.hour

      report_for(user_id, start_hour, end_hour, now)
    rescue StandardError => e
      Rails.logger.error("[RelatórioDiário] atendente #{user_id}: #{e.message}")
    end
  end

  private

  def report_for(user_id, start_hour, end_hour, now)
    user = User.find_by(id: user_id)
    return if user.blank?

    shift_start = now.beginning_of_day + start_hour.hours
    shift_end = [now.beginning_of_day + end_hour.hours, now].min
    metrics = Metrics.new(user, now.beginning_of_day, shift_start, shift_end).to_h
    text = message(user, start_hour, end_hour, now, metrics)

    if mode == 'live'
      slack_id = slack_user_id(user.email)
      post(slack_id, text) if slack_id
      post(admin, "Cópia do relatório enviado para *#{user.name}*#{' (Slack não encontrado)' unless slack_id}:\n\n#{text}") if admin
    elsif admin
      post(admin, ":eyes: *PRÉVIA para aprovação* (ainda não foi para #{user.name})\n\n#{text}")
    end
  end

  def message(user, start_hour, end_hour, now, m)
    first = user.name.to_s.split.first
    [
      "*:bar_chart: Seu dia no atendimento — #{WEEKDAYS[now.wday]}, #{now.strftime('%d/%m')}*",
      "Olá, #{first}! Aqui está o resumo do seu expediente (#{start_hour}h às #{end_hour}h):",
      '',
      '*Atendimentos*',
      "• #{m[:conversations]} conversas atendidas · #{m[:messages]} mensagens enviadas",
      "• #{m[:resolved]} conversas resolvidas",
      '',
      '*Tempo de resposta*',
      response_line(':speech_balloon: Chat — espera por você depois da IA', m[:chat], GOALS[:chat_seconds], 'até 1 min'),
      response_line(':envelope: E-mail — 1ª resposta', m[:email], GOALS[:email_seconds], 'até 2 h'),
      '',
      '*Presença*',
      "• Online no expediente: *#{format('%.1f', m[:online_hours]).tr('.', ',')} h* de #{end_hour - start_hour} h · " \
      "#{m[:online_hours] >= GOALS[:online_hours] ? ':white_check_mark:' : ':warning:'} meta: #{GOALS[:online_hours]} h",
      ("• Primeira entrada: #{m[:first_online]}" if m[:first_online]),
      '',
      '*Satisfação (últimos 7 dias)*',
      csat_line(m[:csat]),
      '',
      '*Prazos (SLA)*',
      "• Estouros de prazo hoje: *#{m[:sla_breaches]}* #{m[:sla_breaches].zero? ? ':white_check_mark:' : ':warning:'}",
      '',
      '*Para amanhã*',
      pending_line(m[:pending])
    ].compact.join("\n")
  end

  def response_line(label, stats, _goal_seconds, goal_label)
    return "• #{label}: sem conversas hoje" if stats[:count].zero?

    pct = stats[:within_pct]
    "• #{label}: *#{duration(stats[:median])}* (mediana de #{stats[:count]}) · " \
      "#{pct >= GOALS[:within_pct] ? ':white_check_mark:' : ':warning:'} #{pct}% #{goal_label} (meta: #{GOALS[:within_pct]}%)"
  end

  def csat_line(csat)
    return '• Sem avaliações nos últimos 7 dias' if csat[:count].zero?

    "• Nota média: *#{format('%.1f', csat[:average]).tr('.', ',')}* em #{csat[:count]} avaliações · " \
      "#{csat[:average] >= GOALS[:csat] ? ':white_check_mark:' : ':warning:'} meta: #{GOALS[:csat].to_s.tr('.', ',')}"
  end

  def pending_line(pending)
    return '• Nenhuma conversa sua com cliente esperando :white_check_mark:' if pending[:count].zero?

    "• #{pending[:count]} conversa(s) sua(s) com cliente esperando · a mais antiga há #{duration(pending[:oldest_seconds])}"
  end

  def duration(seconds)
    seconds = seconds.to_i
    return "#{seconds} s" if seconds < 60
    return "#{(seconds / 60.0).round} min" if seconds < 3600

    hours, rest = seconds.divmod(3600)
    "#{hours} h #{(rest / 60.0).round} min"
  end

  def schedules
    ENV.fetch('DAILY_REPORT_AGENTS', '13:9-18,14:13-22,15:13-22,8:9-18,7:13-22').split(',').filter_map do |pair|
      user_id, hours = pair.strip.split(':')
      start_hour, end_hour = hours.to_s.split('-').map(&:to_i)
      [user_id.to_i, [start_hour, end_hour]] if user_id.present? && end_hour.to_i.positive?
    end
  end

  def working_day?(now)
    ENV.fetch('DAILY_REPORT_DAYS', 'seg-sex') == 'todos' || !(now.saturday? || now.sunday?)
  end

  def mode
    ENV.fetch('DAILY_REPORT_MODE', 'preview')
  end

  def admin
    ENV.fetch('DAILY_REPORT_ADMIN_SLACK', nil)
  end

  def slack_user_id(email)
    response = HTTParty.get('https://slack.com/api/users.lookupByEmail', query: { email: email },
                                                                         headers: { 'Authorization' => "Bearer #{ENV.fetch('SLACK_BOT_TOKEN', nil)}" }, timeout: 10)
    response.parsed_response.is_a?(Hash) && response.parsed_response['ok'] ? response.parsed_response.dig('user', 'id') : nil
  end

  def post(channel, text)
    response = HTTParty.post('https://slack.com/api/chat.postMessage',
                             headers: { 'Authorization' => "Bearer #{ENV.fetch('SLACK_BOT_TOKEN', nil)}", 'Content-Type' => 'application/json; charset=utf-8' },
                             body: { channel: channel, text: text, unfurl_links: false }.to_json, timeout: 10)
    return if response.parsed_response.is_a?(Hash) && response.parsed_response['ok']

    Rails.logger.warn("[RelatórioDiário] Slack: #{response.body.to_s[0,
                                                                     200]}")
  end

  # Métricas de um atendente no dia, a partir do banco do Chatwoot
  class Metrics
    def initialize(user, day_start, shift_start, shift_end)
      @user = user
      @day_start = day_start
      @shift_start = shift_start
      @shift_end = shift_end
    end

    def to_h
      {
        conversations: sent.distinct.count(:conversation_id), messages: sent.count,
        resolved: ReportingEvent.where(user_id: @user.id, name: 'conversation_resolved', created_at: @day_start..@shift_end).count,
        chat: summarize(chat_waits, DailyAgentReportJob::GOALS[:chat_seconds]),
        email: summarize(email_waits, DailyAgentReportJob::GOALS[:email_seconds]),
        online_hours: online_seconds / 3600.0, first_online: first_online,
        csat: csat, sla_breaches: sla_breaches, pending: pending
      }
    end

    private

    def sent
      # reorder(nil): Message tem ordenação padrão, que quebra o group/minimum
      Message.reorder(nil).where(sender_type: 'User', sender_id: @user.id, message_type: :outgoing, private: false, created_at: @day_start..@shift_end)
    end

    def email_inbox_ids
      @email_inbox_ids ||= Inbox.where(channel_type: 'Channel::Email').pluck(:id)
    end

    # Cliente esperando por uma pessoa: da 1ª mensagem dele sem resposta humana até a
    # 1ª resposta do atendente no dia (antes do expediente não conta)
    def chat_waits
      sent.where.not(inbox_id: email_inbox_ids).group(:conversation_id).minimum(:created_at).filter_map do |conversation_id, reply_at|
        last_human = Message.reorder(nil).where(conversation_id: conversation_id, message_type: :outgoing, private: false, sender_type: 'User')
                            .where.not(sender_id: DailyAgentReportJob::AI_USER_IDS).where(created_at: ...reply_at).maximum(:created_at)
        waiting = Message.reorder(nil).where(conversation_id: conversation_id, message_type: :incoming).where(created_at: ...reply_at)
        waiting = waiting.where('created_at > ?', last_human) if last_human
        start = waiting.minimum(:created_at)
        reply_at - [start, @shift_start].max if start
      end
    end

    def email_waits
      ReportingEvent.where(user_id: @user.id, name: 'first_response', inbox_id: email_inbox_ids, created_at: @day_start..@shift_end)
                    .filter_map { |e| e.event_end_time - [e.event_start_time, @shift_start].max if e.event_end_time && e.event_start_time }
    end

    def summarize(waits, goal)
      return { count: 0 } if waits.empty?

      sorted = waits.map { |w| [w, 0].max }.sort
      median = sorted.size.odd? ? sorted[sorted.size / 2] : (sorted[(sorted.size / 2) - 1] + sorted[sorted.size / 2]) / 2.0
      { count: waits.size, median: median, within_pct: ((waits.count { |w| w <= goal } * 100.0) / waits.size).round }
    end

    def availability_logs
      @availability_logs ||= begin
        before = AgentAvailabilityLog.where(user_id: @user.id).where(created_at: ...@shift_start).order(:created_at).last
        [before, *AgentAvailabilityLog.where(user_id: @user.id, created_at: @shift_start..@shift_end).order(:created_at)].compact
      end
    end

    def online_seconds
      availability_logs.each_with_index.sum do |log, index|
        next 0 unless log.availability.to_s == 'online' || log.availability.to_s == '0'

        from = [log.created_at, @shift_start].max
        to = [availability_logs[index + 1]&.created_at || @shift_end, @shift_end].min
        [to - from, 0].max
      end
    end

    def first_online
      log = availability_logs.find { |l| l.created_at >= @day_start && (l.availability.to_s == 'online' || l.availability.to_s == '0') }
      log&.created_at&.in_time_zone(DailyAgentReportJob::TIME_ZONE)&.strftime('%H:%M')
    end

    def csat
      scope = CsatSurveyResponse.where(assigned_agent_id: @user.id, created_at: (@day_start - 6.days)..@shift_end)
      { count: scope.count, average: scope.average(:rating).to_f }
    end

    def sla_breaches
      SlaEvent.joins(:conversation).where(conversations: { assignee_id: @user.id }, event_type: %w[frt nrt], created_at: @day_start..@shift_end).count
    end

    def pending
      scope = Conversation.where(assignee_id: @user.id, status: :open).where.not(waiting_since: nil)
      oldest = scope.minimum(:waiting_since)
      { count: scope.count, oldest_seconds: oldest ? Time.current - oldest : 0 }
    end
  end
end
