# frozen_string_literal: true

class LinkCrawlWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 0

  def perform(status_id)
    FetchLinkCardService.new.call(Status.includes(:preview_cards).find(status_id))
  rescue ActiveRecord::RecordNotFound
    true
  end
end
