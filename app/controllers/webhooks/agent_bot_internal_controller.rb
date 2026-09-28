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
  rescue StandardError => e
    Rails.logger.error("[AgentBotInternal] #{e.class}: #{e.message}")
  ensure
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
    submitted = params.dig(:content_attributes, :submitted_values)
    return if submitted.blank?

    conversation = find_conversation
    return if conversation.blank?

    case params[:content_type]
    when 'input_select'
      handle_routing_selection(conversation, submitted)
    when 'form'
      handle_form_submission(conversation, submitted)
    end
  end

  def handle_routing_selection(conversation, submitted)
    selected_value = submitted.first&.dig(:value) || submitted.first&.dig('value')
    return if selected_value.blank?

    team_id = case selected_value
              when 'aluno'    then TEAM_SUCESSO
              when 'nao_aluno' then TEAM_COMERCIAL
              end
    return unless team_id

    conversation.update!(team_id: team_id)
    send_contact_form(conversation)
  end

  def handle_form_submission(conversation, submitted)
    values = submitted.each_with_object({}) do |field, hash|
      key = field[:name] || field['name']
      val = field[:value] || field['value']
      hash[key] = val if key.present?
    end

    contact = conversation.contact
    updates = {}
    updates[:name] = values['name'] if values['name'].present? && !contact_has_real_name?(contact)
    updates[:email] = values['email'] if values['email'].present? && contact.email.blank?
    contact.update(updates) if updates.present?

    name = values['name'].presence
    greeting = name ? "Obrigado, #{name}!" : 'Obrigado!'
    send_bot_message(conversation, "#{greeting} Já vou te conectar com a equipe. 😊")
    conversation.bot_handoff! if conversation.pending?
  end

  def contact_has_real_name?(contact)
    return false if contact.name.blank?

    contact.name !~ /\A[a-z]+-[a-z]+-\d+\z/
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

  def send_contact_form(conversation)
    send_bot_message(
      conversation,
      'Para te conectar com a equipe, preencha seus dados:',
      content_type: 'form',
      content_attributes: {
        items: [
          { name: 'name', label: 'Nome', type: 'text', required: true, placeholder: 'Seu nome' },
          { name: 'email', label: 'E-mail', type: 'email', required: true, placeholder: 'seu@email.com' }
        ],
        button_label: 'Enviar'
      }
    )
  end
end
