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

    # Conversation has team assigned but still pending = waiting for contact info
    if conversation.team_id.present? && conversation.pending?
      process_contact_info(conversation)
      return
    end

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

    send_bot_message(conversation, 'Antes de te conectar com a equipe, me diz seu nome e email?')
  end

  def process_contact_info(conversation)
    content = params[:content].to_s.strip
    return if content.blank?

    contact = conversation.contact
    email = content[/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/]
    name = content.gsub(/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/, '').strip
    name = nil if name.blank?

    updates = {}
    updates[:email] = email if email.present? && contact.email.blank?
    updates[:name] = name if name.present? && (contact.name.blank? || contact.name.start_with?('Contact'))
    contact.update!(updates) if updates.present?

    if email.present?
      greeting = name.present? ? "Obrigado, #{name}!" : 'Obrigado!'
      send_bot_message(conversation, "#{greeting} Já vou te conectar com a equipe. 😊")
      conversation.bot_handoff!
    else
      send_bot_message(conversation, 'Pode me informar seu email? Assim a equipe consegue te retornar.')
    end
  end

  def find_conversation
    conv_data = params[:conversation]
    return if conv_data.blank?

    Conversation.find_by(
      display_id: conv_data[:id],
      account_id: conv_data.dig(:account, :id)
    )
  end

  def send_bot_message(conversation, text, content_type: nil, content_attributes: nil)
    agent_bot = conversation.inbox&.agent_bot
    return if agent_bot.blank?

    msg_params = {
      content: text,
      message_type: 'outgoing',
      sender_type: 'AgentBot',
      sender_id: agent_bot.id
    }
    msg_params[:content_type] = content_type if content_type
    msg_params[:content_attributes] = content_attributes if content_attributes

    Messages::MessageBuilder.new(nil, conversation, msg_params).perform
  end

  def send_routing_question(conversation)
    send_bot_message(
      conversation,
      'Olá! 👋 Bem-vindo ao Curso Beta! Me conta: você já é nosso aluno?',
      content_type: 'input_select',
      content_attributes: {
        items: [
          { title: 'Sim, já sou aluno', value: 'aluno' },
          { title: 'Ainda não sou aluno', value: 'nao_aluno' }
        ]
      }
    )
  end
end
