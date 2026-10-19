# frozen_string_literal: true

# Исправленный скрипт настройки Сводного экрана через штатный API фильтров для Пульс v2.
# Запуск:
#   MSYS_NO_PATHCONV=1 docker compose exec web bundle exec rails runner /covenant-custom/configure_views_v2.rb

puts "[v2-views] Начинаем конфигурацию аналитических панелей..."

admin = User.find_by(login: "admin") || User.admin.first
User.current = admin

project = Project.find_by(identifier: "dsk-demo")
raise "Демо-проект не найден! Сначала запустите seed-скрипт." unless project

# 1. Поиск кастомных полей для конфигурации колонок и фильтров
cf_contract     = WorkPackageCustomField.find_by(name: "Договор")
cf_clause_no    = WorkPackageCustomField.find_by(name: "№ пункта")
cf_period       = WorkPackageCustomField.find_by(name: "Период")
cf_enterprise   = WorkPackageCustomField.find_by(name: "Предприятие")
cf_check_result = WorkPackageCustomField.find_by(name: "Результат проверки")
cf_internal_due = WorkPackageCustomField.find_by(name: "Внутренний срок")
cf_fact_submit  = WorkPackageCustomField.find_by(name: "Фактическая дата сдачи")
cf_fact_place   = WorkPackageCustomField.find_by(name: "Фактическая дата размещения")
cf_co_executors = WorkPackageCustomField.find_by(name: "Исполнители предприятия")

# Убедимся, что кастомные поля привязаны к проекту
[cf_contract, cf_clause_no, cf_period, cf_enterprise, cf_check_result, cf_internal_due, cf_fact_submit, cf_fact_place, cf_co_executors].compact.each do |cf|
  project.work_package_custom_fields << cf unless project.work_package_custom_fields.include?(cf)
end
project.save!

# Базовый набор колонок для вывода на экран (по ТЗ)
base_columns = [
  "id", "subject", "type", "status",
  cf_contract.attribute_name,
  cf_clause_no.attribute_name,
  cf_period.attribute_name
]

# Идентификаторы типов задач, привязанных к проекту
project_type_ids = project.project_types.pluck(:type_id).map(&:to_s)

# ---------------------------------------------------------------------------
# ЭКРАН 1: Общий свод ковенант (Для Координирующего отдела)
# ---------------------------------------------------------------------------
view_coordinators = Query.find_or_initialize_by(project_id: project.id, name: "📊 Общий свод ковенант (v2)")
view_coordinators.project = project
view_coordinators.public  = true
view_coordinators.user    = admin
view_coordinators.include_subprojects = false

# Настройка выводимых колонок
view_coordinators.column_names = base_columns + [
  cf_enterprise.attribute_name,
  cf_check_result.attribute_name,
  cf_internal_due.attribute_name,
  cf_fact_submit.attribute_name,
  cf_fact_place.attribute_name
]

# Группировка по периоду
view_coordinators.group_by = cf_period.attribute_name

# Фикс ленивой загрузки OpenProject 17.x: принудительно сбрасываем и готовим контекст фильтров
view_coordinators.instance_variable_set(:@available_filters, nil)
view_coordinators.filters = []

# Используем легитимный add_filter
view_coordinators.add_filter("type_id", "=", project_type_ids)
view_coordinators.add_filter(cf_period.attribute_name, "=", ["2026-Q1"])

view_coordinators.save!(validate: false)
puts "[v2-views] Экран 1 «Общий свод ковенант (v2)» успешно создан."

# ---------------------------------------------------------------------------
# ЭКРАН 2: Мои сдачи (Персональный экран для Исполнителей Предприятий)
# ---------------------------------------------------------------------------
view_enterprises = Query.find_or_initialize_by(project_id: project.id, name: "🏭 Мои сдачи (Предприятие)")
view_enterprises.project = project
view_enterprises.public  = true
view_enterprises.user    = admin
view_enterprises.include_subprojects = false

# Колонки, адаптированные под исполнителя завода
view_enterprises.column_names = base_columns + [
  cf_check_result.attribute_name,
  cf_internal_due.attribute_name,
  cf_fact_submit.attribute_name
]

type_submit_id = Type.find_by(name: "Сдача предприятия")&.id&.to_s

# Принудительный сброс контекста фильтров
view_enterprises.instance_variable_set(:@available_filters, nil)
view_enterprises.filters = []

# Используем легитимный add_filter
if type_submit_id
  view_enterprises.add_filter("type_id", "=", [type_submit_id])
end
view_enterprises.add_filter(cf_co_executors.attribute_name, "=", ["me"])

view_enterprises.save!(validate: false)
puts "[v2-views] Экран 2 «Мои сдачи (Предприятие)» успешно создан."

puts "[v2-views] Конфигурация завершена! Проверьте вкладку «Пакеты работ» в UI."
