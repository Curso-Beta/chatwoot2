# Decisão humana sobre comentário em dúvida (Instagram::CommentModeration). O link
# chega por mensagem direta no Slack, assinado e válido por 7 dias. A página pede
# confirmação (POST): abrir o link sozinho não apaga nada.
class InstagramModerationController < ActionController::Base
  skip_forgery_protection

  # url_safe: o token vai no caminho do link do Slack
  def self.verifier
    @verifier ||= ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key('instagram_moderation'), url_safe: true, serializer: JSON
    )
  end

  def self.token_for(channel, value, action)
    verifier.generate(
      { 'channel_id' => channel.id, 'action' => action,
        'comment' => value.slice('id', 'text', 'media').merge('from' => value['from'].to_h.slice('id', 'username')) },
      expires_in: 7.days
    )
  end

  def show
    @data = decoded
    return render_message('Link inválido ou vencido.', :not_found) if @data.blank?

    action = @data['action'] == 'apagar' ? 'Apagar' : 'Manter'
    render html: page(<<~HTML).html_safe
      <p style="color:#555">@#{ERB::Util.h(@data.dig('comment', 'from', 'username'))} comentou:</p>
      <blockquote style="border-left:3px solid #ccc;margin:0;padding:8px 12px">#{ERB::Util.h(@data.dig('comment', 'text'))}</blockquote>
      <form method="post" style="margin-top:20px">
        <button style="font-size:16px;padding:10px 18px;border-radius:8px;border:0;background:#{action == 'Apagar' ? '#d43f5e' : '#2f8f6a'};color:#fff;cursor:pointer">
          #{action} comentário
        </button>
      </form>
    HTML
  end

  def create
    data = decoded
    return render_message('Link inválido ou vencido.', :not_found) if data.blank?
    return render_message('Este comentário já foi decidido.') unless ::Redis::Alfred.set("ig_moderation:decided:#{data.dig('comment', 'id')}", 1,
                                                                                         nx: true, ex: 30.days)

    channel = Channel::Instagram.find_by(id: data['channel_id'])
    moderation = Instagram::CommentModeration.new(channel)
    if data['action'] == 'apagar'
      ok = moderation.delete!(data['comment'], 'apagado após revisão', by: 'humano')
      render_message(ok ? 'Comentário apagado.' : 'Não consegui apagar (talvez já tenha sido apagado).')
    else
      moderation.keep!(data['comment'], by: 'humano')
      render_message('Comentário mantido.')
    end
  end

  private

  def decoded
    self.class.verifier.verified(params[:token])
  rescue StandardError
    nil
  end

  def render_message(text, status = :ok)
    render html: page("<p style=\"font-size:18px\">#{ERB::Util.h(text)}</p>").html_safe, status: status
  end

  def page(body)
    <<~HTML
      <!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
      <title>Moderação · Instagram</title></head>
      <body style="font-family:-apple-system,system-ui,sans-serif;max-width:560px;margin:40px auto;padding:0 16px">
      <h2 style="margin-bottom:16px">Moderação de comentário</h2>#{body}</body></html>
    HTML
  end
end
