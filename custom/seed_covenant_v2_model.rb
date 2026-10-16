# frozen_string_literal: true

# Исправленный Seed модели второй системы мониторинга ковенант (v2).
# Не трогает тип «Запрос» и данные действующего «Пульса».
#
# Запуск (из корня репозитория, когда стек поднят):
#   docker compose exec web bundle exec rails runner /covenant-custom/seed_covenant_v2_model.rb
#
# Идемпотентен: можно перезапускать.

puts "[v2-seed] start"

admin = User.find_by(login: "admin") || User.admin.first
raise "admin user not found" unless admin
User.current = admin

YELLOW = Color.find_by(name: "Yellow") || Color.find_by(hexcode: "#FFFF00") || Color.find_by(name: "yellow-5")
GREEN  = Color.find_by(name: "Green")  || Color.find_by(hexcode: "#35C53F") || Color.find_by(name: "green-5")
RED    = Color.find_by(name: "Red")    || Color.find_by(hexcode: "#FF0000") || Color.find_by(name: "red-5")
BLUE   = Color.find_by(name: "Blue")   || Color.find_by(hexcode: "#0000FF") || Color.find_by(name: "blue-5")

def upsert_status!(name:, is_default: false, is_closed: false, color:, position:)
  st = Status.find_or_initialize_by(name: name)
  st.is_default = is_default
  st.is_closed  = is_closed
  st.color      = color if color
  st.position   = position
  st.save!
  st
end

def upsert_type!(name:, position: nil)
  t = Type.find_or_initialize_by(name: name)
  t.is_milestone  = false
  t.is_in_roadmap = false
  t.position      = position if position
  t.save!
  t
end

def upsert_wp_cf!(name:, field_format:, possible_values: nil, multi_value: false, is_for_all: false)
  cf = WorkPackageCustomField.find_by(name: name)
  cf ||= WorkPackageCustomField.new(name: name, field_format: field_format)
  cf.field_format = field_format
  cf.is_for_all   = is_for_all
  cf.is_filter    = true
  cf.searchable   = %w[string text].include?(field_format)
  cf.multi_value  = multi_value
  if possible_values && field_format == "list"
    cf.possible_values = possible_values if cf.custom_options.empty?
  end
  cf.save!
  cf
end

def link_cfs_to_type!(type, cfs)
  cfs.each do |cf|
    exists = ActiveRecord::Base.connection.select_value(
      "SELECT 1 FROM custom_fields_types WHERE type_variant_id = #{type.id} AND custom_field_id = #{cf.id}"
    )
    next if exists

    ActiveRecord::Base.connection.execute(
      "INSERT INTO custom_fields_types (type_variant_id, custom_field_id) VALUES (#{type.id}, #{cf.id})"
    )
  end
  type.changes_applied if type.respond_to?(:changes_applied)
end

def set_form_groups!(type, groups)
  raw_groups = groups.map do |name, attrs|
    { "name" => name, "attributes" => attrs }
  end

  if type.respond_to?(:form_configuration)
    conf = type.form_configuration || type.build_form_configuration
    if conf.respond_to?(:structure=)
      conf.structure = raw_groups
    elsif conf.respond_to?(:attribute_groups=)
      conf.attribute_groups = raw_groups
    elsif conf.respond_to?(:value=)
      conf.value = raw_groups
    end
    conf.save!
    puts "[v2-seed] form OK «#{type.name}» via form_configuration"
  elsif defined?(Type::FormConfiguration)
    conf = Type::FormConfiguration.find_or_initialize_by(type_id: type.id)
    conf.structure = raw_groups if conf.respond_to?(:structure=)
    conf.attribute_groups = raw_groups if conf.respond_to?(:attribute_groups=)
    conf.save!
    puts "[v2-seed] form OK «#{type.name}» via Type::FormConfiguration"
  else
    begin
      service = WorkPackageTypes::UpdateService.new(user: User.current, model: type)
      result = service.call(attribute_groups: groups)
      if result.success?
        puts "[v2-seed] form OK «#{type.name}» via UpdateService"
      else
        puts "[v2-seed] form WARN «#{type.name}»: #{result.errors.full_messages.join(', ')}"
      end
    rescue StandardError => e
      json_column = type.class.columns.map(&:name).find { |c| c.include?("conf") || c.include?("group") }
      if json_column
        type.update_column(json_column.to_sym, raw_groups)
        puts "[v2-seed] form fallback «#{type.name}» → column #{json_column}"
      else
        warn "[v2-seed] form SKIP «#{type.name}»: #{e.class}: #{e.message}"
      end
    end
  end
end

def ensure_workflows!(type, statuses)
  roles = ProjectRole.where(builtin: 0)
  roles = ProjectRole.all if roles.none?
  roles = roles.distinct

  workflow_type_key = if Workflow.column_names.include?("type_variant_id")
                        :type_variant_id
                      elsif Workflow.column_names.include?("type_id")
                        :type_id
                      else
                        raise "Unknown type column in workflows: #{Workflow.column_names.join(', ')}"
                      end

  Workflow.where(workflow_type_key => type.id).delete_all
  roles.find_each do |role|
    statuses.each do |from|
      statuses.each do |to|
        next if from.id == to.id
        params = {
          role_id: role.id,
          old_status_id: from.id,
          new_status_id: to.id
        }
        params[workflow_type_key] = type.id
        Workflow.create!(params)
      end
    end
  end
  puts "[v2-seed] workflows «#{type.name}»: #{Workflow.where(workflow_type_key => type.id).count} (#{workflow_type_key})"
