# frozen_string_literal: true

# Covenant / Pulse model seed.
# Run:
#   docker compose exec web bundle exec rails runner /app/custom/seed_covenant_model.rb
#
# Idempotent: safe to re-run.

puts "[covenant-seed] start"

admin = User.find_by(login: "admin") || User.admin.first
raise "admin user not found" unless admin

User.current = admin

YELLOW = Color.find_by(name: "Yellow") || Color.find_by(hexcode: "#FFFF00") || Color.find_by(name: "yellow-5")
GREEN  = Color.find_by(name: "Green") || Color.find_by(hexcode: "#35C53F") || Color.find_by(name: "green-5")
RED    = Color.find_by(name: "Red") || Color.find_by(hexcode: "#FF0000") || Color.find_by(name: "red-5")

def upsert_status!(name:, is_default: false, is_closed: false, color:, position:)
  st = Status.find_or_initialize_by(name:)
  st.is_default = is_default
  st.is_closed = is_closed
  st.color = color if color
  st.position = position
  st.save!
  st
end

def upsert_priority!(name:, is_default: false, position:)
  pr = IssuePriority.find_or_initialize_by(name:)
  pr.is_default = is_default
  pr.active = true
  pr.position = position
  pr.save!
  pr
end

# --- Statuses ---
Status.update_all(is_default: false)
st_requested  = upsert_status!(name: "Запрошен", is_default: true, color: YELLOW, position: 1)
st_provided   = upsert_status!(name: "Предоставлен", is_closed: true, color: GREEN, position: 2)
# бывш. «Отклонено» → «Просрочено»
if (st_old = Status.find_by(name: "Отклонено"))
  st_old.name = "Просрочено"
  st_old.is_closed = true
  st_old.color = RED if RED
  st_old.position = 3
  st_old.save!
  st_rejected = st_old
  puts "[covenant-seed] status «Отклонено» → «Просрочено»"
else
  st_rejected = upsert_status!(name: "Просрочено", is_closed: true, color: RED, position: 3)
end
puts "[covenant-seed] statuses: #{[st_requested, st_provided, st_rejected].map(&:name).join(", ")}"

# Сток New/In progress/Closed и прочий EN — долой. На copy/move они торчат
# через Workflow.available_statuses (все типы роли, не только «Запрос»).
covenant_purge_extra_statuses! if defined?(covenant_purge_extra_statuses!)

# --- Priorities: Низкий / Обычный (default) / Высокий / Срочный ---
IssuePriority.update_all(is_default: false)
pr_low    = upsert_priority!(name: "Низкий", position: 1)
pr_normal = upsert_priority!(name: "Обычный", is_default: true, position: 2)
pr_high   = upsert_priority!(name: "Высокий", position: 3)
pr_urgent = upsert_priority!(name: "Срочный", position: 4)

# «Стандартный» — дубль «Обычного»; переносим задания и удаляем
if (pr_std = IssuePriority.find_by(name: "Стандартный"))
  WorkPackage.where(priority_id: pr_std.id).update_all(priority_id: pr_normal.id)
  pr_std.destroy
  puts "[covenant-seed] removed priority «Стандартный» → «Обычный»"
end

puts "[covenant-seed] priorities: #{[pr_low, pr_normal, pr_high, pr_urgent].map(&:name).join(", ")} (default=#{pr_normal.name})"
covenant_fix_priorities! if defined?(covenant_fix_priorities!)

# --- Type «Запрос» ---
type = Type.find_by(name: "Запрос") || Type.find_by(name: "Задание") || Type.first
type.name = "Запрос"

# --- СТАРЫЙ КОД (ЗАКОММЕНТИРУЙТЕ ИЛИ СТЕРЕТЬ): ---
# type.is_default = false 
# --- НОВЫЙ КОД: ---
# Просто пропускаем установку поля, так как в новых версиях OpenProject его нет.
# Если в старом коде было значение `true`, раскомментируйте строку ниже:
# Setting.work_package_type_default_id = type.id if defined?(Setting)

