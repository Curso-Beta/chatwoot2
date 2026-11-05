# Roda a moderação fora do recebimento do aviso da Meta (a IA leva alguns segundos).
class InstagramCommentModerationJob < ApplicationJob
  queue_as :default

  def perform(channel_id, value)
    channel = Channel::Instagram.find_by(id: channel_id)
    return if channel.blank? || !Instagram::CommentModeration.enabled?

    Instagram::CommentModeration.new(channel).moderate(value)
  end
end
