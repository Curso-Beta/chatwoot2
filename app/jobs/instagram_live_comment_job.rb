# Comentário de live: primeiro a moderação (ofensivo/ambíguo é apagado e não
# recebe o direct), depois o direct da Ana (Instagram::LiveKeywordFlow). Fora do
# recebimento do aviso da Meta porque a IA leva alguns segundos.
class InstagramLiveCommentJob < ApplicationJob
  queue_as :default

  def perform(channel_id, value)
    channel = Channel::Instagram.find_by(id: channel_id)
    return if channel.blank?

    barrado = Instagram::CommentModeration.enabled? && Instagram::CommentModeration.new(channel).moderate(value)
    Instagram::LiveKeywordFlow.new(channel).handle(value) if !barrado && Instagram::LiveKeywordFlow.enabled_for?(channel)
  end
end
