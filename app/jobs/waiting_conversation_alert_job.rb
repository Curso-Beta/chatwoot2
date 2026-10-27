class WaitingConversationAlertJob < ApplicationJob
  queue_as :scheduled_jobs

  CHANNEL_LABELS = {
    'Channel::WebWidget' => 'Chat do site',
    'Channel::Email' => 'E-mail',
    'Channel::Whatsapp' => 'WhatsApp',
    'Channel::Instagram' => 'Instagram',
    'Channel::FacebookPage' => 'Facebook',
    'Channel::Api' => 'API'
  }.freeze
  AVAILABILITY_LABELS = { 'online' => 'online', 'busy' => 'ocupado', 'offline' => 'offline' }.freeze
  TIME_ZONE = 'America/Sao_Paulo'.freeze
  DEDUP_TTL = 8.days

  def perform(dry_run: false)
    return unless dry_run || enabled?

    account_ids.each do |account_id|
      next unless dry_run || within_business_hours?(account_id)

      account = Account.find_by(id: account_id)
      next if account.blank?

      alert_account(account, dry_run)
    rescue StandardError => e
      Rails.logger.error("[WaitingAlert] Account #{account_id}: #{e.message}")
    end
  end

  private

  def alert_account(account, dry_run)
    online_names = online_agent_names(account)
    waiting_conversations(account).each do |conversation|
      wait_start = conversation.human_wait_start
      next if wait_start.blank? || wait_start < max_wait.ago

      wait_minutes = ((Time.current - wait_start) / 60).floor
      next if wait_minutes < limit_for(conversation.inbox)

      text = build_message(account, conversation, wait_minutes, online_names)
      if dry_run
        Rails.logger.info("[WaitingAlert][dry-run] #{channel_for(account.id)}\n#{text}")
        next
      end
      deliver_once(conversation, wait_start, text, channel_for(account.id))
    end
  end

  # Espera por humano: conta da 1ª mensagem do cliente sem resposta humana, ou da última
  # mensagem da IA depois dela (passagem). Respostas da IA não contam como atendimento.
  # Sem responsável e com a IA conversando, a IA está cuidando: não alerta.
  def waiting_conversations(account)
    ai_ids = ai_assignee_ids.presence || [0]
    human_wait_sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, ai_ids, ai_ids])
      CROSS JOIN LATERAL (
        SELECT MAX(m.created_at) AS last_human FROM messages m
        WHERE m.conversation_id = conversations.id AND m.message_type = 1 AND m.private = false
          AND m.sender_type = 'User' AND m.sender_id NOT IN (?)
      ) h
      CROSS JOIN LATERAL (
        SELECT MIN(m.created_at) AS first_in FROM messages m
        WHERE m.conversation_id = conversations.id AND m.message_type = 0
          AND m.created_at > COALESCE(h.last_human, '-infinity'::timestamp)
      ) i
      CROSS JOIN LATERAL (
        SELECT MAX(m.created_at) AS last_ai FROM messages m
        WHERE m.conversation_id = conversations.id AND m.message_type = 1 AND m.private = false
          AND m.created_at > i.first_in
          AND (m.sender_type = 'AgentBot' OR (m.sender_type = 'User' AND m.sender_id IN (?)))
      ) a
    SQL

    account.conversations.open
           .where(last_activity_at: max_wait.ago..)
           .where.not(inbox_id: excluded_inbox_ids)
           .where('conversations.assignee_id IS NULL OR conversations.assignee_id NOT IN (?)', ai_ids)
           .joins(human_wait_sql)
           .where('i.first_in IS NOT NULL')
           .where('conversations.assignee_id IS NOT NULL OR a.last_ai IS NULL')
           .select('conversations.*, GREATEST(i.first_in, a.last_ai) AS human_wait_start')
           .includes(:inbox, :contact, :assignee)
  end

  def deliver_once(conversation, wait_start, text, channel)
    key = "waiting_alert:#{conversation.id}:#{wait_start.to_i}"
    return unless ::Redis::Alfred.set(key, 1, nx: true, ex: DEDUP_TTL)

    post_to_slack(text, channel)
  rescue StandardError => e
    ::Redis::Alfred.delete(key)
    Rails.logger.error("[WaitingAlert] Conversation #{conversation.id}: #{e.message}")
  end

  def post_to_slack(text, channel = ENV.fetch('SLACK_ATENDIMENTO_CHANNEL'))
    response = HTTParty.post(
      'https://slack.com/api/chat.postMessage',
      headers: { 'Authorization' => "Bearer #{ENV.fetch('SLACK_BOT_TOKEN')}", 'Content-Type' => 'application/json; charset=utf-8' },
      body: { channel: channel, text: text, unfurl_links: false }.to_json,
      timeout: 10
    )
    raise "Slack #{response.code} #{response.parsed_response&.dig('error')}" unless response.success? && response.parsed_response&.dig('ok')
  end

  def build_message(account, conversation, wait_minutes, online_names)
    inbox = conversation.inbox
    channel = CHANNEL_LABELS[inbox.channel_type] || 'Canal'
    link = "#{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{account.id}/conversations/#{conversation.display_id}"
    [
      "⏳ *Cliente esperando há #{format_wait(wait_minutes)}* — #{account.name} · #{channel} (#{inbox.name})",
      "Cliente: #{conversation.contact&.name.presence || 'Cliente'} · Responsável: #{assignee_text(account, conversation)}",
      "Online agora: #{online_names.any? ? online_names.join(', ') : '⚠️ *ninguém online*'}",
      "<#{link}|Abrir conversa ##{conversation.display_id}>"
    ].join("\n")
  end

  def assignee_text(account, conversation)
    assignee = conversation.assignee
    return '*sem responsável*' if assignee.blank?

    status = account.account_users.find_by(user_id: assignee.id)&.availability_status
    "#{assignee.name} (#{AVAILABILITY_LABELS[status] || 'offline'})"
  end

  def online_agent_names(account)
    account.account_users.includes(:user).select { |au| au.user.present? && au.availability_status == 'online' }.map { |au| au.user.name }
  end

  def format_wait(minutes)
    return "#{minutes} min" if minutes < 60

    hours, rest = minutes.divmod(60)
    rest.zero? ? "#{hours}h" : format('%<h>dh%<m>02d', h: hours, m: rest)
  end

  def limit_for(inbox)
    inbox.channel_type == 'Channel::Email' ? env_int('WAIT_ALERT_EMAIL_MIN', 120) : env_int('WAIT_ALERT_CHAT_MIN', 10)
  end

  # WAIT_ALERT_HOURS_<conta> = "9-18" (todo dia) ou "9-18:seg-sex" (só dias úteis)
  def within_business_hours?(account_id)
    hours, days = ENV.fetch("WAIT_ALERT_HOURS_#{account_id}", ENV.fetch('WAIT_ALERT_HOURS', '9-22')).split(':')
    open_hour, close_hour = hours.split('-').map(&:to_i)
    now = Time.current.in_time_zone(TIME_ZONE)
    return false if days == 'seg-sex' && (now.saturday? || now.sunday?)

    now.hour >= open_hour && now.hour < close_hour
  end

  # WAIT_ALERT_CHANNELS = "1:#canal-a,2:#canal-b"; sem entrada usa SLACK_ATENDIMENTO_CHANNEL
  def channel_for(account_id)
    mapping = ENV.fetch('WAIT_ALERT_CHANNELS', '').split(',').to_h { |pair| pair.strip.split(':', 2) }
    mapping[account_id.to_s].presence || ENV.fetch('SLACK_ATENDIMENTO_CHANNEL')
  end

  def ai_assignee_ids
    id_list('WAIT_ALERT_AI_USER_IDS', '')
  end

  def enabled?
    ENV['SLACK_BOT_TOKEN'].present? && ENV['SLACK_ATENDIMENTO_CHANNEL'].present?
  end

  def account_ids
    id_list('WAIT_ALERT_ACCOUNT_IDS', '2')
  end

  def excluded_inbox_ids
    id_list('WAIT_ALERT_EXCLUDE_INBOX_IDS', '')
  end

  def max_wait
    env_int('WAIT_ALERT_MAX_DAYS', 3).days
  end

  def id_list(name, default)
    ENV.fetch(name, default).split(',').map(&:strip).reject(&:blank?).map(&:to_i)
  end

  def env_int(name, default)
    ENV.fetch(name, default).to_i
  end
end
