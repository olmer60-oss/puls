# frozen_string_literal: true

# Covenant AD catalog. Локальная копия без адреса каталога.
# Used by seed (Project CF «Завод AD») and LDAP login membership overlay.
# Not an initializer — require from seed / zzz_covenant_ldap.rb.

module CovenantAd
  CF_NAME = "Завод AD"
  CF_IDENTIFIER = "ad_org"

  # Глобальные админы Пульса (логин sAMAccountName и/или mail). При LDAP-логине → admin=true,
  # membership-sync по заводу их не трогает.
  # Локальная копия: корпоративные учётки сюда не кладём.
  SUPER_ADMINS = %w[].freeze

  def self.super_admin?(user_or_login)
    keys = case user_or_login
           when User
             [user_or_login.login, user_or_login.mail]
           else
             [user_or_login]
           end
    keys = keys.compact.map { |v| v.to_s.downcase }
    SUPER_ADMINS.any? { |a| keys.include?(a.downcase) }
  end

  def self.promote_super_admin!(user)
    return user if user.nil? || user.admin?
    return user unless super_admin?(user)

    user.update!(admin: true)
    Rails.logger.info("[covenant-ldap] super-admin #{user.login}")
    user
  rescue StandardError => e
    Rails.logger.warn("[covenant-ldap] promote super-admin failed: #{e.class}: #{e.message}")
    user
  end

  # OU code (as in DN) → display name. Keys stored case-insensitively.
  COMPANY_MAPPING = {
    "COAL" => "Участок Коксовый",
    "BUT" => "Шахта Бутовская",
    "imh-vtm" => "ПМХ-Втормет",
    "KVT" => "КВОиТ",
    "kma" => "КМАруда",
    "KNPC" => "КНПЦ",
    "koks" => "ПАО КОКС",
    "metizy" => "Метизы Тула-Сталь",
    "PITS" => "ПМХ-Инфотех",
    "PLM" => "Полема",
    "PMH" => "УК ПМХ",
    "sort" => "ПРОМСОРТ",
    "tchm" => "Тулачермет",
    "TD" => "Торговый дом Тула-сталь",
    "ts" => "Промсорт-Тула",
    "tst" => "ТУЛЬСКАЯ СТАЛЬ",
    "tts" => "Тулатеплосеть",
    "vlm" => "Волмет-трейдинг",
    "yardhotel" => "Горный отдых"
  }.freeze

  # Canonical AD code → OpenProject project identifier + name
  ENTERPRISES = [
    { ad_code: "koks", identifier: "pao-koks", name: "ПАО «Кокс»", legacy: %w[ao-severstal] },
    { ad_code: "tchm", identifier: "ao-tulachermet", name: "АО «Тулачермет»", legacy: %w[pao-gazprom] },
    { ad_code: "kma", identifier: "ao-kmaruda", name: "АО «Комбинат КМАруда»", legacy: %w[ao-nlmk] },
    { ad_code: "COAL", identifier: "ooo-uchastok-koksovy", name: "ООО «Участок «Коксовый»", legacy: %w[pao-lukoil] },
    { ad_code: "BUT", identifier: "ooo-shakhta-butovskaia", name: "ООО \"Шахта \"Бутовская\"", legacy: [] },
    { ad_code: "imh-vtm", identifier: "ooo-pmh-vtormet", name: "ООО «ПМХ-Втормет»", legacy: %w[ao-rzd] },
    { ad_code: "PITS", identifier: "ooo-pmh-infotech", name: "ООО «ПМХ-ИНФОТЕХ»", legacy: %w[pao-sber] },
    { ad_code: "PMH", identifier: "ooo-uk-pmh", name: "ООО УК «ПМХ»", legacy: [] },
    { ad_code: "KVT", identifier: "ao-kvoit", name: "АО «КВОиТ»", legacy: [] },
    { ad_code: "KNPC", identifier: "ao-knpc", name: "АО «КНПЦ»", legacy: [] },
    { ad_code: "metizy", identifier: "ooo-metizy-tula-stal", name: "ООО «Метизы Тула-Сталь»", legacy: [] },
    { ad_code: "PLM", identifier: "ao-polema", name: "АО «Полема»", legacy: [] },
    { ad_code: "sort", identifier: "ao-promsort", name: "АО «ПРОМСОРТ»", legacy: [] },
    { ad_code: "TD", identifier: "ooo-td-tula-stal", name: "ООО «Торговый дом Тула-сталь»", legacy: [] },
    { ad_code: "ts", identifier: "ooo-promsort-tula", name: "ООО «Промсорт-Тула»", legacy: [] },
    { ad_code: "tst", identifier: "ao-tulskaya-stal", name: "АО «Тульская сталь»", legacy: [] },
    { ad_code: "tts", identifier: "ooo-tulateploset", name: "ООО «Тулатеплосеть»", legacy: [] },
    { ad_code: "vlm", identifier: "ooo-volmet-trading", name: "ООО «Волмет-трейдинг»", legacy: [] },
    { ad_code: "yardhotel", identifier: "ooo-gornyy-otdyh", name: "ООО «Горный отдых»", legacy: [] }
  ].freeze

  module_function

  def company_label(code)
    return nil if code.blank?

    COMPANY_MAPPING.each do |k, v|
      return v if k.casecmp?(code.to_s)
    end
    nil
  end

  def canonical_code(code)
    return nil if code.blank?

    COMPANY_MAPPING.each_key do |k|
      return k if k.casecmp?(code.to_s)
    end
    nil
  end

  # То, что видит пользователь. Код OU («PITS») в подписи не показываем.
  def public_label(value)
    text = value.to_s
    return text if text.blank?

    if (parts = text.split(" — ", 2)).size == 2 && canonical_code(parts[0])
      return parts[1]
    end

    text
  end

  # Из значения опции CF → канонический код OU. Понимает и «PITS — …», и голое название.
  def code_from_option_value(value)
    text = value.to_s
    return nil if text.blank?

    if (parts = text.split(" — ", 2)).size == 2
      return canonical_code(parts[0]) || parts[0]
    end

    COMPANY_MAPPING.each do |code, label|
      return code if label.casecmp?(text)
    end
    canonical_code(text)
  end

  # List option label shown in Project CF. Код OU нужен только внутри, в UI — название.
  def cf_option_label(code)
    canon = canonical_code(code) || code.to_s
    company_label(canon) || canon
  end

  def cf_option_labels
    ENTERPRISES.map { |e| cf_option_label(e[:ad_code]) }
  end

  # «PITS — ПМХ-Инфотех» → «ПМХ-Инфотех» на месте, id опции не меняется.
  def ensure_public_option_labels!(cf)
    return unless cf

    ENTERPRISES.each do |entry|
      code = canonical_code(entry[:ad_code]) || entry[:ad_code].to_s
      label = cf_option_label(code)
      existing = cf.custom_options.find { |opt| code_from_option_value(opt.value).to_s.casecmp?(code) }
      if existing
        existing.update_columns(value: label) if existing.value != label
      else
        cf.custom_options.create!(value: label)
      end
    end
  end

  # Parse AD org code from user DN (Security Hub logic).
  # Returns canonical key from COMPANY_MAPPING or nil.
  def org_code_from_dn(dn)
    return nil if dn.blank?

    dn = dn.to_s
    return nil unless dn.match?(/OU=Users/i)

    # COAL: OU=Users,OU=UK,OU=COAL,OU=IMH Group
    if dn.match?(/OU=Users,OU=UK,OU=COAL,OU=IMH Group/i)
      return canonical_code("COAL")
    end

    # Шахта Бутовская лежит внутри COAL, не рядом с заводами.
    if dn.match?(/OU=Users,OU=BUT,OU=COAL,OU=IMH Group/i)
      return canonical_code("BUT")
    end

    # Standard: OU=Users,OU=<CODE>,OU=IMH Group
    m = dn.match(/OU=Users,OU=([^,]+),OU=IMH Group/i)
    return nil unless m

    canonical_code(m[1])
  end

  def enterprise_for_code(code)
    canon = canonical_code(code)
    return nil unless canon

    ENTERPRISES.find { |e| e[:ad_code].casecmp?(canon) }
  end
end
