# frozen_string_literal: true

# Предсоздать / повысить LDAP-пользователей до глобальных админов Пульса.
# Логин = sAMAccountName (часть почты до @). Пароль — только AD.
#
#   docker compose exec web bundle exec rails runner /app/custom/seed_covenant_admins.rb

puts "[covenant-admins] start"

ADMINS = [].freeze

if ADMINS.empty?
  puts "[covenant-admins] список пуст, локальный админ — admin/admin"
  exit 0
end

source = LdapAuthSource.find_by(name: "pmh")
raise "[covenant-admins] LdapAuthSource «pmh» not found — сначала подними web с LDAP env" unless source

ADMINS.each do |row|
  login = row[:login]
  mail = row[:mail]

  attrs = begin
    source.get_user_attributes(login)
  rescue StandardError => e
    Rails.logger.warn("[covenant-admins] LDAP lookup #{login}: #{e.class}: #{e.message}")
    nil
  end

  user = User.find_by(login:) || User.find_by("lower(mail) = ?", mail.downcase) || User.new(login:)
  user.login = login
  user.mail = mail
  user.firstname = attrs&.[](:firstname).presence || login
  user.lastname = attrs&.[](:lastname).presence || "AD"
  user.ldap_auth_source = source
  user.admin = true
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

  # Локальный пароль не используется (auth через LDAP), но OP иногда валидирует presence.
  if user.new_record? || user.password.blank?
    rnd = SecureRandom.hex(24)
    user.password = rnd
    user.password_confirmation = rnd
  end

  user.save!(validate: false)
  puts "[covenant-admins] #{user.login} <#{user.mail}> admin=#{user.admin?} ldap=#{user.ldap_auth_source&.name} id=#{user.id}"
end

puts "[covenant-admins] done"
