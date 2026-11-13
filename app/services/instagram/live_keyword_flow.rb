# Comentou a palavra-chave na live → direct na hora (Curso Beta, Black Friday,
# 13/11/2026). Só a abertura sai daqui: quando a pessoa responde, a conversa é da
# Ana (plataforma de agentes), que pergunta a profissão e manda a página da Black
# da formação. A Meta só aceita a resposta privada enquanto a live está no ar.
# Uma mensagem por pessoa por live. Liga com LIVE_FLOW_ENABLED=true;
# LIVE_FLOW_INBOX_ID (padrão 15), LIVE_FLOW_KEYWORDS (regex), LIVE_FLOW_TEXT.
class Instagram::LiveKeywordFlow
  # "black" em qualquer forma (Black Friday, blackfriday, blacks) ou "quero"
  DEFAULT_KEYWORDS = 'black|\bquero\b'.freeze
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
    Rails.logger.info("[Live] comentário #{value['id']} (@#{value.dig('from', 'username')}): direct #{ok ? 'enviado' : "falhou #{response.body.to_s[0, 200]}"}")
  end

  private

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
