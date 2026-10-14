# frozen_string_literal: true

# Covenant: папки завода = скрытые подпроекты.
class CovenantFoldersController < ApplicationController
  no_authorization_required! :index, :create, :update_ad_org

  rescue_from ActiveRecord::RecordNotFound, with: :redirect_no_enterprise

  before_action :require_login
  before_action :find_visible_covenant_project
  before_action :authorize_covenant_folders
  before_action :redirect_child_to_parent_folders, only: :index

  def index
    @folders = folder_scope
    @unfiled_count = @project.work_packages.count
    @can_create = can_create_folder?
    load_ad_org!
    render template: "covenant_folders/index", layout: "base"
  end

  def update_ad_org
    unless User.current.admin?
      flash[:error] = "Сменить предприятие может только администратор."
      redirect_to covenant_folders_path_for(@project)
      return
    end

    cf = ad_org_cf
    option = cf&.custom_options&.find_by(id: params[:ad_org_option_id])
    if cf.nil? || option.nil?
      flash[:error] = "Не выбрано предприятие."
      redirect_to covenant_folders_path_for(@project)
      return
    end

    previous = @project.custom_value_for(cf)&.value
    assign_ad_org!(@project, cf, option.id)
    cascaded = cascade_ad_org!(@project, cf, previous, option.id)

    flash[:notice] =
      "Предприятие: #{ad_org_public_label(option.value)}. Папок обновлено: #{cascaded}. " \
      "Кто видит предприятие — при следующем входе (по OU в AD)."
    redirect_to covenant_folders_path_for(@project)
  end

  def create
    unless can_create_folder?
      flash[:error] = "Недостаточно прав, чтобы создать папку."
      redirect_to covenant_folders_path_for(@project)
      return
    end

    name = params[:name].to_s.strip
    if name.blank?
      flash[:error] = "Укажите название папки."
      redirect_to covenant_folders_path_for(@project)
      return
    end

    call = Projects::CreateService.new(user: User.current).call(folder_create_params(name))
    folder = call.result

    if call.success?
      configure_folder!(folder)
      copy_parent_memberships!(folder)
      flash[:notice] = "Папка «#{folder.name}» создана."
      redirect_to project_work_packages_path(folder)
    else
      flash[:error] = call.message.presence || folder&.errors&.full_messages&.to_sentence.presence ||
                      "Не удалось создать папку."
      redirect_to covenant_folders_path_for(@project)
    end
  end

  private

  def find_visible_covenant_project
    @project = Project.visible(User.current).find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    redirect_no_enterprise
  end

  def authorize_covenant_folders
    return if performed?
    return if User.current.admin?
    return if User.current.allowed_in_project?(:view_work_packages, @project)

    redirect_no_enterprise
  end

  def redirect_no_enterprise(_exception = nil)
    return if performed?

    flash[:warning] = I18n.t(:notice_covenant_no_enterprises)
    redirect_to projects_path, status: :see_other
  end

  def redirect_child_to_parent_folders
    return if @project.parent_id.nil?

    redirect_to covenant_folders_path_for(@project), status: :see_other
  end

  def can_create_folder?
    user = User.current
    return true if user.admin?
    return true if user.allowed_in_project?(:add_subprojects, @project)
    return true if user.allowed_globally?(:add_project)

    false
  end

  def folder_scope
    @project.children.visible(User.current).active.order(:name)
  end

  def folder_create_params(name)
    attrs = {
      name:,
      identifier: unique_folder_identifier(name),
      parent_id: @project.id,
      workspace_type: "project",
      public: false
    }
    ad = parent_ad_org_value
    attrs[:custom_field_values] = { ad[:cf].id => ad[:value] } if ad
    attrs
  end

  def parent_ad_org_value
    cf = ad_org_cf
    return unless cf

    raw = @project.custom_value_for(cf)&.value
    return if raw.blank?

    { cf:, value: raw }
  end

  def ad_org_public_label(value)
    return value.to_s unless defined?(CovenantAd)

    CovenantAd.public_label(value)
  end

  def ad_org_cf
    return unless defined?(ProjectCustomField)

    name = defined?(CovenantAd) ? CovenantAd::CF_NAME : "Завод AD"
    ProjectCustomField.find_by(name:)
  end

  def load_ad_org!
    @ad_org_cf = ad_org_cf
    @ad_org_options = @ad_org_cf&.custom_options&.order(:position)&.to_a || []
    current = @project.custom_value_for(@ad_org_cf)&.value if @ad_org_cf
    @ad_org_option = @ad_org_options.find { |o| o.id.to_s == current.to_s || o.value.to_s == current.to_s }
    @ad_org_label = ad_org_public_label(@ad_org_option&.value).presence || "не задан"
    @can_edit_ad_org = User.current.admin? && @ad_org_cf.present?
  end

  def assign_ad_org!(project, cf, option_id)
    project.custom_field_values = { cf.id => option_id }
    project.save(validate: false)
  end

  def cascade_ad_org!(root, cf, previous, option_id)
    n = 0
    root.descendants.find_each do |child|
      raw = child.custom_value_for(cf)&.value
      next unless raw.blank? || raw.to_s == previous.to_s

      assign_ad_org!(child, cf, option_id)
      n += 1
    end
    n
  rescue StandardError => e
    Rails.logger.warn("[covenant-folders] cascade AD org failed: #{e.class}: #{e.message}")
    n
  end

  def unique_folder_identifier(name)
    slug = Project.suggest_identifier(name).to_s
    slug = "folder" if slug.blank? || slug.match?(/\A\d+\z/)
    base = "#{@project.identifier}-#{slug}".gsub(/-+/, "-")[0, 90]
    ident = base
    n = 2
    while Project.exists?(identifier: ident)
      ident = "#{base}-#{n}"
      n += 1
    end
    ident
  end

  def configure_folder!(folder)
    folder.enabled_module_names = %w[work_package_tracking activity]
    type = Type.find_by(name: "Запрос")
    folder.types = [type] if type
    if @project.respond_to?(:work_package_custom_fields)
      folder.work_package_custom_fields = @project.work_package_custom_fields
    end
    folder.save(validate: false)
  end

  def copy_parent_memberships!(folder)
    @project.members.includes(:principal, :roles).find_each do |src|
      next if src.principal.nil?

      member = Member.find_or_initialize_by(project: folder, principal: src.principal)
      member.roles = src.roles if member.roles.empty?
      member.save if member.changed? || member.new_record? || member.member_roles.empty?
    end
  rescue StandardError => e
    Rails.logger.warn("[covenant-folders] copy members failed: #{e.class}: #{e.message}")
  end
end
