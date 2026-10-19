# frozen_string_literal: true

# Скрипт автоматического перевода просроченных сдач предприятий в статус «Просрочено».
# Запуск:
#   MSYS_NO_PATHCONV=1 docker compose exec web bundle exec rails runner /covenant-custom/check_overdue_v2.rb

puts "[v2-overdue] Запуск проверки дедлайнов по ковенантам..."

# Устанавливаем системного пользователя для логирования изменений в истории задач
admin = User.find_by(login: "admin") || User.admin.first
User.current = admin

# Находим нужные системные сущности
project = Project.find_by(identifier: "dsk-demo")
raise "Демо-проект 'dsk-demo' не найден!" unless project

type_submit = Type.find_by(name: "Сдача предприятия")
raise "Тип задачи 'Сдача предприятия' не найден!" unless type_submit

status_requested = Status.find_by(name: "Запрошен")
status_overdue   = Status.find_by(name: "Просрочено")

raise "Системные статусы 'Запрошен' или 'Просрочено' не найдены в системе!" if status_requested.nil? || status_overdue.nil?

cf_internal_due = WorkPackageCustomField.find_by(name: "Внутренний срок")
raise "Кастомное поле 'Внутренний срок' не найдено!" unless cf_internal_due

# Текущая дата для сравнения
today = Date.today
updated_count = 0

puts "[v2-overdue] Ищем задачи типа '#{type_submit.name}' в статусе '#{status_requested.name}'..."

# Выбираем только открытые задачи нужного типа в рамках нашего проекта
work_packages = WorkPackage.where(project_id: project.id, type_id: type_submit.id, status_id: status_requested.id)

work_packages.find_each do |wp|
  # Извлекаем значение кастомного поля «Внутренний срок»
  due_date_value = wp.custom_value_for(cf_internal_due.id)&.value
  next if due_date_value.blank?

  begin
    # Парсим дату (OpenProject сохраняет её в формате YYYY-MM-DD)
    internal_due_date = Date.parse(due_date_value)
    
    # Если внутренний срок прошел, а задача все еще "Запрошена" -> переводим в "Просрочено"
    if internal_due_date < today
      puts "[v2-overdue] Задача ##{wp.id} '#{wp.subject}' просрочена (Дедлайн: #{internal_due_date}). Переводим в статус 'Просрочено'..."
      
      # Используем штатный метод обновления OpenProject, чтобы зафиксировать изменения в истории (Journal)
      wp.status_id = status_overdue.id
      
      # Добавляем системный комментарий в историю задачи
      wp.journal_notes = "Автоматическая система: Срок выполнения ковенанты истек (#{internal_due_date}). Статус изменен на Просрочено."
      
      if wp.save
        updated_count += 1
      else
        puts "[v2-overdue] ❌ Не удалось обновить задачу ##{wp.id}: #{wp.errors.full_messages.join(', ')}"
      end
    end
  rescue ArgumentError => e
    puts "[v2-overdue] ⚠️ Ошибка парсинга даты для задачи ##{wp.id}: #{e.message}"
  end
end

puts "[v2-overdue] Проверка завершена. Обновлено задач: #{updated_count}."
