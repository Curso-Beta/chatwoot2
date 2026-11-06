# Recupera conversas do Instagram que a Meta não avisou (Curso Beta e Hotwebinar,
# 06/11/2026). Em 150 conversas do @cursobeta, 14 nunca chegaram ao Chatwoot —
# pedidos de mensagem de quem não conversou antes. A cada 5 min, compara a lista
# de conversas da Meta com os contatos da caixa e passa o que faltar pelo mesmo
# caminho do webhook (Instagram::MessageText): contato, conversa e notificação
# normais. Mensagem repetida é descartada pelo id da Meta.
# Liga com IG_SYNC_ENABLED=true; IG_SYNC_INBOX_IDS (padrão 11,15).
class InstagramConversationSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  LOOKBACK = 48.hours
  MAX_PER_RUN = 20

  def perform(dry_run: false, lookback_hours: nil)
    return unless dry_run || ENV['IG_SYNC_ENABLED'] == 'true'

    since = (lookback_hours || LOOKBACK.in_hours).to_i.hours.ago
    inbox_ids.each do |inbox_id|
      channel = Inbox.find_by(id: inbox_id)&.channel
      next unless channel.is_a?(Channel::Instagram)

      sync(channel, since, dry_run)
    rescue StandardError => e
      Rails.logger.error("[IgSync] caixa #{inbox_id}: #{e.message}")
    end
  end

  private

  def sync(channel, since, dry_run)
    known = ContactInbox.where(inbox_id: channel.inbox.id).pluck(:source_id).to_set
    missing_conversations(channel, since, known).first(MAX_PER_RUN).each do |conversation_id, user|
      messages = conversation_messages(channel, conversation_id)
      next if messages.none? { |m| m.dig('from', 'id') == user['id'] }

      tag = dry_run ? '[IgSync][dry-run]' : '[IgSync]'
      Rails.logger.info("#{tag} #{channel.inbox.name}: @#{user['username']} fora do Chatwoot, #{messages.size} mensagem(ns)")
      next if dry_run

      messages.sort_by { |m| m['created_time'].to_s }.each { |m| ::Instagram::MessageText.new(webhook_payload(channel, user, m), channel).perform }
    end
  end

  def missing_conversations(channel, since, known)
    found = []
    url = "#{base_url}/me/conversations"
    query = { platform: 'instagram', fields: 'updated_time,participants', limit: 50, access_token: channel.access_token }
    4.times do
      page = get(url, query)
      (page['data'] || []).each do |conversation|
        return found if Time.zone.parse(conversation['updated_time'].to_s) < since

        user = (conversation.dig('participants', 'data') || []).find { |p| p['id'] != channel.instagram_id }
        found << [conversation['id'], user] if user && known.exclude?(user['id'])
      end
      url = page.dig('paging', 'next')
      break if url.blank?

      query = {}
    end
    found
  end

  def conversation_messages(channel, conversation_id)
    get("#{base_url}/#{conversation_id}", { fields: 'messages{id,created_time,from,to,message}', access_token: channel.access_token })
      .dig('messages', 'data') || []
  end

  # Mesmo formato do aviso da Meta; mensagem da própria conta vira eco
  def webhook_payload(channel, user, message)
    from_business = message.dig('from', 'id') == channel.instagram_id
    {
      sender: { id: from_business ? channel.instagram_id : user['id'] },
      recipient: { id: from_business ? user['id'] : channel.instagram_id },
      timestamp: (Time.zone.parse(message['created_time'].to_s).to_f * 1000).to_i,
      message: { mid: message['id'], text: message['message'].presence || '(anexo — ver no Instagram)', is_echo: from_business || nil }.compact
    }.with_indifferent_access
  end

  def get(url, query)
    response = HTTParty.get(url, query: query, timeout: 20)
    return response.parsed_response if response.success? && response.parsed_response.is_a?(Hash)

    Rails.logger.warn("[IgSync] leitura falhou: #{response.body.to_s[0, 200]}")
    {}
  end

  def inbox_ids
    ENV.fetch('IG_SYNC_INBOX_IDS', '11,15').split(',').map(&:strip).reject(&:blank?).map(&:to_i)
  end

  def base_url
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
