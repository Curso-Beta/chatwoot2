# Comentou na live → direct na hora (Curso Beta, Black Friday,
# 13/11/2026). Só a abertura sai daqui, já perguntando a profissão: quando a pessoa
# responde, a conversa é da Ana (plataforma de agentes), que lê a abertura no
# histórico do Chatwoot (sabe que veio da live) e manda a página da Black da
# formação. A Meta só aceita a resposta privada enquanto a live está no ar.
# Uma mensagem por pessoa por live. Liga com LIVE_FLOW_ENABLED=true;
# LIVE_FLOW_INBOX_ID (padrão 15), LIVE_FLOW_KEYWORDS (regex), LIVE_FLOW_TEXT.
class Instagram::LiveKeywordFlow
  # Breno, 13/11: qualquer comentário na live dispara (uma vez por pessoa por live).
  # Para voltar a filtrar: LIVE_FLOW_KEYWORDS='black|\bquero\b'
  DEFAULT_KEYWORDS = '\S'.freeze
  DEFAULT_TEXT = "Oi! Aqui é a Ana, do Curso Beta 👋\n\n" \
                 'Vi seu comentário na live da Black Friday! Me conta: qual é a sua profissão? ' \
                 'Assim eu te mando o link da oferta da formação certa pra você.'.freeze

  def self.enabled_for?(channel)
    ENV['LIVE_FLOW_ENABLED'] == 'true' && channel.inbox&.id.to_s == ENV.fetch('LIVE_FLOW_INBOX_ID', '15')
  end

  def initialize(channel)
    @channel = channel
  end

  # value: payload do aviso "live_comments" (id, text, from, media)
  def handle(value)
    return if value['id'].blank? || value.dig('from', 'id') == @channel.instagram_id
    return unless keyword_regex.match?(value['text'].to_s)

    once = "live_flow:#{value.dig('media', 'id')}:#{value.dig('from', 'id') || value['id']}"
    return unless ::Redis::Alfred.set(once, 1, nx: true, ex: 2.days)

    response = HTTParty.post("#{base_url}/#{@channel.instagram_id.presence || 'me'}/messages",
                             headers: { 'Content-Type' => 'application/json' },
                             query: { access_token: @channel.access_token },
                             body: { recipient: { comment_id: value['id'] }, message: { text: text } }.to_json, timeout: 15)
    ok = response.success? && response.parsed_response.is_a?(Hash) && response.parsed_response['error'].blank?
    ::Redis::Alfred.delete(once) unless ok
    ensure_contact(response.parsed_response['recipient_id'], value) if ok
    Rails.logger.info("[Live] comentário #{value['id']} (@#{value.dig('from', 'username')}): direct #{ok ? 'enviado' : "falhou #{response.body.to_s[0, 200]}"}")
  end

  private

  # Quem só comentou ainda não deu consentimento: a Meta recusa o perfil (erro 230)
  # e o eco da abertura se perderia sem contato. Criado aqui, o eco entra na
  # conversa, e a Ana lê a abertura no histórico quando a pessoa responder.
  def ensure_contact(recipient_id, value)
    return if recipient_id.blank? || @channel.inbox.contact_inboxes.exists?(source_id: recipient_id)

    username = value.dig('from', 'username')
    ::ContactInboxWithContactBuilder.new(
      source_id: recipient_id, inbox: @channel.inbox,
      contact_attributes: { name: username.presence || "Instagram #{recipient_id}",
                            additional_attributes: { social_instagram_user_name: username, origem: 'live_black' }.compact }
    ).perform
  rescue StandardError => e
    Rails.logger.warn("[Live] não criei o contato #{recipient_id}: #{e.message}")
  end

  def keyword_regex
    Regexp.new(ENV.fetch('LIVE_FLOW_KEYWORDS', DEFAULT_KEYWORDS), Regexp::IGNORECASE)
  end

  def text
    ENV['LIVE_FLOW_TEXT'].presence || DEFAULT_TEXT
  end

  def base_url
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