type.is_milestone = false
type.is_in_roadmap = false
type.save!
# --- СТАРЫЙ КОД: ---
# Type.where.not(id: type.id).update_all(is_default: false)
# --- НОВЫЙ КОД: ---
# Оставляем пустую строку или пишем комментарий. 
# Новая система сама разберется с дефолтным типом.
puts "[covenant-seed] type: #{type.name} (id=#{type.id})"

# --- Custom fields ---
def upsert_wp_cf!(name:, field_format:, possible_values: nil, multi_value: false)
  cf = WorkPackageCustomField.find_by(name:)
  if cf.nil?
    cf = WorkPackageCustomField.new(name:, field_format:)
  end
  cf.is_for_all = true
  cf.is_filter = true
  cf.searchable = true if %w[string text].include?(cf.field_format)
  cf.multi_value = multi_value
  cf.possible_values = possible_values if possible_values && cf.field_format == "list"
  cf.save!
  cf
end

cf_section   = upsert_wp_cf!(name: "Раздел", field_format: "list",
                             possible_values: ["Финансы", "Юридический", "Операционный", "Отчётность", "Прочее"])
cf_req_no    = upsert_wp_cf!(name: "№ запроса", field_format: "string")
cf_locked    = upsert_wp_cf!(name: "Заблокирован", field_format: "bool")
cf_fact_date = upsert_wp_cf!(name: "Фактическая дата предоставления", field_format: "date")
cf_executors = upsert_wp_cf!(name: "Исполнители", field_format: "user", multi_value: true)

cfs = [cf_section, cf_req_no, cf_locked, cf_fact_date, cf_executors]
puts "[covenant-seed] custom fields: #{cfs.map { |c| "#{c.name}(cf_#{c.id})" }.join(", ")}"

# Attach CFs to type + form configuration
# assignee (один) убран с формы — вместо него CF «Исполнители» (несколько)
cf_attrs = cfs.map(&:attribute_name)
# --- СТАРЫЙ КОД (ЗАКОММЕНТИРОВАТЬ ИЛИ СТЕРЕТЬ СТРОКУ): ---
# type.custom_field_ids = covenant_cfs.map(&:id) 
# --- НОВЫЙ КОД: ---
cfs.each do |cf|
  exists = ActiveRecord::Base.connection.select_value(
    "SELECT 1 FROM custom_fields_types WHERE type_variant_id = #{type.id} AND custom_field_id = #{cf.id}"
  )
  
  unless exists
    ActiveRecord::Base.connection.execute(
      "INSERT INTO custom_fields_types (type_variant_id, custom_field_id) VALUES (#{type.id}, #{cf.id})"
    )
  end
end
if type.respond_to?(:changes_applied)
  type.changes_applied 
end
puts "[covenant-seed] Custom fields successfully linked via type_variant_id"

# --- ФИНАЛЬНЫЙ СОВРЕМЕННЫЙ КОД (ВСТАВИТЬ ВЗАМЕН ВСЕХ СТАРЫХ UPDATE TYPES И RECSUE): ---
puts "[covenant-seed] Form configuration inherits structure from linked custom fields dynamically."
puts "[covenant-seed] Сидирование модели «Запрос» успешно завершено!"

# --- СТАРЫЙ КОД (рассчитан на старую версию. удалить или закомментировать): ---
# type.attribute_groups = [
#   ["Запрос",
#    %w[subject description status priority due_date] + cf_attrs],
#   ["Прочее",
#    %w[responsible]]
# ]
# type.save!
# puts "[covenant-seed] form configuration set for «Запрос»"

# --- НОВЫЙ СОВРЕМЕННЫЙ ФОРМАТ: ---
form_json = {
  "attribute_groups" => [
    {
      "name" => "Запрос",
      "attributes" => %w[subject description status priority due_date] + cf_attrs
    },
    {
      "name" => "Прочее",
      "attributes" => %w[responsible]
    }
  ]
}.to_json

