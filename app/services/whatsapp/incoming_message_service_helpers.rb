module Whatsapp::IncomingMessageServiceHelpers
  def download_attachment_file(attachment_payload)
    Down.download(inbox.channel.media_url(attachment_payload[:id]), headers: inbox.channel.api_headers)
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: conversation_additional_attributes
    }
  end

  def processed_params
    @processed_params ||= params
  end

  def account
    @account ||= inbox.account
  end

  def message_type
    messages_data.first[:type]
  end

  def message_content(message)
    # TODO: map interactive messages back to button messages in chatwoot
    message.dig(:text, :body) ||
      message.dig(:button, :text) ||
      message.dig(:interactive, :button_reply, :title) ||
      message.dig(:interactive, :list_reply, :title) ||
      message.dig(:name, :formatted_name)
  end

  def file_content_type(file_type)
    return :image if %w[image sticker].include?(file_type)
    return :audio if %w[audio voice].include?(file_type)
    return :video if ['video'].include?(file_type)
    return :location if ['location'].include?(file_type)
    return :contact if ['contacts'].include?(file_type)

    :file
  end

  def unprocessable_message_type?(message_type)
    %w[reaction ephemeral unsupported request_welcome].include?(message_type)
  end

  def processed_waid(waid)
    Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(waid, :cloud)
  end

  def error_webhook_event?(message)
    message.key?('errors')
  end

  def log_error(message)
    Rails.logger.warn "Whatsapp Error: #{message['errors'][0]['title']} - contact: #{message['from']}"
  end

  def process_in_reply_to(message)
    @in_reply_to_external_id = message['context']&.[]('id')
  end

  def find_message_by_source_id(source_id)
    return unless source_id

    @message = Message.find_by(source_id: source_id)
  end

  def lock_message_source_id!
    return false if messages_data.blank?

    Whatsapp::MessageDedupLock.new(messages_data.first[:id]).acquire!
  end

  def conversation_additional_attributes
    {
      'source' => 'whatsapp',
      'whatsapp' => whatsapp_conversation_payload
    }
  end

  def merge_whatsapp_conversation_attributes(existing_attributes)
    existing_attributes = (existing_attributes || {}).deep_stringify_keys
    existing_whatsapp = existing_attributes['whatsapp'].is_a?(Hash) ? existing_attributes['whatsapp'].deep_stringify_keys : {}

    merged_attributes = existing_attributes.merge('source' => 'whatsapp')
    merged_attributes['whatsapp'] = build_whatsapp_attributes(existing_whatsapp)
    merged_attributes
  end

  private

  def whatsapp_conversation_payload
    build_whatsapp_attributes({})
  end

  def build_whatsapp_attributes(existing_whatsapp)
    tracking_attributes = existing_whatsapp.fetch('tracking', {}).deep_merge(whatsapp_tracking_attributes)

    whatsapp_attributes = {
      'provider' => inbox.channel.provider,
      'channel' => whatsapp_channel_attributes,
      'contact' => whatsapp_contact_attributes,
      'tracking' => tracking_attributes.presence,
      'referral' => existing_whatsapp['referral'].presence || whatsapp_message_referral.presence,
      'context' => existing_whatsapp['context'].presence || whatsapp_message_context.presence,
      'first_message' => existing_whatsapp['first_message'].presence || whatsapp_message_summary.presence,
      'last_message' => whatsapp_message_summary.presence
    }

    whatsapp_attributes.delete_if { |_key, value| value.blank? }
  end

  def whatsapp_channel_attributes
    metadata = processed_params.try(:[], :metadata).to_h.with_indifferent_access

    channel_attributes = {
      'phone_number' => inbox.channel.phone_number,
      'display_phone_number' => metadata[:display_phone_number],
      'phone_number_id' => metadata[:phone_number_id]
    }

    channel_attributes.delete_if { |_key, value| value.blank? }
  end

  def whatsapp_contact_attributes
    contact_params = @processed_params.try(:[], :contacts).try(:first).to_h.with_indifferent_access
    first_message = messages_data.first.to_h.with_indifferent_access

    contact_attributes = {
      'source_id' => @contact_inbox&.source_id,
      'wa_id' => contact_params[:wa_id] || first_message[:from] || first_message[:to],
      'profile_name' => contact_params.dig(:profile, :name),
      'phone_number' => @contact&.phone_number
    }

    contact_attributes.delete_if { |_key, value| value.blank? }
  end

  def whatsapp_tracking_attributes
    referral = whatsapp_message_referral
    return {} if referral.blank?

    tracking_attributes = {
      'ctwa_clid' => referral['ctwa_clid'],
      'ref' => referral['ref'],
      'source_id' => referral['source_id'],
      'source_type' => referral['source_type'],
      'source_url' => referral['source_url']
    }

    tracking_attributes.delete_if { |_key, value| value.blank? }
  end

  def whatsapp_message_summary
    message = messages_data.first.to_h.with_indifferent_access
    return {} if message.blank?

    message_summary = {
      'id' => message[:id]&.to_s,
      'from' => message[:from],
      'to' => message[:to],
      'type' => message[:type],
      'timestamp' => message[:timestamp]
    }

    message_summary.delete_if { |_key, value| value.blank? }
  end

  def whatsapp_message_referral
    sanitize_whatsapp_payload_hash(messages_data.first.to_h.with_indifferent_access[:referral])
  end

  def whatsapp_message_context
    sanitize_whatsapp_payload_hash(messages_data.first.to_h.with_indifferent_access[:context])
  end

  def sanitize_whatsapp_payload_hash(value)
    return {} unless value.is_a?(Hash)

    value.deep_stringify_keys.compact_blank
  end
end
