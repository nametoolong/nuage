# frozen_string_literal: true

class FollowingAccountsController < ApplicationController
  include AccountControllerConcern
  include SignatureVerification
  include WebAppControllerConcern

  before_action :require_account_signature!, if: -> { request.format == :json && authorized_fetch_mode? }
  before_action :set_cache_headers

  skip_around_action :set_locale, if: -> { request.format == :json }
  skip_before_action :require_functional!, unless: :whitelist_mode?

  def index
    respond_to do |format|
      format.html do
        expires_in 0, public: true unless user_signed_in?
      end

      format.json do
        if page_requested? && @account.hide_collections?
          forbidden
          next
        end

        expires_in(page_requested? ? 0 : 3.minutes, public: public_fetch_mode?)

        render json: ActivityPub::Renderer.new(:actor, collection_presenter).render, content_type: 'application/activity+json'
      end
    end
  end

  private

  def follows
    return @follows if defined?(@follows)

    scope = Follow.where(account: @account)
    scope = scope.where.not(target_account_id: current_account.excluded_from_timeline_account_ids) if user_signed_in?
    @follows = scope.recent.page(params[:page]).per(FOLLOW_PER_PAGE).preload(:target_account)
  end

  def page_requested?
    params[:page].present?
  end

  def page_url(page)
    account_following_index_url(@account, page: page) unless page.nil?
  end

  def next_page_url
    page_url(follows.next_page) if follows.respond_to?(:next_page)
  end

  def prev_page_url
    page_url(follows.prev_page) if follows.respond_to?(:prev_page)
  end

  def collection_presenter
    if @account.hide_collections?
      ActivityPub::CollectionPresenter.new(
        type: :unordered,
        size: @account.following_count
      )
    elsif page_requested?
      ActivityPub::CollectionPresenter.new(
        id: account_following_index_url(@account, page: params.fetch(:page, 1)),
        type: :ordered,
        size: @account.following_count,
        items: follows.map { |follow| ActivityPub::TagManager.instance.uri_for(follow.target_account) },
        part_of: account_following_index_url(@account),
        next: next_page_url,
        prev: prev_page_url
      )
    else
      ActivityPub::CollectionPresenter.new(
        id: account_following_index_url(@account),
        type: :ordered,
        size: @account.following_count,
        first: page_url(1)
      )
    end
  end
end