end

# ---------------------------------------------------------------------------
# 1. Статусы v2
# ---------------------------------------------------------------------------
st_awaiting   = upsert_status!(name: "Ожидается",       is_default: false, is_closed: false, color: YELLOW, position: 10)
st_submitted  = upsert_status!(name: "Сдано",           is_default: false, is_closed: true,  color: GREEN,  position: 11)
st_overdue    = Status.find_by(name: "Просрочено") ||
                upsert_status!(name: "Просрочено",      is_default: false, is_closed: true,  color: RED,    position: 3)
st_placing    = upsert_status!(name: "На размещении",   is_default: false, is_closed: false, color: BLUE,   position: 12)
st_placed     = upsert_status!(name: "Размещено",       is_default: false, is_closed: true,  color: GREEN,  position: 13)

puts "[v2-seed] statuses OK"

# ---------------------------------------------------------------------------
# 2. Типы
# ---------------------------------------------------------------------------
type_covenant  = upsert_type!(name: "Ковенанта",           position: 20)
type_submit    = upsert_type!(name: "Сдача предприятия",   position: 21)
type_material  = upsert_type!(name: "Материал размещения", position: 22)

puts "[v2-seed] types OK"

# ---------------------------------------------------------------------------
# 3. Кастомные поля (Скорректировано по ТЗ)
# ---------------------------------------------------------------------------
cf_contract     = upsert_wp_cf!(name: "Договор",              field_format: "list", possible_values: %w[ДСК ССК Поставка])
cf_clause_no    = upsert_wp_cf!(name: "№ пункта",             field_format: "string")
cf_period       = upsert_wp_cf!(name: "Период",               field_format: "string")
cf_enterprise   = upsert_wp_cf!(name: "Предприятие",          field_format: "list",
                                possible_values: %w[ДСК-1 ДСК-2 ДСК-3 ПАО-Кокс])
cf_frequency    = upsert_wp_cf!(name: "Периодичность",        field_format: "list",
                                possible_values: %w[месяц квартал полугодие год])
cf_check_method = upsert_wp_cf!(name: "Способ проверки",      field_format: "string")
cf_calc_method  = upsert_wp_cf!(name: "Метод расчёта",        field_format: "string")
cf_threshold    = upsert_wp_cf!(name: "Порог",                field_format: "float")
cf_unit         = upsert_wp_cf!(name: "Единица измерения",    field_format: "string")
cf_value        = upsert_wp_cf!(name: "Значение показателя",  field_format: "float")
cf_internal_due = upsert_wp_cf!(name: "Внутренний срок",      field_format: "date")
cf_contract_due = upsert_wp_cf!(name: "Договорный срок",      field_format: "date")
cf_needs_place  = upsert_wp_cf!(name: "Требует размещения",   field_format: "bool")
cf_check_result = upsert_wp_cf!(name: "Результат проверки",   field_format: "list",
                                possible_values: ["Соблюдено", "Нарушено", "Недостаточно данных"])
cf_fact_submit  = upsert_wp_cf!(name: "Фактическая дата сдачи", field_format: "date")
cf_fact_place   = upsert_wp_cf!(name: "Фактическая дата размещения", field_format: "date")

cf_co_executors = upsert_wp_cf!(name: "Исполнители предприятия", field_format: "user", multi_value: true)

cfs_covenant = [
  cf_contract, cf_clause_no, cf_frequency, cf_check_method, cf_calc_method,
  cf_threshold, cf_unit, cf_needs_place, cf_contract_due
]
cfs_submit = [
  cf_contract, cf_clause_no, cf_period, cf_enterprise,
  cf_value, cf_internal_due, cf_check_result, cf_fact_submit, cf_co_executors
]
cfs_material = [
  cf_contract, cf_clause_no, cf_period,
  cf_contract_due, cf_fact_place
]

link_cfs_to_type!(type_covenant, cfs_covenant)
link_cfs_to_type!(type_submit,   cfs_submit)
link_cfs_to_type!(type_material, cfs_material)

puts "[v2-seed] custom fields linked"

set_form_groups!(type_covenant, [
  ["Ковенанта", %w[subject description status priority] + cfs_covenant.map(&:attribute_name)],
  ["Прочее",    %w[responsible]]
])
set_form_groups!(type_submit, [
  ["Сдача",  %w[subject description status priority due_date] + cfs_submit.map(&:attribute_name)],
  ["Прочее", %w[responsible]]
])
set_form_groups!(type_material, [
  ["Размещение", %w[subject description status priority due_date] + cfs_material.map(&:attribute_name)],
  ["Прочее",     %w[responsible]]
])

