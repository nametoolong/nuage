# frozen_string_literal: true

class RemoveFromFollowersService < BaseService
  def call(source_account, target_accounts)
    source_account.passive_relationships.where(account_id: target_accounts).find_each do |follow|
      follow.destroy

      if source_account.local? && !follow.account.local? && follow.account.activitypub?
        create_notification(follow)
      end
    end
  end

  private

  def create_notification(follow)
    ActivityPub::DeliveryWorker.perform_async(build_json(follow), follow.target_account_id, follow.account.inbox_url)
  end

  def build_json(follow)
    Oj.dump(ActivityPub::Renderer.new(:reject_follow, follow).render)
  end
end
