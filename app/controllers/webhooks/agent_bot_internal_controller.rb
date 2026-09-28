class Webhooks::AgentBotInternalController < ActionController::API
  TEAM_SUCESSO = 1
  TEAM_COMERCIAL = 3

  def process_payload
    case params[:event]
    when 'webwidget_triggered'
      handle_webwidget_triggered
    when 'message_created'
      handle_message_created
    when 'message_updated'
      handle_message_updated
    end

    head :ok
  end

  private

  def handle_webwidget_triggered
    contact_inbox = ContactInbox.find_by(id: params[:id])
    return if contact_inbox.blank?

    existing = contact_inbox.conversations.where(status: [:open, :pending]).last
    return if existing.present?

    conversation = Conversation.create!(
      account_id: contact_inbox.inbox.account_id,
      inbox_id: contact_inbox.inbox_id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      status: :pending
    )

    send_routing_question(conversation)
  end

  def handle_message_created
    return unless params[:message_type] == 'incoming'

    conversation = find_conversation
    return if conversation.blank?

    already_asked = conversation.messages.exists?(content_type: 'input_select', message_type: :outgoing)
    return if already_asked

    send_routing_question(conversation)
  end

  def handle_message_updated
    return unless params[:content_type] == 'input_select'

    submitted = params.dig(:content_attributes, :submitted_values)
    return if submitted.blank?

    conversation = find_conversation
    return if conversation.blank?

    selected_value = submitted.first&.dig(:value) || submitted.first&.dig('value')
    return if selected_value.blank?

    team_id = case selected_value
              when 'aluno'    then TEAM_SUCESSO
              when 'nao_aluno' then TEAM_COMERCIAL
              end
    return unless team_id

    conversation.update!(team_id: team_id)
    conversation.bot_handoff! if conversation.pending?
  end

  def find_conversation
    conv_data = params[:conversation]
    return if conv_data.blank?

    Conversation.find_by(
      display_id: conv_data[:id],
      account_id: conv_data.dig(:account, :id)
    )
  end

  def send_routing_question(conversation)
    agent_bot = conversation.inbox&.agent_bot
    return if agent_bot.blank?

    Messages::MessageBuilder.new(nil, conversation, {
      content: 'Olá! 👋 Bem-vindo ao Curso Beta! Me conta: você já é nosso aluno?',
      message_type: 'outgoing',
      content_type: 'input_select',
      sender_type: 'AgentBot',
      sender_id: agent_bot.id,
      content_attributes: {
        items: [
          { title: 'Sim, já sou aluno', value: 'aluno' },
          { title: 'Ainda não sou aluno', value: 'nao_aluno' }
        ]
      }
    }).perform
  end
end