ensure_workflows!(type_covenant, [st_awaiting, st_submitted, st_overdue])
ensure_workflows!(type_submit,   [st_awaiting, st_submitted, st_overdue])
ensure_workflows!(type_material, [st_placing, st_placed, st_overdue])

# ---------------------------------------------------------------------------
# 4. Демо-проект
# ---------------------------------------------------------------------------
project = Project.find_by(identifier: "dsk-demo") || Project.new
project.identifier = "dsk-demo"
project.name       = "ДСК — демо v2"
project.public     = false
project.workspace_type = "project" if project.respond_to?(:workspace_type=)
project.enabled_module_names = %w[work_package_tracking activity]
project.save!

existing_types = project.types.to_a
project.types = (existing_types + [type_covenant, type_submit, type_material]).uniq
project.work_package_custom_fields = (
  project.work_package_custom_fields.to_a +
  cfs_covenant + cfs_submit + cfs_material +
  WorkPackageCustomField.where(is_for_all: true).to_a
).uniq
project.save!

role = ProjectRole.find_by(name: "Администратор проекта") ||
       ProjectRole.find_by(name: "Project admin") ||
       ProjectRole.givable.first ||
       ProjectRole.first
raise "No project role" unless role

member = Member.find_or_initialize_by(project: project, principal: admin)
member.roles = [role] if member.roles.empty?
member.save! if member.changed? || member.new_record? || member.member_roles.empty?

puts "[v2-seed] project «#{project.name}» готов"

# ---------------------------------------------------------------------------
# 5. Демо-данные
# ---------------------------------------------------------------------------
def find_or_build_wp(project:, subject:, type:)
  wp = WorkPackage.find_by(project: project, subject: subject)
  wp || WorkPackage.new(project: project, subject: subject, type: type, author: User.current)
end

cov = find_or_build_wp(project: project, subject: "п. 5.2 — Коэффициент покрытия процентов", type: type_covenant)
cov.description = "Минимальный коэффициент покрытия процентов по итогам квартала. Источник: договор ДСК."
cov.status   = st_awaiting
cov.priority = IssuePriority.find_by(name: "Обычный") || IssuePriority.first
cov.save!

cov.custom_field_values = {
  cf_contract.id     => "ДСК",
  cf_clause_no.id    => "5.2",
  cf_frequency.id    => "квартал",
  cf_check_method.id => "расчёт по отчётности",
  cf_calc_method.id  => "EBITDA / проценты к уплате",
  cf_threshold.id    => 2.5,
  cf_unit.id         => "коэф.",
  cf_needs_place.id  => "1",
  cf_contract_due.id => Date.new(2026, 5, 15)
}
cov.save!
puts "[v2-seed] covenant ##{cov.id} создана"

submissions = [
  { ent: "ДСК-1", value: 2.8, status: st_submitted, result: "Соблюдено",
    internal: Date.new(2026, 4, 20), fact: Date.new(2026, 4, 18) },
  { ent: "ДСК-2", value: 2.1, status: st_submitted, result: "Нарушено",
    internal: Date.new(2026, 4, 20), fact: Date.new(2026, 4, 22) },
  { ent: "ДСК-3", value: nil, status: st_awaiting, result: "Недостаточно данных",
    internal: Date.new(2026, 4, 20), fact: nil }
]

submissions.each do |row|
  subj = "Сдача #{row[:ent]} — 2026-Q1 — п. 5.2"
  wp = find_or_build_wp(project: project, subject: subj, type: type_submit)
  wp.parent      = cov
  wp.description = "Данные предприятия #{row[:ent]} за 2026-Q1"
  wp.status      = row[:status]
  wp.priority    = IssuePriority.find_by(name: "Обычный") || IssuePriority.first
  wp.due_date    = row[:internal]
  wp.save!

  wp.custom_field_values = {
    cf_contract.id     => "ДСК",
    cf_clause_no.id    => "5.2",
    cf_period.id       => "2026-Q1",
    cf_enterprise.id   => row[:ent],
    cf_value.id        => row[:value],
    cf_internal_due.id => row[:internal],
    cf_check_result.id => row[:result],
    cf_fact_submit.id  => row[:fact],
    cf_co_executors.id => [admin.id.to_s]
  }.reject { |_, v| v.nil? }
  wp.save!
  puts "[v2-seed] submit ##{wp.id} [#{row[:ent]}] → #{row[:status].name}"
end

mat = find_or_build_wp(project: project, subject: "Материал в СберФинлайн — 2026-Q1 — п. 5.2", type: type_material)
mat.parent      = cov
mat.description = "Итоговый пакет по п. 5.2 за 2026-Q1 (свод по предприятиям)."
mat.status      = st_placing
mat.priority    = IssuePriority.find_by(name: "Обычный") || IssuePriority.first
mat.due_date    = Date.new(2026, 5, 15)
mat.save!

mat.custom_field_values = {
  cf_contract.id     => "ДСК",
  cf_clause_no.id    => "5.2",
  cf_period.id       => "2026-Q1",
  cf_contract_due.id => Date.new(2026, 5, 15)
}
mat.save!
puts "[v2-seed] material ##{mat.id} создан"

puts "[v2-seed] done"
