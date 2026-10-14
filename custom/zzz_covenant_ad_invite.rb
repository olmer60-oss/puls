# frozen_string_literal: true

# Covenant: AD-поиск только с кнопки «Пригласить».
# Обычный селектор исполнителей — только уже существующие юзеры Pulse.

require "net/ldap"

ad_catalog = [
  Rails.root.join("custom/covenant_ad.rb"),
  Pathname.new("/app/custom/covenant_ad.rb")
].find(&:exist?)
load ad_catalog.to_s if ad_catalog && !defined?(CovenantAd)

unless defined?(COVENANT_AD_INVITE_ROUTES_DRAWN)
  Object.const_set(:COVENANT_AD_INVITE_ROUTES_DRAWN, true)
  Rails.application.routes.append do
    get "covenant/ad_invite/search", to: "covenant_ad_invite#search"
    post "covenant/ad_invite", to: "covenant_ad_invite#create"
  end
end

module CovenantAdInvite
  class << self
    MIN_QUERY = 2
    LIMIT = 20

    def factory_for(project)
      return nil unless project

      root = project
      root = root.parent while root.parent
      root
    end

    def ad_code_for(project)
      factory = factory_for(project)
      return nil unless factory && defined?(CovenantAd)

      cf = ProjectCustomField.find_by(name: CovenantAd::CF_NAME)
      return nil unless cf

      raw = factory.custom_value_for(cf)&.value
      return nil if raw.blank?

      opt = cf.custom_options.find { |o| o.id.to_s == raw.to_s }
      return nil unless opt

      CovenantAd.code_from_option_value(opt.value)
    end

    def ou_base_for(code)
      source = ldap_source
      return nil unless source && code.present?

      root_base = source.base_dn.presence
      return nil if root_base.blank?
      if code.to_s.casecmp?("COAL")
        "OU=Users,OU=UK,OU=COAL,#{root_base}"
      elsif code.to_s.casecmp?("BUT")
        "OU=Users,OU=BUT,OU=COAL,#{root_base}"
      else
        "OU=Users,OU=#{code},#{root_base}"
      end
    end

    def ldap_source
      return unless defined?(LdapAuthSource)

      LdapAuthSource.find_by(name: "pmh")
    end

    def search(project, query)
      q = query.to_s.strip
      return { error: "Введите минимум #{MIN_QUERY} символа.", people: [] } if q.length < MIN_QUERY

      code = ad_code_for(project)
      return { error: "У предприятия не задан завод AD.", people: [] } if code.blank?

      source = ldap_source
      return { error: "LDAP не настроен.", people: [] } unless source

      base = ou_base_for(code)
      esc = Net::LDAP::Filter.escape(q)
      name_filter = %w[sAMAccountName mail displayName cn sn givenName].map do |attr|
        Net::LDAP::Filter.eq(attr, "*#{esc}*")
      end.reduce(:|)
      filter = source.default_filter & name_filter

      people = []
      source.with_connection do |ldap|
        ldap.search(
          base:,
          filter:,
          size: LIMIT,
          attributes: source.search_attributes + %w[displayName distinguishedName]
        ) do |entry|
          row = person_from_entry(source, entry, code)
          people << row if row
          break if people.size >= LIMIT
        end
      end

      { error: nil, people:, ad_code: code }
    rescue StandardError => e
      Rails.logger.warn("[covenant-ad-invite] search failed: #{e.class}: #{e.message}")
      { error: "Каталог недоступен. Попробуйте позже.", people: [] }
    end

    def invite!(project, login, work_package: nil)
      login = login.to_s.strip
      return { error: "Не указан логин." } if login.blank?

      code = ad_code_for(project)
      return { error: "У предприятия не задан завод AD." } if code.blank?

      source = ldap_source
      return { error: "LDAP не настроен." } unless source

      attrs = source.get_user_attributes(login)
      dn = attrs&.[](:dn).to_s
      return { error: "В AD нет такого пользователя." } if attrs.blank? || dn.blank?

      person_code = CovenantAd.org_code_from_dn(dn)
      unless person_code&.casecmp?(code)
        return { error: "Этот человек из другого предприятия." }
      end

      mail = attrs[:mail].to_s.strip
      return { error: "В AD нет почты — пригласить нельзя." } unless mail.include?("@")

      user = upsert_user!(source, attrs, login, mail)
      add_membership!(user, project)
      add_membership!(user, work_package.project) if work_package
      assigned = work_package ? assign_executor!(work_package, user) : { assigned: false }

      {
        error: nil,
        user:,
        user_id: user.id,
        mail: user.mail,
        name: user.name,
        login: user.login,
        assigned: assigned[:assigned] == true
      }
    rescue StandardError => e
      Rails.logger.warn("[covenant-ad-invite] invite failed: #{e.class}: #{e.message}")
      { error: "Не удалось пригласить: #{e.message}" }
    end

    def assign_existing!(work_package, user_id)
      user = User.find_by(id: user_id.to_i)
      return { error: "Пользователь не найден." } unless user && work_package

      add_membership!(user, work_package.project)
      assigned = assign_executor!(work_package, user)
      {
        error: assigned[:error],
        user_id: user.id,
        login: user.login,
        name: user.name,
        mail: user.mail,
        assigned: assigned[:assigned] == true
      }
    end

    private

    def person_from_entry(source, entry, expected_code)
      mapped = source.get_user_attributes_from_ldap_entry(entry)
      login = mapped[:login].to_s.strip
      return nil if login.blank?

      dn = mapped[:dn].to_s
      person_code = CovenantAd.org_code_from_dn(dn)
      return nil unless person_code&.casecmp?(expected_code)

      mail = mapped[:mail].to_s.strip
      name = [mapped[:firstname], mapped[:lastname]].compact.join(" ").strip
      name = LdapAuthSource.get_attr(entry, "displayName").to_s.strip if name.blank?
      name = login if name.blank?

      { login:, mail:, name: }
    end

    def upsert_user!(source, attrs, login, mail)
      user = User.find_by(login:) ||
             User.find_by("lower(mail) = ?", mail.downcase) ||
             User.new(login:)
      user.login = login
      user.mail = mail
      user.firstname = attrs[:firstname].presence || login
      user.lastname = attrs[:lastname].presence || "AD"
      user.ldap_auth_source = source
      if user.respond_to?(:status=)
        status_active = if defined?(Principal) && Principal.respond_to?(:statuses)
                          Principal.statuses[:active]
                        elsif User.respond_to?(:statuses)
                          User.statuses[:active]
                        else
                          1
                        end
        user.status = status_active
      end
      user.language = "ru" if user.respond_to?(:language=)
      if user.new_record? || user.password.blank?
        rnd = SecureRandom.hex(24)
        user.password = rnd
        user.password_confirmation = rnd
      end
      user.save!(validate: false)
      CovenantAd.promote_super_admin!(user) if defined?(CovenantAd)
      user
    end

    def add_membership!(user, project)
      return if user.admin? || project.nil?

      if defined?(CovenantLdapMembership)
        CovenantLdapMembership.ensure_plant_membership!(user, project)
        return
      end

      role = ProjectRole.find_by(name: "Участник") || ProjectRole.givable.order(:id).first
      return unless role

      root = project
      root = root.parent while root.parent
      [root, project].uniq.each do |target|
        member = Member.find_or_initialize_by(project: target, principal: user)
        member.roles = [role] if member.roles.empty?
        member.save if member.changed? || member.new_record? || member.member_roles.empty?
      end
    end

    def assign_executor!(work_package, user)
      return { assigned: false } unless work_package && user
      return { assigned: false, error: "Нет поля Исполнители." } unless defined?(CovenantAssignees)

      cf = CovenantAssignees.custom_field
      return { assigned: false, error: "Нет поля Исполнители." } unless cf

      previous = CovenantAssignees.user_ids_for(work_package)
      return { assigned: true, already: true } if previous.include?(user.id)

      ids = (previous + [user.id]).uniq
      wp = work_package.reload
      if defined?(WorkPackages::UpdateService)
        call = WorkPackages::UpdateService
               .new(user: User.current, model: wp)
               .call(custom_field_values: { cf.id => ids.map(&:to_s) })
        if call.success?
          Rails.logger.info("[covenant-ad-invite] assigned #{user.login} → wp=#{wp.id}")
          return { assigned: true }
        end
        Rails.logger.warn("[covenant-ad-invite] UpdateService: #{call.message}")
      end

      wp.custom_field_values = { cf.id => ids.map(&:to_s) }
      CovenantAssignees.sync_assigned_to!(wp)
      wp.save(validate: false)
      Rails.logger.info("[covenant-ad-invite] assigned #{user.login} → wp=#{wp.id} (direct)")
      { assigned: true }
    rescue StandardError => e
      Rails.logger.warn("[covenant-ad-invite] assign failed: #{e.class}: #{e.message}")
      { assigned: false, error: e.message }
    end
  end
end

Rails.logger.info("[covenant-ad-invite] routes /covenant/ad_invite")
