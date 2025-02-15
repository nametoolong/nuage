# frozen_string_literal: true

class ActivityPub::MoveDistributionWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'push'

  def perform(migration_id)
    @migration = AccountMigration.find(migration_id)
    @account   = @migration.account

    ActivityPub::DeliveryWorker.push_bulk(inboxes) do |inbox_url|
      [signed_payload, @account.id, inbox_url]
    end

    ActivityPub::DeliveryWorker.push_bulk(Relay.enabled.pluck(:inbox_url)) do |inbox_url|
      [signed_payload, @account.id, inbox_url]
    end
  rescue ActiveRecord::RecordNotFound
    true
  end

  private

  def inboxes
    @inboxes ||= (@migration.account.followers.inboxes + @migration.account.blocked_by.inboxes).uniq
  end

  def signed_payload
    @signed_payload ||= Oj.dump(ActivityPub::Renderer.new(:move, @migration).render(signer: @account))
  end
end
