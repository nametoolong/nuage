# frozen_string_literal: true

class Api::V2::InstancesController < Api::V1::InstancesController
  def show
    expires_in 3.minutes, public: true
    render_with_cache { REST::InstanceSerializer.render(InstancePresenter.new) }
  end
end
