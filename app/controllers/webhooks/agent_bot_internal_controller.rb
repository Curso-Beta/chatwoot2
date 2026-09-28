require 'net/http'

class Webhooks::AgentBotInternalController < ActionController::API
  TEAM_SUCESSO = 1
  TEAM_COMERCIAL = 3
  IA_ENDPOINT = 'https://plataforma-agentes-production.up.railway.app/api/chatwoot'.freeze

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

    if conversation_routed?(conversation)
      forward_to_ia
      return
    end

    already_asked = conversation.messages.exists?(content_type: 'input_select', message_type: :outgoing)
    return if already_asked

    send_routing_question(conversation)
  end

  def handle_message_updated
    submitted = params.dig(:content_attributes, :submitted_values)
    return if submitted.blank?

    conversation = find_conversation
    return if conversation.blank?

    return unless params[:content_type] == 'input_select'

    handle_routing_selection(conversation, submitted)
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
    send_bot_message(conversation, 'Um momento, vou te conectar com a equipe... 😊')
    conversation.bot_handoff! if conversation.pending?

    trigger_ia(conversation)
  end

  def conversation_routed?(conversation)
    conversation.team_id.present? && conversation.open?
  end

  def trigger_ia(conversation)
    first_msg = conversation.messages.where(message_type: :incoming).order(:created_at).first
    return if first_msg.blank?

    contact = conversation.contact
    contact_data = {
      id: contact.id,
      name: contact.name,
      email: contact.email,
      phone_number: contact.phone_number,
      type: 'contact'
    }.compact

    payload = {
      event: 'message_created',
      message_type: 'incoming',
      content: first_msg.content,
      id: first_msg.id,
      conversation: {
        id: conversation.display_id,
        account: { id: conversation.account_id }
      },
      account: { id: conversation.account_id },
      sender: contact_data,
      contact: contact_data
    }

    post_to_ia(payload)
  end

  def forward_to_ia
    post_to_ia(params.to_unsafe_h)
  end

  def post_to_ia(payload)
    uri = URI(IA_ENDPOINT)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
    request.body = payload.to_json
    http.request(request)
  rescue StandardError => e
    Rails.logger.error("[AgentBotInternal] IA forward failed: #{e.class}: #{e.message}")
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
