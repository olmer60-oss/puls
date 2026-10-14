# frozen_string_literal: true

# Covenant: AD-поиск / upsert с кнопки «Пригласить».
class CovenantAdInviteController < ApplicationController
  no_authorization_required! :search, :create

  before_action :require_login
  before_action :find_invite_project
  before_action :authorize_ad_invite

  def search
    result = CovenantAdInvite.search(@project, params[:q])
    render json: {
      error: result[:error],
      people: result[:people] || []
    }
  end

  def create
    wp = find_invite_work_package
    result =
      if params[:login].present?
        CovenantAdInvite.invite!(@project, params[:login], work_package: wp)
      elsif params[:user_id].present? && wp
        CovenantAdInvite.assign_existing!(wp, params[:user_id])
      else
        { error: "Не указан пользователь." }
      end
    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
      return
    end

    render json: {
      error: nil,
      user_id: result[:user_id],
      login: result[:login],
      name: result[:name],
      mail: result[:mail],
      assigned: result[:assigned],
      message: result[:assigned] ? "«#{result[:name]}» назначен исполнителем." : "«#{result[:name]}» добавлен. Ставим в исполнители…"
    }
  end

  private

  def find_invite_project
    ident = params[:project_id].to_s
    @project = Project.visible(User.current).find(ident)
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Предприятие не найдено." }, status: :not_found
  end

  def find_invite_work_package
    id = params[:work_package_id].to_s
    return if id.blank?

    WorkPackage.visible(User.current).find_by(id:)
  end

  def authorize_ad_invite
    return if performed?
    return if User.current.admin?
    return if User.current.allowed_in_project?(:edit_work_packages, @project)
    return if User.current.allowed_in_project?(:manage_members, @project)

    render json: { error: "Недостаточно прав." }, status: :forbidden
  end
end