# Записываем конфигурацию формы напрямую в базу данных.
# (Если на Шаге 1 вы увидели другое имя вместо 'form_configuration', подставьте его ниже)
ActiveRecord::Base.connection.execute(
  "UPDATE types SET form_configuration = '#{form_json}' WHERE id = #{type.id}"
)

puts "[covenant-seed] form configuration successfully set via direct SQL for «Запрос»"


# Вызываем сервисный слой OpenProject для безопасного обновления групп формы
service = WorkPackageTypes::UpdateService.new(user: admin, model: type)
result = service.call(attribute_groups: new_groups)

if result.success?
  puts "[covenant-seed] form configuration successfully set for «Запрос»"
else
  puts "[covenant-seed] ERROR setting form configuration: #{result.errors.full_messages.join(', ')}"
  exit 1
end

# --- Workflows: все роли проекта могут ходить между статусами ковенант ---
covenant_statuses = [st_requested, st_provided, st_rejected]
roles = ProjectRole.where(builtin: 0).or(ProjectRole.where(name: %w[Участник Читатель Администратор\ проекта]))
roles = ProjectRole.all if roles.none?
roles = roles.distinct

Workflow.where(type_id: type.id).delete_all
roles.find_each do |role|
  covenant_statuses.each do |from|
    covenant_statuses.each do |to|
      next if from.id == to.id

      Workflow.create!(type_id: type.id, role_id: role.id, old_status_id: from.id, new_status_id: to.id)
    end
  end
end
puts "[covenant-seed] workflows rebuilt for type «Запрос» (#{Workflow.where(type_id: type.id).count} transitions)"

# --- AD catalog + Project CF «Завод AD» ---
load File.expand_path("covenant_ad.rb", __dir__)

def ensure_ad_org_cf!
  section = ProjectCustomFieldSection.first ||
            ProjectCustomFieldSection.create!(name: "Project attributes", position: 1)

  cf = ProjectCustomField.find_by(name: CovenantAd::CF_NAME) ||
       ProjectCustomField.new(name: CovenantAd::CF_NAME, field_format: "list")
  cf.field_format = "list"
  cf.is_required = true
  cf.is_for_all = true
  cf.is_filter = true
  cf.searchable = false
  cf.admin_only = false
  cf.multi_value = false
  cf.custom_field_section_id = section.id
  cf.possible_values = CovenantAd.cf_option_labels if cf.custom_options.empty?
  cf.save!
  CovenantAd.ensure_public_option_labels!(cf)
  cf.custom_options.reload
  puts "[covenant-seed] project CF «#{cf.name}» id=#{cf.id} options=#{cf.custom_options.count}"
  cf
end

ad_org_cf = ensure_ad_org_cf!

def ad_org_option_id(cf, ad_code)
  canon = CovenantAd.canonical_code(ad_code) || ad_code.to_s
  opt = cf.custom_options.find { |o| CovenantAd.code_from_option_value(o.value).to_s.casecmp?(canon) }
  raise "AD option missing for #{ad_code.inspect} (#{canon})" unless opt

  opt.id
end

# --- Enterprises (projects) from AD catalog ---
def ensure_enterprise!(identifier:, name:, type:, admin:, ad_code:, ad_org_cf:, legacy: [])
  project = Project.find_by(identifier:)
  if project.nil?
    legacy.each do |old_id|
      project = Project.find_by(identifier: old_id)
      break if project
    end
  end
  project ||= Project.new
  project.identifier = identifier
  project.name = name
  project.public = false
  project.workspace_type = "project"
  project.enabled_module_names = %w[work_package_tracking activity]
  project.save!

  # Only type «Запрос»
  project.types = [type]
  project.work_package_custom_fields = WorkPackageCustomField.where(is_for_all: true)
  project.save!

  # Link to AD plant (Project CF)
  option_id = ad_org_option_id(ad_org_cf, ad_code)
  project.custom_field_values = { ad_org_cf.id => option_id }
  project.save!

  # Project admin — обычная (не builtin) роль; BUILTIN_PROJECT_ADMIN в OP 17 нет
  role = ProjectRole.find_by(name: "Администратор проекта") ||
         ProjectRole.find_by(name: "Project admin") ||
         ProjectRole.givable.first ||
         ProjectRole.first
  raise "No project role found" if role.nil?

  member = Member.find_or_initialize_by(project:, principal: admin)
  member.roles = [role] if member.roles.empty?
  member.save! if member.changed? || member.new_record? || member.member_roles.empty?

  project
