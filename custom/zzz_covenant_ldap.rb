# frozen_string_literal: true

# Covenant: LDAP — on login assign Member to own plant by OU. Host пустой, каталог не подключается.
# No full user sync. Requires OPENPROJECT_SEED_LDAP_PMH_* (or COVENANT_LDAP_*) env.

ad_catalog = [
  Rails.root.join("custom/covenant_ad.rb"),
  Pathname.new("/app/custom/covenant_ad.rb")
].find(&:exist?)
load ad_catalog.to_s if ad_catalog && !defined?(CovenantAd)

module CovenantLdapMembership
  module_function

  def ad_org_cf
    @ad_org_cf ||= ProjectCustomField.find_by(name: CovenantAd::CF_NAME)
  end

  def member_role
    @member_role ||= ProjectRole.find_by(name: "Участник") ||
                     ProjectRole.find_by(name: "Member") ||
                     ProjectRole.givable.order(:id).first
  end

  def option_for_code(code)
    cf = ad_org_cf
    return nil unless cf

    canon = CovenantAd.canonical_code(code) || code.to_s
    cf.custom_options.find { |o| CovenantAd.code_from_option_value(o.value).to_s.casecmp?(canon) }
  end

  def find_project_for_code(code)
    find_roots_for_code(code).first
  end

  # Несколько корней с одним «Завод AD» (напр. seed ooo-pmh-infotech + тестовый test) — все в зоне завода.
  def find_roots_for_code(code)
    cf = ad_org_cf
    opt = option_for_code(code)
    return [] unless cf && opt

    ids = CustomValue.where(
      custom_field_id: cf.id,
      customized_type: "Project",
      value: opt.id.to_s
    ).pluck(:customized_id)

    Project.active.where(id: ids, parent_id: nil).order(:id).to_a
  end

  def ad_code_for_root(root)
    cf = ad_org_cf
    return nil unless cf && root

    raw = root.custom_value_for(cf)&.value
    return nil if raw.blank?

    opt = cf.custom_options.find { |o| o.id.to_s == raw.to_s }
    return nil unless opt

    CovenantAd.code_from_option_value(opt.value)
  end

  def same_plant_ad_code?(a, b)
    return false if a.blank? || b.blank?

    ca = CovenantAd.canonical_code(a) || a.to_s
    cb = CovenantAd.canonical_code(b) || b.to_s
    ca.casecmp?(cb)
  end

  def projects_with_ad_org
    cf = ad_org_cf
    return Project.none unless cf

    ids = CustomValue.where(custom_field_id: cf.id, customized_type: "Project")
                     .where.not(value: [nil, ""])
                     .pluck(:customized_id)
    Project.where(id: ids)
  end

  def enterprise_root_for(project)
    return nil unless project

    root = project
    root = root.parent while root.parent
    root
  end

  def enterprise_tree_ids(root)
    return [] unless root

    ids = [root.id]
    lft = root.lft.to_i
    rgt = root.rgt.to_i
    if root.lft.present? && root.rgt.present? && lft.positive? && rgt >= lft
      ids.concat(Project.where(lft: lft..rgt).pluck(:id))
    end

    # Запасной путь, если nested set битый или не совпадает с .active
    frontier = [root.id]
    loop do
      child_ids = Project.where(parent_id: frontier).pluck(:id)
      child_ids -= ids
      break if child_ids.empty?

      ids.concat(child_ids)
      frontier = child_ids
    end

    ids.uniq
  end

  def ad_enterprise_root?(project)
    return false unless project&.parent_id.nil?

    cf = ad_org_cf
    return false unless cf

    project.custom_value_for(cf)&.value.present?
  end

  def grant_member_on_projects!(user, project_ids, role)
    Array(project_ids).uniq.each do |pid|
      proj = Project.find_by(id: pid)
      next unless proj

      member = Member.find_or_initialize_by(project: proj, principal: user)
      member.roles = [role]
      member.save!
    end
  end

  # Все корни с тем же «Завод AD» + папки; membership на чужих заводах снять.
  def sync_plant_by_code!(user, code)
    return if user.nil? || user.admin?

    role = member_role
    raise "Member role not found" if role.nil?

    roots = find_roots_for_code(code)
    if roots.empty?
      Rails.logger.warn("[covenant-ldap] no project roots for AD code=#{code} user=#{user.login}")
      return []
    end

    target_ids = roots.each_with_object([]) do |root, acc|
      acc.concat(enterprise_tree_ids(root))
    end.uniq.to_set

    if target_ids.empty?
      Rails.logger.warn("[covenant-ldap] #{user.login}: empty trees for AD code=#{code}")
      return roots
    end

    Member.where(principal: user).includes(:project).find_each do |member|
      proj = member.project
      next unless proj&.active?
      next if target_ids.include?(proj.id)

      other_root = enterprise_root_for(proj)
      next unless other_root && ad_enterprise_root?(other_root)

      other_code = ad_code_for_root(other_root)
      next if same_plant_ad_code?(other_code, code)

      member.destroy
      Rails.logger.info("[covenant-ldap] removed #{user.login} from #{proj.identifier}")
    end

    grant_member_on_projects!(user, target_ids.to_a, role)
    roots
  end

  def ensure_plant_membership!(user, project)
    return if user.nil? || user.admin?
    return unless project

    root = enterprise_root_for(project)
    return unless root && ad_enterprise_root?(root)

    code = ad_code_for_root(root)
    return unless code

    sync_plant_by_code!(user, code)
    root
  end

  def sync!(user, dn:)
    return if user.nil? || user.admin?

    code = CovenantAd.org_code_from_dn(dn)
    unless code
      Rails.logger.warn("[covenant-ldap] no AD org in DN for #{user.login}: #{dn}")
      return
    end

    roots = sync_plant_by_code!(user, code)
    return if roots.blank?

    tree_n = roots.sum { |r| enterprise_tree_ids(r).size }
    ids = roots.map(&:identifier).join(", ")
    Rails.logger.info(
      "[covenant-ldap] #{user.login} → Member of #{ids} (#{tree_n} projects, #{code})"
    )
    roots.first
  end

  def sync_for_login!(user, login, auth_source)
    return unless user && auth_source.is_a?(LdapAuthSource)

    CovenantAd.promote_super_admin!(user)

    attrs = auth_source.get_user_attributes(login)
    dn = attrs&.[](:dn)
    unless dn
      Rails.logger.warn("[covenant-ldap] DN not found for #{login}")
      return
    end

    sync!(user, dn:)
  end
