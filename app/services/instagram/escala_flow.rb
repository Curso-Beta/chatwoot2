# Fluxo "comentou ESCALA → recebe o link no direct" (Hotwebinar, 04/11/2026).
#
# 1. Comentário com a palavra-chave → resposta pública sorteada + resposta privada
#    (direct) com o botão "Quero o link". A Meta só libera mais mensagens depois que
#    a pessoa responde no direct; o botão é essa resposta.
# 2. Tocou no botão (ou escreveu "quero") → texto da imersão + cartão com o botão
#    "Fazer minha aplicação".
#
# Fala direto com a API do Instagram: o Chatwoot não envia botões nesse canal. O
# que sai volta como eco pelo webhook e aparece na conversa para o time.
class Instagram::EscalaFlow
  PAYLOAD = 'ESCALA_LINK'.freeze
  PUBLIC_REPLIES = [
    'Te mandei no direct 📩',
    'Enviado! Confere seu direct 👀',
    'Acabei de te mandar o link no direct ✅'
  ].freeze
  BUTTON_LABEL = 'Quero o link'.freeze
  OPENING = "Oi! Aqui é da Hotwebinar × VK Metrics 👋\n\n" \
            'Vi que você comentou ESCALA. Toca no botão abaixo que eu te mando o link da aplicação ' \
            'da imersão A Escala Lucrativa.'.freeze
  OPENING_FALLBACK = "#{OPENING}\n\nSe o botão não aparecer, é só responder QUERO aqui.".freeze
  LINK_TEXT = "Aqui está 👇\n\n" \
              "A Escala Lucrativa\n" \
              "Imersão presencial · 16 e 17 de novembro\n" \
              "Auditório Hotmart · Rua Girassol, 365 · Vila Madalena · SP\n\n" \
              "Dois dias com os fundadores da Hotwebinar e da VK Metrics para destravar a escala com funis de webinário.\n\n" \
              "30 vagas · só por aplicação · aplicações até 15/11.\n" \
              'A aplicação leva 2 minutos: nome, WhatsApp e algumas perguntas rápidas sobre a sua operação.'.freeze
  LINK_URL = 'https://page.hotwebinar.com.br/escala-lucrativa?utm_source=instagram&utm_medium=dm' \
             '&utm_campaign=escala-lucrativa&utm_content=escala-link'.freeze
  WANTS_LINK = /\A\s*(quero(\s+o\s+link)?|link)\s*[!.]*\s*\z/i
  DEDUP_TTL = 30.days

  def self.enabled?
    ENV['ESCALA_ENABLED'] == 'true' && ENV['ESCALA_SINCE'].present?
  end

  def self.inbox
    Inbox.find_by(id: ENV.fetch('ESCALA_INBOX_ID', '11'))
  end

  # A pessoa respondeu no direct: tocou no botão ou escreveu "quero"
  def self.wants_link?(messaging)
    return true if messaging.dig(:message, :quick_reply, :payload) == PAYLOAD
    return false if messaging.dig(:message, :is_echo).present? || !WANTS_LINK.match?(messaging.dig(:message, :text).to_s)

    # "quero" escrito só vale para quem recebeu a abertura do ESCALA
    ::Redis::Alfred.get(opened_key(messaging.dig(:sender, :id))).present?
  end

  def self.opened_key(recipient_id)
    "escala:opened:#{recipient_id}"
  end

  def initialize(channel)
    @channel = channel
  end

  def handle_comment(comment)
    reply_publicly(comment['id'])
    response = send_dm({ comment_id: comment['id'] }, { text: OPENING, quick_replies: [quick_reply] })
    response = send_dm({ comment_id: comment['id'] }, { text: OPENING_FALLBACK }) unless ok?(response)
    recipient_id = ok?(response) ? response.parsed_response['recipient_id'] : nil
    ::Redis::Alfred.set(self.class.opened_key(recipient_id), 1, ex: 7.days) if recipient_id.present?
    Rails.logger.info("[Escala] comentário #{comment['id']} (@#{comment.dig('from', 'username')}): direct #{ok?(response) ? 'enviado' : 'falhou'}")
    ok?(response)
  end

  def send_link(recipient_id)
    key = "escala:link:#{@channel.id}:#{recipient_id}"
    return unless ::Redis::Alfred.set(key, 1, nx: true, ex: 10.minutes)

    send_dm({ id: recipient_id }, { text: LINK_TEXT })
    response = send_dm({ id: recipient_id }, { attachment: link_card })
    send_dm({ id: recipient_id }, { text: "É só tocar aqui: #{LINK_URL}" }) unless ok?(response)
    Rails.logger.info("[Escala] link enviado para #{recipient_id}")
  end

  private

  def quick_reply
    { content_type: 'text', title: BUTTON_LABEL, payload: PAYLOAD }
  end

  def link_card
    {
      type: 'template',
      payload: {
        template_type: 'generic',
        elements: [{
          title: 'A Escala Lucrativa',
          subtitle: 'Imersão presencial · 16 e 17/11 · São Paulo',
          buttons: [{ type: 'web_url', url: LINK_URL, title: 'Fazer minha aplicação' }]
        }]
      }
    }
  end

  def reply_publicly(comment_id)
    response = HTTParty.post("#{base_url}/#{comment_id}/replies",
                             body: { message: PUBLIC_REPLIES.sample, access_token: @channel.access_token }, timeout: 15)
    Rails.logger.warn("[Escala] resposta pública falhou em #{comment_id}: #{response.body.to_s[0, 200]}") unless ok?(response)
  end

  def send_dm(recipient, message)
    HTTParty.post("#{base_url}/#{@channel.instagram_id.presence || 'me'}/messages",
                  headers: { 'Content-Type' => 'application/json' },
                  query: { access_token: @channel.access_token },
                  body: { recipient: recipient, message: message }.to_json, timeout: 15).tap do |response|
      Rails.logger.warn("[Escala] envio falhou: #{response.body.to_s[0, 300]}") unless ok?(response)
    end
  end

  def ok?(response)
    response.present? && response.success? && response.parsed_response.is_a?(Hash) && response.parsed_response['error'].blank?
  end

  def base_url
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
