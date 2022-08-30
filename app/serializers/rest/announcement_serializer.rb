# frozen_string_literal: true

class REST::AnnouncementSerializer < ActiveModel::Serializer
  include FormattingHelper

  attributes :id, :content, :starts_at, :ends_at, :all_day,
             :published_at, :updated_at

  attribute :read, if: :current_user?

  has_many :mentions
  has_many :statuses
  attribute :tags
  attribute :emojis
  has_many :reactions, serializer: REST::ReactionSerializer

  def current_user?
    !current_user.nil?
  end

  def id
    object.id.to_s
  end

  def read
    object.announcement_mutes.where(account: current_user.account).exists?
  end

  def content
    linkify(object.text)
  end

  def reactions
    object.reactions(current_user&.account)
  end

  class AccountSerializer < ActiveModel::Serializer
    attributes :id, :username, :url, :acct

    def id
      object.id.to_s
    end

    def url
      ActivityPub::TagManager.instance.url_for(object)
    end

    def acct
      object.pretty_acct
    end
  end

  class StatusSerializer < ActiveModel::Serializer
    attributes :id, :url

    def id
      object.id.to_s
    end

    def url
      ActivityPub::TagManager.instance.url_for(object)
    end
  end

  def emojis
    REST::CustomEmojiSerializer.render_as_json(object.emojis)
  end

  def tags
    object.tags.map do |tag|
      {name: tag.name, url: tag_url(tag)}
    end
  end
end