end

def covenant_ensure_ldap_auth_source!
  return unless defined?(LdapAuthSource)

  host = ENV["OPENPROJECT_SEED_LDAP_PMH_HOST"].presence || ENV["COVENANT_LDAP_HOST"]
  return unless host.present?

  bind_user = ENV["OPENPROJECT_SEED_LDAP_PMH_BINDUSER"].presence ||
              ENV["COVENANT_LDAP_BIND_DN"].presence
  bind_pass = ENV["OPENPROJECT_SEED_LDAP_PMH_BINDPASSWORD"].presence ||
              ENV["COVENANT_LDAP_BIND_PASSWORD"]
  base_dn = ENV["OPENPROJECT_SEED_LDAP_PMH_BASEDN"].presence ||
            ENV["COVENANT_LDAP_BASE_DN"].presence
  port = (ENV["OPENPROJECT_SEED_LDAP_PMH_PORT"].presence || ENV["COVENANT_LDAP_PORT"] || "636").to_i
  filter = ENV["OPENPROJECT_SEED_LDAP_PMH_FILTER"].presence || "(objectClass=person)"
  tls_verify = ActiveModel::Type::Boolean.new.cast(
    ENV.fetch("OPENPROJECT_SEED_LDAP_PMH_TLS__VERIFY", ENV.fetch("COVENANT_LDAP_TLS_VERIFY", "false"))
  )

  src = LdapAuthSource.find_or_initialize_by(name: "pmh")
  src.host = host
  src.port = port
  src.tls_mode = :simple_tls
  src.verify_peer = tls_verify
  src.account = bind_user
  src.account_password = bind_pass if bind_pass.present?
  src.base_dn = base_dn
  src.filter_string = filter
  src.onthefly_register = true
  src.attr_login = ENV.fetch("OPENPROJECT_SEED_LDAP_PMH_LOGIN__MAPPING", "sAMAccountName")
  src.attr_firstname = ENV.fetch("OPENPROJECT_SEED_LDAP_PMH_FIRSTNAME__MAPPING", "givenName")
  src.attr_lastname = ENV.fetch("OPENPROJECT_SEED_LDAP_PMH_LASTNAME__MAPPING", "sn")
  src.attr_mail = ENV.fetch("OPENPROJECT_SEED_LDAP_PMH_MAIL__MAPPING", "mail")
  src.save!
  Rails.logger.info("[covenant-ldap] LdapAuthSource «pmh» → #{host}:#{port} base=#{base_dn}")
  src
