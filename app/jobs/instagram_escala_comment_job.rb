# Reserva do fluxo ESCALA: o caminho normal é o aviso de comentário da Meta, que
# dispara na hora (Webhooks::InstagramEventsJob). Esta busca pega o que o aviso
# perder. Ver Instagram::EscalaFlow. Liga com ESCALA_ENABLED=true e ESCALA_SINCE
# (ISO 8601): comentários anteriores nunca recebem mensagem. ESCALA_ONLY_USERNAMES = modo teste.
class InstagramEscalaCommentJob < ApplicationJob
  queue_as :scheduled_jobs

  MAX_PER_RUN = 30

  def perform(dry_run: false)
    return unless dry_run || Instagram::EscalaFlow.enabled?

    channel = Instagram::EscalaFlow.inbox&.channel
    return unless channel.is_a?(Channel::Instagram)

    since = Time.zone.parse(ENV.fetch('ESCALA_SINCE', 1.day.ago.iso8601))
    flow = Instagram::EscalaFlow.new(channel)
    sent = 0
    pending_comments(channel, since).each do |comment|
      break if sent >= MAX_PER_RUN

      if dry_run
        Rails.logger.info("[Escala][dry-run] responderia #{comment['id']} (@#{comment.dig('from', 'username')}): #{comment['text']}")
        next
      end
      next unless Instagram::EscalaFlow.claim_comment?(comment['id'])

      sent += 1
      flow.handle_comment(comment)
    end
  end

  private

  def pending_comments(channel, since)
    media_ids(channel).flat_map { |media_id| comments(channel, media_id) }.select do |comment|
      Time.zone.parse(comment['timestamp'].to_s) >= since &&
        comment.dig('from', 'id') != channel.instagram_id &&
        Instagram::EscalaFlow.allowed_user?(comment.dig('from', 'username')) &&
        Instagram::EscalaFlow.keyword?(comment['text'])
    rescue ArgumentError
      false
    end
  end

  # ESCALA_MEDIA_IDS fixa os posts; sem ela, os 10 mais recentes
  def media_ids(channel)
    fixed = Instagram::EscalaFlow.media_ids
    return fixed if fixed.any?

    get(channel, 'me/media', fields: 'id', limit: 10).fetch('data', []).pluck('id')
  end

  def comments(channel, media_id)
    get(channel, "#{media_id}/comments", fields: 'id,text,timestamp,from', limit: 50).fetch('data', [])
  end

  def get(channel, path, params)
    response = HTTParty.get("https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}/#{path}",
                            query: params.merge(access_token: channel.access_token), timeout: 15)
    return response.parsed_response if response.success? && response.parsed_response.is_a?(Hash)

    Rails.logger.warn("[Escala] leitura falhou em #{path}: #{response.body.to_s[0, 200]}")
    {}
  end
end
