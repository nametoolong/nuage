# frozen_string_literal: true

class InitialStateSerializer < Blueprinter::Base
  field :meta do |object|
    instance_presenter = InstancePresenter.new

    store = {
      streaming_api_base_url: Rails.configuration.x.streaming_api_base_url,
      access_token: object[:token],
      locale: I18n.locale,
      domain: instance_presenter.domain,
      title: instance_presenter.title,
      admin: object[:admin]&.id&.to_s,
      search_enabled: Chewy.enabled?,
      repository: Mastodon::Version.repository,
      source_url: instance_presenter.source_url,
      version: instance_presenter.version,
      limited_federation_mode: Rails.configuration.x.whitelist_mode,
      mascot: instance_presenter.mascot&.file&.url,
      profile_directory: Setting.profile_directory,
      trends: Setting.trends,
      registrations_open: Setting.registrations_mode != 'none' && !Rails.configuration.x.single_user_mode,
      timeline_preview: Setting.timeline_preview,
      activity_api_enabled: Setting.activity_api_enabled,
      single_user_mode: Rails.configuration.x.single_user_mode,
      translation_enabled: TranslationService.configured?,
    }

    if object[:current_account]
      current_account = object[:current_account]
      user_settings = current_account.user.settings.get_multi(%w(
        unfollow_modal
        boost_modal
        delete_modal
        auto_play_gif
        display_media
        expand_spoilers
        reduce_motion
        disable_swiping
        advanced_layout
        use_blurhash
        use_pending_items
        trends
        crop_images
      )).symbolize_keys

      store.merge!(user_settings)

      store[:me] = current_account.id.to_s
      store[:trends] &&= Setting.trends
    else
      store[:auto_play_gif] = Setting.auto_play_gif
      store[:display_media] = Setting.display_media
      store[:reduce_motion] = Setting.reduce_motion
      store[:use_blurhash]  = Setting.use_blurhash
      store[:crop_images]   = Setting.crop_images
    end

    store[:disabled_account_id] = object[:disabled_account].id.to_s if object[:disabled_account]
    store[:moved_to_account_id] = object[:moved_to_account].id.to_s if object[:moved_to_account]

    if Rails.configuration.x.single_user_mode
      store[:owner] = object[:owner]&.id&.to_s
    end

    store
  end

  field :compose do |object|
    store = {}

    if object[:current_account]
      current_account = object[:current_account]
      store[:me]                = current_account.id.to_s
      store[:default_privacy]   = object[:visibility] || current_account.user.setting_default_privacy
      store[:default_sensitive] = current_account.user.setting_default_sensitive
      store[:default_language]  = current_account.user.preferred_posting_language
    end

    store[:text] = object[:text] if object[:text]

    store
  end

  RELEVANT_ACCOUNTS = %i(current_account admin owner disabled_account moved_to_account)

  field :accounts do |object|
    accounts = RELEVANT_ACCOUNTS.filter_map { |name| object[name] }

    ActiveRecord::Associations::Preloader.new.preload(accounts, [:account_stat, :user, { moved_to_account: [:account_stat, :user] }])

    accounts.each_with_object({}) do |acct, h|
      h[acct.id.to_s] = REST::AccountSerializer.render_as_json(acct)
    end
  end

  field :media_attachments do
    { accept_content_types: MediaAttachment.supported_file_extensions + MediaAttachment.supported_mime_types }
  end

  field :languages do
    LanguagesHelper::INITIAL_STATE_LOCALE_LIST
  end

  field :settings

  association :push_subscription, blueprint: REST::WebPushSubscriptionSerializer
  association :role, blueprint: REST::RoleSerializer
end
