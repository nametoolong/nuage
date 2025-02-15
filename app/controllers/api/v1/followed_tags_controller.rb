# frozen_string_literal: true

class Api::V1::FollowedTagsController < Api::BaseController
  include BlueprintHelper

  TAGS_LIMIT = 100

  before_action -> { doorkeeper_authorize! :follow, :read, :'read:follows' }
  before_action :require_user!
  before_action :set_results

  after_action :insert_pagination_headers

  def index
    render json: render_blueprint_with_account(REST::TagSerializer, @results.map(&:tag), relationships: TagRelationshipsPresenter.new(@results.map(&:tag), current_user&.account_id))
  end

  private

  def set_results
    @results = TagFollow.where(account: current_account).joins(:tag).eager_load(:tag).to_a_paginated_by_id(
      limit_param(TAGS_LIMIT),
      params_slice(:max_id, :since_id, :min_id)
    )
  end

  def insert_pagination_headers
    set_pagination_headers(next_path, prev_path)
  end

  def next_path
    api_v1_followed_tags_url pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    api_v1_followed_tags_url pagination_params(since_id: pagination_since_id) unless @results.empty?
  end

  def pagination_max_id
    @results.last.id
  end

  def pagination_since_id
    @results.first.id
  end

  def records_continue?
    @results.size == limit_param(TAGS_LIMIT)
  end

  def pagination_params(core_params)
    params.slice(:limit).permit(:limit).merge(core_params)
  end
end
