class Whatsapp::TemplateManagementService
  WHATSAPP_API_VERSION = 'v14.0'.freeze

  def initialize(whatsapp_channel)
    @whatsapp_channel = whatsapp_channel
  end

  def create_template(params)
    request_body = build_create_body(params)
    response = HTTParty.post(
      "#{business_account_path}/message_templates",
      headers: api_headers,
      body: request_body.to_json
    )
    process_create_response(response, params)
  end

  def update_template(template_id, params)
    request_body = build_update_body(params)
    response = HTTParty.post(
      "#{api_base_path}/#{WHATSAPP_API_VERSION}/#{template_id}",
      headers: api_headers,
      body: request_body.to_json
    )
    process_update_response(response, template_id)
  end

  def delete_template(template_name)
    response = HTTParty.delete(
      "#{business_account_path}/message_templates?name=#{template_name}",
      headers: api_headers
    )

    if response.success?
      sync_templates_async
      { success: true }
    else
      { success: false, error: parse_error(response) }
    end
  end

  private

  def build_create_body(params)
    body = {
      name: params[:name],
      language: params[:language],
      category: params[:category]&.upcase
    }
    body[:components] = build_components(params[:components]) if params[:components].present?
    body[:allow_category_change] = params[:allow_category_change] if params.key?(:allow_category_change)
    body
  end

  def build_update_body(params)
    body = {}
    body[:components] = build_components(params[:components]) if params[:components].present?
    body[:category] = params[:category]&.upcase if params[:category].present?
    body
  end

  def build_components(components)
    components.map do |component|
      comp = { type: component[:type]&.upcase }

      case comp[:type]
      when 'HEADER'
        build_header_component(comp, component)
      when 'BODY'
        comp[:text] = component[:text]
        comp[:example] = component[:example] if component[:example].present?
      when 'FOOTER'
        comp[:text] = component[:text]
      when 'BUTTONS'
        comp[:buttons] = build_buttons(component[:buttons])
      end

      comp
    end
  end

  def build_header_component(comp, component)
    comp[:format] = component[:format]&.upcase if component[:format].present?
    comp[:text] = component[:text] if component[:text].present?
    comp[:example] = component[:example] if component[:example].present?
    comp
  end

  def build_buttons(buttons)
    return [] if buttons.blank?

    buttons.map do |button|
      btn = { type: button[:type]&.upcase, text: button[:text] }
      btn[:url] = button[:url] if button[:url].present?
      btn[:phone_number] = button[:phone_number] if button[:phone_number].present?
      btn[:example] = button[:example] if button[:example].present?
      btn
    end
  end

  def process_create_response(response, params)
    if response.success?
      sync_templates_async
      {
        success: true,
        template_id: response['id'],
        template_name: params[:name],
        status: response['status'] || 'PENDING'
      }
    else
      { success: false, error: parse_error(response) }
    end
  end

  def process_update_response(response, template_id)
    if response.success?
      sync_templates_async
      { success: true, template_id: template_id }
    else
      { success: false, error: parse_error(response) }
    end
  end

  def parse_error(response)
    parsed = response.parsed_response
    if parsed.is_a?(Hash) && parsed['error']
      {
        message: parsed.dig('error', 'message'),
        code: parsed.dig('error', 'code'),
        type: parsed.dig('error', 'type')
      }
    else
      { message: "HTTP #{response.code}", code: response.code }
    end
  end

  def sync_templates_async
    Channels::Whatsapp::TemplatesSyncJob.perform_later(@whatsapp_channel)
  end

  def business_account_path
    "#{api_base_path}/#{WHATSAPP_API_VERSION}/#{@whatsapp_channel.provider_config['business_account_id']}"
  end

  def api_headers
    {
      'Authorization' => "Bearer #{@whatsapp_channel.template_access_token}",
      'Content-Type' => 'application/json'
    }
  end

  def api_base_path
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end
end