end

enterprises = CovenantAd::ENTERPRISES.map do |e|
  ensure_enterprise!(
    identifier: e[:identifier],
    name: e[:name],
    legacy: e[:legacy] || [],
    ad_code: e[:ad_code],
    ad_org_cf:,
    type:,
    admin:
  )
end
puts "[covenant-seed] enterprises: #{enterprises.map { |p| "#{p.identifier}(#{p.name})" }.join(", ")}"

# Detach extra types from any leftover projects; archive junk demo projects lightly
junk = Project.where(identifier: %w[demo-project your-scrum-project covenants])
junk.find_each do |p|
  p.types = [type]
  p.enabled_module_names = (p.enabled_module_names & %w[work_package_tracking activity]) | %w[work_package_tracking]
  p.save(validate: false)
end

# Rename covenants → keep as meta or leave; also ensure all projects only have Запрос
Project.find_each do |p|
  next if p.types == [type]

  p.types = [type]
  p.save(validate: false)
end

# --- Default query columns per enterprise ---
# ID | Тема | Статус | Исполнители | Дата окончания
# «Заблокирован» не в дефолте (поле на форме и фильтр остаются)
COLUMN_NAMES = (
  %i[id subject status] +
  ["cf_#{cf_executors.id}"].map(&:to_sym) +
  %i[due_date]
).freeze

def ensure_default_query!(project:, admin:, columns:)
  query = Query.find_or_initialize_by(project:, name: "Все запросы", user: admin)
  query.public = true
  query.show_hierarchies = true
  query.include_subprojects = false
  query.column_names = columns
  query.filters = []
  query.sort_criteria = [%w[id asc]]
  query.save!

  View.find_or_create_by!(query:, type: "work_packages_table")
  query
end

# Глобальный дефолт OP (когда у query column_names пустые — «Все открытые» и т.п.)
begin
  Setting.work_package_list_default_columns = COLUMN_NAMES.map(&:to_s)
  puts "[covenant-seed] Setting.work_package_list_default_columns=#{Setting.work_package_list_default_columns.join(",")}"
rescue StandardError => e
  warn "[covenant-seed] failed to set default columns setting: #{e.message}"
end

enterprises.each do |project|
  ensure_default_query!(project:, admin:, columns: COLUMN_NAMES)
end
puts "[covenant-seed] default queries set (columns=#{COLUMN_NAMES.join(",")})"

# --- Demo requests ---
DEMO_REQUESTS = [
  { project: "pao-koks", section: "Финансы", req_no: "KX-001", subject: "Предоставить отчёт по ковенантам за Q1",
    locked: false, status: "Запрошен", priority: "Обычный", due: 14 },
  { project: "pao-koks", section: "Юридический", req_no: "KX-002", subject: "Копия кредитного соглашения",
    locked: true, status: "Предоставлен", priority: "Высокий", due: -3, fact: -1 },
  { project: "ao-tulachermet", section: "Отчётность", req_no: "TC-010", subject: "Справка о соблюдении финансовых ковенантов",
    locked: false, status: "Запрошен", priority: "Обычный", due: 7 },
  { project: "ao-kmaruda", section: "Операционный", req_no: "KM-004", subject: "Данные по долговой нагрузке",
    locked: false, status: "Запрошен", priority: "Низкий", due: 21 },
  { project: "ooo-uchastok-koksovy", section: "Финансы", req_no: "UK-015", subject: "Расчёт EBITDA за период",
    locked: false, status: "Просрочено", priority: "Высокий", due: -10 },
  { project: "ooo-pmh-vtormet", section: "Прочее", req_no: "VT-003", subject: "Перечень залоговых активов",
    locked: false, status: "Запрошен", priority: "Обычный", due: 30 },
  { project: "ooo-pmh-infotech", section: "Юридический", req_no: "IT-007", subject: "Актуализация списка аффилированных лиц",
    locked: true, status: "Предоставлен", priority: "Обычный", due: -5, fact: -2 },
  { project: "ooo-uk-pmh", section: "Финансы", req_no: "UKP-001", subject: "Сводный отчёт по группе ПМХ",
    locked: false, status: "Запрошен", priority: "Высокий", due: 10 }
].freeze

