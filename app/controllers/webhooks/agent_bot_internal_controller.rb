require 'net/http'

class Webhooks::AgentBotInternalController < ActionController::API
  TEAM_SUCESSO = 1
  TEAM_COMERCIAL = 3
  IA_ENDPOINT = 'https://plataforma-agentes-production.up.railway.app/api/chatwoot'.freeze
  IA_BOT_ID = 2

  IA_AGENT_COMERCIAL = 11
  IA_AGENT_SUCESSO = 12
  IA_AGENTS = [IA_AGENT_COMERCIAL, IA_AGENT_SUCESSO].freeze

  def process_payload
    case params[:event]
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

  def handle_message_created
    conversation = find_conversation
    return if conversation.blank?

    if params[:message_type] == 'incoming'
      if conversation_routed?(conversation)
        forward_to_ia(conversation) if assigned_to_ia?(conversation)
      else
        send_routing_question_unless_asked(conversation)
      end
    elsif campaign_message?
      send_routing_question_unless_asked(conversation)
    elsif handoff_requested?(conversation)
      perform_handoff(conversation)
    end
  end

  def campaign_message?
    params.dig(:additional_attributes, :campaign_id).present?
  end

  def send_routing_question_unless_asked(conversation)
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

    email = values['email'].to_s.strip.downcase.presence
    name = values['name'].to_s.strip.presence
    contact = conversation.contact

    if email.present?
      existing = Contact.find_by(email: email, account_id: conversation.account_id)
      if existing && existing.id != contact.id
        existing.update(name: name) if name.present? && !contact_has_real_name?(existing)
        conversation.update_columns(contact_id: existing.id)
        conversation.contact_inbox&.update_columns(contact_id: existing.id)
        contact = existing
      else
        updates = {}
        updates[:email] = email if contact.email.blank?
        updates[:name] = name if name.present? && !contact_has_real_name?(contact)
        contact.update(updates) if updates.present?
      end
    elsif name.present? && !contact_has_real_name?(contact)
      contact.update(name: name)
    end

    greeting = name ? "Obrigado, #{name}!" : 'Obrigado!'
    send_bot_message(conversation, "#{greeting} Já vou te conectar com a equipe, enquanto isso escreva como podemos te ajudar? 😊")
    conversation.bot_handoff! if conversation.pending?
    assign_ia_agent(conversation)
    trigger_ia(conversation)
  end

  def contact_has_real_name?(contact)
    return false if contact.name.blank?

    contact.name !~ /\A[a-z]+-[a-z]+-\d+\z/
  end

  # Com time definido, a conversa já passou pela recepção — em qualquer
  # status menos resolvida. Antes exigia "open": quando a pessoa resolvia a
  # conversa pelo widget e voltava a escrever, ela reabria como "pending", a
  # recepção não repassava nada e a IA ficava muda (Vânia, 60501, 28/09/2026).
  def conversation_routed?(conversation)
    conversation.team_id.present? && !conversation.resolved?
  end

  def assigned_to_ia?(conversation)
    IA_AGENTS.include?(conversation.assignee_id)
  end

  def handoff_requested?(conversation)
    params[:message_type] == 'outgoing' &&
      assigned_to_ia?(conversation) &&
      params.dig(:content_attributes, :handoff).present?
  end

  def perform_handoff(conversation)
    team = Team.find_by(id: conversation.team_id)
    return if team.blank?

    humans = team.members.where.not(id: IA_AGENTS)
    return if humans.empty?

    online_ids = humans.select { |u| u.availability_status == 'online' }.map(&:id)
    pool = online_ids.presence || humans.pluck(:id)

    agent_loads = pool.map do |uid|
      [uid, Conversation.where(team_id: team.id, assignee_id: uid, status: :open).count]
    end
    next_agent_id = agent_loads.min_by(&:last).first

    conversation.update!(assignee_id: next_agent_id)

    agent = User.find(next_agent_id)
    if online_ids.present?
      send_bot_message(conversation, "#{agent.name} vai continuar seu atendimento. 😊")
    else
      send_bot_message(conversation, "Nossas atendentes não estão disponíveis no momento. Sua conversa foi encaminhada para #{agent.name} e será respondida assim que possível. 😊")
    end
    Rails.logger.info("[AgentBotInternal] Handoff conversation #{conversation.display_id} to #{agent.name} (#{agent.id}), online=#{online_ids.present?}")
  end

  def assign_ia_agent(conversation)
    agent_id = ia_agent_for_team(conversation.team_id)
    return unless agent_id

    conversation.update!(assignee_id: agent_id)
  end

  def ia_agent_for_team(team_id)
    case team_id
    when TEAM_COMERCIAL then IA_AGENT_COMERCIAL
    when TEAM_SUCESSO then IA_AGENT_SUCESSO
    end
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

    agent_id = ia_agent_for_team(conversation.team_id)
    agent = User.find_by(id: agent_id) if agent_id

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
    payload[:ia_agent] = { id: agent.id, name: agent.name, email: agent.email } if agent

    post_to_ia(payload)
  end

  def forward_to_ia(conversation)
    payload = params.to_unsafe_h
    agent_id = ia_agent_for_team(conversation.team_id)
    agent = User.find_by(id: agent_id) if agent_id
    payload[:ia_agent] = { id: agent.id, name: agent.name, email: agent.email } if agent
    post_to_ia(payload)
  end

  def post_to_ia(payload)
    ia_bot = AgentBot.find_by(id: IA_BOT_ID)
    return if ia_bot.blank?

    AgentBots::WebhookJob.perform_later(
      ia_bot.outgoing_url,
      payload,
      :agent_bot_webhook,
      secret: ia_bot.secret,
      delivery_id: SecureRandom.uuid
    )
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
      'Para te atender melhor, preencha seus dados:',
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