rescue StandardError => e
  Rails.logger.warn("[covenant-ldap] ensure auth source failed: #{e.class}: #{e.message}")
  nil
end

def covenant_patch_ldap_authenticate!
  return unless defined?(LdapAuthSource)
  return if defined?(CovenantLdapAuthPatch) && LdapAuthSource.ancestors.include?(CovenantLdapAuthPatch)

  unless defined?(CovenantLdapAuthPatch)
    Object.const_set(:CovenantLdapAuthPatch, Module.new do
      def authenticate(login, password)
        user = super
        if user
          begin
            CovenantLdapMembership.sync_for_login!(user, login, self)
          rescue StandardError => e
            Rails.logger.warn("[covenant-ldap] post-auth sync failed: #{e.class}: #{e.message}")
          end
        end
        user
      end
    end)
  end

  LdapAuthSource.prepend(CovenantLdapAuthPatch)
  Rails.logger.info("[covenant-ldap] LdapAuthSource#authenticate → plant membership")
rescue StandardError => e
  Rails.logger.warn("[covenant-ldap] authenticate patch failed: #{e.class}: #{e.message}")
end

def covenant_user_landing_path_for(user)
  if user&.logged? && defined?(Project)
    allowed = Project.allowed_to(user, :view_work_packages).active
    project = allowed.where(parent_id: nil).order(:id).first || allowed.order(:id).first
    return covenant_folders_path_for(project) if project
  end

  "/projects"
rescue StandardError
  "/projects"
end

def covenant_no_enterprises?(user)
  return false unless user&.logged?
  return false if user.admin?
  return false unless defined?(Project)

  !Project.allowed_to(user, :view_work_packages).active.exists?
rescue StandardError
  false
end

def covenant_patch_redirect_after_login!
  return unless defined?(Accounts::RedirectAfterLogin)
  return if defined?(CovenantRedirectAfterLogin) &&
            Accounts::RedirectAfterLogin.ancestors.include?(CovenantRedirectAfterLogin)

  unless defined?(CovenantRedirectAfterLogin)
    Object.const_set(:CovenantRedirectAfterLogin, Module.new do
      def default_redirect
        flash[:warning] = I18n.t(:notice_covenant_no_enterprises) if covenant_no_enterprises?(User.current)
        redirect_back_or_default(covenant_user_landing_path_for(User.current))
      end

      def first_login_redirect
        flash[:warning] = I18n.t(:notice_covenant_no_enterprises) if covenant_no_enterprises?(User.current)
        redirect_back_or_default(covenant_user_landing_path_for(User.current))
      end
    end)
  end

  Accounts::RedirectAfterLogin.prepend(CovenantRedirectAfterLogin)
  Rails.logger.info("[covenant-ldap] after_login → user enterprise or /projects")
rescue StandardError => e
  Rails.logger.warn("[covenant-ldap] redirect patch failed: #{e.class}: #{e.message}")
end

def covenant_public_ad_option_labels!
  return unless defined?(ProjectCustomField) && defined?(CovenantAd)

  cf = ProjectCustomField.find_by(name: CovenantAd::CF_NAME)
  return unless cf

  CovenantAd.ensure_public_option_labels!(cf)
  Rails.logger.info("[covenant-ldap] AD plant options shown without OU code")
rescue StandardError => e
  Rails.logger.warn("[covenant-ldap] public AD labels failed: #{e.class}: #{e.message}")
end

Rails.application.config.after_initialize do
  covenant_ensure_ldap_auth_source!
  covenant_patch_ldap_authenticate!
  covenant_patch_redirect_after_login!
  covenant_public_ad_option_labels!
end