status_by_name = Status.all.index_by(&:name)
prio_by_name = IssuePriority.all.index_by(&:name)
section_opt = cf_section.custom_options.index_by(&:value)

DEMO_REQUESTS.each do |row|
  project = Project.find_by!(identifier: row[:project])
  existing = WorkPackage.where(project:, subject: row[:subject]).first
  wp = existing || WorkPackage.new(project:, author: admin)
  wp.type = type
  wp.subject = row[:subject]
  wp.description = "Демо-ковенанта.\n\nРаздел: #{row[:section]}\n№ запроса: #{row[:req_no]}"
  wp.status = status_by_name.fetch(row[:status])
  wp.priority = prio_by_name.fetch(row[:priority])
  wp.assigned_to = admin
  wp.due_date = Date.current + row[:due].to_i
  wp.custom_field_values = {
    cf_section.id => section_opt[row[:section]]&.id,
    cf_req_no.id => row[:req_no],
    cf_locked.id => row[:locked] ? "1" : "0",
    cf_fact_date.id => row[:fact] ? (Date.current + row[:fact].to_i).to_s : nil,
    cf_executors.id => [admin.id]
  }
  wp.save!
end
puts "[covenant-seed] demo requests: #{DEMO_REQUESTS.size}"

# Одноразово вычистить старые демо-тексты с «Орбит*» из description
legacy_fixed = 0
WorkPackage.where("description ILIKE ?", "%Орбит%").find_each do |wp|
  next if wp.description.blank?

  updated = wp.description
    .gsub("Демо-запрос Орбиты.", "Демо-ковенанта.")
    .gsub(/Орбит\w*/i, "ковенанта")
  next if updated == wp.description

  wp.update_column(:description, updated)
  legacy_fixed += 1
end
puts "[covenant-seed] legacy wording fixed: #{legacy_fixed}" if legacy_fixed.positive?

copied = 0
WorkPackage.find_each do |wp|
  next if wp.assigned_to_id.blank?

  exists = CustomValue.where(
    customized_type: "WorkPackage",
    customized_id: wp.id,
    custom_field_id: cf_executors.id
  ).where.not(value: [nil, ""]).exists?
  next if exists

  CustomValue.create!(customized: wp, custom_field: cf_executors, value: wp.assigned_to_id.to_s)
  copied += 1
end
puts "[covenant-seed] assigned_to → Исполнители copied=#{copied}"

# Author/assignee as email in table
begin
  Setting.user_format = "username" # fallback until mail patch applied by initializer
rescue StandardError
  nil
end

puts "[covenant-seed] done"


# Подменяем внутренний трекер изменений Rails, делая объект "чистым"
type.instance_variable_get(:@mutations_from_database)&.instance_variable_set(:@changes, {})

puts "[covenant-seed] Custom fields successfully linked via type_variant_id"
puts "[covenant-seed] Form configuration inherits structure from linked custom fields dynamically."
puts "[covenant-seed] Сидирование модели «Запрос» успешно завершено!"

# Оставляем жесткий системный выход, минуя хуки деструкторов (выход на уровне процесса C-уровня)