# Moderação de comentários do Instagram (Hotwebinar, 05/11/2026).
#
# Cada comentário novo (aviso "comments" da Meta) passa por uma IA:
#   - ofensivo (xingamento, ódio, golpe, spam) ou em dúvida → apagado na hora;
#   - normal → nada;
#   - IA sem resposta → mensagem direta no Slack para quem decide, com links
#     para apagar ou manter (InstagramModerationController).
# Não responde ninguém. Todo comentário apagado fica registrado no Redis
# (LOG_KEY) com texto, autor e post, porque apagar não tem volta.
# Liga com IG_MODERATION_ENABLED=true; IG_MODERATION_SLACK_USER = quem decide;
# IG_MODERATION_OPENAI_KEY = chave da IA.
class Instagram::CommentModeration
  LOG_KEY = 'ig_moderation:log'.freeze
  LOG_SIZE = 2000
  CATEGORIES = %w[ofensivo duvida normal].freeze
  PROMPT = <<~PROMPT.freeze
    Você modera comentários no Instagram da Hotwebinar, uma plataforma brasileira de webinários.
    Classifique o comentário em UMA categoria:
    - "ofensivo": xingamento, palavrão dirigido a alguém, ofensa, ódio, preconceito, assédio,
      ameaça, golpe, link suspeito, spam ou propaganda de terceiros.
    - "duvida": pode ser ofensivo mas não é claro — crítica dura sem palavrão, ironia agressiva,
      acusação ("isso é golpe?"), reclamação muito agressiva, conteúdo ambíguo.
    - "normal": todo o resto, inclusive elogio, pergunta, reclamação educada, emoji, marcação de
      amigo e palavras-chave de campanha (ex.: "ESCALA").
    Na dúvida entre "ofensivo" e "duvida", escolha "duvida".
    Responda só com JSON: {"categoria": "ofensivo|duvida|normal", "motivo": "até 12 palavras"}
  PROMPT

  def self.enabled?
    ENV['IG_MODERATION_ENABLED'] == 'true'
  end

  def initialize(channel)
    @channel = channel
  end

  # value: payload do aviso "comments" ou "live_comments" (id, text, from, media, parent_id).
  # Devolve true quando o comentário foi barrado (mesmo que a Meta recuse apagar).
  def moderate(value)
    return false if value['id'].blank? || value['text'].blank?
    return false if value.dig('from', 'id') == @channel.instagram_id
    return false unless ::Redis::Alfred.set("ig_moderation:seen:#{value['id']}", 1, nx: true, ex: 7.days)

    verdict = classify(value['text'])
    Rails.logger.info("[Moderação] #{value['id']} (@#{value.dig('from', 'username')}): #{verdict['categoria']} — #{verdict['motivo']}")
    # Breno, 06/11: ambíguo também é apagado. Só a falha da IA vai ao Slack:
    # sem resposta dela, nada é apagado.
    if verdict['falhou']
      ask_human(value, verdict['motivo'])
      false
    elsif %w[ofensivo duvida].include?(verdict['categoria'])
      delete!(value, "#{verdict['categoria']}: #{verdict['motivo']}", by: 'ia')
      true
    else
      false
    end
  end

  def delete!(value, reason, by:)
    response = HTTParty.delete("#{base_url}/#{value['id']}", query: { access_token: @channel.access_token }, timeout: 15)
    ok = response.success? && response.parsed_response.is_a?(Hash) && response.parsed_response['success']
    log(value, reason, by, ok ? 'apagado' : "falhou: #{response.body.to_s[0, 160]}")
    Rails.logger.warn("[Moderação] não apaguei #{value['id']}: #{response.body.to_s[0, 200]}") unless ok
    ok
  end

  def keep!(value, by:)
    log(value, 'mantido após revisão', by, 'mantido')
  end

  private

  def classify(text)
    response = HTTParty.post(
      "#{openai_endpoint.chomp('/')}/v1/chat/completions",
      headers: { 'Authorization' => "Bearer #{openai_key}", 'Content-Type' => 'application/json' },
      body: {
        model: ENV.fetch('IG_MODERATION_MODEL', 'gpt-4o-mini'),
        temperature: 0,
        response_format: { type: 'json_object' },
        messages: [{ role: 'system', content: PROMPT }, { role: 'user', content: text.to_s[0, 2000] }]
      }.to_json,
      timeout: 20
    )
    parsed = JSON.parse(response.parsed_response.dig('choices', 0, 'message', 'content').to_s)
    CATEGORIES.include?(parsed['categoria']) ? parsed : { 'falhou' => true, 'motivo' => 'resposta da IA fora do padrão' }
  rescue StandardError => e
    # IA fora do ar: ninguém é apagado sem a IA; vai para revisão humana
    Rails.logger.error("[Moderação] IA falhou: #{e.message}")
    { 'falhou' => true, 'motivo' => 'a IA não respondeu' }
  end

  def ask_human(value, reason)
    user = ENV.fetch('IG_MODERATION_SLACK_USER', nil)
    token = ENV.fetch('SLACK_BOT_TOKEN', nil)
    return if user.blank? || token.blank?

    link = ->(action) { "#{ENV.fetch('FRONTEND_URL', '')}/instagram_moderation/#{InstagramModerationController.token_for(@channel, value, action)}" }
    text = [
      ":warning: *Comentário para revisar no Instagram @#{@channel.inbox&.name}*",
      "> #{value['text'].to_s.tr("\n", ' ')[0, 500]}",
      "Autor: @#{value.dig('from', 'username') || '?'} · Motivo da IA: #{reason}",
      permalink(value).then { |url| url ? "<#{url}|Ver o post>" : nil },
      "<#{link.call('apagar')}|:wastebasket: Apagar>   ·   <#{link.call('manter')}|:white_check_mark: Manter>"
    ].compact.join("\n")
    HTTParty.post('https://slack.com/api/chat.postMessage',
                  headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json; charset=utf-8' },
                  body: { channel: user, text: text, unfurl_links: false, unfurl_media: false }.to_json, timeout: 10)
  rescue StandardError => e
    Rails.logger.error("[Moderação] Slack falhou: #{e.message}")
  end

  def permalink(value)
    media_id = value.dig('media', 'id')
    return if media_id.blank?

    response = HTTParty.get("#{base_url}/#{media_id}", query: { fields: 'permalink', access_token: @channel.access_token }, timeout: 10)
    response.success? ? response.parsed_response['permalink'] : nil
  end

  def log(value, reason, by, result)
    entry = {
      at: Time.current.iso8601, comment_id: value['id'], text: value['text'], author: value.dig('from', 'username'),
      media_id: value.dig('media', 'id'), reason: reason, by: by, result: result
    }
    ::Redis::Alfred.lpush(LOG_KEY, entry.to_json)
    ::Redis::Alfred.with { |r| r.ltrim(LOG_KEY, 0, LOG_SIZE - 1) }
    Rails.logger.info("[Moderação] #{result}: #{entry.to_json}")
  end

  # IG_MODERATION_OPENAI_KEY = referência à chave da plataforma de agentes no Railway
  # (a do Captain estava revogada em 05/11/2026); sem ela, a do Captain
  def openai_key
    ENV['IG_MODERATION_OPENAI_KEY'].presence || GlobalConfigService.load('CAPTAIN_OPEN_AI_API_KEY', nil)
  end

  def openai_endpoint
    GlobalConfigService.load('CAPTAIN_OPEN_AI_ENDPOINT', nil).presence || 'https://api.openai.com/'
  end

  def base_url
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
